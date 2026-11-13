; BACKUP -- back up files to diskettes, for NASM:
;       nasm -f bin -o BACKUP.COM BACKUP.ASM
;
;       BACKUP d:[path][filename[.ext]] d: [/S] [/M] [/A] [/D:mm-dd-yy]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's BACKUP does, in its
; format (see BR.INC), so that its RESTORE and PC DOS 2's read the same
; diskettes. /S takes the subdirectories too, /M only files changed since
; they were last backed up, /A adds to the backup diskettes already there,
; /D only files changed on or after the date. A file too big for what is
; left on a diskette goes on in the next. Exit codes: 0 done, 1 nothing to
; back up, 3 stopped with Ctrl-Break, 4 an error.
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
        mov     ax,2523h                ; Ctrl-Break: exit code 3
        mov     dx,onbreak
        int     21h
        call    parse
        ; the target's first diskette
        cmp     byte [opta],0
        je      .new
        mov     dx,m_inslast
        call    print
        mov     dx,m_tdrv
        call    print
        call    anykey
        mov     ah,0Dh
        int     21h
        call    readid
        jc      .nolast
        cmp     byte [idbuf+ID_LAST],0FFh
        jne     .nolast
        mov     ax,[idbuf+ID_SEQ]
        mov     [diskno],al
        mov     byte [idbuf+ID_LAST],0  ; not the last one now
        call    writeid
        jc      fail
        call    banner
        jmp     .go
.nolast:
        mov     dx,m_notlast
        call    print
        mov     al,4
        jmp     exit
.new:   call    newdisk
.go:    mov     di,curdir
        mov     si,srcdir
        call    strcpy
        call    walk
        mov     byte [idbuf+ID_LAST],0FFh
        call    writeid
        jc      fail
        cmp     byte [found],0
        jne     .end
        mov     dx,m_nofiles
        call    print
        mov     al,1
        jmp     exit
.end:   mov     al,0
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
        ; the source: d:[path][name]
        cmp     byte [si+1],':'
        jne     .bad
        mov     al,[si]
        call    upper
        sub     al,'@'
        mov     [srcdrv],al
        call    chkdrv
        jc      .baddrv
        add     si,2
        mov     dl,[srcdrv]
        mov     di,srcdir
        call    abspath
        jc      .badpath
        call    skipsp
        ; the target: d:
        cmp     byte [si+1],':'
        jne     .nparm
        mov     al,[si]
        call    upper
        sub     al,'@'
        mov     [tgtdrv],al
        call    chkdrv
        jc      .baddrv
        add     al,'@'
        mov     [m_tdrv],al
        mov     [idname],al
        mov     [tgtname],al
        add     si,2
        mov     al,[tgtdrv]
        cmp     al,[srcdrv]
        je      .same
        ; the switches
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
.s1:    cmp     al,'M'
        jne     .s2
        mov     byte [optm],1
        jmp     .sw
.s2:    cmp     al,'A'
        jne     .s3
        mov     byte [opta],1
        jmp     .sw
.s3:    cmp     al,'D'
        jne     .bad
        cmp     byte [si],':'
        jne     .bad
        inc     si
        call    getdate
        jc      .baddate
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
        jmp     .err
.baddate:
        mov     dx,m_baddate
.err:   call    print
        mov     al,4
        jmp     exit

; Is drive AL (1 = A) there? CF if not.
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

; mm-dd-yy (or mm/dd/yy, yyyy) at SI: into DATE, packed as a directory
; entry's. CF if it is not a date.
getdate:
        call    getnum
        jc      .r
        mov     [dmon],al
        call    sep
        jc      .r
        call    getnum
        jc      .r
        mov     [dday],al
        call    sep
        jc      .r
        call    getnum
        jc      .r
        cmp     ax,100
        jae     .y4
        add     ax,1900
        cmp     ax,1980
        jae     .y4
        add     ax,100
