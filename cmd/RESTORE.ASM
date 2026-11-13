; RESTORE -- restore files from backup diskettes, for NASM:
;       nasm -f bin -o RESTORE.COM RESTORE.ASM
;
;       RESTORE d: [d:][path]filename[.ext] [/S] [/P]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's RESTORE does: it reads
; diskettes written by BACKUP (the format is in BR.INC), one after another,
; and puts back the files that match, into the directories they came from
; on the drive named. /S takes the files from the subdirectories too; /P
; asks before replacing a file that is read-only or has changed since it
; was backed up. Exit codes: 0 done, 1 nothing to restore, 3 stopped with
; Ctrl-Break, 4 an error.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

BUFSIZE equ     8000h

start:  mov     ah,30h
        int     21h
        cmp     al,2
        jae     .ver
        mov     dx,m_badver
        call    print
        int     20h
.ver:   mov     sp,stacktop
        mov     ax,2523h
        mov     dx,onbreak
        int     21h
        call    parse
        ; the pattern as a file control block name, to compare names with
        mov     si,pattern
        mov     di,patfcb
        mov     ax,2901h
        int     21h
        mov     ah,1Ah
        mov     dx,dta
        int     21h

.disk:  call    insdisk
        call    anykey
        mov     ah,0Dh
        int     21h
.again: call    readid
        jnc     .isbk
        mov     dx,m_notbk
        call    print
        mov     al,4
        jmp     exit
.isbk:  mov     al,[idbuf+ID_SEQ]
        cmp     al,[diskno]
        je      .inseq
        cmp     byte [seqok],0
        jne     .take
        mov     byte [seqok],1
        mov     dx,m_outseq
        call    print
        call    anykey
        mov     ah,0Dh
        int     21h
        jmp     .again
.take:  mov     [diskno],al             ; going on with this one
.inseq: mov     byte [seqok],0
mov     dx,m_restoring
        call    print
        mov     al,[diskno]
        call    put2
        mov     dx,m_stars
        call    print
        call    files
        cmp     byte [idbuf+ID_LAST],0FFh
        je      .end
        inc     byte [diskno]
        jmp     .disk
.end:   cmp     word [cont],0           ; a file left open: its rest is
        je      .e1                     ; missing
        mov     bx,[cont]
        mov     ah,3Eh
        int     21h
        mov     dx,m_seqerr
        call    print
        mov     al,4
        jmp     exit
.e1:    cmp     byte [found],0
        jne     .ok
        mov     dx,m_nofiles
        call    print
        mov     al,1
        jmp     exit
.ok:    mov     al,0
exit:   mov     ah,4Ch
        int     21h
fail:   mov     al,4
        jmp     exit
onbreak:
        mov     ax,4C03h
        int     21h

; ------------------------------------------------------------------ parse
parse:  mov     si,81h
        call    skipsp
        cmp     byte [si],CR
        je      .nparm
        ; the backup drive
        cmp     byte [si+1],':'
        jne     .bad
        mov     al,[si]
        call    upper
        sub     al,'@'
        mov     [srcdrv],al
        call    chkdrv
        jc      .baddrv
        add     al,'@'
        mov     [m_tdrv],al
        mov     [idname],al
        mov     [srcname],al
        add     si,2
        call    skipsp
        cmp     byte [si],CR
        je      .nparm
        ; the files: [d:][path][name]
        mov     al,0
        mov     ah,19h
        int     21h
        inc     al
        mov     [dstdrv],al
        cmp     byte [si+1],':'
        jne     .nod
        mov     al,[si]
        call    upper
        sub     al,'@'
        mov     [dstdrv],al
        call    chkdrv
        jc      .baddrv
        add     si,2
.nod:   mov     al,[dstdrv]
        cmp     al,[srcdrv]
        je      .same
        mov     dl,al
        mov     di,dstdir
        call    abspath
        jc      .badpath
.sw:    call    skipsp
        lodsb
        cmp     al,CR
        je      .done
        cmp     al,'/'
        jne     .bad
        lodsb
        call    upper
        cmp     al,'S'
        jne     .s1
        mov     byte [opts],1
        jmp     .sw
.s1:    cmp     al,'P'
        jne     .bad
        mov     byte [optp],1
        jmp     .sw
.done:  ret
.nparm: mov     dx,m_nparm
        jmp     .err
.bad:   mov     dx,m_badparm
        jmp     .err
.baddrv:
        mov     dx,m_baddrv
        jmp     .err
.badpath:
        mov     dx,m_badpath
        jmp     .err
.same:  mov     dx,m_same
.err:   call    print
        mov     al,4
        jmp     exit

