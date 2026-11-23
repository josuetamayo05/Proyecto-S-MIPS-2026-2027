#!/usr/bin/env python3
"""Prueba por separado los subcircuitos de la CPU (no modifica el circuito).

Uso: LOGISIM_JAR=ruta/al.jar python3 tools/verify_blocks.py [archivo.circ]
"""
from pathlib import Path
import os
import random
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
JAR = os.environ.get('LOGISIM_JAR', '/snap/logisim-evolution-snapcraft/current/jar/logisim-evolution.jar')
CIRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT/'circuit/smips.circ'
fallos_totales = 0


def probar(circuito, ordenes):
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run(['java', '-Djava.awt.headless=true', f'-Djava.util.prefs.userRoot={d}', '--class-path', JAR,
                            str(ROOT/'tools/Probe.java'), str(CIRC.resolve()), circuito],
                           input=ordenes, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'Fallo al simular {circuito}:\n{r.stderr[-3000:]}')
    return [dict(x.split('=') for x in l.split()) for l in r.stdout.splitlines() if '=' in l]


def poner(**valores):
    return ''.join(f'set {k} {v:x}\n' for k, v in valores.items())


def informe(nombre, salidas, esperadas):
    """esperadas: lista de (descripcion, {salida: valor}); None = no importa."""
    global fallos_totales
    assert len(salidas) == len(esperadas), f'{nombre}: {len(salidas)} respuestas, se esperaban {len(esperadas)}'
    malos = [f'{d}: {k}={o[k]}, esperado {v:x}' for o, (d, e) in zip(salidas, esperadas)
             for k, v in e.items() if v is not None and o[k] != format(v, 'x')]
    fallos_totales += len(malos)
    print(f'{"FALLO" if malos else "OK   "} {nombre} ({len(esperadas)} comprobaciones)')
    for m in malos[:10]:
        print('       ', m)


def alu():
    M = 0xffffffff
    s32 = lambda x: x - (1 << 32) if x >> 31 else x
    ops = [lambda a, b, s: (a + b) & M, lambda a, b, s: (a - b) & M, lambda a, b, s: a & b, lambda a, b, s: a | b,
           lambda a, b, s: int(s32(a) < s32(b)), lambda a, b, s: (b << s) & M, lambda a, b, s: b >> s,
           lambda a, b, s: (b << 16) & M]
    rnd = random.Random(1)
    bordes = [0, 1, 5, M, 0x80000000, 0x7fffffff, 0xffff0000, 0x12345678]
    valor = lambda: rnd.choice(bordes + [rnd.getrandbits(32)])
    casos = [(op, valor(), valor(), rnd.choice([0, 1, 4, 16, 31])) for op in range(8) for _ in range(25)]
    sal = probar('ALU', ''.join(poner(A=a, B=b, Shamt=s, ALUControl=op) + 'show\n' for op, a, b, s in casos))
    esp = []
    for op, a, b, s in casos:
        r = ops[op](a, b, s)
        esp.append((f'op={op} A={a:08x} B={b:08x} shamt={s}', {'Result': r, 'Zero': int(r == 0)}))
    informe('ALU', sal, esp)


def branch_control():
    casos = [tuple(n >> i & 1 for i in range(5)) for n in range(32)]
    nombres = ('PCWrite', 'PCWriteCond', 'IsBeq', 'IsBne', 'Zero')
    sal = probar('Branch_Control', ''.join(poner(**dict(zip(nombres, c))) + 'show\n' for c in casos))
    informe('Branch_Control', sal, [(str(c), {'PCWriteFinal': c[0] | (c[1] & ((c[2] & c[4]) | (c[3] & (1 - c[4]))))})
                                    for c in casos])


def decodificador():
    ADD, SUB, AND, OR, SLT, SLL, SRL, LUI = range(8)
    F = ['IsRType', 'IsBranch', 'IsBeq', 'IsBne', 'IsJump', 'IsJal', 'IsJr', 'IsSyscall', 'IsLoad', 'IsStore',
         'IsByte', 'IsUnsigned']
    # clave -> (flags activos, ALUOp, ImmType); None = no importa
    funct = {0x00: SLL, 0x02: SRL, 0x20: ADD, 0x21: ADD, 0x22: SUB, 0x24: AND, 0x25: OR, 0x2A: SLT}
    R = {f: ('IsRType', a, None) for f, a in funct.items()}
    R[0x08] = ('IsRType IsJr', None, None)
    R[0x0C] = ('IsRType IsSyscall', None, None)
    OP = {0x02: ('IsJump', None, None), 0x03: ('IsJump IsJal', None, None), 0x04: ('IsBranch IsBeq', SUB, None),
          0x05: ('IsBranch IsBne', SUB, None), 0x08: ('', ADD, 1), 0x09: ('', ADD, 1), 0x0A: ('', SLT, 1),
          0x0C: ('', AND, 0), 0x0D: ('', OR, 0), 0x0F: ('', LUI, None), 0x20: ('IsLoad IsByte', ADD, 1),
          0x23: ('IsLoad', ADD, 1), 0x24: ('IsLoad IsByte IsUnsigned', ADD, 1), 0x28: ('IsStore IsByte', ADD, 1),
          0x2B: ('IsStore', ADD, 1)}
    casos = [(o, f) for o in range(64) for f in range(64)]
    sal = probar('Instruction_Decoder', ''.join(poner(Opcode=o, Funct=f) + 'show\n' for o, f in casos))
    esp = []
    for o, f in casos:
        x = R.get(f) if o == 0 else OP.get(o)
        e = {'Illegal': int(x is None), 'Legal': int(x is not None)}
        if x:
            e.update({k: int(k in x[0].split()) for k in F}, ALUOp=x[1], ImmType=x[2])
        esp.append((f'op={o:02x} funct={f:02x}', e))
    informe('Instruction_Decoder', sal, esp)


