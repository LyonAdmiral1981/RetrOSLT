; WAITSWAP n: asks the test script to change the diskette in drive A
; (byte 0000:04F0 = A5h), waits until it has (5Ah), then waits n seconds
; more, as a person would before typing the next command.
        org 100h
        cpu 8086
        xor ax,ax
        mov es,ax
        mov byte [es:04F0h],0A5h
.w:     cmp byte [es:04F0h],5Ah
        jne .w
        mov al,[80h]                    ; command tail: seconds, one digit
        mov cl,0
        cmp al,2
        jb .go
        mov cl,[82h]
        sub cl,'0'
.go:    mov al,18                       ; ticks a second
        mul cl
        mov cx,ax
        jcxz .done
        mov bx,[es:046Ch]
.t:     mov ax,[es:046Ch]
        sub ax,bx
        cmp ax,cx
        jb .t
.done:  mov ax,4C00h
        int 21h
