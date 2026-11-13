; COMP -- compare files, for NASM:   nasm -f bin -o COMP.COM COMP.ASM
;
;       COMP [d:][path][filename [d:][path][filename]]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's COMP does: global
; filename characters in the first name select the files; the second may be
; only a drive or path, or name the files with global characters, as COPY's
; does; at most ten differences are shown for a pair; and at the end it
; asks whether to compare more.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

CR      equ     13
LF      equ     10
BUFSZ   equ     8192

start:  mov     ah,30h
        int     21h
        cmp     al,2
        jae     .ok
        mov     dx,m_badver
        mov     ah,9
        int     21h
        int     20h
.ok:    mov     dx,dta
        mov     ah,1Ah
        int     21h
        ; the names from the command line
        mov     si,81h
        mov     di,name1
        call    getword
        mov     di,name2
        call    getword
again:  cmp     byte [name1],0
        jne     .have1
        mov     dx,m_enter1
        mov     di,name1
        call    ask
.have1: cmp     byte [name2],0
        jne     .have2
        mov     dx,m_enter2
        mov     di,name2
        call    ask
.have2: call    compareall
        ; more?
.more:  mov     dx,m_more
        call    print
        mov     ah,1
        int     21h
        push    ax
        call    crlf
        pop     ax
        and     al,0DFh
        cmp     al,'Y'
        je      .yes
        cmp     al,'N'
        jne     .more
        mov     ax,4C00h
        int     21h
.yes:   mov     byte [name1],0
        mov     byte [name2],0
        jmp     again

; the next blank-separated word at SI to DI, ASCIIZ, upper case
getword:
.skip:  lodsb
        cmp     al,' '
        je      .skip
        cmp     al,9
        je      .skip
        cmp     al,','
        je      .skip
.lp:    cmp     al,CR
        je      .end
        cmp     al,' '
        je      .end
        cmp     al,9
        je      .end
        cmp     al,','
        je      .end
        call    upper
        stosb
        lodsb
        jmp     .lp
.end:   dec     si
        mov     byte [di],0
        ret

upper:  cmp     al,'a'
        jb      .r
        cmp     al,'z'
        ja      .r
        sub     al,20h
.r:     ret

; prompt DX, read a line, its first word to DI
ask:    push    di
        call    print
        call    crlf
        mov     byte [inbuf],64
        mov     dx,inbuf
        mov     ah,0Ah
        int     21h
        call    crlf
        mov     bl,[inbuf+1]
        xor     bh,bh
        mov     byte [inbuf+2+bx],CR
        mov     si,inbuf+2
        pop     di
        jmp     getword

; ------------------------------------------------------------------ the files
compareall:
        ; split name1 into its directory part (DIR1, through the last \ or :)
        mov     si,name1
        mov     di,dir1
        call    dirpart
        mov     byte [found],0
        mov     dx,name1
        mov     cx,0
        mov     ah,4Eh
        int     21h
        jnc     .each
        mov     dx,name1
        call    printz
        mov     dx,m_notfound
        call    print
        ret
.each:  mov     byte [found],1
        ; file 1: DIR1 + the name found
        mov     si,dir1
        mov     di,full1
        call    copyz
        mov     si,dta+30
        call    copyz
        ; file 2: from NAME2 and the name found
        call    makename2
        call    comparepair
        mov     ah,4Fh
        int     21h
        jnc     .each
        ret

; DIRPART: copy SI to DI through its last "\" or ":", ASCIIZ
dirpart:
        mov     bx,di                   ; end of the directory part so far
.lp:    lodsb
        stosb
        or      al,al
        jz      .end
        cmp     al,'\'
        je      .mark
        cmp     al,':'
        jne     .lp
.mark:  mov     bx,di
        jmp     .lp
.end:   mov     byte [bx],0
        ret

copyz:  lodsb
        stosb
        or      al,al
        jnz     copyz
        dec     di
        ret

