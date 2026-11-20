# t2_memoria.asm - Prueba de los accesos a memoria
#
# Instrucciones: lw, sw, lb, lbu, sb, addi, lui, ori (la), jal, jr, syscall
# Casos de la Tabla 1 que cubre:
#   - lw, sw: desplazamiento positivo y desplazamiento negativo       (linea 1)
#   - lb, lbu: bytes con bit 7 = 1 en distintas posiciones de la
#     palabra (d[1:0] = 0, 2 y 3) y un byte positivo de control       (linea 2)
#   - sb: en las cuatro posiciones de una misma palabra
#     (d[1:0] = 0, 1, 2, 3), comprobando con lw despues de cada sb
#     que los otros bytes no cambiaron                                (linea 3)
#
# Salida esperada (3 lineas):
#   33333333 CAFE0001 22222222 BEEF0002 11111111
#   FFFFFF92 FFFFFFF1 00000092 00000080 0000007F
#   556677A0 5566B1A0 55C2B1A0 D3C2B1A0 000000C2

        .data
arr:    .word 0x11111111, 0x22222222, 0x33333333, 0x44444444
bytes:  .word 0x80F17F92            # byte0=92 byte1=7F byte2=F1 byte3=80
buf:    .word 0x55667788

        .text
main:
        # ---------- linea 1: lw y sw ----------
        la   $s0, arr
        lw   $a1, 8($s0)            # desplazamiento positivo -> arr[2]
        jal  phex
        li   $t0, 0xCAFE0001
        sw   $t0, 12($s0)           # arr[3] = CAFE0001
        lw   $a1, 12($s0)
        jal  phex
        addi $s1, $s0, 12           # $s1 apunta a arr[3]
        lw   $a1, -8($s1)           # desplazamiento negativo -> arr[1]
        jal  phex
        li   $t1, 0xBEEF0002
        sw   $t1, -12($s1)          # arr[0] = BEEF0002
        lw   $a1, 0($s0)
        jal  phex
        lw   $a1, 4($s0)            # arr[1] sigue igual
        lui  $t2, 0x1111
        ori  $t2, $t2, 0x1111
        sub  $a1, $a1, $t2          # 22222222 - 11111111 = 11111111
        jal  phex
        jal  nl

        # ---------- linea 2: lb y lbu ----------
        la   $s2, bytes
        lb   $a1, 0($s2)            # 92 -> FFFFFF92
        jal  phex
        lb   $a1, 2($s2)            # F1 -> FFFFFFF1
        jal  phex
        lbu  $a1, 0($s2)            # 92 -> 00000092
        jal  phex
        lbu  $a1, 3($s2)            # 80 -> 00000080
        jal  phex
        lb   $a1, 1($s2)            # 7F -> 0000007F (positivo)
        jal  phex
        jal  nl

        # ---------- linea 3: sb en las 4 posiciones ----------
        la   $s3, buf               # buf = 55667788
        li   $t0, 0x123456A0        # solo debe escribirse el byte bajo
        sb   $t0, 0($s3)
        lw   $a1, 0($s3)            # 556677A0
        jal  phex
        li   $t0, 0xB1
        sb   $t0, 1($s3)
        lw   $a1, 0($s3)            # 5566B1A0
        jal  phex
        li   $t0, 0xC2
        sb   $t0, 2($s3)
        lw   $a1, 0($s3)            # 55C2B1A0
        jal  phex
        li   $t0, 0xD3
        sb   $t0, 3($s3)
        lw   $a1, 0($s3)            # D3C2B1A0
        jal  phex
        lbu  $a1, 2($s3)            # se relee un byte escrito con sb
        jal  phex
        jal  nl

        li   $v0, 10
        syscall

# ------------------------------------------------------------
# phex: imprime $a1 en hexadecimal (8 cifras) y un espacio.
# Modifica $a0, $a1, $v0, $t8, $t9.
phex:   li   $t8, 8
ph_lp:  srl  $a0, $a1, 28
        slti $t9, $a0, 10
        bne  $t9, $zero, ph_num
        addi $a0, $a0, 55
        j    ph_out
ph_num: addi $a0, $a0, 48
ph_out: li   $v0, 11
        syscall
        sll  $a1, $a1, 4
        addi $t8, $t8, -1
        bne  $t8, $zero, ph_lp
        li   $a0, 32
        li   $v0, 11
        syscall
        jr   $ra

# nl: imprime un salto de linea. Modifica $a0 y $v0.
nl:     li   $a0, 10
        li   $v0, 11
        syscall
        jr   $ra
