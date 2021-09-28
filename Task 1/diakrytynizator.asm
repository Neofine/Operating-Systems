SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60

STDIN equ 0
STDOUT equ 1

MODULO equ 1113984                      ; Constant, the number I modulo by

BUF_SIZE equ 1024                       ; Constant, size of input and output buffers

section .bss
        buffer resb BUF_SIZE            ; Array storing BUF_SIZE characters read on input
        printBuffer resb BUF_SIZE+4     ; Array storing BUF_SIZE+4 characters to be printed on output
        printIt  resb 2                 ; Iterator (printBuffer + printIt) pointing at least not
                                        ; occupied place on printBuffer
        stackEnd resb 8                 ; Pointer to an element at the bottom of the stack
        len      resb 2                 ; Amount of characters on input buffer, can be less than BUF_SIZE
        it       resb 2                 ; Points (buffer+it) at character on input buffer which has
                                        ; not been read yet
        end_flag resb 1                 ; Is set to 1 if there is no more input to be read, 0 otherwise

; Ends programme with code 0 - success
%macro exit 0
        print_buffer_out

        mov     rax, SYS_EXIT
        mov     rdi, 0
        syscall
%endmacro

; Ends programme with code 1 - error
%macro error_exit 0
        print_buffer_out

        mov     rax, SYS_EXIT
        mov     rdi, 1
        syscall
%endmacro

; Reads input on buffer and sets certain variables from .bss
%macro get_part_input 0
        mov     rax, SYS_READ               ; Reads BUF_SIZE of characters on buffer
        mov     rdi, STDIN
        mov     rsi, buffer
        mov     rdx, BUF_SIZE
        syscall

        mov     word [it], 0                ; Character number 0 has not been read yet
        mov     word [len], ax              ; Amount of characters read is ax
        mov     byte [end_flag], 0          ; Temporarly sets end_flag to 0, it can change later

        cmp     rax, BUF_SIZE               ; If amount of read characters == BUF_SIZE then end macro
        je      %%end

        mov     byte [end_flag], 1          ; Amount of characters read is less than BUF_SIZE
                                            ; so end_flag is set to TRUE
%%end:

%endmacro

; Prints printBuffer out and sets printIt to 0
%macro print_buffer_out 0
        mov     rax, SYS_WRITE              ; Prints printBuffer out
        mov     rdi, STDOUT
        mov     rsi, printBuffer
        movzx   rdx, word [printIt]
        syscall

        mov     word [printIt], 0           ; Least not occupied place on printBuffer is at index 0

%endmacro

; Changes string (from polynomial) to numer and stores it in rax register
%macro to_number 1
        mov     r11, 0                     ; Final number
        mov     r10, %1                    ; Pointer to the first element of string
        mov     r12, MODULO                ; Sets r12 to modulo which I will apply to every
                                           ; polynomial word

%%convert:
        movzx   rsi, byte [r10]            ; Reads current string element
        cmp     rsi, 0                     ; If it is 0 then it's the end of the string
        je      %%end
        sub     rsi, '0'                   ; To change character to number we need to subtract
                                           ; '0' from it

        ; If this number isn't in interval of [0, 9] then it's not a number - abort
        cmp     rsi, 0
        jl      _abort

        cmp     rsi, 9
        jg      _abort

        imul    r11, 10                    ; Adds current number to those processed
        add     r11, rsi

        mov     rax, r11                   ; Calculate modulo of current number
        mov     rdx, 0
        div     r12
        mov     r11, rdx

        inc     r10                        ; Increases pointer of a string
        jmp     %%convert

%%end:
        mov     rax, r11                   ; Answer is on rax

%endmacro


; Reads byte by byte UTF-8 characters and sets decimal equivalent on rax
;
; Arguments:
; - First UTF-8 number in rax
; - Number of bytes of UTF-8 character
; - How much to subtract from first numer to get a valid decimal number
%macro get_xbyte 2
        mov     r9, rax
        sub     r9, %2                  ; This is a first number in UTF-8 so it has UTF-8 specifix
                                        ; prefix so I subtract it to get decimal number
        mov     r10b, %1                ; How much loops I will do in %%get_next
        dec     r10b