; FULL2 from NAME2 and the found name: if NAME2 ends in ":" or "\", or names
; a directory, the found name is added; global characters in NAME2 take the
; found name's characters.
makename2:
        mov     si,name2
        mov     di,full2
        call    copyz                   ; DI at its NUL
        mov     al,[di-1]
        cmp     al,':'
        je      .addname
        cmp     al,'\'
        je      .addname
        ; a directory?
        push    di
        mov     dx,dta2
        mov     ah,1Ah
        int     21h
        mov     dx,full2
        mov     cx,10h
        mov     ah,4Eh
        int     21h
        pushf
        mov     dx,dta
        mov     ah,1Ah
        int     21h
        popf
        pop     di
        jc      .template
        test    byte [dta2+21],10h
        jz      .template
        mov     al,'\'
        stosb
.addname:
        mov     si,dta+30
        jmp     copyz
.template:
        ; NAME2's last part as a template over the found name
        mov     si,name2
        mov     di,full2
        call    dirpart                 ; FULL2 = its directory part, DI at end
        mov     di,full2
.end:   cmp     byte [di],0
        je      .t0
        inc     di
        jmp     .end
.t0:    mov     si,name2
        call    lastpart                ; SI = NAME2's file name
        mov     bx,dta+30               ; the found name
        ; name: up to 8, then the extension
        call    tpart
        cmp     byte [si],'.'
        jne     .noext1
        inc     si
.noext1:
        ; the found name's extension
.fx:    mov     al,[bx]
        or      al,al
        jz      .fe
        inc     bx
        cmp     al,'.'
        jne     .fx
.fe:    cmp     byte [si],0
        je      .done
        mov     al,'.'
        stosb
        call    tpart
.done:  mov     byte [di],0
        ret

; copy one part of a template SI over the found part BX to DI: '*' takes the
; rest of the part, '?' one character
tpart:  mov     al,[si]
        or      al,al
        jz      .r
        cmp     al,'.'
        je      .r
        inc     si
        cmp     al,'*'
        je      .star
        cmp     al,'?'
        jne     .lit
        mov     al,[bx]
        or      al,al
        jz      .q0
        cmp     al,'.'
        je      .q0
        inc     bx
        stosb
        jmp     tpart
.q0:    jmp     tpart
.lit:   stosb
        cmp     byte [bx],0
        je      tpart
        cmp     byte [bx],'.'
        je      tpart
        inc     bx
        jmp     tpart
.star:  mov     al,[bx]
        or      al,al
        jz      .skip
        cmp     al,'.'
        je      .skip
        inc     bx
        stosb
        jmp     .star
.skip:  mov     al,[si]                 ; past the rest of the template part
        or      al,al
        jz      .r
        cmp     al,'.'
        je      .r
        inc     si
        jmp     .skip
.r:     ret

lastpart:
        mov     bx,si
.lp:    lodsb
        or      al,al
        jz      .e
        cmp     al,'\'
        je      .m
        cmp     al,':'
        jne     .lp
.m:     mov     bx,si
        jmp     .lp
.e:     mov     si,bx
        ret

; ------------------------------------------------------------------ one pair
comparepair:
        call    crlf
        mov     dx,full1
        call    printz
        mov     dx,m_and
        call    print
        mov     dx,full2
        call    printz
        call    crlf
        mov     dx,full1
        mov     ax,3D00h
        int     21h
        jc      .bad1
        mov     [h1],ax
        mov     dx,full2
        mov     ax,3D00h
        int     21h
        jc      .bad2
        mov     [h2],ax
        ; the same size?
        mov     bx,[h1]
        call    size
        mov     [s1lo],ax
        mov     [s1hi],dx
        mov     bx,[h2]
        call    size
        cmp     ax,[s1lo]
        jne     .diffsize
        cmp     dx,[s1hi]
        jne     .diffsize
        mov     word [offlo],0
        mov     word [offhi],0
        mov     byte [nerr],0
        mov     byte [last],1Ah
.read:  mov     bx,[h1]
        mov     dx,buf1
        mov     cx,BUFSZ
        mov     ah,3Fh
        int     21h
        jc      .close
        mov     [n],ax
        mov     bx,[h2]
        mov     dx,buf2
        mov     cx,ax
        mov     ah,3Fh
        int     21h
        jc      .close
        mov     cx,[n]
        jcxz    .eof
        mov     si,buf1
        mov     di,buf2
        mov     bx,0
