extern debug

section .bss
    alignb 8
    access:     resb N+1            ; token array for synchronization, takes values:
                                    ; 0 - no content is on wait_for and content yet
                                    ; 1 - I content on those 2 arrays and I am ready for synchronization
                                    ; 2 - I am during synchronization
                                    ; 3 - I have ended synchronization, now I can set myself to 0 again
    wait_for:   resq N+1            ; in this array natisses tell who they are waiting for after W command 
    content:    resq N+1            ; in this array natisses share their content of the top of the stack during synchronization


; Macro which allows natisses to synchronize, takes one
; argument, equal to number of natisse we need to synchronize with
%macro sync_with 1
    mov     r9, %1                  ; Natisse number will be stored on r9
    inc     r9                      ; I increase both values by one, because natisses numeration
    inc     r12                     ; starts from 0, so I want for value 0 to be neutral on array wait_for

    pop     r10                     ; I take the value I want to exchange

    mov     rax, content            ; I place on my index on content array this value
    xchg    qword [rax+8*r12], r10

    
    mov     rax, wait_for           ; On my index on wait_for array I tell that I am waiting for other natisse
    mov     r10, r9
    xchg    qword [rax+8*r12], r10


    mov     r13, access             ; All is set up and ready, I can sygnalize that on access array
    mov     al, 1
    xchg    byte [r13+r12], al


    mov     dil, 2
%%try_access:                       ; I try to exchange 3 for 1, to get exclusive access to the natisse I want to synchronize with
    mov     al, 1
    lock    \
    cmpxchg byte [r13+r9], dil
    jne     %%try_access

    mov     rax, wait_for           ; If natisse I want to synchronize with is waiting for me then I jump to %%try_comm...
    cmp     qword [rax+8*r9], r12
    je      %%try_comm

    mov     al, 1                   ; ... otherwise I give away token to fight for it once again
    xchg    byte [r13+r9], al
    jmp     %%try_access
    
    
%%try_comm:
    mov     r10, content            ; I place on rax the value I want to push on my stack
    mov     rax, 0
    xchg    rax, qword [r10+8*r9]

    push    rax                     ; I push it

    mov     al, 3                   ; I set that r9 (the natisse I just synchronized with) have ended synchronization
    xchg    byte [r13+r9], al

    mov     dil, 0
%%try_again:                        ; Now I wait for r9 to give me token that it also ended synchronization
    mov     al, 3
    lock    \
    cmpxchg byte [r13+r12], dil
    jne     %%try_again

    dec     r12                     ; I have increased my value by 1, now I need to decrease it once again

    go_next 0                       ; That's it! We can go to the next command!

%endmacro

; Reducing code macro
; places on r15 (input mode register), given argument
; and jumps to next command
%macro go_next 1
    mov     r15, %1
    jmp     next_command
%endmacro

section .text
    global  notec

; r12 - natissis number
; r14 - current character
; r15 - if function is in input mode
align 8
notec:

    ; I am saving these registers for function to be ABI compatible
    push    rsp
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r15, 0                  ; By default function isn't in input mode
    mov     r12, rdi                ; Natissis number is passed as first argument of the function
    lea     r14, [rsi]              ; String of instructions is passed as second argument

    mov     rbx, rsp                ; I save current rsp to restore it at the end of function

next_command:
    movzx   rax, byte [r14]         ; On rax is current character (operation)
    inc     r14                     ; r14 is now pointing at next character

    cmp     rax, 0                  ; If rax == 0 then it is the end of the string, time to end the function!
    je      done

    cmp     rax, '='                ; Quit input mode
    je      break_input

    cmp     rax, '+'                ; Sum of two top numbers
    je      sum

    cmp     rax, '*'                ; Multiplication of two top numbers
    je      multiply 

    cmp     rax, '-'                ; Arithmetic negation of top number
    je      arith_neg

    cmp     rax, '&'                ; Perform AND operation on two top numbers
    je      do_and

    cmp     rax, '|'                ; Perform OR operation on two top numbers
    je      do_or

    cmp     rax, '^'                ; Perform XOR operation on two top numbers
    je      do_xor

    cmp     rax, '~'                ; Perform binary negation on top number
    je      bin_neg

    cmp     rax, 'Z'                ; Delete top number
    je      del_top

    cmp     rax, 'Y'                ; Duplicate top number
    je      dup_top

    cmp     rax, 'X'                ; Two top numbers switch places
    je      xchg_top

    cmp     rax, 'N'                ; Push amount of natissis on stack
    je      push_natissis

    cmp     rax, 'n'                ; Push number of this natissis on stack
    je      push_my_number

    cmp     rax, 'g'                ; Call debug function
    je      call_debug

    cmp     rax, 'W'                ; Synchronize with top number and switch their top numbers
    je      sync_two

    ; Assuming the input is correct only commands left are those making a hexadecimal number 

    cmp     rax, '9'                ; Check if it is a number
    jle concat_num

    cmp     rax, 'F'                ; Check if it is a big character
    jle concat_char

    sub     rax, 32                 ; If it isn't a number nor big character it must be small character, so make it big!
    jmp concat_char

break_input:
    go_next 0