chkdrv: push    ax
        push    dx
        mov     dl,al
        mov     ah,36h
        int     21h
        cmp     ax,0FFFFh
        pop     dx
        pop     ax
        je      .no
        clc
        ret
.no:    stc
        ret

; BACKUPID.@@@ into IDBUF; CF if it is not there
readid: mov     dx,idname
        mov     ax,3D00h
        int     21h
        jc      .r
        mov     bx,ax
        mov     dx,idbuf
        mov     cx,128
        mov     ah,3Fh
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     ax
        popf
        jc      .r
        cmp     ax,128
        jb      .no
        clc
.r:     ret
.no:    stc
        ret

; ------------------------------------------------------------------ files
; Each backed-up file in the diskette's root directory
files:  mov     di,srcpath
        mov     si,srcname
        call    strcpy
        mov     si,s_all
        call    strcat
        mov     dx,srcpath
        xor     cx,cx
        mov     ah,4Eh
        int     21h
.lp:    jc      .r
        mov     si,dta+30
        mov     di,s_id
        mov     cx,13
        repe    cmpsb
        je      .next                   ; BACKUPID.@@@ itself
        call    one
        mov     ah,1Ah
        mov     dx,dta
        int     21h
.next:  mov     ah,4Fh
        int     21h
        jmp     .lp
.r:     ret

; The file named in the DTA
one:    mov     di,srcpath
        mov     si,srcname
        call    strcpy
        mov     si,dta+30
        call    strcat
        mov     dx,srcpath
        mov     ax,3D00h
        int     21h
        jc      .r
        mov     [inh],ax
        mov     bx,ax
        mov     dx,hdr
        mov     cx,128
        mov     ah,3Fh
        int     21h
        jc      .close
        cmp     ax,128
        jne     .close
        mov     byte [hdr+H_PATH+63],0
        ; the rest of a file begun on the last diskette?
        cmp     word [cont],0
        je      .new
        mov     si,hdr+H_PATH
        mov     di,contpath
        call    strcmp
        jne     .new
        mov     ax,[cont]
        mov     [outh],ax
        mov     word [cont],0
        jmp     .data
.new:   call    match
        jc      .close
        call    replace
        jc      .close
        ; make its directories, then the file
        call    mkdirs
        mov     dx,dstpath
        mov     ax,4301h
        xor     cx,cx
        int     21h
        mov     dx,dstpath
        xor     cx,cx
        mov     ah,3Ch
        int     21h
        jnc     .made
        mov     dx,m_cantmake
        call    print
        jmp     .close
.made:  mov     [outh],ax
        mov     byte [found],1
        mov     si,hdr+H_PATH
        call    printz
        call    crlf
.data:  mov     bx,[inh]
        mov     dx,buffer
        mov     cx,BUFSIZE
        mov     ah,3Fh
        int     21h
        jc      .rerr
        or      ax,ax
        jz      .eof
        mov     cx,ax
        mov     bx,[outh]
        mov     ah,40h
        int     21h
        jc      .werr
        cmp     ax,cx
        jne     .werr
        jmp     .data
.eof:   ; its date and time are the backup's
        mov     bx,[inh]
        mov     ax,5700h
        int     21h
        mov     bx,[outh]
        mov     ax,5701h
        int     21h
        cmp     byte [hdr+H_LAST],0FFh
        je      .last
        mov     [cont],bx               ; more on the next diskette
        mov     si,hdr+H_PATH
        mov     di,contpath
        call    strcpy
        jmp     .close
.last:  mov     ah,3Eh
        int     21h
.close: mov     bx,[inh]
        mov     ah,3Eh
        int     21h
.r:     ret
.rerr:  mov     dx,m_srcerr
        jmp     .err
.werr:  mov     dx,m_tgterr
.err:   call    print
        jmp     fail

; Does the header's path match what was asked for? CF if not. Sets DSTPATH
; ("d:" and the path) on the way.
match:  mov     di,dstpath
        mov     al,[dstdrv]
        add     al,'@'
        mov     [di],al
        mov     word [di+1],':'
        add     di,2
        mov     si,hdr+H_PATH
        call    strcat
        ; its directory: up to the last "\"
        mov     si,hdr+H_PATH
        mov     bx,si
.f:     lodsb
        or      al,al
        jz      .e
        cmp     al,'\'
        jne     .f
        mov     bx,si                   ; just after it
        jmp     .f
.e:     ; the name, against the pattern
        push    bx
        mov     si,bx
        mov     di,namefcb
        mov     ax,2900h
        int     21h
        pop     bx
        mov     si,namefcb+1
        mov     di,patfcb+1
        mov     cx,11
