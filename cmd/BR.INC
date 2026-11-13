; BR.INC -- what BACKUP and RESTORE share: the 2.x backup format, messages
; and small helpers.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026
;
; A backup diskette holds BACKUPID.@@@ in its root directory, 128 bytes:
;       0       0FFh on the last diskette of the set, 0 before it
;       1       the diskette's number in the set (a word, from 1)
;       3       the year it was written (a word), 5 the day, 6 the month
; and each file backed up, in the root directory under its own name, with
; the original date and time, behind a 128-byte header:
;       0       0FFh if this is the file's last (or only) part, 0 if more
;               follows on the next diskette
;       1       the number of the diskette this part is on
;       5       the file's full path, without the drive (ASCIIZ)
;       53h     the length of the path plus 1

ID_LAST equ     0
ID_SEQ  equ     1
ID_YEAR equ     3
ID_DAY  equ     5
ID_MON  equ     6
H_LAST  equ     0
H_SEQ   equ     1
H_PATH  equ     5
H_LEN   equ     53h

CR      equ     13
LF      equ     10

; Print the "$" string DX
print:  push    ax
        mov     ah,9
        int     21h
        pop     ax
        ret
; Print the ASCIIZ string DS:SI
printz: push    ax
        push    dx
.lp:    lodsb
        or      al,al
        jz      .r
        mov     dl,al
        mov     ah,2
        int     21h
        jmp     .lp
.r:     pop     dx
        pop     ax
        ret
crlf:   push    dx
        mov     dx,m_crlf
        call    print
        pop     dx
        ret
; Print AL as two digits
put2:   push    ax
        push    dx
        aam
        add     ax,'00'
        push    ax
        mov     dl,ah
        mov     ah,2
        int     21h
        pop     ax
        mov     dl,al
        mov     ah,2
        int     21h
        pop     dx
        pop     ax
        ret
; Wait for a key, after flushing what was typed ahead
anykey: mov     dx,m_strike
        call    print
        mov     ax,0C08h
        int     21h
        or      al,al                   ; an extended key: its second byte
        jnz     .r
        mov     ah,8
        int     21h
.r:     call    crlf
        ret
; "Insert backup diskette nn in drive d:", then a key
insdisk:
        mov     dx,m_insert
        call    print
        mov     al,[diskno]
        call    put2
        mov     dx,m_indrive
        call    print
        ret
; AL = a letter, upper case
upper:  cmp     al,'a'
        jb      .r
        cmp     al,'z'
        ja      .r
        sub     al,20h
.r:     ret
; Skip blanks at SI
skipsp: cmp     byte [si],' '
        je      .s
        cmp     byte [si],9
        jne     .r
.s:     inc     si
        jmp     skipsp
.r:     ret

; The ASCIIZ string at SI to the end of DI; DI left at its terminating 0
strcat: push    si
.f:     cmp     byte [di],0
        je      .c
        inc     di
        jmp     .f
.c:     lodsb
        stosb
        or      al,al
        jnz     .c
        dec     di
        pop     si
        ret
; Copy the ASCIIZ string SI to DI
strcpy: mov     byte [di],0
        jmp     strcat

; Add "\" to the directory DI unless it ends in one already
addsl:  push    di
.f:     cmp     byte [di],0
        je      .e
        inc     di
        jmp     .f
.e:     cmp     byte [di-1],'\'
        je      .r
        mov     word [di],'\'
.r:     pop     di
        ret