def banco():
    inicial = lambda i: {28: 0x1800, 29: 0x3FFC}.get(i, 0)
    escrito = lambda i: 0 if i == 0 else 0xA0000000 + i*0x111
    leer = ''.join(poner(ReadReg1=i, ReadReg2=31 - i) + 'show\n' for i in range(32))
    reset = poner(RESET=1) + 'clk\n' + poner(RESET=0)
    o = poner(CLK=0, RegWrite=0, WriteReg=0, WriteData=0) + reset + leer
    o += poner(RegWrite=0, WriteReg=5, WriteData=0xDEAD) + 'clk\n' + leer          # sin RegWrite no escribe
    o += ''.join(poner(RegWrite=1, WriteReg=i, WriteData=0xA0000000 + i*0x111) + 'clk\n' for i in range(32))
    o += poner(RegWrite=0) + leer
    o += poner(RegWrite=1, WriteReg=29, WriteData=0x1234) + reset + poner(RegWrite=0) + leer   # gana el reset
    esp = []
    for fase, f in (('reset', inicial), ('RegWrite=0', inicial), ('escritura', escrito), ('segundo reset', inicial)):
        esp += [(f'{fase} r{i}/r{31 - i}', {'ReadData1': f(i), 'ReadData2': f(31 - i)}) for i in range(32)]
    informe('Register_File', probar('Register_File', o), esp)


def control():
    SAL = ['PCWrite', 'PCWriteCond', 'IorD', 'IRWrite', 'RegWrite', 'RegDst', 'MemToReg', 'ALUSrcA', 'ALUSrcB',
           'MEM_WE', 'TTY_WE', 'HALT', 'PCSource', 'ALUControl']
    ENT = ['IsRType', 'IsLoad', 'IsStore', 'IsBranch', 'IsJump', 'IsJal', 'IsJr', 'IsSyscall', 'Illegal']
    OP = 6      # ALUOp de prueba: permite ver si pasa a ALUControl o se fuerza ADD (0)
    E = {'IF': dict(PCWrite=1, IRWrite=1, ALUSrcB=1), 'ID': dict(ALUSrcB=3, PCSource=3),
         'ID_JR': dict(PCWrite=1, ALUSrcB=3, PCSource=3), 'EX_R': dict(ALUSrcA=1, ALUControl=OP),
         'EX_I': dict(ALUSrcA=1, ALUSrcB=2, ALUControl=OP), 'EX_M': dict(ALUSrcA=1, ALUSrcB=2),
         'MEM_R': dict(IorD=1), 'MEM_W': dict(IorD=1, MEM_WE=1), 'WB_R': dict(RegWrite=1, RegDst=1),
         'WB_I': dict(RegWrite=1), 'WB_M': dict(RegWrite=1, MemToReg=1),
         'BR': dict(PCWriteCond=1, ALUSrcA=1, PCSource=1, ALUControl=OP), 'J': dict(PCWrite=1, PCSource=2),
         'JAL': dict(PCWrite=1, PCSource=2, RegWrite=1, RegDst=2, MemToReg=2), 'SYS': {}, 'TTY': dict(TTY_WE=1),
         'HALT': dict(HALT=1)}
    clases = [('tipo R', 'IsRType', 0, 'IF ID EX_R WB_R IF'), ('tipo I', '', 0, 'IF ID EX_I WB_I IF'),
              ('load', 'IsLoad', 0, 'IF ID EX_M MEM_R WB_M IF'), ('store', 'IsStore', 0, 'IF ID EX_M MEM_W IF'),
              ('branch', 'IsBranch', 0, 'IF ID BR IF'), ('j', 'IsJump', 0, 'IF ID J IF'),
              ('jal', 'IsJump IsJal', 0, 'IF ID JAL IF'), ('jr', 'IsRType IsJr', 0, 'IF ID_JR IF'),
              ('syscall 11', 'IsRType IsSyscall', 11, 'IF ID TTY IF'),
              ('syscall 10', 'IsRType IsSyscall', 10, 'IF ID SYS HALT HALT HALT'),
              ('syscall 1', 'IsRType IsSyscall', 1, 'IF ID SYS IF'),
              ('ilegal (op=0)', 'IsRType Illegal', 0, 'IF ID HALT HALT HALT'),
              ('ilegal', 'Illegal', 0, 'IF ID HALT HALT HALT')]
    o, esp = '', []
    for nombre, activos, v0, estados in clases:
        o += poner(CLK=0, ALUOp=OP, V0_Val=v0, RESET=1, **{k: 0 for k in ENT}) + 'clk\nshow\n' + poner(RESET=0)
        esp.append((f'{nombre} con RESET=1', dict(MEM_WE=0, TTY_WE=0, HALT=0)))
        for i, e in enumerate(estados.split()):
            o += 'show\nclk\n'
            if i == 0:      # el IR se carga al final de IF
                o += poner(**{k: 1 for k in activos.split()})
            esp.append((f'{nombre} ciclo {i} ({e})', {k: E[e].get(k, 0) for k in SAL}))
    informe('Control_Unit', probar('Control_Unit', o), esp)


if __name__ == '__main__':
    for prueba in (alu, branch_control, decodificador, banco, control):
        prueba()
    print('\nTodo correcto' if not fallos_totales else f'\n{fallos_totales} fallos')
    sys.exit(bool(fallos_totales))
