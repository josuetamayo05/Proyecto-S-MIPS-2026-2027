# t1_aritmetica.asm - Prueba de las instrucciones aritmeticas y logicas
#
# Instrucciones: add, sub, and, or, slt, slti, sll, srl, addi, addu, addiu,
#                andi, ori, lui, jal, jr, syscall
# Casos de la Tabla 1 que cubre:
#   - add, sub: operandos positivos y con un operando negativo        (linea 1)
#   - and, or: operandos con unos en los 16 bits altos                (linea 2)
#   - lui: inmediato con bit 15 = 1 (0x8001)                          (linea 2)
#   - andi, ori: inmediato con bit 15 = 1 (extension con ceros)       (linea 2)
#   - slt, slti: resultado 1 y resultado 0; con operando negativo en
#     el que con signo y sin signo dan distinto (-300 < 1000, 1000 < -1) (linea 3)
#   - addi: inmediato negativo                                        (linea 3)
#   - sll, srl: shamt = 0 y shamt != 0; srl sobre negativo            (linea 4)
#   - addiu, addu: mediante li (-32768 y 32767) y move                (linea 5)
#
# Salida esperada (5 lineas, cada valor en hexadecimal):
#   000004D2 000002BC 000002FE 00000216 FFFFFAEC
#   F000F000 FFF0FFF0 80010000 00008421 00008000
#   00000001 00000000 00000001 00000000 FFFFFFFF
#   F0F0FF00 0F0FF000 F0F0FF00 00F0F0FF 0000000F
#   FFFF8000 00007FFF FFFF8000 00008000

        .text
main:
        # ---------- linea 1: add y sub ----------
        li   $s0, 1000              # addiu
        li   $s1, 234
        li   $s2, -300              # negativo
        add  $a1, $s0, $s1          # 1000 + 234 = 1234
        jal  phex
        add  $a1, $s0, $s2          # 1000 + (-300) = 700
        jal  phex
        sub  $a1, $s0, $s1          # 1000 - 234 = 766
        jal  phex
        sub  $a1, $s1, $s2          # 234 - (-300) = 534
        jal  phex
        sub  $a1, $s2, $s0          # -300 - 1000 = -1300
        jal  phex
        jal  nl

        # ---------- linea 2: and, or, lui, ori, andi ----------
        li   $s3, 0xF0F0FF00        # lui + ori
        li   $s4, 0xFF00F0F0
        and  $a1, $s3, $s4          # F000F000
        jal  phex
        or   $a1, $s3, $s4          # FFF0FFF0
        jal  phex
        lui  $a1, 0x8001            # 80010000
        jal  phex
        ori  $a1, $zero, 0x8421     # 00008421 (no FFFF8421)
        jal  phex
        andi $a1, $s4, 0x8F0F       # F0F0 & 8F0F = 00008000
        jal  phex
        jal  nl

        # ---------- linea 3: slt, slti, addi ----------
        slt  $a1, $s2, $s0          # -300 < 1000 -> 1 (sin signo daria 0)
        jal  phex
        slt  $a1, $s0, $s2          # 1000 < -300 -> 0
        jal  phex
        slti $a1, $s2, -299         # -300 < -299 -> 1
        jal  phex
        slti $a1, $s0, -1           # 1000 < -1 -> 0 (sin signo daria 1)
        jal  phex
        addi $a1, $s0, -1001        # 1000 - 1001 = -1
        jal  phex
        jal  nl

        # ---------- linea 4: sll y srl ----------
        sll  $a1, $s3, 0            # shamt = 0
        jal  phex
        sll  $a1, $s3, 4            # 0F0FF000
        jal  phex
        srl  $a1, $s3, 0            # shamt = 0
        jal  phex
        srl  $a1, $s3, 8            # valor negativo: entran ceros -> 00F0F0FF
        jal  phex
        srl  $a1, $s2, 28           # FFFFFED4 >> 28 = 0000000F
        jal  phex
        jal  nl

        # ---------- linea 5: li (addiu) y move (addu) ----------
        li   $t0, -32768            # addiu $t0, $zero, -32768
        move $a1, $t0               # addu
        jal  phex
        li   $t1, 32767
        move $a1, $t1
        jal  phex
        move $t2, $t0               # addu de nuevo
        move $a1, $t2
        jal  phex
        addiu $a1, $t1, 1           # 32767 + 1 = 0x8000
        jal  phex
        jal  nl

        li   $v0, 10                # fin del programa
        syscall

# ------------------------------------------------------------
# phex: imprime $a1 en hexadecimal (8 cifras) y un espacio.
# Modifica $a0, $a1, $v0, $t8, $t9.
phex:   li   $t8, 8
ph_lp:  srl  $a0, $a1, 28           # cifra mas significativa
        slti $t9, $a0, 10
        bne  $t9, $zero, ph_num
        addi $a0, $a0, 55           # 10..15 -> 'A'..'F'
        j    ph_out
ph_num: addi $a0, $a0, 48           # 0..9 -> '0'..'9'
ph_out: li   $v0, 11
        syscall
        sll  $a1, $a1, 4
        addi $t8, $t8, -1
        bne  $t8, $zero, ph_lp
        li   $a0, 32                # espacio
        li   $v0, 11
        syscall
        jr   $ra

# nl: imprime un salto de linea. Modifica $a0 y $v0.
nl:     li   $a0, 10
        li   $v0, 11
        syscall
        jr   $ra