; Make a path absolute and upper case. SI: what was typed (after any drive),
; ending in a blank, "/", or CR; DL: the drive (1 = A). Into DI (64+ bytes):
; "\DIR\..." (no drive, no last "\" unless the root), and the last part,
; if it has no "\" after it and is not a directory, into PATTERN as typed.
; SI is left after the path. CF if the directory is not there.
abspath:
        push    di
        mov     [ap_drive],dl
        ; the part typed: up to a blank, "/" or CR
        mov     bx,ap_buf
.cp:    lodsb
        cmp     al,' '
        je      .end
        cmp     al,9
        je      .end
        cmp     al,'/'
        je      .end
        cmp     al,CR
        je      .end
        call    upper
        mov     [bx],al
        inc     bx
        jmp     .cp
.end:   dec     si
        mov     byte [bx],0
        mov     word [di],'\'           ; from the root
        cmp     byte [ap_buf],'\'
        je      .abs
        push    si                      ; or the current directory
        mov     si,di
        inc     si
        mov     dl,[ap_drive]
        mov     ah,47h
        int     21h
        pop     si
        jc      .bad
.abs:   ; then each part of what was typed, "." and ".." worked out
        push    si
        mov     si,ap_buf
        cmp     byte [si],'\'
        jne     .part
        inc     si
.part:  cmp     byte [si],0
        je      .done
        ; the part: up to "\" or the end
        mov     bx,si
.pe:    cmp     byte [bx],0
        je      .last
        cmp     byte [bx],'\'
        je      .dir
        inc     bx
        jmp     .pe
.last:  ; the last part: a directory, or a file name or pattern
        push    bx
        mov     bx,si
.wc:    mov     al,[bx]
        inc     bx
        cmp     al,'?'
        je      .pat
        cmp     al,'*'
        je      .pat
        or      al,al
        jnz     .wc
        call    isdir
        jmp     .isd
.pat:   stc
.isd:
        pop     bx
        jnc     .dir
        push    di
        mov     di,pattern
        call    strcpy
        pop     di
        jmp     .done
.dir:   mov     al,[bx]
        mov     byte [bx],0
        push    ax
        push    bx
        call    adddir
        pop     bx
        pop     ax
        mov     [bx],al
        mov     si,bx
        cmp     byte [si],0
        je      .done
        inc     si
        jmp     .part
.done:  pop     si
        pop     di
        ; and is it there?
        push    si
        mov     si,di
        cmp     word [si],'\'
        je      .ok
        mov     word [chkdir],0
        mov     bx,chkdir
        mov     al,[ap_drive]
        add     al,'@'
        mov     [bx],al
        mov     byte [bx+1],':'
        push    di
        lea     di,[bx+2]
        call    strcpy
        pop     di
        mov     dx,chkdir
        mov     cx,10h
        mov     ah,1Ah
        push    dx
        mov     dx,ap_dta
        int     21h
        pop     dx
        mov     ah,4Eh
        int     21h
        jc      .no
        test    byte [ap_dta+21],10h
        jz      .no
.ok:    pop     si
        clc
        ret
.no:    pop     si
        stc
        ret
.bad:   pop     di
        stc
        ret

; Add the part SI (ASCIIZ) to the directory DI: "." stays, ".." goes up
adddir: cmp     word [si],'.'
        je      .r
        cmp     word [si],'..'
        jne     .add
        cmp     byte [si+2],0
        jne     .add
        ; back to the last "\"
        push    di
        mov     bx,di
.f:     cmp     byte [di],0
        je      .b
        inc     di
        jmp     .f
.b:     cmp     di,bx
        je      .t
        dec     di
        cmp     byte [di],'\'
        jne     .b
.t:     cmp     di,bx                   ; keep the root's "\"
        jne     .cut
        inc     di
.cut:   mov     byte [di],0
        pop     di
.r:     ret
.add:   push    si
        call    addsl
        call    strcat
        pop     si
        ret

; Is the directory DI plus the part SI a directory? CF if not.
isdir:  push    si
        push    di
        mov     bx,chkdir
        mov     al,[ap_drive]
        add     al,'@'
        mov     [bx],al
        mov     byte [bx+1],':'
        mov     byte [bx+2],0
        push    si
        mov     si,di
        lea     di,[bx+2]
        call    strcpy
        mov     di,chkdir
        call    addsl
        pop     si
        call    strcat
        mov     ah,1Ah
        mov     dx,ap_dta
        int     21h
        mov     dx,chkdir
        mov     cx,10h
        mov     ah,4Eh
        int     21h
        jc      .no
        test    byte [ap_dta+21],10h
        jz      .no
        pop     di
        pop     si
        clc
        ret
.no:    pop     di
        pop     si
        stc
        ret

ap_drive db     0
ap_buf  times 80 db 0
chkdir  times 80 db 0
ap_dta  times 43 db 0
pattern db      "*.*",0
        times 10 db 0

m_crlf  db      CR,LF,"$"
m_strike db     "Strike any key when ready $"
m_insert db     CR,LF,"Insert backup diskette $"
m_indrive db    " in drive "
m_tdrv  db      "A:",CR,LF,"$"
m_badver db     "Incorrect DOS version",CR,LF,"$"
m_badparm db    "Invalid parameter",CR,LF,"$"
m_baddrv db     "Invalid drive specification",CR,LF,"$"
m_badpath db    "Invalid path",CR,LF,"$"
m_same  db      "Source and target drives are the same",CR,LF,"$"
m_nparm db      "Invalid number of parameters",CR,LF,"$"
idname  db      "A:\BACKUPID.@@@",0