.y4:    sub     ax,1980
        jb      .bad
        cmp     ax,119
        ja      .bad
        mov     cl,9
        shl     ax,cl
        mov     bl,[dmon]
        or      bl,bl
        jz      .bad
        cmp     bl,12
        ja      .bad
        xor     bh,bh
        mov     cl,5
        shl     bx,cl
        or      ax,bx
        mov     bl,[dday]
        or      bl,bl
        jz      .bad
        cmp     bl,31
        ja      .bad
        xor     bh,bh
        or      ax,bx
        mov     [date],ax
        mov     byte [optd],1
        clc
.r:     ret
.bad:   stc
        ret
sep:    lodsb
        cmp     al,'-'
        je      .ok
        cmp     al,'/'
        je      .ok
        cmp     al,'.'
        je      .ok
        stc
        ret
.ok:    clc
        ret
; a number at SI: AX; CF if none
getnum: xor     ax,ax
        xor     cx,cx
.lp:    mov     bl,[si]
        sub     bl,'0'
        cmp     bl,9
        ja      .e
        mov     dx,10
        mul     dx
        xor     bh,bh
        add     ax,bx
        inc     si
        inc     cx
        jmp     .lp
.e:     cmp     cx,1
        ret                             ; CF if no digits

; ------------------------------------------------------------------ the target
; Ask for the next diskette, empty its root directory, and start it
newdisk:
        call    insdisk
        mov     dx,m_erase
        call    print
        call    anykey
        mov     ah,0Dh
        int     21h
        ; erase the files in its root directory
        mov     ah,1Ah
        mov     dx,tdta
        int     21h
.find:  mov     di,erpath               ; (found again each time: the
        mov     si,tgtname              ; one before is gone)
        call    strcpy
        mov     si,s_all+1
        call    strcat
        mov     dx,erpath
        mov     cx,0
        mov     ah,4Eh
        int     21h
        jc      .start
        mov     di,erpath+3
        mov     byte [di],0
        mov     si,tdta+30
        call    strcat
        mov     dx,erpath
        mov     ax,4301h                ; not read-only any more
        xor     cx,cx
        int     21h
        mov     ah,41h
        int     21h
        jnc     .next
        mov     dx,m_noerase
        call    print
        mov     si,erpath
        call    printz
        call    crlf
        jmp     fail
.next:  jmp     .find
.start: mov     byte [fresh],1
        mov     byte [idbuf+ID_LAST],0
        mov     al,[diskno]
        xor     ah,ah
        mov     [idbuf+ID_SEQ],ax
        call    writeid
        jc      fail
banner: mov     dx,m_backing
        call    print
        mov     al,[diskno]
        call    put2
        mov     dx,m_stars
        jmp     print

; BACKUPID.@@@ from the target into IDBUF; CF if it is not there
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

; IDBUF, with today's date, to BACKUPID.@@@ on the target; CF on an error
writeid:
        mov     ah,2Ah
        int     21h
        mov     [idbuf+ID_YEAR],cx
        mov     [idbuf+ID_DAY],dl
        mov     [idbuf+ID_MON],dh
        mov     dx,idname
        mov     ax,4301h
        xor     cx,cx
        int     21h
        mov     dx,idname
        xor     cx,cx
        mov     ah,3Ch
        int     21h
        jc      .err
        mov     bx,ax
        mov     dx,idbuf
        mov     cx,128
        mov     ah,40h
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     ax
        popf
        jc      .err
        cmp     ax,128
        jb      .err
        clc
        ret
.err:   mov     dx,m_tgterr
        call    print
        stc
        ret

; The next diskette: this one is not the last
nextdisk:
        inc     byte [diskno]
        jmp     newdisk

; ------------------------------------------------------------------ the walk
; Back up the files in CURDIR ("\..." on the source), and with /S the
; directories in it, each with its own DTA on the stack.
walk:   push    bp
        sub     sp,44
        mov     bp,sp
        call    setdta
        ; the files
        call    spec
        mov     si,pattern
        call    strcat
        mov     dx,srcpath
        xor     cx,cx                   ; normal and read-only files
        mov     ah,4Eh
        int     21h
.file:  jc      .dirs
        call    wanted
        jc      .fnext
        call    backup
.fnext: call    setdta
        mov     ah,4Fh
        int     21h
        jmp     .file
