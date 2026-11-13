; TREE -- show the directories of a disk, and optionally their files, for
; NASM:   nasm -f bin -o TREE.COM TREE.ASM
;
;       TREE [d:] [/F]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's TREE does.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

CR      equ     13
LF      equ     10
MAXDEPTH equ    32

start:  mov     ah,30h                  ; DOS 2 or later
        int     21h
        cmp     al,2
        jae     .ver
        mov     dx,m_badver
        mov     ah,9
        int     21h
        int     20h
.ver:   ; the command line: a drive, and /F
        mov     si,81h
.scan:  lodsb
        cmp     al,CR
        je      .go
        cmp     al,'/'
        jne     .notsw
        lodsb
        and     al,0DFh
        cmp     al,'F'
        jne     badparm
        mov     byte [files],1
        jmp     .scan
.notsw: cmp     al,' '
        je      .scan
        cmp     al,9
        je      .scan
        cmp     byte [si],':'
        jne     badparm
        and     al,0DFh
        sub     al,'A'
        cmp     al,25
        ja      badparm
        mov     [drv],al
        mov     byte [drvset],1
        inc     si
        jmp     .scan
.go:    cmp     byte [drvset],0
        jne     .have
        mov     ah,19h
        int     21h
        mov     [drv],al
.have:  mov     al,[drv]
        add     al,'A'
        mov     [path],al
        mov     word [path+1],':\'
        mov     byte [path+3],0
        ; our own disk transfer area for each level of the search
        mov     dx,m_head
        call    print
        mov     di,path+3
        xor     bx,bx                   ; depth
        call    walk
        cmp     byte [anydir],0
        jne     .done
        mov     dx,m_nosub
        call    print
.done:  mov     ax,4C00h
        int     21h

badparm:
        mov     dx,m_badparm
        call    print
        mov     ax,4C01h
        int     21h

; WALK: list the directory PATH (which ends in "\"; DI = its end), then each
; of its subdirectories in turn. BX = depth.
walk:   cmp     bx,MAXDEPTH
        jb      .ok
        ret
.ok:    push    di
        push    bx
        ; the DTA for this level
        mov     ax,bx
        mov     cx,43
        mul     cx
        add     ax,dtas
        mov     [dta],ax
        mov     dx,ax
        mov     ah,1Ah
        int     21h
        ; the directory's own heading (not for the root)
        cmp     bx,0
        je      .subs
        mov     dx,m_path
        call    print
        mov     byte [di-1],0           ; without its last "\"
        mov     dx,path+2
        call    printz
        mov     byte [di-1],'\'
        call    crlf
        call    crlf
        ; its subdirectories, by name
        mov     dx,m_subs
        call    print
        call    .listdirs
        jnz     .files
        mov     dx,m_none
        call    print
.files: cmp     byte [files],0
        je      .subs
        call    crlf
        mov     dx,m_files
        call    print
        call    .listfiles
        jnz     .subs1
        mov     dx,m_none
        call    print
.subs1: call    crlf
.subs:  call    crlf
        ; now go into each subdirectory
        pop     bx
        pop     di
        push    di
        push    bx
        mov     si,m_star
        call    append
        mov     dx,path
        mov     cx,10h
        mov     ah,4Eh
        int     21h
.next:  jc      .ret
        mov     si,[dta]
        test    byte [si+21],10h
        jz      .skip
        cmp     byte [si+30],'.'
        je      .skip
        mov     byte [anydir],1
        ; PATH\name
        pop     bx
        pop     di
        push    di
        push    bx
        add     si,30
        call    append
        mov     al,'\'
        call    appendc                 ; PATH\name\, DI after it
        inc     bx
        push    word [dta]
        call    walk
        pop     word [dta]
        mov     dx,[dta]
        mov     ah,1Ah
        int     21h
.skip:  mov     ah,4Fh
        int     21h
        jmp     .next
.ret:   pop     bx
        pop     di
        mov     byte [di],0
        ret

; list this directory's subdirectories (or files); ZF clear if any
.listdirs:
        mov     byte [want],10h
        jmp     .list
.listfiles:
        mov     byte [want],0
.list:  pop     ax                      ; our return
        pop     cx                      ; walk's: depth, end of path
        pop     dx
        push    dx
        push    cx
        push    ax
        mov     di,dx
        push    di
        mov     si,m_star
        call    append
        mov     byte [count],0
        mov     dx,path
        mov     cx,16h                  ; hidden, system, directories
        mov     ah,4Eh
        int     21h
.l1:    jc      .l9
        mov     si,[dta]
        mov     al,[si+21]
        and     al,10h
        cmp     al,[want]
        jne     .l2
        cmp     byte [si+30],'.'
        je      .l2
        cmp     byte [count],0
        je      .first
        mov     dx,m_indent
        call    print
.first: inc     byte [count]
        add     si,30
        call    shownm
        call    crlf
.l2:    mov     ah,4Fh
        int     21h
        jmp     .l1
.l9:    pop     di
        mov     byte [di],0
        cmp     byte [count],0
        ret

; a name from a directory search, as NAME    .EXT
shownm: mov     cx,8
.n:     lodsb
        or      al,al
        jz      .pad
        cmp     al,'.'
        je      .dot
        call    putc
        loop    .n
        lodsb
        cmp     al,'.'
        jne     .end
.dot:   jcxz    .ext
.sp:    mov     al,' '
        call    putc
        loop    .sp
.ext:   mov     al,'.'
        call    putc
.e:     lodsb
        or      al,al
        jz      .end
        call    putc
        jmp     .e
.pad:
.end:   ret

; append the ASCIIZ string SI at DI (DI left at its NUL)
append: lodsb
        stosb
        or      al,al
        jnz     append
        dec     di
        ret
appendc:
        stosb
        mov     byte [di],0
        ret

putc:   push    dx
        mov     dl,al
        mov     ah,2
        int     21h
        pop     dx
        ret
crlf:   mov     dx,m_crlf
print:  mov     ah,9
        int     21h
        ret
printz: push    si
        mov     si,dx
.lp:    lodsb
        or      al,al
        jz      .done
        call    putc
        jmp     .lp
.done:  pop     si
        ret

drv     db      0
drvset  db      0
files   db      0
anydir  db      0
want    db      0
count   db      0
dta     dw      0
m_head  db      CR,LF,"DIRECTORY PATH LISTING",CR,LF,LF,"$"
m_path  db      "Path: $"
m_subs  db      "Sub-directories:  $"
m_files db      "Files:            $"
m_indent db     "                  $"
m_none  db      "None",CR,LF,"$"
m_nosub db      "No sub-directories exist",CR,LF,LF,"$"
m_crlf  db      CR,LF,"$"
m_star  db      "*.*",0
m_badparm db    "Invalid parameter",CR,LF,"$"
m_badver db     "Incorrect DOS version",CR,LF,"$"
path    times 80 db 0
dtas    times MAXDEPTH*43 db 0
