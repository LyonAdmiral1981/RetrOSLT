; FLOPPY.INC -- diskette routines shared by DISKCOPY and DISKCOMP, which
; work through the ROM BIOS, a track at a time, as PC DOS 2.10's do.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

; The two drives: SRCDRV and DSTDRV are 0 or 1 (A: or B:); PHYSRC and
; PHYDST the physical drives (the same drive on a one-drive computer).
srcdrv  db      0
dstdrv  db      0
physrc  db      0
phydst  db      0
onedrv  db      0               ; 1: one physical drive for both
spt     db      9
sides   db      2
tracks  db      40
fmtdone db      0               ; the target has been formatted this copy
numflop db      1

; How many diskette drives: NUMFLOP.
countdrives:
        int     11h
        mov     cl,6
        mov     bx,ax
        shr     bx,cl
        and     bl,3
        inc     bl
        test    al,1
        jnz     .ok
        mov     bl,1
.ok:    mov     [numflop],bl
        ret

; Drive letters from the command line at 81h: up to two, and /1 (and /8,
; for DISKCOMP). Defaults: the current drive (A: or B:) for both. CF if a
; parameter is wrong.
parsedrives:
        mov     ah,19h
        int     21h
        cmp     al,1
        jbe     .def
        xor     al,al
.def:   mov     [srcdrv],al
        mov     [dstdrv],al
        mov     si,81h
        xor     cx,cx                   ; drives seen
.lp:    lodsb
        cmp     al,13
        je      .done
        cmp     al,' '
        je      .lp
        cmp     al,9
        je      .lp
        cmp     al,'/'
        je      .sw
        and     al,0DFh
        sub     al,'A'
        cmp     al,1
        ja      .bad
        cmp     byte [si],':'
        jne     .bad
        inc     si
        jcxz    .first
        cmp     cx,1
        jne     .bad
        mov     [dstdrv],al
        inc     cx
        jmp     .lp
.first: mov     [srcdrv],al
        mov     [dstdrv],al
        inc     cx
        jmp     .lp
.sw:    lodsb
        cmp     al,'1'
        jne     .sw8
        mov     byte [opt1],1
        jmp     .lp
.sw8:   cmp     al,'8'
        jne     .bad
        mov     byte [opt8],1
        jmp     .lp
.done:  mov     al,[srcdrv]
        mov     [physrc],al
        mov     al,[dstdrv]
        mov     [phydst],al
        mov     byte [onedrv],0
        mov     al,[srcdrv]
        cmp     al,[dstdrv]
        je      .one
        cmp     byte [numflop],1
        ja      .two
        mov     byte [physrc],0         ; A: and B: on one drive
        mov     byte [phydst],0
.one:   mov     byte [onedrv],1
.two:   clc
        ret
.bad:   stc
        ret
opt1    db      0
opt8    db      0

; The format of the diskette in drive DL: SPT and SIDES from its FAT ID
; byte (the first byte of its second sector). CF if it cannot be read or
; the byte is not one of the four.
getformat:
        mov     [gfdrv],dl
        mov     byte [dpteot],9         ; read the second sector, which is
        call    setdpt                  ; in the same place on all four
        mov     di,4
.try:   mov     ax,0201h
        mov     cx,0002h
        xor     dh,dh
        mov     dl,[gfdrv]
        mov     bx,secbuf
        push    ds
        pop     es
        int     13h
        jnc     .read
        xor     ah,ah
        int     13h
        dec     di
        jnz     .try
        stc
        ret
.read:  mov     al,[secbuf]
        mov     bx,fmtid
        mov     cx,4
.lp:    cmp     al,[bx]
        je      .found
        inc     bx
        loop    .lp
        stc
        ret
.found: sub     bx,fmtid
        mov     al,[fmtspt+bx]
        mov     [spt],al
        mov     al,[fmtsides+bx]
        mov     [sides],al
        clc
        ret
gfdrv   db      0
fmtid   db      0FDh,0FFh,0FCh,0FEh
fmtspt  db      9,8,9,8
fmtsides db     2,2,1,1

; Set the diskette parameter table's sectors per track (byte 4) to DPTEOT,
; and the format gap and fill as DOS 2 formats; RESTDPT puts back 9.
dpteot  db      9
setdpt: push    ds
        push    si
        xor     ax,ax
        mov     ds,ax
        lds     si,[1Eh*4]
        mov     al,[cs:dpteot]
        mov     [si+4],al
        pop     si
        pop     ds
        ret
restdpt:
        mov     byte [dpteot],9
        jmp     setdpt