%%get_next:                             ; This is a loop to read every UTF-8 byte of this character
        inc     word [it]

        mov     ax, word [it]           ; If I read every character in buffer I need to reload it
        cmp     ax, word [len]
        je      %%reload

        mov     rax, buffer             ; Gets next character...
        movzx   r11, word [it]
        add     rax, r11                ; ... And sets it on rax

        ; If it isn't in interval of [128, 191] then is also isn't valid UTF-8 character
        cmp     byte [rax], 128
        jl      _abort

        cmp     byte [rax], 191
        jg      _abort

        sub     byte [rax], 128         ; This number looks like 10xxxxxx, so I subtract 10000000
                                        ; to get valid number in decimal

        shl     r9, 6                   ; I multiply current value by 2^6 to have place to add rax to it

        movzx   rax, byte [rax]
        add     r9, rax

        dec     r10b

        cmp     r10b, 0                 ; I end when I read every byte declared in argument
        jne     %%get_next


        jmp     %%end

%%reload:                                ; Reloads input buffer
        cmp byte [end_flag], 1           ; If end_flag is TRUE then there is no more input - error
        je      _abort

        get_part_input                   ; Loads input

        dec     word [it]                ; Decreases iterator, because in next step we jump to
                                         ; %%get_next which will increase it once again

        jmp     %%get_next

%%end:
        mov     rax, r9                   ; Output is on rax

%endmacro

; Given decimal it calculates (w(%1 - 128) % 1113984) + 128 and places it on rax register
%macro poly_change 1
        mov     r11, 0              ; On r11 I temporarly store answer
        mov     r12, %1
        sub     r12, 128            ; On r12 I store polynomial x = %1 - 128
        mov     rsi, 1              ; Rsi - x ^ k where k increases every loop
        mov     r10, rsp            ; R10 - pointer to subsequent polynomial elements
        mov     r13, MODULO         ; MODULO = 1113984
%%next_coef:
        mov     r8, rsi             ; r8 - temporal variable to calculate answer
        imul    r8, [r10]           ; r8 = x ^ k * w_k
        add     r11, r8
        imul    rsi, r12            ; Updates rsi to be new x ^ (k+1)

        mov     rax, rsi            ; I modulo x ^ (k+1) to be (x ^ (k+1)) % MODULO
        mov     rdx, 0
        div     r13
        mov     rsi, rdx

        mov     rax, r11            ; I modulo current value
        mov     rdx, 0
        div     r13
        mov     r11, rdx

        add     r10, 8              ; Jumps to next polynomial element

        cmp     r10, [stackEnd]     ; If r10 still points at polynomial then I loop
        jle     %%next_coef

        mov     rax, r11            ; I calculate modulo
        mov     rdx, 0
        div     r13
        mov     rax, rdx
        add     rax, 128            ; rax = (w(%1 - 128) % 1113984) + 128
%endmacro

; Given decimal value to print it changes it to UTF-8 and adds to printBuffer
%macro print_out 1
        mov     rax, %1             ; On rax I store decimal value

        cmp     rax, 128            ; If rax is ascii then I don't apply polynomial on it
        jb      %%to_print

        poly_change rax             ; I apply polynomial if number isn't in ascii

%%to_print:

        mov     r9, rax

        cmp     r9, 128             ; If it is in ascii
        jb      %%ascii_out

        cmp     r9, 2048            ; If it is a 2 byte UTF-8 character
        jb      %%byte_2out

        cmp     r9, 65536           ; If it is a 3 byte UTF-8 character
        jb      %%byte_3out

        jmp     %%byte_4out         ; If it is a 4 byte UTF-8 character

%%ascii_out:

        mov     rax, printBuffer            ; Calculating least not occupied index on printBuffer
        movzx   rsi, word [printIt]
        add     rax, rsi

        mov     byte [rax], r9b             ; Placing ASCII character on calculated index

        inc     word [printIt]              ; Now least occupied index is index+1

        cmp     word [printIt], BUF_SIZE    ; If I have reached end of buffer then I need to print it!
        je      %%clear_buff

        jmp     %%done                      ; Go to end of macro

%%byte_2out:
        BYTE_XOUT 2, r9, 192    ; Print out 2 byte character

        jmp     %%done          ; Go to end of macro

%%byte_3out:
        BYTE_XOUT 3, r9, 224    ; Print out 3 byte character

        jmp     %%done          ; Go to end of macro

%%byte_4out:
        BYTE_XOUT 4, r9, 240    ; Print out 4 byte character

        jmp     %%done          ; Go to end of macro

%%clear_buff:
        print_buffer_out        ; Print out buffer

%%done:

%endmacro

; Reads the input and prints is changed by polynomial
%macro get_string 0

        get_part_input                      ; Loads input on buffer

        mov     word [printIt], 0           ; Nothing is on printBuffer so printIt = 0

