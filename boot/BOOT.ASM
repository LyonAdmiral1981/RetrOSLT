; RetrOS/LT boot sector, for NASM:  nasm -f bin -o BOOT.BIN BOOT.ASM
;
; The ROM BIOS loads this sector at 0000:7C00 and jumps to it. It finds
; RETBIO.COM and RETDOS.COM as the first two entries of the root directory,
; as DOS 2 requires, loads RETBIO.COM (which must be contiguous, as FORMAT /S
; and SYS lay it down) at 0070:0000, a track at a time, and jumps to it with
; the drive in DL. RETBIO.COM loads RETDOS.COM itself.
;
; It works on a diskette and on the DOS partition of a fixed disk, whose
; master boot record loads it with DL = 80h. The IBM PC's first ROM BIOS
; does not say which drive it started from, so a diskette is taken to be
; drive 0, and a volume whose media byte is F8h the first fixed disk.
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     7C00h

DIRBUF  equ     7E00h           ; one sector of the root directory
DPTCOPY equ     0522h           ; the diskette parameters, as DOS 2 keeps them
IOSEG   equ     0070h

start:  jmp     short boot
        nop
oem:    db      "RETROSLT"
; BIOS parameter block (360 KB diskette; FORMAT and SYS write the real one)
bps:    dw      512
spc:    db      2
res:    dw      1
nfats:  db      2
rootn:  dw      112
totsec: dw      720
media:  db      0FDh
fatsz:  dw      2
spt:    dw      9
heads:  dw      2
hidden: dw      0

boot:   cli
        xor     ax,ax
        mov     ss,ax
        mov     sp,7C00h
        mov     ds,ax
        mov     es,ax
        sti
        cld
        ; which drive
        xor     dl,dl
        cmp     byte [media],0F8h
        jne     .flop
        mov     dl,80h
.flop:  mov     [drive],dl
        ; the diskette parameter table, with this disk's sectors per track
        push    ds
        lds     si,[1Eh*4]
        mov     di,DPTCOPY
        mov     cx,11
        rep     movsb
        pop     ds
        mov     al,[spt]
        mov     [DPTCOPY+4],al
        cli
        mov     word [1Eh*4],DPTCOPY
        mov     word [1Eh*4+2],0
        sti
        xor     ah,ah
        int     13h                     ; reset, with the new table
        ; the root directory
        mov     al,[nfats]
        cbw
        mul     word [fatsz]
        add     ax,[res]
        add     ax,[hidden]
        mov     [rootsec],ax
        mov     bx,DIRBUF
        call    readsec
        jc      bootfail
        mov     si,DIRBUF
        mov     di,ioname
        mov     cx,11
        repe    cmpsb
        jne     nosys
        mov     si,DIRBUF+32
        mov     cx,11
        repe    cmpsb                   ; di now at dosname
        jne     nosys
        ; the first data sector
        mov     ax,[rootn]
        mov     cl,4
        shr     ax,cl
        add     ax,[rootsec]
        mov     bx,ax
        ; RETBIO.COM: cluster and length
        mov     ax,[DIRBUF+26]
        sub     ax,2
        mov     cl,[spc]
        xor     ch,ch
        mul     cx
        add     ax,bx                   ; its first sector
        mov     dx,[DIRBUF+28]
        add     dx,511
        mov     cl,9
        shr     dx,cl                   ; its sectors (it is under 64K)
        mov     cx,dx
        mov     bx,IOSEG
        mov     es,bx
        xor     bx,bx
.load:  push    ax                      ; a track at a time: to its end,
        xor     dx,dx                   ; or as many as are left
        div     word [spt]
        mov     di,[spt]
        sub     di,dx
        pop     ax
        cmp     di,cx
        jbe     .n
        mov     di,cx
.n:     xchg    ax,di
        mov     [count],al
        xchg    ax,di
        push    cx
        call    readsec
        pop     cx
        jc      bootfail
        add     ax,di
        sub     cx,di
        xchg    ax,di
        mov     dl,9
        xchg    cx,dx
        shl     ax,cl
        xchg    cx,dx
        add     bx,ax
        xchg    ax,di
        or      cx,cx
        jnz     .load
        mov     dl,[drive]
        jmp     IOSEG:0

; Read COUNT sectors from sector AX (from the start of the disk, and not
; past the end of its track) to ES:BX. CF on failure.
readsec:
        push    ax
        push    bx
        mov     si,3                    ; tries
.try:   push    ax
        xor     dx,dx
        div     word [spt]
        mov     cl,dl
        inc     cl                      ; sector
        xor     dx,dx
        div     word [heads]
        mov     dh,dl                   ; head
        mov     ch,al                   ; cylinder
        ror     ah,1
        ror     ah,1
        and     ah,0C0h
        or      cl,ah
        mov     dl,[drive]
        mov     ah,2
        mov     al,[count]
        int     13h
        pop     ax
        jnc     .ok
        push    ax
        xor     ah,ah
        int     13h
        pop     ax
        dec     si
        jnz     .try
        stc
.ok:    pop     bx
        pop     ax
        ret

nosys:  mov     si,msgnosys
        call    print
        xor     ah,ah
        int     16h
        int     19h

bootfail:
        mov     si,msgfail
        call    print
.halt:  jmp     .halt

print:  lodsb
        or      al,al
        jz      .done
        mov     ah,14
        mov     bx,7
        int     10h
        jmp     print
.done:  ret

drive:  db      0
count:  db      1               ; sectors a read
rootsec: dw     0
ioname: db      "RETBIO  COM"
dosname: db     "RETDOS  COM"
msgnosys: db    13,10,"Non-System disk or disk error",13,10
        db      "Replace and strike any key when ready",13,10,0
msgfail: db     13,10,"Disk Boot failure",13,10,0

        times   510-($-$$) db 0
        dw      0AA55h
