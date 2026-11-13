; ANSI.SYS -- the extended screen and keyboard driver, for NASM:
;       nasm -f bin -o ANSI.SYS ANSI.ASM
;
;       DEVICE=ANSI.SYS                 in CONFIG.SYS
;
; Written for RetrOS/LT to behave as PC DOS 2.10's ANSI.SYS does. It takes
; the place of CON, writes through the ROM BIOS with an attribute of its own,
; and acts on these escape sequences (ESC [ ...):
;
;       r;cH  r;cf      cursor position     nA nB nC nD   up down right left
;       s  u            save, restore       6n            report position
;       2J              clear the screen    K             erase to end of line
;       p;...m          attributes: 0 1 4 5 7 8 30-37 40-47
;       =nh  =nl        screen mode 0-6; 7 wraps (h) or not (l) at the end
;       k;"string";...p reassign a key (0;s for an extended key)
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     0

ESC     equ     27
MAXPARM equ     128                     ; bytes of parameters in one sequence
KEYSIZE equ     512                     ; room for reassigned keys

header: dd      -1
        dw      8013h                   ; character, standard input and output,
        dw      strategy                ; and INT 29h output
        dw      interrupt
        db      "CON     "

rhptr   dd      0

strategy:
        mov     [cs:rhptr],bx
        mov     [cs:rhptr+2],es
        retf

interrupt:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    bp
        push    cs
        pop     ds
        les     bx,[rhptr]
        mov     al,[es:bx+2]
        cmp     al,10
        ja      .unk
        xor     ah,ah
        mov     si,ax
        shl     si,1
        mov     word [es:bx+3],0100h    ; done
        call    [cmdtab+si]
.exit:  pop     bp
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        retf
.unk:   mov     word [es:bx+3],8103h    ; unknown command
        jmp     .exit

cmdtab: dw      init, nothing, nothing, unknown, read, peek, nothing, flush
        dw      write, write, nothing

unknown:
        mov     word [es:bx+3],8103h
nothing:
        ret

; ------------------------------------------------------------------ input
; Characters waiting to be read before the keyboard: a reassigned key's
; string, the second byte of an extended key, or a position report.
QSIZE   equ     128
queue   times QSIZE db 0
qhead   dw      0
qtail   dw      0
brk     db      0                       ; Ctrl-Break was pressed

; AL into the queue
qput:   push    bx
        mov     bx,[cs:qtail]
        mov     [cs:queue+bx],al
        inc     bx
        and     bx,QSIZE-1
        cmp     bx,[cs:qhead]
        je      .full
        mov     [cs:qtail],bx
.full:  pop     bx
        ret

; Fill the queue from the keyboard if it is empty. Waits for a key if
; NOWAIT is 0; otherwise returns ZF set if there is nothing.
nowait  db      0
fill:   mov     ax,[qhead]
        cmp     ax,[qtail]
        jne     .have
        cmp     byte [brk],0
        jne     .break
        cmp     byte [nowait],0
        je      .wait
        mov     ah,1
        int     16h
        jz      .r                      ; nothing yet
.wait:  cmp     byte [brk],0
        jne     .break
        mov     ah,1
        int     16h
        jz      .wait
        xor     ah,ah
        int     16h
        or      ax,ax                   ; Ctrl-Break leaves 0000
        jnz     .key
        jmp     .wait
.break: mov     byte [brk],0
        mov     al,3
        call    qput
        jmp     .have
.key:   call    keyin
.have:  or      sp,sp                   ; ZF clear: there is a character
.r:     ret

; A key, AX from INT 16h: its reassignment, or itself
keyin:  mov     dx,ax                   ; DX = the key code to look for
        or      al,al
        jz      .ext
        xor     dh,dh                   ; an ASCII key: its character alone
.ext:   mov     si,keytab
.find:  cmp     si,[keyend]
        jae     .none
        mov     cl,[si]                 ; entry: length, code (2), string
        xor     ch,ch
        cmp     [si+1],dx
        je      .found
        add     si,cx
        add     si,3
        jmp     .find
.found: add     si,3
        jcxz    .r
.f1:    lodsb
        call    qput
        loop    .f1
.r:     ret
.none:  or      al,al
        jnz     .one
        call    qput                    ; 0, then the scan code
        mov     al,ah
.one:   jmp     qput

; the next character from the queue: AL
qget:   mov     bx,[qhead]
        mov     al,[queue+bx]
        ret
qnext:  mov     bx,[qhead]
        inc     bx
        and     bx,QSIZE-1
        mov     [qhead],bx
        ret

read:   mov     cx,[es:bx+18]
        les     di,[es:bx+14]
        jcxz    .r
.lp:    push    cx
        push    es
        push    di
        mov     byte [nowait],0
        call    fill
        call    qget
        call    qnext
        pop     di
        pop     es
        pop     cx
        stosb
        loop    .lp
.r:     ret

peek:   push    es
        push    bx
        mov     byte [nowait],1
        call    fill
        pop     bx
        pop     es
        jz      .busy
        push    bx
        call    qget
        pop     bx
        mov     [es:bx+13],al
        ret
.busy:  mov     word [es:bx+3],0300h    ; busy: nothing there
        ret

flush:  mov     ax,[qtail]
        mov     [qhead],ax
        mov     byte [brk],0
.lp:    mov     ah,1
        int     16h
        jz      .r
        xor     ah,ah
        int     16h
        jmp     .lp
.r:     ret

int1b:  mov     byte [cs:brk],1
        iret

; ------------------------------------------------------------------ output
write:  mov     cx,[es:bx+18]
        les     si,[es:bx+14]
        jcxz    .r
.lp:    mov     al,[es:si]
        inc     si
        push    cx
        push    si
        push    es
        call    outchar
        pop     es
        pop     si
        pop     cx
        loop    .lp
.r:     ret

int29:  push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    bp
        push    cs
        pop     ds
        call    outchar
        pop     bp
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

attr    db      07h
wrap    db      1
state   db      0                       ; 0 text, 1 after ESC, 2 in [...]
quote   db      0                       ; in a quoted string: its quote mark
nparm   dw      0                       ; parameters complete so far
parms   times MAXPARM+1 db 0
digits  db      0                       ; the current parameter has digits
savrow  db      0
savcol  db      0
mode    db      0
cols    db      0
page    db      0
row     db      0
col     db      0

; The screen as it is now: MODE, COLS, PAGE, ROW, COL
where:  mov     ah,0Fh
        int     10h
        mov     [mode],al
        mov     [cols],ah
        mov     [page],bh
        mov     ah,3
        int     10h
        mov     [row],dh
        mov     [col],dl
        ret
; the cursor to ROW, COL
place:  mov     ah,2
        mov     bh,[page]
        mov     dh,[row]
        mov     dl,[col]
        int     10h
        ret

outchar:
        cmp     byte [state],0
        jne     escape
        cmp     al,ESC
        jne     text
        mov     byte [state],1
        ret

text:   push    ax
        call    where
        pop     ax
        cmp     al,13
        je      .cr
        cmp     al,10
        je      .lf
        cmp     al,8
        je      .bs
        cmp     al,7
        je      .bel
        cmp     byte [mode],4           ; graphics: the ROM writes it
        jb      .text
        cmp     byte [mode],7
        je      .text
        mov     ah,0Eh
        mov     bl,[attr]
        and     bl,7Fh
        int     10h
        ret
.text:  mov     ah,9
        mov     bh,[page]
        mov     bl,[attr]
        mov     cx,1
        int     10h
        inc     byte [col]
        mov     al,[col]
        cmp     al,[cols]
        jb      place
        cmp     byte [wrap],0
        jne     .wr
        dec     byte [col]
        jmp     place
.wr:    mov     byte [col],0
.lf:    cmp     byte [row],24
        jb      .down
        mov     ax,0601h                ; scroll up a line
        mov     bh,[attr]
        and     bh,7Fh
        xor     cx,cx
        mov     dh,24
        mov     dl,[cols]
        dec     dl
        int     10h
        jmp     place
.down:  inc     byte [row]
        jmp     place
.cr:    mov     byte [col],0
        jmp     place
.bs:    cmp     byte [col],0
        je      .r
        dec     byte [col]
        jmp     place
.bel:   mov     ax,0E07h
        xor     bx,bx
        int     10h
.r:     ret

escape: cmp     byte [state],1
        jne     inparm
        cmp     al,'['
        jne     .not
        mov     byte [state],2
        mov     word [nparm],0
        mov     byte [parms],0
        mov     byte [digits],0
        mov     byte [quote],0
        ret
.not:   mov     byte [state],0          ; not a sequence: the character alone
        jmp     text

inparm: mov     bx,[nparm]
        cmp     byte [quote],0
        je      .noq
        cmp     al,[quote]              ; the end of the string
        je      .endq
        cmp     bx,MAXPARM-1
        jae     .r
        mov     [parms+bx],al
        inc     word [nparm]
        mov     byte [parms+bx+1],0
.r:     ret
.endq:  mov     byte [quote],0
        mov     byte [digits],2         ; a string ended: no number to end
        ret
.noq:   cmp     al,'"'
        je      .q
        cmp     al,"'"
        jne     .nq
.q:     mov     [quote],al
        ret
.nq:    cmp     al,'0'
        jb      .nd
        cmp     al,'9'
        ja      .nd
        sub     al,'0'                  ; a digit
        mov     cl,al
        mov     al,[parms+bx]
        mov     ah,10
        mul     ah
        add     al,cl
        mov     [parms+bx],al
        mov     byte [digits],1
        ret
.nd:    cmp     al,';'
        jne     .ns
        cmp     byte [digits],2         ; a parameter ends here (but a
        je      .sk                     ; string has already)
        call    nextparm
        ret
.sk:    mov     byte [digits],0
        ret
.ns:    cmp     al,'='                  ; = and ? before a mode number
        je      .r
        cmp     al,'?'
        je      .r
        ; the command letter
        cmp     byte [digits],1
        jne     .go
        call    nextparm
.go:    mov     byte [state],0
        mov     di,commands
.find:  cmp     byte [di],0
        je      .r
        cmp     al,[di]
        je      .hit
        add     di,3
        jmp     .find
.hit:   jmp     [di+1]

nextparm:
        mov     byte [digits],0
        cmp     word [nparm],MAXPARM-1
        jae     .r
        inc     word [nparm]
        mov     bx,[nparm]
        mov     byte [parms+bx],0
.r:     ret

commands:
        db      'H'
        dw      cup
        db      'f'
        dw      cup
        db      'A'
        dw      cuu
        db      'B'
        dw      cud
        db      'C'
        dw      cuf
        db      'D'
        dw      cub
        db      's'
        dw      scp
        db      'u'
        dw      rcp
        db      'n'
        dw      dsr
        db      'J'
        dw      ed
        db      'K'
        dw      el
        db      'm'
        dw      sgr
        db      'h'
        dw      sm
        db      'l'
        dw      rm
        db      'p'
        dw      kbd
        db      0

; AL = parameter BX (0 if it is not there), or 1 if it is 0
p1:     mov     al,0
        cmp     bx,[nparm]
        jae     .z
        mov     al,[parms+bx]
.z:     or      al,al
        jnz     .r
        inc     al
.r:     ret

cup:    call    where
        xor     bx,bx
        call    p1
        dec     al
        cmp     al,24
        ja      .c
        mov     [row],al
.c:     mov     bx,1
        call    p1
        dec     al
        cmp     al,[cols]
        jae     .p
        mov     [col],al
.p:     jmp     place

cuu:    call    where
        xor     bx,bx
        call    p1
        sub     [row],al
        jnc     place
        mov     byte [row],0
        jmp     place
cud:    call    where
        xor     bx,bx
        call    p1
        add     al,[row]
        cmp     al,24
        jbe     .s
        mov     al,24
.s:     mov     [row],al
        jmp     place
cuf:    call    where
        xor     bx,bx
        call    p1
        add     al,[col]
        jc      .e
        cmp     al,[cols]
        jb      .s
.e:     mov     al,[cols]
        dec     al
.s:     mov     [col],al
        jmp     place
cub:    call    where
        xor     bx,bx
        call    p1
        sub     [col],al
        jnc     place
        mov     byte [col],0
        jmp     place

scp:    call    where
        mov     al,[row]
        mov     [savrow],al
        mov     al,[col]
        mov     [savcol],al
        ret
rcp:    call    where
        mov     al,[savrow]
        mov     [row],al
        mov     al,[savcol]
        mov     [col],al
        jmp     place

; ESC[6n: ESC[rr;ccR into the input
dsr:    cmp     word [nparm],1
        jne     .r
        cmp     byte [parms],6
        jne     .r
        call    where
        mov     al,ESC
        call    qput
        mov     al,'['
        call    qput
        mov     al,[row]
        inc     al
        call    put2
        mov     al,';'
        call    qput
        mov     al,[col]
        inc     al
        call    put2
        mov     al,'R'
        call    qput
        mov     al,13
        jmp     qput
.r:     ret
put2:   aam
        add     ax,'00'
        push    ax
        mov     al,ah
        call    qput
        pop     ax
        jmp     qput

ed:     cmp     byte [parms],2
        jne     .r
        call    where
        mov     ax,0600h
        mov     bh,[attr]
        and     bh,7Fh
        xor     cx,cx
        mov     dh,24
        mov     dl,[cols]
        dec     dl
        int     10h
        mov     word [row],0            ; ROW and COL
        jmp     place
.r:     ret

el:     call    where
        mov     cl,[cols]
        sub     cl,[col]
        xor     ch,ch
        mov     ax,0920h
        mov     bh,[page]
        mov     bl,[attr]
        and     bl,7Fh
        int     10h
        ret

; attributes; the ANSI colors in IBM order
colors  db      0,4,2,6,1,5,3,7
sgr:    xor     bx,bx
        cmp     word [nparm],0
        jne     .lp
        mov     byte [attr],07h         ; none: as 0
        ret
.lp:    cmp     bx,[nparm]
        jae     .r
        mov     al,[parms+bx]
        inc     bx
        mov     ah,[attr]
        or      al,al
        jnz     .n0
        mov     ah,07h
        jmp     .set
.n0:    cmp     al,1
        jne     .n1
        or      ah,08h                  ; high intensity
        jmp     .set
.n1:    cmp     al,4
        jne     .n4
        and     ah,0F8h                 ; underscore (on the monochrome
        or      ah,01h                  ; display)
        jmp     .set
.n4:    cmp     al,5
        jne     .n5
        or      ah,80h                  ; blink
        jmp     .set
.n5:    cmp     al,7
        jne     .n7
        and     ah,88h                  ; reverse
        or      ah,70h
        jmp     .set
.n7:    cmp     al,8
        jne     .n8
        and     ah,0F0h                 ; invisible: as the background
        mov     cl,ah
        shr     cl,1
        shr     cl,1
        shr     cl,1
        shr     cl,1
        and     cl,7
        or      ah,cl
        jmp     .set
.n8:    cmp     al,30
        jb      .lp
        cmp     al,37
        ja      .bg
        sub     al,30
        push    bx
        mov     bx,colors
        xlat
        pop     bx
        and     ah,0F8h
        or      ah,al
        jmp     .set
.bg:    cmp     al,40
        jb      .lp
        cmp     al,47
        ja      .lp
        sub     al,40
        push    bx
        mov     bx,colors
        xlat
        pop     bx
        mov     cl,4
        shl     al,cl
        and     ah,8Fh
        or      ah,al
.set:   mov     [attr],ah
        jmp     .lp
.r:     ret

; =nh: screen mode n (0-6), or 7: wrap at the end of a line
sm:     mov     al,[parms]
        cmp     al,7
        je      .wrap
        ja      .r
        xor     ah,ah
        int     10h
.r:     ret
.wrap:  mov     byte [wrap],1
        ret
rm:     mov     al,[parms]
        cmp     al,7
        jne     sm
        mov     byte [wrap],0
        ret

; k;...p: the key (one number, or 0 and a number for an extended key, or a
; quoted character) and what it now gives. Nothing after the key puts it
; back as it was.
kbd:    mov     cx,[nparm]
        jcxz    .r
        mov     si,parms
        lodsb
        dec     cx
        xor     ah,ah
        or      al,al
        jnz     .key
        jcxz    .r
        lodsb                           ; extended: 0 and the scan code
        dec     cx
        mov     ah,al
        xor     al,al
.key:   mov     dx,ax
        ; take out any old entry for this key
        mov     di,keytab
.find:  cmp     di,[keyend]
        jae     .add
        mov     bl,[di]
        xor     bh,bh
        add     bx,3
        cmp     [di+1],dx
        je      .del
        add     di,bx
        jmp     .find
.del:   push    si
        push    cx
        push    ds
        pop     es
        mov     si,di
        add     si,bx
        mov     cx,[keyend]
        sub     cx,si
        rep     movsb
        mov     [keyend],di
        pop     cx
        pop     si
.add:   jcxz    .r                      ; nothing: back as it was
        mov     di,[keyend]
        mov     ax,di
        add     ax,cx
        add     ax,3
        cmp     ax,keytab+KEYSIZE
        ja      .r                      ; no room
        push    ds
        pop     es
        mov     al,cl
        stosb
        mov     ax,dx
        stosw
        rep     movsb
        mov     [keyend],di
.r:     ret

keyend  dw      keytab
keytab:
resend  equ     keytab+KEYSIZE

; ------------------------------------------------------------------ init
; (in the reassignment table, which it no longer needs once it has run)
init:   mov     word [es:bx+14],resend
        mov     [es:bx+16],cs
        push    es
        xor     ax,ax
        mov     es,ax
        cli
        mov     word [es:29h*4],int29
        mov     [es:29h*4+2],cs
        mov     word [es:1Bh*4],int1b
        mov     [es:1Bh*4+2],cs
        sti
        pop     es
        ret
