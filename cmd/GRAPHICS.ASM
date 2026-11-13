; GRAPHICS -- print the graphics screen with Shift-PrtSc, for NASM:
;       nasm -f bin -o GRAPHICS.COM GRAPHICS.ASM
;
;       GRAPHICS
;
; Written for RetrOS/LT to behave as PC DOS 2.10's GRAPHICS does. It stays
; resident and takes INT 5, the print-screen interrupt. In a text mode the
; ROM BIOS prints the screen as before; in the color graphics modes the
; screen goes to the IBM Graphics Printer as dots, sideways on the paper:
; 640x200 one dot for a dot, 320x200 two by two dots for a dot, in four
; shades for the four colors. The status byte at 0050:0000 is kept as the
; ROM keeps it: 1 while printing, 0 when done, 0FFh after an error.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

ESC     equ     27

start:  jmp     install

sig     db      "GRAPHICS"
old5    dd      0

int5:   push    ax
        push    bx
        mov     ah,0Fh
        int     10h
        cmp     al,4                    ; 4, 5, 6: the graphics modes
        jb      .rom
        cmp     al,6
        jbe     .ours
.rom:   pop     bx
        pop     ax
        jmp     far [cs:old5]
.ours:  push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    bp
        mov     bl,al                   ; the mode
        xor     ax,ax
        mov     ds,ax
        cmp     byte [500h],1           ; already printing
        je      .exit
        mov     byte [500h],1
        sti
        mov     ax,0B800h
        mov     es,ax
        push    cs
        pop     ds
        mov     [hires],bl
        sub     byte [hires],6          ; 0: 640x200
        call    pscreen
        xor     ax,ax
        mov     ds,ax
        mov     byte [500h],0
        jnc     .exit
        mov     byte [500h],0FFh
.exit:  pop     bp
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

hires   db      0                       ; 0 for 640x200

; Print the screen at ES:0. CF on a printer error.
pscreen:
        mov     si,setup
        call    pstr
        jc      .r
        xor     bp,bp                   ; the byte column, 0-79
.line:  mov     si,gfx                  ; ESC K, 400 columns
        call    pstr
        jc      .r
        mov     dx,199                  ; from the bottom row up
.row:   mov     ax,dx                   ; the screen byte: row DX, column BP
        shr     ax,1
        mov     cx,80
        push    dx
        mul     cx
        pop     dx
        add     ax,bp
        mov     di,ax
        test    dl,1
        jz      .even
        add     di,2000h
.even:  mov     al,[es:di]
        cmp     byte [hires],0
        jne     .med
        call    pchar                   ; 640x200: the byte, twice
        jc      .r
        call    pchar
        jc      .r
        jmp     .next
.med:   call    shades                  ; 320x200: two columns
        mov     al,bl
        call    pchar
        jc      .r
        mov     al,bh
        call    pchar
        jc      .r
.next:  dec     dx
        jns     .row
        mov     al,13
        call    pchar
        jc      .r
        mov     al,10
        call    pchar
        jc      .r
        inc     bp
        cmp     bp,80
        jb      .line
        mov     si,reset
        call    pstr
.r:     ret

; AL = four 320x200 dots: BL, BH = the two printer columns for them
shades: xor     bx,bx
        mov     cx,4
.dot:   shl     bl,1                    ; two printer dots down for each
        shl     bl,1
        shl     bh,1
        shl     bh,1
        rol     al,1
        rol     al,1
        push    ax
        and     al,3
        jz      .c
        cmp     al,3
        jne     .c12
        or      bx,0303h                ; color 3: all four dots
        jmp     .c
.c12:   cmp     al,2
        jne     .c1
        or      bx,0102h                ; color 2: two, corner to corner
        jmp     .c
.c1:    or      bx,0002h                ; color 1: one
.c:     pop     ax
        loop    .dot
        ret

; Print the counted string at SI; CF on an error
pstr:   lodsb
        mov     cl,al
        xor     ch,ch
.lp:    lodsb
        push    cx
        call    pchar
        pop     cx
        jc      .r
        loop    .lp
.r:     ret

; Print AL on LPT1; CF on an error (timed out, out of paper, or I/O error)
pchar:  push    dx
        push    ax
        xor     dx,dx
        xor     ah,ah
        int     17h
        test    ah,29h
        pop     ax
        pop     dx
        jz      .ok
        stc
        ret
.ok:    clc
        ret

setup   db      5, ESC,"A",8,ESC,"2"    ; lines 8/72 inch apart
gfx     db      4, ESC,"K",144,1        ; 400 dots across
reset   db      5, ESC,"A",12,ESC,"2"   ; and back to 1/6 inch
resend:

; ------------------------------------------------------------------ install
install:
        mov     ax,3505h
        int     21h
        cmp     bx,int5
        jne     .new
        mov     si,sig
        mov     di,si
        mov     cx,8
        repe    cmpsb
        je      .done                   ; already there
.new:   mov     [old5],bx
        mov     [old5+2],es
        mov     dx,int5
        mov     ax,2505h
        int     21h
        mov     dx,resend+15
        mov     cl,4
        shr     dx,cl
        mov     ax,3100h
        int     21h
.done:  mov     ax,4C00h
        int     21h