.dirs:  cmp     byte [opts],0
        je      .r
        call    spec
        mov     si,s_all
        inc     si                      ; "*.*", not "\*.*"
        call    strcat
        call    setdta
        mov     dx,srcpath
        mov     cx,10h
        mov     ah,4Eh
        int     21h
.dir:   jc      .r
        test    byte [bp+21],10h
        jz      .dnext
        cmp     byte [bp+30],'.'
        je      .dnext
        ; into it
        mov     di,curdir
        call    addsl
        lea     si,[bp+30]
        call    strcat
        call    walk
        ; and back out
        mov     di,curdir
        mov     si,di
.e:     cmp     byte [si],0
        je      .b
        inc     si
        jmp     .e
.b:     dec     si
        cmp     byte [si],'\'
        jne     .b
        cmp     si,di
        jne     .cut
        inc     si
.cut:   mov     byte [si],0
.dnext: call    setdta
        mov     ah,4Fh
        int     21h
        jmp     .dir
.r:     add     sp,44
        pop     bp
        ret

setdta: push    dx
        push    ds
        push    ss
        pop     ds
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        pop     ds
        pop     dx
        ret

; SRCPATH = "d:" CURDIR "\"
spec:   mov     di,srcpath
        mov     al,[srcdrv]
        add     al,'@'
        mov     [di],al
        mov     word [di+1],':'
        add     di,2
        mov     si,curdir
        call    strcat
        mov     di,srcpath
        call    addsl
        ret

; Is the file in the DTA at BP to be backed up? CF if not.
wanted: cmp     byte [optm],0
        je      .m
        test    byte [bp+21],20h        ; changed since the last backup
        jz      .no
.m:     cmp     byte [optd],0
        je      .yes
        mov     ax,[bp+24]
        cmp     ax,[date]
        jb      .no
.yes:   clc
        ret
.no:    stc
        ret

; ------------------------------------------------------------------ a file
; Back up the file in the DTA at BP, from CURDIR
backup: mov     byte [found],1
        ; its path: in the header, and on the source
        mov     di,hdr
        mov     cx,128
        xor     al,al
        rep     stosb
        mov     di,hdr+H_PATH
        mov     si,curdir
        call    strcpy
        call    addsl
        lea     si,[bp+30]
        call    strcat
        mov     ax,di
        sub     ax,hdr+H_PATH-1
        mov     [hdr+H_LEN],al
        mov     si,hdr+H_PATH
        call    printz
        call    crlf
        mov     di,srcpath
        mov     al,[srcdrv]
        add     al,'@'
        mov     [di],al
        mov     word [di+1],':'
        add     di,2
        mov     si,hdr+H_PATH
        call    strcat
        ; open it
        mov     dx,srcpath
        mov     ax,3D00h
        int     21h
        jnc     .open
        mov     dx,m_cantbu
        call    print
        ret
.open:  mov     [src],ax
        mov     bx,ax
        mov     ax,5700h
        int     21h
        mov     [ftime],cx
        mov     [fdate],dx
        mov     ax,[bp+26]              ; its size
        mov     [left],ax
        mov     ax,[bp+28]
        mov     [left+2],ax
        ; the name on the target
        mov     di,tgtpath
        mov     si,tgtname
        call    strcpy
        lea     si,[bp+30]
        call    strcat
.part:  ; room on this diskette? a file of this name already there?
        call    setdtat
        mov     dx,tgtpath
        mov     cx,6
        mov     ah,4Eh
        int     21h
        jnc     .full
        mov     dl,[tgtdrv]
        mov     ah,36h
        int     21h
        mul     cx                      ; bytes per cluster
        mul     bx                      ; DX:AX free
        sub     ax,128+1                ; room for the header and a byte
        sbb     dx,0
        jb      .full
        add     ax,1
        adc     dx,0
        ; this part: all that is left, or what fits
        mov     cx,[left]
        mov     bx,[left+2]
        cmp     bx,dx
        jb      .fits
        ja      .some
        cmp     cx,ax
        jbe     .fits
.some:  mov     cx,ax
        mov     bx,dx
        mov     byte [hdr+H_LAST],0
        jmp     .make
