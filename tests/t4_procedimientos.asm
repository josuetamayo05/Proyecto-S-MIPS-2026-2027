# t4_procedimientos.asm - Prueba de procedimientos, pila, $zero y syscall
#
# Instrucciones: jal, jr, sw, lw, addi, add, slti, beq, addu (move),
#                addiu (li), syscall
# Casos de la Tabla 1 que cubre:
#   - jal, jr: procedimientos que llaman a otros (no hoja): fact es
#     recursivo y llama a mul; sumcuad llama a mul. Ambos guardan
#     $ra (y $s0, $s1) en la pila y retornan correctamente.
#   - $zero: se escribe en $zero con addi, add y addu y despues se
#     comprueba que sigue valiendo 0.
#   - syscall: servicio 11 (imprimir caracter) en todo el programa y
#     servicio 10 (terminar) al final.
#
# Salida esperada (2 lineas):
#   00000078 0000001E 00001234 00003FFC
#   00000000 OK

        .text
main:
        # ---------- linea 1: procedimientos ----------
        li   $s0, 0x1234            # sumcuad debe conservar $s0
        li   $a0, 5
        jal  fact                   # fact(5) = 120 = 0x78
        move $a1, $v0
        jal  phex
        li   $a0, 4
        jal  sumcuad                # 1 + 4 + 9 + 16 = 30 = 0x1E
        move $a1, $v0
        jal  phex
        move $a1, $s0               # sigue valiendo 0x1234
        jal  phex
        move $a1, $sp               # la pila quedo equilibrada: 0x3FFC
        jal  phex
        jal  nl

        # ---------- linea 2: escrituras en $zero ----------
        addi $zero, $zero, 77
        add  $zero, $s0, $s0
        addu $zero, $s0, $s0
        move $a1, $zero             # debe imprimir 00000000
        jal  phex
        li   $a0, 'O'
        li   $v0, 11
        syscall
        li   $a0, 'K'
        li   $v0, 11
        syscall
        jal  nl

        li   $v0, 10                # syscall 10: fin
        syscall

# ------------------------------------------------------------
# fact: $v0 = $a0! (recursivo, no hoja)
fact:   slti $t0, $a0, 2
        beq  $t0, $zero, f_rec
        li   $v0, 1                 # caso base: 0! = 1! = 1
        jr   $ra
f_rec:  addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $a0, 0($sp)
        addi $a0, $a0, -1
        jal  fact                   # $v0 = (n-1)!
        lw   $a0, 0($sp)            # recupera n
        move $a1, $v0
        jal  mul                    # $v0 = n * (n-1)!
        lw   $ra, 4($sp)
        addi $sp, $sp, 8
        jr   $ra

# sumcuad: $v0 = 1^2 + 2^2 + ... + $a0^2 (no hoja, conserva $s0 y $s1)
sumcuad:
        addi $sp, $sp, -12
        sw   $ra, 8($sp)
        sw   $s0, 4($sp)
        sw   $s1, 0($sp)
        move $s0, $a0               # i = n
        li   $s1, 0                 # acumulador
sc_lp:  beq  $s0, $zero, sc_fin
        move $a0, $s0
        move $a1, $s0
        jal  mul                    # $v0 = i * i
        add  $s1, $s1, $v0
        addi $s0, $s0, -1
        j    sc_lp
sc_fin: move $v0, $s1
        lw   $s1, 0($sp)
        lw   $s0, 4($sp)
        lw   $ra, 8($sp)
        addi $sp, $sp, 12
        jr   $ra

# mul: $v0 = $a0 * $a1 con sumas sucesivas ($a1 >= 0). Procedimiento hoja.
mul:    li   $v0, 0
m_lp:   beq  $a1, $zero, m_fin
        add  $v0, $v0, $a0
        addi $a1, $a1, -1
        j    m_lp
m_fin:  jr   $ra

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