; Read (AH=2), write (AH=3) or verify (AH=4) track CH, side DH, of drive DL,
; SPT sectors, at ES:BX; four tries. CF and AH = ROM status on failure.
trackio:
        mov     [tio_fn],ah
        mov     byte [tio_try],4
.try:   mov     ah,[tio_fn]
        mov     al,[spt]
        mov     cl,1
        push    bx
        push    cx
        push    dx
        int     13h
        pop     dx
        pop     cx
        pop     bx
        jnc     .ok
        mov     [tio_st],ah
        cmp     ah,3                    ; write protected
        je      .fail
        xor     ah,ah
        int     13h
        dec     byte [tio_try]
        jnz     .try
.fail:  mov     ah,[tio_st]
        stc
.ok:    ret
tio_fn  db      0
tio_try db      0
tio_st  db      0

; Format track CH, side DH of drive DL with SPT sectors.
fmttrack:
        push    bx
        push    es
        mov     di,[afbuf]
        push    ds
        pop     es
        mov     cl,1
.af:    mov     al,ch
        stosb
        mov     al,dh
        stosb
        mov     al,cl
        stosb
        mov     al,2
        stosb
        inc     cl
        cmp     cl,[spt]
        jbe     .af
        mov     byte [tio_try],3
.try:   mov     ah,5
        mov     al,[spt]
        mov     bx,[afbuf]
        push    cx
        push    dx
        int     13h
        pop     dx
        pop     cx
        jnc     .ok
        mov     [tio_st],ah
        xor     ah,ah
        int     13h
        dec     byte [tio_try]
        jnz     .try
        mov     ah,[tio_st]
        stc
.ok:    pop     es
        pop     bx
        ret
afbuf   dw      af1
af1     times 36 db 0
af2     times 36 db 0

; Pick the address-field buffer that does not cross 64K, and work out how
; many tracks fit in memory from BUFSEG up: TRKBUF tracks of 512*SPT bytes,
; never across a 64K boundary (each track is placed on its own).
setupmem:
        mov     ax,ds
        mov     cl,4
        shl     ax,cl
        add     ax,af1
        add     ax,36
        jnc     .af
        mov     word [afbuf],af2
.af:    ret

; ES:BX for track buffer number AX (each 512*SPT bytes, from BUFSEG,
; skipping a 64K boundary). CF if it is past the end of memory.
bufaddr:
        push    cx
        push    dx
        mov     cx,ax
        mov     ax,[bufseg]
.lp:    ; does a track at AX:0 cross a 64K boundary?
        mov     dx,ax
        and     dx,0FFFh                ; paragraph within its 64K
        add     dx,[trkparas]
        cmp     dx,1000h
        jbe     .fits
        add     ax,0FFFh                ; start at the next 64K
        and     ax,0F000h
.fits:  jcxz    .here
        add     ax,[trkparas]
        dec     cx
        jmp     .lp
.here:  mov     dx,ax
        add     dx,[trkparas]
        cmp     dx,[memtop]
        ja      .full
        mov     es,ax
        xor     bx,bx
        pop     dx
        pop     cx
        clc
        ret
.full:  pop     dx
        pop     cx
        stc
        ret
bufseg  dw      0
trkparas dw     0
memtop  dw      0

; Print the ASCIIZ-less "$" string DX; read a key; AL = it.
print:  push    ax
        mov     ah,9
        int     21h
        pop     ax
        ret
getkey: mov     ah,0Ch                  ; flush, then read with no echo
        mov     al,8
        int     21h
        ret
anykey: mov     dx,m_strike
        call    print
        call    getkey
        mov     dx,m_crlf
        jmp     print

; Ask "... (Y/N)?" (DX); CF clear for Y.
askyn:  push    dx
        call    print
        mov     ah,0Ch
        mov     al,1
        int     21h
        pop     dx
        and     al,0DFh
        cmp     al,'Y'
        je      .y
        cmp     al,'N'
        jne     askyn
        push    dx
        mov     dx,m_crlf
        call    print
        pop     dx
        stc
        ret
.y:     mov     dx,m_crlf
        call    print
        clc
        ret

putnumdig:                              ; AL = 0-99
        aam
        or      ah,ah
        jz      .one
        push    ax
        mov     dl,ah
        add     dl,'0'
        mov     ah,2
        int     21h
        pop     ax
.one:   mov     dl,al
        add     dl,'0'
        mov     ah,2
        int     21h
        ret

m_strike db     "Strike any key when ready $"
m_crlf  db      13,10,"$"
m_badver db     "Incorrect DOS version",13,10,"$"
m_badparm db    "Invalid parameter",13,10,"$"
m_baddrv db     "Invalid drive specification",13,10,"$"
secbuf  times 512 db 0
