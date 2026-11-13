; ASSIGN -- send requests for one drive to another, for NASM:
;       nasm -f bin -o ASSIGN.COM ASSIGN.ASM
;
;       ASSIGN [x=y [...]]          ASSIGN alone puts every drive back
;
; Written for RetrOS/LT to behave as PC DOS 2.10's ASSIGN does. It stays
; resident the first time, catching INT 21h (requests that name a drive by
; letter in a path, or by number in a file control block or register) and
; INT 25h and 26h (absolute disk reads and writes). Its resident part is laid
; out as IBM's: the drive table at offset 103h and the INT 21h handler at
; 122h, where PC DOS 2's FORMAT looks to see whether ASSIGN is in use.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

start:  jmp     install

table:  db      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
        db      24,25,26                ; 103h: drive n (1 = A) goes to table[n-1]
old21   dd      0                       ; 11Dh
        times   22h-($-$$) db 0             ; the INT 21h handler: at 122h
int21:  cmp     ah,0Eh                  ; select disk: DL = drive, 0 = A
        je      .dl0
        cmp     ah,1Ch                  ; allocation information, DL 0 = default
        je      .dl1
        cmp     ah,36h                  ; free space, DL 0 = default
        je      .dl1
        cmp     ah,47h                  ; current directory, DL 0 = default
        je      .dl1
        cmp     ah,32h                  ; drive parameters, DL 0 = default
        je      .dl1
        cmp     ah,0Fh                  ; file control block requests
        jb      .pass
        cmp     ah,17h
        jbe     .fcb
        cmp     ah,21h
        jb      .pass
        cmp     ah,24h
        jbe     .fcb
        cmp     ah,27h
        je      .fcb
        cmp     ah,28h
        je      .fcb
        cmp     ah,39h                  ; path requests: DS:DX
        jb      .pass
        cmp     ah,3Dh
        jbe     .path
        cmp     ah,41h
        je      .path
        cmp     ah,43h
        je      .path
        cmp     ah,4Bh
        je      .path
        cmp     ah,4Eh
        je      .path
        cmp     ah,56h
        je      .rename
.pass:  jmp     far [cs:old21]

.dl0:   push    bx                      ; DL = 0-based drive
        mov     bl,dl
        inc     bl
        call    map
        dec     bl
        mov     dl,bl
        pop     bx
        jmp     .pass
.dl1:   or      dl,dl                   ; DL = 1-based, 0 = default
        jz      .pass
        push    bx
        mov     bl,dl
        call    map
        mov     dl,bl
        pop     bx
        jmp     .pass

.fcb:   push    bx
        push    si
        mov     si,dx
        cmp     byte [si],0FFh          ; an extended FCB: the drive is at +7
        jne     .f1
        add     si,7
.f1:    mov     bl,[si]
        or      bl,bl
        jz      .f2                     ; the default drive: left alone
        call    map
        mov     [si],bl
.f2:    pop     si
        pop     bx
        jmp     .pass

.path:  push    si                      ; the drive letter is changed in the
        mov     si,dx                   ; caller's string, and DOS given the
        call    mappath                 ; request as it stands (calling DOS
        mov     al,[cs:origal]          ; and returning would break EXEC's
        pop     si                      ; return to its caller)
        jmp     .pass

.rename:
        push    si
        mov     si,dx
        call    mappath
        push    ds
        push    es
        pop     ds
        mov     si,di
        call    mappath
        pop     ds
        mov     al,[cs:origal]
        pop     si
        jmp     .pass

; MAPPATH: if DS:SI starts "x:", change x to its assignment; AL = the
; original letter, or 0. Saves the caller's AL in ORIGAL.
mappath:
        mov     [cs:origal],al
        xor     al,al
        cmp     byte [si+1],':'
        jne     .r
        mov     al,[si]
        push    bx
        mov     bl,al
        and     bl,0DFh
        sub     bl,'A'-1
        cmp     bl,26
        ja      .x
        call    map
        add     bl,'A'-1
        mov     [si],bl
.x:     pop     bx
.r:     ret

; BL = drive (1 = A): to its assignment
map:    cmp     bl,1
        jb      .r
        cmp     bl,26
        ja      .r
        push    bx
        xor     bh,bh
        mov     bl,[cs:table-1+bx]
        mov     [cs:mapped],bl
        pop     bx
        mov     bl,[cs:mapped]
.r:     ret

int25:  call    mapal
        jmp     far [cs:old25]
int26:  call    mapal
        jmp     far [cs:old26]
mapal:  push    bx                      ; AL = drive, 0 = A
        mov     bl,al
        inc     bl
        call    map
        dec     bl
        mov     al,bl
        pop     bx
        ret

old25   dd      0
old26   dd      0
origal  db      0
mapped  db      0
resend:

; ------------------------------------------------------------------ install
install:
        ; already resident? (INT 21h at offset 122h, with our table)
        mov     ax,3521h
        int     21h
        mov     [rseg],es
        cmp     bx,int21
        jne     .new
        cmp     word [es:109h],0807h
        jne     .new
        mov     byte [resident],1
        jmp     .parse
.new:   mov     [rseg],cs
.parse: ; reset the table, then apply x=y pairs
        mov     es,[rseg]
        mov     di,table
        mov     al,1
        mov     cx,26
.reset: stosb
        inc     al
        loop    .reset
        mov     si,81h
.lp:    lodsb
        cmp     al,13
        je      .done
        cmp     al,' '
        je      .lp
        cmp     al,9
        je      .lp
        cmp     al,','
        je      .lp
        call    letter
        jc      .bad
        mov     bl,al
        lodsb
        cmp     al,':'
        jne     .eq
        lodsb
.eq:    cmp     al,'='
        jne     .bad
        lodsb
        call    letter
        jc      .bad
        cmp     byte [si],':'
        jne     .set
        inc     si
.set:   xor     bh,bh
        mov     [es:table-1+bx],al
        jmp     .lp
.done:  cmp     byte [resident],0
        jne     .exit
        ; stay resident
        mov     ax,3521h
        int     21h
        mov     [old21],bx
        mov     [old21+2],es
        mov     ax,3525h
        int     21h
        mov     [old25],bx
        mov     [old25+2],es
        mov     ax,3526h
        int     21h
        mov     [old26],bx
        mov     [old26+2],es
        mov     dx,int21
        mov     ax,2521h
        int     21h
        mov     dx,int25
        mov     ax,2525h
        int     21h
        mov     dx,int26
        mov     ax,2526h
        int     21h
        mov     dx,resend+15
        mov     cl,4
        shr     dx,cl
        mov     ax,3100h
        int     21h
.exit:  mov     ax,4C00h
        int     21h
.bad:   mov     dx,m_badparm
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h

; AL = a drive letter: to 1 = A ... 26 = Z; CF if not one
letter: and     al,0DFh
        sub     al,'A'-1
        cmp     al,1
        jb      .no
        cmp     al,26
        ja      .no
        clc
        ret
.no:    stc
        ret

rseg    dw      0
resident db     0
m_badparm db    "Invalid parameter",13,10,"$"