.fits:  mov     byte [hdr+H_LAST],0FFh
.make:  mov     [part],cx
        mov     [part+2],bx
        mov     al,[diskno]
        mov     [hdr+H_SEQ],al
        mov     dx,tgtpath
        xor     cx,cx
        mov     ah,3Ch
        int     21h
        jc      .full                   ; the root directory is full
        mov     byte [fresh],0
        mov     [tgt],ax
        mov     bx,ax
        mov     dx,hdr
        mov     cx,128
        mov     ah,40h
        int     21h
        jc      .werr
        cmp     ax,cx
        jne     .werr
        ; the data
.copy:  mov     ax,[part]
        or      ax,[part+2]
        jz      .copied
        mov     cx,BUFSIZE
        cmp     word [part+2],0
        jne     .c1
        cmp     [part],cx
        jae     .c1
        mov     cx,[part]
.c1:    mov     bx,[src]
        mov     dx,buffer
        mov     ah,3Fh
        int     21h
        jc      .rerr
        or      ax,ax
        jz      .rerr                   ; shorter than it was
        mov     cx,ax
        mov     bx,[tgt]
        mov     ah,40h
        int     21h
        jc      .werr
        cmp     ax,cx
        jne     .werr
        sub     [part],ax
        sbb     word [part+2],0
        sub     [left],ax
        sbb     word [left+2],0
        jmp     .copy
.copied:
        mov     bx,[tgt]
        mov     cx,[ftime]
        mov     dx,[fdate]
        mov     ax,5701h
        int     21h
        mov     ah,3Eh
        int     21h
        jc      .werr
        mov     ax,[left]
        or      ax,[left+2]
        jz      .done
.full:  cmp     byte [fresh],0          ; nothing fits on an empty
        je      .nf                     ; diskette
        mov     dx,m_cantuse
        jmp     .err
.nf:    call    nextdisk
        jmp     .part
.done:  mov     bx,[src]
        mov     ah,3Eh
        int     21h
        ; backed up: the archive bit off
        mov     dx,srcpath
        mov     ax,4300h
        int     21h
        jc      .r
        and     cx,0FFDFh
        mov     ax,4301h
        int     21h
.r:     ret
.rerr:  mov     dx,m_srcerr
        jmp     .err
.werr:  mov     dx,m_tgterr
.err:   call    print
        jmp     fail

setdtat:
        mov     ah,1Ah
        mov     dx,tdta
        int     21h
        ret

; ------------------------------------------------------------------ data
%include "BR.INC"

m_erase db      "Warning! Diskette files will be erased",CR,LF,"$"
m_backing db    CR,LF,"*** Backing up files to diskette $"
m_stars db      " ***",CR,LF,"$"
m_inslast db    CR,LF,"Insert last backup diskette in drive $"
m_notlast db    "Last backup diskette not inserted",CR,LF,"$"
m_nofiles db    "Warning! No files were found to back up",CR,LF,"$"
m_noerase db    "Unable to erase $"
m_cantbu db     "*** Not able to back up file ***",CR,LF,"$"
m_srcerr db     "Error reading the source file",CR,LF,"$"
m_tgterr db     "Error writing the backup diskette",CR,LF,"$"
m_cantuse db   "Target can not be used for backup",CR,LF,"$"
m_baddate db    "Invalid date",CR,LF,"$"
s_all   db      "\*.*",0
tgtname db      "A:\",0

srcdrv  db      0
tgtdrv  db      0
opts    db      0
optm    db      0
opta    db      0
optd    db      0
date    dw      0
dmon    db      0
dday    db      0
diskno  db      1
found   db      0
fresh   db      0
src     dw      0
tgt     dw      0
ftime   dw      0
fdate   dw      0
left    dd      0
part    dd      0
idbuf   times 128 db 0
hdr     times 128 db 0
srcdir  times 80 db 0
curdir  times 80 db 0
srcpath times 80 db 0
tgtpath times 80 db 0
tdta    times 43 db 0
erpath  times 80 db 0
        times 1024 db 0
stacktop:
buffer:
