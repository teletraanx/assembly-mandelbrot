; Abigale Tucker
; Tested with:
; nasm -felf64 mandelbrot.asm -o mandelbrot.o
; gcc -no-pie -znoexecstack mandelbrot.o -o mandelbrot
; ./mandelbrot 512 100 mandel.pgm

global main

extern atoi, fopen, fprintf, fputc, fclose

section .data
    write_mode: db "wb", 0    ; fopen mode write binary for images
    header_fmt: db "P5", 10, "%d %d", 10, "255", 10, 0    ; P5 \n <width> <height> \n 255

    real_min: dq -1.0
    real_max: dq 1.0
    imag_min: dq -1.0
    imag_max: dq 1.0
    two:      dq 2.0
    escape4:  dq 4.0

section .text

main:
    ; preserving callee-saved registers
    ; will be using r12-r15 because they survive function calls 
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; main(int argc, char **argv)
    ; sub rsp, 24    ; 16 byte alignment and stack space ; nevermind I think stack is aligned after those 5 pushes

    ; argv[0] = program, argv[1] = image size, argv[2] = iterations, argv[3] = output file path 
    cmp rdi, 4
    jl .bad_args

    mov rbx, rsi    ; rbx = argv ptr

    ; size = atoi(argv[1])
    mov rdi, [rbx + 8]    ; argv[1]
    call atoi    ; convert image size ascii to int in eax
    mov r12d, eax    ; IMAGE SIZE = r12d (using rXd registers for lower 32 bits)

    ; iterations = atoi(argv[2])
    mov rdi, [rbx + 16]    ; argv[2]
    call atoi    ; iterations ascii to int in eax
    mov r14d, eax    ; ITERATIONS = r14d

    ; output path = argv[3]
    mov r13, [rbx + 24]    ; argv[3], OUTPUT PATH = r13

    ; fp = fopen(output_path, "wb")
    mov rdi, r13    ; filename
    mov rsi, write_mode    ; mode: write binary
    call fopen    ; FILE* = rax

    cmp rax, 0     ; check if null
    je .bad_args

    mov r15, rax    ; FILE* = r15

    ; fprintf(fp, "P5\n%d %d\n255\n", size, size)
    mov rdi, r15    ; FILE*
    mov rsi, header_fmt    ; format
    mov edx, r12d    ; first %d width
    mov ecx, r12d    ; second %d height
    mov eax, 0   ; for variadic functions, I'm passing no vector registers 
    call fprintf

    mov ebx, 0    ; ebx = row

.row_loop:
    cmp ebx, r12d    ; if row >= size, done
    jge .done_pixels

    mov r13d, 0    ; r13d = col

.col_loop:
    ; while col < size
    cmp r13d, r12d
    jge .next_row

    movsd xmm6, [real_max]
    subsd xmm6, [real_min]    ; xmm6 = real_max - real_min

    cvtsi2sd xmm0, r13d    ; xmm0 = (double)col
    mulsd xmm6, xmm0     ; xmm6 = col * real_range

    mov eax, r12d    ; eax = size
    dec eax
    cvtsi2sd xmm1, eax    ; xmm1 = (double)size - 1

    divsd xmm6, xmm1    ; xmm6 = col * real_range / (size-1)
    addsd xmm6, [real_min]    ; xmm6 = cr (coordinate real)

    movsd xmm7, [imag_max]
    subsd xmm7, [imag_min]    ; xmm7 = imag_max - imag_min

    cvtsi2sd xmm0, ebx    ; xmm0 = (double)row
    mulsd xmm7, xmm0    ; xmm7 = row * imag_range
    divsd xmm7, xmm1    ; xmm7 = row * imag_range / (size-1)

    movsd xmm0, [imag_max]
    subsd xmm0, xmm7    ; xmm0 = image_max - scaled_row
    movsd xmm7, xmm0    ; xmm7 = ci (coordinate imaginary)

    ; Mandelbrot iteration
    ; z starts at 0 + 0i
    ; c is cr + ci*i
    ; zr_next = zr*zr - zi*zi + cr
    ; zi_next = 2*zr*zi + ci
    ; If zr*zr + zi*zi > 4, the point escaped. (Instead of using square root)
    ; Escaped = white
    ; Never escaped after max iterations = black

    pxor xmm2, xmm2    ; packed xor, zr = 0.0, didn't want to define 0.0 const
    pxor xmm3, xmm3    ; zi = 0.0

    mov r10d, r14d    ; r10d = remaining iterations

.mandel_loop:
    cmp r10d, 0
    jle .not_escaped

    ; zr_next = zr*zr - zi*zi + cr
    movsd xmm4, xmm2    ; xmm4 = zr
    mulsd xmm4, xmm2    ; xmm4 = zr*zr

    movsd xmm5, xmm3
    mulsd xmm5, xmm3    ; xmm5 = zi*zi

    subsd xmm4, xmm5    ; xmm4 = zr*zr - zi*zi
    addsd xmm4, xmm6    ; xmm4 = zr_next = + cr

    ; zi_next = 2*zr*zi + ci
    movsd xmm5, xmm2
    mulsd xmm5, xmm3    ; xmm5 = zr*zi
    mulsd xmm5, [two]    ; *2
    addsd xmm5, xmm7    ; xmm5 = zi_next = +ci

    ; updating with new values
    movsd xmm2, xmm4    ; xmm2 = new zr 
    movsd xmm3, xmm5    ; xmm3 = new zi

    ; escape check
    ; if zr*zr + zi*zi > 4.0, escaped
    movsd xmm0, xmm2    ; xmm0 = zr
    mulsd xmm0, xmm2    ; zr*zr

    movsd xmm1, xmm3
    mulsd xmm1, xmm3    ; zi*zi

    addsd xmm0, xmm1    ; xmm0 = zr*zr + zi*zi

    comisd xmm0, [escape4]    ; compare mag squared to 4.0
    ja .escaped    ; if above, it escaped

    dec r10d    ; not escaped yet, try another iteration
    jmp .mandel_loop

.not_escaped:
    ; if this label is reached, point never escaped during iterations
    mov eax, 0    ; black
    jmp .write_pixel

.escaped:
    mov eax, 255    ; white

.write_pixel:
    mov edi, eax
    mov rsi, r15
    call fputc

    inc r13d
    jmp .col_loop

.next_row:
    inc ebx
    jmp .row_loop

.done_pixels:
    mov rdi, r15
    call fclose

    mov eax, 0
    jmp .clean

.bad_args:
    mov eax, 1

.clean:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