.n:     mov     al,[di]
        cmp     al,'?'
        je      .n1
        cmp     al,[si]
        jne     .no
.n1:    inc     si
        inc     di
        loop    .n
        ; the directory, against DSTDIR
        dec     bx                      ; at the "\"
        mov     cx,bx
        sub     cx,hdr+H_PATH           ; its length: 0 for the root
        mov     si,dstdir
        cmp     word [si],'\'           ; the root asked for
        jne     .d
        jcxz    .yes
        cmp     byte [opts],0
        jne     .yes
        jmp     .no
.d:     mov     di,hdr+H_PATH
.dc:    lodsb
        or      al,al
        jz      .dend
        cmp     al,[di]
        jne     .no
        inc     di
        jmp     .dc
.dend:  cmp     di,bx
        je      .yes                    ; the same directory
        cmp     byte [opts],0
        je      .no
        cmp     byte [di],'\'
        je      .yes                    ; below it
.no:    stc
        ret
.yes:   clc
        ret

; With /P: ask before replacing a read-only file, or one changed since it
; was backed up. CF to leave it.
replace:
        cmp     byte [optp],0
        je      .yes
        mov     dx,dstpath
        mov     ax,4300h
        int     21h
        jc      .yes                    ; not there: nothing to replace
        mov     dx,m_readonly
        test    cl,1
        jnz     .ask
        mov     dx,dstpath
        mov     ax,3D00h
        int     21h
        jc      .yes
        mov     bx,ax
        mov     ax,5700h
        int     21h
        push    cx
        push    dx
        mov     ah,3Eh
        int     21h
        mov     bx,[inh]
        mov     ax,5700h
        int     21h
        pop     ax
        pop     bx
        cmp     ax,dx
        jne     .changed
        cmp     bx,cx
        je      .yes
.changed:
        mov     dx,m_changed
.ask:   push    dx
        mov     dx,m_warnfile
        call    print
        mov     si,dstpath+2
        call    printz
        pop     dx
        call    print
.yn:    mov     dx,m_replace
        call    print
        mov     ax,0C01h
        int     21h
        call    upper
        push    ax
        call    crlf
        pop     ax
        cmp     al,'Y'
        je      .yes
        cmp     al,'N'
        jne     .yn
        stc
        ret
.yes:   clc
        ret

; Make the directories of DSTPATH ("d:\A\B\NAME"), one at a time
mkdirs: mov     si,dstpath+3
.lp:    lodsb
        or      al,al
        jz      .r
        cmp     al,'\'
        jne     .lp
        mov     byte [si-1],0
        mov     dx,dstpath
        mov     ah,39h
        int     21h                     ; (already there is no matter)
        mov     byte [si-1],'\'
        jmp     .lp
.r:     ret

; Compare the ASCIIZ strings SI and DI: ZF if they are the same
strcmp: lodsb
        cmp     al,[di]
        jne     .r
        inc     di
        or      al,al
        jnz     strcmp
.r:     ret

; ------------------------------------------------------------------ data
%include "BR.INC"

m_restoring db  CR,LF,"*** Restoring files from diskette $"
m_stars db      " ***",CR,LF,"$"
m_notbk db      "Source does not contain backup files",CR,LF,"$"
m_outseq db     "Warning! Diskette is out of sequence",CR,LF
        db      "Replace the diskette or continue if okay",CR,LF,"$"
m_seqerr db     "Restore file sequence error",CR,LF,"$"
m_nofiles db    "Warning! No files were found to restore",CR,LF,"$"
m_warnfile db   "Warning! File $"
m_readonly db   CR,LF,"is a read-only file",CR,LF,"$"
m_changed db    CR,LF,"was changed after it was backed up",CR,LF,"$"
m_replace db    "Replace the file (Y/N)? $"
m_cantmake db   "Unable to create the file",CR,LF,"$"
m_srcerr db     "Error reading the backup diskette",CR,LF,"$"
m_tgterr db     "Error writing the file",CR,LF,"$"
s_all   db      "*.*",0
s_id    db      "BACKUPID.@@@",0
srcname db      "A:\",0

srcdrv  db      0
dstdrv  db      0
opts    db      0
optp    db      0
diskno  db      1
found   db      0
inh     dw      0
outh    dw      0
cont    dw      0
seqok   db      0
idbuf   times 128 db 0
hdr     times 128 db 0
patfcb  times 37 db 0
namefcb times 37 db 0
dstdir  times 80 db 0
dstpath times 80 db 0
contpath times 80 db 0
srcpath times 80 db 0
dta     times 43 db 0
        times 1024 db 0
stacktop:
buffer:
