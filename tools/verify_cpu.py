#!/usr/bin/env python3
"""Comprueba en la placa lo que run_tests.py no mide (no modifica el circuito).

Para programs/, tests/ y unos programas codificados a mano compara con un emulador S-MIPS el texto
del TTY, el numero de ciclos con TTY_WE=1 (R4) y con MEM_WE=1 (R5). Ademas: instrucciones ilegales
(R10), HALT permanente (PC, registros y RAM sin cambios en 200 ciclos) y salidas con RESET=1 (R6).
Uso: LOGISIM_JAR=... MARS_JAR=... python3 tools/verify_cpu.py [archivo.circ]
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
JAR = os.environ.get('LOGISIM_JAR', '/snap/logisim-evolution-snapcraft/current/jar/logisim-evolution.jar')
CIRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT/'circuit/smips.circ'
M = 0xffffffff


def I(op, rs, rt, imm):
    return op << 26 | rs << 21 | rt << 16 | imm & 0xffff


V0, A0, SYS = 2, 4, 0xC
li = lambda r, v: I(9, 0, r, v)
imprimir = lambda c: [li(V0, 11), li(A0, ord(c)), SYS]
FIN = [li(V0, 10), SYS]
A_MANO = {
    'ilegal_opcode_3f': imprimir('A') + [0xFC000000] + imprimir('B') + FIN,
    'ilegal_funct_01': imprimir('A') + [0x00000001] + imprimir('B') + FIN,
    'ilegal_opcode_0b': imprimir('A') + [I(0x0B, 0, 8, 0)] + imprimir('B') + FIN,
    # escribe en $zero, nop, syscall 1 (sin efecto) e imprime '0' + $zero
    'nop_syscall1_zero': [I(9, 0, 0, 5), 0, li(V0, 1), SYS, li(V0, 11), I(9, 0, A0, ord('0')), SYS]
                         + imprimir('K') + FIN,
}


def emular(imagen):
    """Emulador S-MIPS independiente. Devuelve (texto, numero de stores)."""
    mem = [0]*4096
    for linea in imagen.read_text().splitlines()[1:]:
        a, ws = linea.split(':')
        for i, w in enumerate(ws.split()):
            mem[int(a, 16) + i] = int(w, 16)
    r = [0]*32
    r[28], r[29], pc, texto, stores = 0x1800, 0x3FFC, 0, '', 0
    sg = lambda x, n=32: x - (1 << n) if x >> (n - 1) else x
    for _ in range(100000):
        w = mem[pc >> 2 & 0xfff]
        pc = pc + 4 & M
        op, rs, rt, rd, sh, fn = w >> 26, w >> 21 & 31, w >> 16 & 31, w >> 11 & 31, w >> 6 & 31, w & 63
        z, se = w & 0xffff, sg(w & 0xffff, 16)
        a, b = r[rs], r[rt]
        d, v = (rd if op == 0 else rt), None
        p = (a + se & M) >> 2 & 0xfff
        k = 8*(a + se & 3)
        if op == 0:
            if fn in (0x20, 0x21): v = a + b
            elif fn == 0x22: v = a - b
            elif fn == 0x24: v = a & b
            elif fn == 0x25: v = a | b
            elif fn == 0x2A: v = int(sg(a) < sg(b))
            elif fn == 0: v = b << sh
            elif fn == 2: v = b >> sh
            elif fn == 8: pc = a
            elif fn == 0xC:
                if r[V0] == 10: return texto, stores
                if r[V0] == 11: texto += chr(r[A0] & 0x7f)
            else: return texto, stores
        elif op in (8, 9): v = a + se
        elif op == 0xA: v = int(sg(a) < se)
        elif op == 0xC: v = a & z
        elif op == 0xD: v = a | z
        elif op == 0xF: v = z << 16
        elif op == 0x23: v = mem[p]
        elif op == 0x20: v = sg(mem[p] >> k & 255, 8)
        elif op == 0x24: v = mem[p] >> k & 255
        elif op == 0x2B: mem[p] = b; stores += 1
        elif op == 0x28: mem[p] = mem[p] & ~(255 << k) | (b & 255) << k; stores += 1
        elif op in (4, 5):
            if (a == b) == (op == 4): pc = pc + 4*se & M
        elif op in (2, 3):
            if op == 3: d, v = 31, pc
            pc = pc & 0xf0000000 | (w & 0x3ffffff) << 2
        else: return texto, stores
        if v is not None and d: r[d] = v & M
    raise RuntimeError(f'{imagen.name}: no termina')


def main():
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        imagenes = []
        for f in sorted((ROOT/'programs').glob('*.asm')) + sorted((ROOT/'tests').glob('*.asm')):
            img = d/(f.stem + '.hex')
            subprocess.run([sys.executable, str(ROOT/'tools/assemble.py'), str(f), '-o', str(img)], check=True,
                           capture_output=True)
            imagenes.append(img)
        for nombre, ws in A_MANO.items():
            img = d/(nombre + '.hex')
            img.write_text('v3.0 hex words addressed\n' + ''.join(
                f'{i:03x}: ' + ' '.join(f'{w:08x}' for w in ws[i:i + 8]) + '\n' for i in range(0, len(ws), 8)))
            imagenes.append(img)
        r = subprocess.run(['java', '-Djava.awt.headless=true', f'-Djava.util.prefs.userRoot={d}/prefs', '--class-path',
                            JAR, str(ROOT/'tools/RunExtra.java'), str(CIRC.resolve()), '60000', *map(str, imagenes)],
                           capture_output=True, text=True)
        filas = [l.split('\t') for l in r.stdout.splitlines() if l.startswith('EXTRA')]
        if r.returncode or len(filas) != len(imagenes):
            sys.exit(f'Fallo la ejecucion:\n{r.stderr[-3000:]}')
        fallos = 0
        for _, img, det, ciclos, we, cambios, rst, tty in filas:
            texto, stores = emular(Path(img))
            obtenido = bytes.fromhex(tty).decode('latin1')
            err = []
            if det != 'true': err.append('no se detuvo')
            if obtenido != texto: err.append(f'TTY {obtenido!r}, esperado {texto!r}')
            if int(we) != stores: err.append(f'MEM_WE {we} ciclos, esperado {stores}')
            if cambios != '0': err.append(f'{cambios} cambios tras HALT')
            if rst != 'true': err.append('salidas incorrectas con RESET=1')
            fallos += bool(err)
            print(f'{"FALLO" if err else "OK   "} {Path(img).stem:20} {ciclos:>5} ciclos, TTY_WE={len(obtenido)}, '
                  f'MEM_WE={we}', *err, sep='\n        ' if err else '')
    print(f'\n{len(filas) - fallos}/{len(filas)} correctos')
    sys.exit(bool(fallos))


if __name__ == '__main__':
    main()
