# t3_saltos.asm - Prueba de los saltos condicionales e incondicionales
#
# Instrucciones: beq, bne, j, add, addi, slt, sll, ori, jal, jr, syscall
# Casos de la Tabla 1 que cubre:
#   - beq: tomado y no tomado; tomado hacia atras (bucle de la linea 3)
#   - bne: tomado y no tomado; tomado hacia atras (bucle de la linea 2)
#   - j: hacia adelante (salta una instruccion) y hacia atras (bucle)
#
# Cada salto marca un bit en $s0; las instrucciones que NO deben
# ejecutarse ponen bits de error (01, 08, 40). Resultado esperado:
#   $s0 = 02 | 04 | 10 | 20 | 80 = 0x000000B6
#
# Salida esperada (3 lineas):
#   000000B6
#   00000037 00000000
#   00000010 00000004 00000006

        .text
main:
        # ---------- linea 1: un caso de cada salto ----------
        li   $s0, 0
        li   $t0, 5
        li   $t1, 5
        beq  $t0, $t1, b1           # TOMADO (5 == 5)
        ori  $s0, $s0, 0x01         # no debe ejecutarse
b1:     ori  $s0, $s0, 0x02
        li   $t1, 6
        beq  $t0, $t1, b2           # NO tomado (5 != 6)
        ori  $s0, $s0, 0x04         # si se ejecuta
b2:     bne  $t0, $t1, b3           # TOMADO (5 != 6)
        ori  $s0, $s0, 0x08         # no debe ejecutarse
b3:     ori  $s0, $s0, 0x10
        bne  $t0, $t0, b4           # NO tomado
        ori  $s0, $s0, 0x20         # si se ejecuta
b4:     j    b5                     # j hacia adelante
        ori  $s0, $s0, 0x40         # no debe ejecutarse
b5:     ori  $s0, $s0, 0x80
        move $a1, $s0
        jal  phex
        jal  nl

        # ---------- linea 2: bne hacia atras ----------
        # suma 10 + 9 + ... + 1 = 55 = 0x37
        li   $t0, 10
        li   $s1, 0
lp1:    add  $s1, $s1, $t0
        addi $t0, $t0, -1
        bne  $t0, $zero, lp1        # TOMADO hacia atras 9 veces
        move $a1, $s1
        jal  phex
        move $a1, $t0               # el contador termina en 0
        jal  phex
        jal  nl

        # ---------- linea 3: beq hacia atras y j hacia atras ----------
        # duplica $s2 mientras $t2 < 4  ->  1 << 4 = 0x10
        li   $s2, 1
        li   $t2, 0
        li   $t3, 4
        li   $t5, 1
lp2:    sll  $s2, $s2, 1
        addi $t2, $t2, 1
        slt  $t4, $t2, $t3
        beq  $t4, $t5, lp2          # TOMADO hacia atras mientras $t2 < 4
        move $a1, $s2
        jal  phex
        move $a1, $t2
        jal  phex
        # cuenta las vueltas de un bucle hecho con j hacia atras
        li   $t6, 0
lp3:    addi $t6, $t6, 1
        slti $t7, $t6, 6
        beq  $t7, $zero, fin3       # sale cuando $t6 = 6
        j    lp3                    # j hacia atras
fin3:   move $a1, $t6
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