.cmp:   mov     al,[si+bx]
        mov     [last],al
        cmp     al,[di+bx]
        je      .same
        call    mismatch
        cmp     byte [nerr],10
        jae     .ten
.same:  inc     bx
        loop    .cmp
        mov     ax,[n]
        add     [offlo],ax
        adc     word [offhi],0
        cmp     word [n],BUFSZ
        je      .read
.eof:   cmp     byte [nerr],0
        jne     .close
        mov     dx,m_ok
        call    print
        cmp     byte [last],1Ah
        je      .close
        mov     dx,m_noeof
        call    print
        jmp     .close
.ten:   mov     dx,m_ten
        call    print
        jmp     .close
.diffsize:
        mov     dx,m_size
        call    print
.close: mov     bx,[h2]
        mov     ah,3Eh
        int     21h
.c1:    mov     bx,[h1]
        mov     ah,3Eh
        int     21h
        ret
.bad1:  mov     dx,full1
        jmp     .nf
.bad2:  mov     bx,[h1]
        mov     ah,3Eh
        int     21h
        mov     dx,full2
.nf:    call    printz
        mov     dx,m_notfound
        jmp     print

; BX = handle: DX:AX = its size, and back to its start
size:   mov     ax,4202h
        xor     cx,cx
        xor     dx,dx
        int     21h
        push    ax
        push    dx
        mov     ax,4200h
        xor     cx,cx
        xor     dx,dx
        int     21h
        pop     dx
        pop     ax
        ret

; a difference at offset OFFSET + BX: file 1's byte [SI+BX], file 2's [DI+BX]
mismatch:
        push    cx
        push    bx
        inc     byte [nerr]
        mov     dx,m_at
        call    print
        mov     ax,[offlo]
        mov     dx,[offhi]
        add     ax,bx
        adc     dx,0
        or      dx,dx
        jz      .lo
        push    ax
        mov     ax,dx
        call    hexw
        pop     ax
.lo:    call    hexw
        call    crlf
        mov     dx,m_f1
        call    print
        pop     bx
        push    bx
        mov     al,[si+bx]
        call    hexb
        call    crlf
        mov     dx,m_f2
        call    print
        pop     bx
        push    bx
        mov     al,[di+bx]
        call    hexb
        call    crlf
        pop     bx
        pop     cx
        ret

hexw:   push    ax
        mov     al,ah
        call    hexb
        pop     ax
hexb:   push    ax
        mov     cl,4
        shr     al,cl
        call    hexn
        pop     ax
hexn:   and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     putc
        add     al,7
putc:   push    dx
        push    ax
        mov     dl,al
        mov     ah,2
        int     21h
        pop     ax
        pop     dx
        ret

crlf:   mov     dx,m_crlf
print:  push    ax
        mov     ah,9
        int     21h
        pop     ax
        ret
printz: push    si
        mov     si,dx
.lp:    lodsb
        or      al,al
        jz      .d
        call    putc
        jmp     .lp
.d:     pop     si
        ret

m_enter1 db     "Enter primary file name$"
m_enter2 db     "Enter 2nd file name or drive id$"
m_and   db      " and $"
m_ok    db      "Files compare ok",CR,LF,"$"
m_size  db      "Files are different sizes",CR,LF,"$"
m_at    db      "Compare error at OFFSET $"
m_f1    db      "File 1 = $"
m_f2    db      "File 2 = $"
m_ten   db      "10 Mismatches - ending compare",CR,LF,"$"
m_noeof db      "EOF mark not found",CR,LF,"$"
m_more  db      CR,LF,"Compare more files (Y/N)? $"
m_notfound db   " - File not found",CR,LF,"$"
m_badver db     "Incorrect DOS version",CR,LF,"$"
m_crlf  db      CR,LF,"$"

found   db      0
nerr    db      0
last    db      0
h1      dw      0
h2      dw      0
n       dw      0
s1lo    dw      0
s1hi    dw      0
offlo   dw      0
offhi   dw      0
name1   times 80 db 0
name2   times 80 db 0
dir1    times 80 db 0
full1   times 80 db 0
full2   times 80 db 0
inbuf   times 68 db 0
dta     times 43 db 0
dta2    times 43 db 0
buf1    times BUFSZ db 0
buf2    times BUFSZ db 0
