; DISKCOPY -- copy a whole diskette, for NASM:
;       nasm -f bin -o DISKCOPY.COM DISKCOPY.ASM
;
;       DISKCOPY [d: [d:]] [/1]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's DISKCOPY does: it copies
; a track at a time through the ROM BIOS, as many tracks as memory holds at
; once, with one drive or two, and formats the target as it goes if it is
; not formatted in the same way. /1 copies only the first side.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

start:  mov     ah,30h
        int     21h
        cmp     al,2
        jae     .ver
        mov     dx,m_badver
        call    print
        int     20h
.ver:   mov     sp,stacktop
        call    countdrives
        call    parsedrives
        jnc     .parms
        mov     dx,m_badparm
        call    print
        mov     ax,4C01h
        int     21h
.parms: call    setupmem
        mov     ax,cs
        mov     bx,progend+15
        mov     cl,4
        shr     bx,cl
        add     ax,bx
        mov     [bufseg],ax
        mov     ax,[2]                  ; top of memory, from the PSP
        mov     [memtop],ax

again:  mov     byte [fmtdone],0
        call    promptsrc
        cmp     byte [onedrv],0
        jne     .p1
        call    prompttgt
.p1:    call    anykey
        mov     dl,[physrc]
        call    getformat
        jnc     .fmt
        mov     dx,m_badsrc
        call    print
        jmp     another
.fmt:   cmp     byte [opt1],0
        je      .sides
        mov     byte [sides],1
.sides: mov     al,[spt]
        mov     [dpteot],al
        call    setdpt
        mov     dx,m_copying
        call    print
        mov     al,[spt]
        call    putnumdig
        mov     dx,m_spt
        call    print
        mov     al,[sides]
        call    putnumdig
        mov     dx,m_sides
        call    print
        ; track buffer size
        mov     al,[spt]
        xor     ah,ah
        mov     cl,5
        shl     ax,cl
        mov     [trkparas],ax
        mov     al,40
        mul     byte [sides]
        mov     [ntracks],ax
        mov     word [first],0

.batch: ; read as many tracks as fit
        mov     ax,[first]
        mov     [cur],ax
        mov     word [inbuf],0
.rd:    mov     ax,[cur]
        cmp     ax,[ntracks]
        jae     .rdone
        mov     ax,[inbuf]
        call    bufaddr
        jc      .rdone
        call    chs
        mov     dl,[physrc]
        mov     ah,2
        call    trackio
        jnc     .rok
        mov     dx,m_rderr
        call    print
        call    sidetrack
        mov     dx,m_unusable
        call    print
        jmp     .end
.rok:   inc     word [cur]
        inc     word [inbuf]
        jmp     .rd
.rdone: ; then write them
        cmp     byte [onedrv],0
        je      .wr0
        call    prompttgt
        call    anykey
.wr0:   mov     ax,[first]
        mov     [cur],ax
        mov     word [inbuf],0
.wr:    mov     ax,[cur]
        cmp     ax,[ntracks]
        jae     .wdone
        mov     ax,[inbuf]
        call    bufaddr
        jc      .wdone
        call    chs
        mov     dl,[phydst]
        mov     ah,3
        call    trackio
        jnc     .wok
        cmp     ah,3
        je      .wprot
        ; not formatted (as the source is): format the track, and again
        cmp     byte [fmtdone],0
        jne     .f1
        mov     byte [fmtdone],1
        push    dx
        push    bx
        mov     dx,m_formatting
        call    print
        pop     bx
        pop     dx
.f1:    call    chs
        mov     dl,[phydst]
        call    fmttrack
        jc      .werr
        call    chs
        mov     dl,[phydst]
        mov     ah,3
        call    trackio
        jc      .werr
.wok:   inc     word [cur]
        inc     word [inbuf]
        jmp     .wr
.wdone: mov     ax,[cur]
        mov     [first],ax
        cmp     ax,[ntracks]
        jae     .done
        cmp     byte [onedrv],0
        je      .batch
        call    promptsrc
        call    anykey
        jmp     .batch
.wprot: mov     dx,m_wprot
        call    print
        jmp     .end
.werr:  mov     dx,m_wrerr
        call    print
        call    sidetrack
        jmp     .end
.done:  mov     dx,m_complete
        call    print
.end:   call    restdpt
another:
        mov     dx,m_another
        call    askyn
        jc      .quit
        jmp     again
.quit:  mov     ax,4C00h
        int     21h

; CH, DH for track CUR: cylinder CUR / SIDES, side CUR mod SIDES
chs:    push    ax
        mov     ax,[cur]
        div     byte [sides]
        mov     ch,al
        mov     dh,ah
        pop     ax
        ret

; "Side n, track nn"
sidetrack:
        mov     dx,m_side
        call    print
        call    chs
        push    cx
        mov     al,dh
        call    putnumdig
        mov     dx,m_track
        call    print
        pop     cx
        mov     al,ch
        call    putnumdig
        mov     dx,m_crlf
        jmp     print

promptsrc:
        mov     dx,m_insrc
        mov     al,[srcdrv]
        jmp     prompt
prompttgt:
        mov     dx,m_intgt
        mov     al,[dstdrv]
prompt: add     al,'A'
        mov     [m_drv1],al
        call    print
        mov     dx,m_drv1
        jmp     print

%include "FLOPPY.INC"

m_insrc db      13,10,"Insert source diskette in drive $"
m_intgt db      13,10,"Insert target diskette in drive $"
m_drv1  db      "A:",13,10,"$"
m_copying db    13,10,"Copying $"
m_spt   db      " sectors per track, $"
m_sides db      " side(s)",13,10,"$"
m_formatting db "Formatting while copying",13,10,"$"
m_complete db   13,10,"Copy complete",13,10,"$"
m_another db    13,10,"Copy another (Y/N)? $"
m_badsrc db     13,10,"Source diskette bad or incompatible",13,10,"$"
m_rderr db      13,10,"Unrecoverable read error on source",13,10,"$"
m_wrerr db      13,10,"Unrecoverable write error on target",13,10,"$"
m_unusable db   "Target diskette may be unusable",13,10,"$"
m_wprot db      13,10,"Attempt to write to write-protected diskette",13,10,"$"
m_side  db      "Side $"
m_track db      ", track $"

ntracks dw      0
first   dw      0
cur     dw      0
inbuf   dw      0
        times 256 db 0
stacktop:
progend:
