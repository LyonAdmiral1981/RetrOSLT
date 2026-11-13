; DISKCOMP -- compare two diskettes, for NASM:
;       nasm -f bin -o DISKCOMP.COM DISKCOMP.ASM
;
;       DISKCOMP [d: [d:]] [/1] [/8]
;
; Written for RetrOS/LT to behave as PC DOS 2.10's DISKCOMP does: it
; compares a track at a time through the ROM BIOS, as many tracks as memory
; holds at once, with one drive or two, and names each track that differs.
; /1 compares only the first side; /8 only eight sectors a track.
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
        mov     ax,[2]
        mov     [memtop],ax

again:  mov     byte [nerr],0
        call    prompt1
        cmp     byte [onedrv],0
        jne     .p1
        call    prompt2
.p1:    call    anykey
        mov     dl,[physrc]
        call    getformat
        jnc     .fmt
        mov     dx,m_bad1
        call    print
        jmp     another
.fmt:   cmp     byte [opt1],0
        je      .s1
        mov     byte [sides],1
.s1:    cmp     byte [opt8],0
        je      .s8
        mov     byte [spt],8
.s8:    mov     al,[spt]
        mov     [dpteot],al
        call    setdpt
        mov     dx,m_comparing
        call    print
        mov     al,[spt]
        call    putnumdig
        mov     dx,m_spt
        call    print
        mov     al,[sides]
        call    putnumdig
        mov     dx,m_sides
        call    print
        mov     al,[spt]
        xor     ah,ah
        mov     cl,5
        shl     ax,cl
        mov     [trkparas],ax
        mov     al,40
        mul     byte [sides]
        mov     [ntracks],ax
        mov     word [first],0

.batch: ; read as many tracks of the first diskette as fit
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
        mov     dx,m_rderr1
        call    print
        call    sidetrack
        jmp     .end
.rok:   inc     word [cur]
        inc     word [inbuf]
        jmp     .rd
.rdone: mov     ax,[cur]
        mov     [last],ax
        cmp     byte [onedrv],0
        je      .c0
        call    prompt2
        call    anykey
.c0:    ; compare each with the second diskette's
        mov     ax,[first]
        mov     [cur],ax
        mov     word [inbuf],0
.cmp:   mov     ax,[cur]
        cmp     ax,[last]
        jae     .cdone
        mov     ax,[inbuf]
        call    bufaddr
        mov     [t1seg],es
        push    ds
        pop     es
        mov     bx,trkbuf2
        call    chs
        mov     dl,[phydst]
        mov     ah,2
        call    trackio
        jnc     .cread
        mov     dx,m_rderr2
        call    print
        call    sidetrack
        jmp     .end
.cread: push    ds
        mov     si,trkbuf2
        mov     di,0
        mov     es,[t1seg]
        mov     al,[spt]
        xor     ah,ah
        mov     cl,8
        shl     ax,cl                   ; words in a track
        mov     cx,ax
        repe    cmpsw
        pop     ds
        je      .same
        inc     byte [nerr]
        mov     dx,m_cmperr
        call    print
        call    sidetrack
.same:  inc     word [cur]
        inc     word [inbuf]
        jmp     .cmp
.cdone: mov     ax,[cur]
        mov     [first],ax
        cmp     ax,[ntracks]
        jae     .done
        cmp     byte [onedrv],0
        je      .batch
        call    prompt1
        call    anykey
        jmp     .batch
.done:  cmp     byte [nerr],0
        jne     .end
        mov     dx,m_ok
        call    print
.end:   call    restdpt
another:
        mov     dx,m_another
        call    askyn
        jc      .quit
        jmp     again
.quit:  mov     ax,4C00h
        int     21h

chs:    push    ax
        mov     ax,[cur]
        div     byte [sides]
        mov     ch,al
        mov     dh,ah
        pop     ax
        ret

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

prompt1:
        mov     dx,m_in1
        mov     al,[srcdrv]
        jmp     prompt
prompt2:
        mov     dx,m_in2
        mov     al,[dstdrv]
prompt: add     al,'A'
        mov     [m_drv],al
        call    print
        mov     dx,m_drv
        jmp     print

%include "FLOPPY.INC"

m_in1   db      13,10,"Insert first diskette in drive $"
m_in2   db      13,10,"Insert second diskette in drive $"
m_drv   db      "A:",13,10,"$"
m_comparing db  13,10,"Comparing $"
m_spt   db      " sectors per track, $"
m_sides db      " side(s)",13,10,"$"
m_ok    db      13,10,"Diskettes compare ok",13,10,"$"
m_cmperr db     "Compare error on $"
m_another db    13,10,"Compare more diskettes (Y/N)? $"
m_bad1  db      13,10,"First diskette bad or incompatible",13,10,"$"
m_rderr1 db     13,10,"Unrecoverable read error on drive 1",13,10,"$"
m_rderr2 db     13,10,"Unrecoverable read error on drive 2",13,10,"$"
m_side  db      "side $"
m_track db      ", track $"

nerr    db      0
ntracks dw      0
first   dw      0
last    dw      0
cur     dw      0
inbuf   dw      0
t1seg   dw      0
        times 256 db 0
stacktop:
trkbuf2 equ     $                       ; (memory after the program)
progend equ     trkbuf2+9*512
