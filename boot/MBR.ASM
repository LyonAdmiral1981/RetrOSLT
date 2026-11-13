; RetrOS/LT master boot record, for NASM:  nasm -f bin -o MBR.BIN MBR.ASM
;
; FDISK writes this to the first sector of a fixed disk, with the partition
; table at its end. The ROM BIOS loads it at 0000:7C00. It moves itself out
; of the way, finds the one active partition, loads that partition's boot
; sector at 0000:7C00, and jumps to it with DL = 80h and DS:SI pointing to
; the partition's entry, as the IBM PC XT's fixed disk startup expects.
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     0600h

start:  cli
        xor     ax,ax
        mov     ss,ax
        mov     sp,7C00h
        mov     ds,ax
        mov     es,ax
        sti
        cld
        mov     si,7C00h
        mov     di,0600h
        mov     cx,256
        rep     movsw
        jmp     0:moved

moved:  mov     si,table
        mov     bl,4
.find:  cmp     byte [si],80h
        je      .active
        cmp     byte [si],0
        jne     invalid
        add     si,16
        dec     bl
        jnz     .find
        int     18h                     ; nothing active: ROM BASIC
.active:
        mov     bp,si                   ; the entry
.rest:  add     si,16                   ; the others must be inactive
        dec     bl
        jz      ldboot
        cmp     byte [si],0
        je      .rest
invalid:
        mov     si,msginv
        jmp     stop

ldboot:  mov     di,5                    ; tries
ldtry:   mov     dx,[bp]                 ; DL = 80h, DH = head
        mov     cx,[bp+2]               ; cylinder and sector
        mov     bx,7C00h
        mov     ax,0201h
        int     13h
        jnc     ldread
        xor     ax,ax
        int     13h
        dec     di
        jnz     ldtry
        mov     si,msgerr
        jmp     stop
ldread:  cmp     word [7DFEh],0AA55h
        mov     si,msgmiss
        jne     stop
        mov     si,bp
        mov     dl,80h
        jmp     0:7C00h

stop:   lodsb
        or      al,al
        jz      .halt
        mov     ah,14
        mov     bx,7
        int     10h
        jmp     stop
.halt:  jmp     .halt

msginv: db      "Invalid partition table",0
msgerr: db      "Error loading operating system",0
msgmiss: db     "Missing operating system",0

        times   1BEh-($-$$) db 0
table:  times   64 db 0
        dw      0AA55h