sum:
    pop     r10                     ; Take top two numbers from the stack and add them
    pop     r11
    add     r10, r11
    push    r10                     ; Then push their sum to the stack
    
    go_next 0

multiply:
    pop     r10                     ; Take top two numbers from the stack and multiply them
    pop     r11
    imul    r10, r11
    push    r10                     ; Then push answer to the stack

    go_next 0

arith_neg:
    pop     r10                         ; Take top number from the stack then perform (2^64-1) - number
    mov     r11, 18446744073709551615   ; This operation will be equal to arithmetic negation modulo 2^64
    sub     r11, r10
    inc     r11                         ; We lose 1 performing this, so we need to add 1!
    push    r11                         ; Push answer to the stack

    go_next 0

do_and:
    pop     r10                     ; Take top two numbers from the stack and AND them
    pop     r11
    and     r10, r11
    
    push    r10                     ; Then push answer to the stack

    go_next 0

do_or:
    pop     r10                     ; Take top two numbers from the stack and OR them
    pop     r11
    or      r10, r11

    push    r10                     ; Then push answer to the stack

    go_next 0

do_xor:
    pop     r10                     ; Take top two numbers from the stack and XOR them
    pop     r11
    xor     r10, r11

    push    r10                     ; Then push answer to the stack

    go_next 0

bin_neg:
    pop     r10                     ; Take top number and NOT it to perform binary negation
    not     r10

    push    r10                     ; Then push answer to the stack

    go_next 0

del_top:
    pop     r10                     ; Pop top number to make it disappear

    go_next 0

dup_top:
    pop     r10                     ; Take top number and push it twice to make it duplicated!
    push    r10
    push    r10

    go_next 0

xchg_top:
    pop     r10                     ; Take two top numbers...
    pop     r11

    push    r10                     ; ... and push them in reverse order!
    push    r11

    go_next 0

push_natissis:
    push    N                       ; Push N onto the stack!

    go_next 0

push_my_number:
    push    r12                     ; Push my natissis number onto the stack

    go_next 0

call_debug:
    mov     rax, rsp                ; Move rsp to the rax and divide it by 16
    mov     r10, 16
    mov     rdx, 0
    div     r10

    cmp     rdx, 0                  ; If rsp mod 16 == 8 then we need to add dummy number to the stack to be ABI friendly :)
    jne     add_dummy

    ; This part is executed when we don't need to add dummy number
    mov     rdi, r12                ; We move our natissis number as first argument
    mov     rsi, rsp                ; We move our stack pointer as second one

    call    debug

    imul    rax, 8                  ; On rax we get by how much we need to move the stack pointer
                                    ; We multiply it by 8, because each push/pop adds or subtracts 8 from the stack
    add     rsp, rax                ; And we add it, and that's it, we can go to the next operation!
    
    go_next 0

add_dummy:
    mov     r13, rsp                ; We add dummy number by subtracting 8 from rsp
    sub     rsp, 8

    mov     rdi, r12                ; We move our natissis number as first argument
    mov     rsi, r13                ; As second argument we move our old rsp (without the dummy number)
                                    ; By performing this we stay ABI friendly and also the debug function 
                                    ; gets pointer to valid 'top' of the stack

    call    debug

    add     rsp, 8                  ; We take off dummy number from our stack
    imul    rax, 8                  ; Same as without dummy number situation we move rsp by rax
    add     rsp, rax

    go_next 0

sync_two:
    pop     r10                     ; Take top number to know with which natissis I shoud synchronize
    sync_with r10                   ; Perform synchronization and exchange

concat_num:
    sub     rax, '0'                ; Rax is a char digit so we need to subtract '0' from it to be real digit

    cmp     r15, 0                  ; If we weren't in input mode then that's it, we push number and go to next command
    je      dont_pop

    ; If we were in input mode already:
    pop     r10                     ; On top of the stack is the number I want to concatenate with
    imul    r10, 16                 ; I add space for this digit by multiplying it by 16
    add     r10, rax                ; All is left to do is add this digit..
    push    r10                     ; ..and push it onto the stack

    go_next 1                       ; Argument to go_next is equal to 1 because we are in input mode

concat_char:
    sub     rax, 'A'                ; To change from character to a number I subtract 'A' from character
    add     rax, 10                 ; And increace this number by 10, because 'A' = 10

    cmp     r15, 0                  ; If we weren't in input mode then that's it, we push number and go to next command
    je      dont_pop

    ; If we were in input mode already:
    pop     r10                     ; On top of the stack is the number I want to concatenate with
    imul    r10, 16                 ; I add space for this digit by multiplying it by 16
    add     r10, rax                ; All is left to do is add this digit..
    push    r10                     ; ..and push it onto the stack

    go_next 1                       ; Argument to go_next is equal to 1 because we are in input mode

dont_pop:
    push    rax                     ; I add rax to the stack

    go_next 1                       ; Argument to go_next is equal to 1 because we are in input mode

done:
    pop     rax                     ; Output of this function is top number of the stack, we place it on rax

    mov rsp, rbx                    ; I clear rest of the stack

    ; I restore registers for them to be equal to the ones before call to this function
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    pop     rsp

    ret