%%get_next:
        mov     ax, word [it]               ; If iterator is pointing on element exceeding buffer
        cmp     ax, word [len]              ; length then we need to reload the buffer
        je      %%reload

        mov     r11, buffer                 ; Calculating next not read character on input buffer
        movzx   rax, word [it]
        add     r11, rax

        mov     al, byte [r11]              ; Moving on al next character

        movzx   rax, al

        cmp     al, 128             ; Ascii character
        jb      %%skip

        cmp      al, 192            ; First character cannot start with 10xxxxxx, error!
        jb      _abort

        cmp     al, 224             ; 2 byte character
        jb      %%2byte

        cmp     al, 240             ; 3 byte character
        jb      %%3byte

        cmp     al, 248             ; 4 byte character
        jb      %%4byte

        jmp     _abort              ; Anything exceding 247 is not valid

%%skip:
        print_out rax               ; Having full character in decimal I need to polynomial
                                    ; change it and print it out

        inc     word [it]           ; Input iterator is pointing at next character
        jmp     %%get_next
%%reload:

        cmp     byte [end_flag], 1  ; If there is need to reload but it's the end of input
        je      %%end

        get_part_input              ; Load input on buffer

        jmp     %%get_next

%%end:
        exit                        ; Return 0 and print buffer

%%2byte:
	get_xbyte   2, 192	    ; Get 2 byte number and change character to decimal


	; If the decimal value of this character is less than 128
	cmp     rax, 128
	jl      _abort

	jmp     %%skip

%%3byte:
	get_xbyte   3, 224	    ; Get 3 byte number and change character to decimal

	; If the decimal value of this character is less than 2048
	cmp     rax, 2048
	jl      _abort

	jmp     %%skip
%%4byte:
	get_xbyte   4, 240	    ; Get 4 byte number and change character to decimal

	; If the decimal value of this character is not in an interval of [65536, 1114111]
	; then if it's less than 65536 it's redundant, it can be written as lesser byte number
	; if it's more then this value doesn't meet cryteria of this task
	cmp     rax, 65536
	jl      _abort

	cmp     rax, 1114111
	jg      _abort

	jmp     %%skip
%endmacro

; Adds a valid UTF-8 number to printBuffer then if the buffer is full, print it out
;
; Arguments:
; - Number of output bytes of a number
; - Number
; - Amount I need to add to the most significant byte for number to be in valid UTF-8
%macro BYTE_XOUT 3
        mov     rax, %3             ; How much I need to add
        mov     r11, %1             ; Amount of bytes in a number
        mov     rdx, %2             ; Number
        mov     rdi, 1              ; Number of loops
        mov     r14b, 128           ; How much I need to add to the rest of bytes

%%loop:
        mov     r10, rdx            ; Gets the current number
        shr     rdx, 6              ; Shifts rdx by 6 to the right, we won't need it later
        and     r10, 63             ; Performs (number & 111111_2) to get the least
                                ; significant 6 bits of a number

        movzx   rsi, word [printIt]       ; Add to the specific place of printBuffer
        add     rsi, r11                    ; current number + 128
        sub     rsi, rdi
        mov     byte [printBuffer+rsi], r10b
        add     byte [printBuffer+rsi], 128

        inc     rdi                         ; Number of loops++

        cmp     rdi, r11                    ; I loop number-of-bytes-of-a-character times
        jle     %%loop

        add     word [printIt], r11w        ; Latest unoccupied index on print
                                            ; buffer += number-of-bytes-of-a-character

        sub     al, 128                     ; I have added 128 to every number so i need to
                                            ; subtract 128 from al

        movzx   rsi, word [printIt]
        sub     rsi, r11                    ; I calculate where is first byte of a character

        add     byte [printBuffer+rsi], al  ; For it to be valid UTF-8 character I add al to
                                            ; the first byte

        cmp     word [printIt], BUF_SIZE    ; If length of printBuffer is less than BUF_SIZE then end...
        jb      %%end

        print_buffer_out                    ; ... else I print the buffer out
%%end:

%endmacro

section .text
        global _start

_start:
        cmp     word [rsp], 1
        je      _abort               ; If there is no polynomial argument then error!

        pop     rax                 ; I pop out the number of arguments of a programme
        pop     rdx                 ; I pop out name of a programme from stack

        sub     rax, 2              ; I calculate the end pointer of a stack
        imul    rax, 8
        add     rax, rsp
        mov     [stackEnd], rax

        mov     r9, rsp
_poly_loop:                     ; In this loop I change polynomial strings to actual numbers
        to_number [r9]          ; String -> number, output in rax
        mov     [r9], rax           ; This pointer no longer points at string, it's number now!

        add     r9, 8

        cmp     r9, [stackEnd]      ; Exit when I don't point at stack anymore
        jle     _poly_loop

        get_string              ; Reads input and prints it out changed by polynomial

        exit

_abort:
        error_exit
