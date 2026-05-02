global main

extern atoi, fopen, fprintf, fputc, fclose

section .data
    write_mode: db "wb", 0    ; fopen mode write binary for images
    header_fmt: db "P5", 10, "%d %d", 10, "255", 10, 0    ; P5 \n <width> <height> \n 255

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
    ; holding off on iterations for now

    ; output file path 
    mov r14, [rbx + 24]    ; argv[3], OUTPUT PATH = r14

    ; FILE* fp = fopen(path, "wb")
    mov rdi, r14    ; filename
    mov rsi, write_mode    ; mode: write binary
    call fopen    ; FILE* = rax

    cmp rax, 0     ; check if null
    je .bad_args

    mov r15, rax    ; FILE* = r15

    ; fprintf(fp, header_fmt, size, size)
    mov rdi, r15    ; FILE*
    mov rsi, header_fmt    ; format 
    mov edx, r12d    ; first %d width
    mov ecx, r12d    ; second %d height
    mov eax, 0    ; for variadic functions, I'm passing no vector registers 
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

    ; color = (row + col) % 256
    mov eax, ebx        ; eax = row
    add eax, r13d       ; eax = row + col
    and eax, 255        ; keep only 0-255

    ; fputc(color, fp)
    mov edi, eax
    mov rsi, r15
    call fputc

    inc r13d    ; col++
    jmp .col_loop

.next_row: 
    inc ebx    ; row++
    jmp .row_loop

.done_pixels:
    mov rdi, r15    ; FILE*
    call fclose

    mov eax, 0
    jmp .clean

.bad_args:
    mov eax, 1    ; return error

.clean:
    ; add rsp, 24

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx 

    ret