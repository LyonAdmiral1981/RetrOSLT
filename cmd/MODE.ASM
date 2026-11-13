; MODE -- set up printers, serial ports and the display, for NASM:
;       nasm -f bin -o MODE.COM MODE.ASM
;
;   MODE LPTn[:][chars][,[lines][,P]]       80 or 132 characters a line,
;                                           6 or 8 lines an inch, P: retry
;   MODE COMn[:]baud[,parity[,data[,stop[,P]]]]
;   MODE LPTn[:]=COMm[:]                     print through a serial port
;   MODE 40|80|BW40|BW80|CO40|CO80|MONO      the display
;   MODE [display],R|L[,T]                   shift the color display
;
; Written for RetrOS/LT to behave as PC DOS 2.10's MODE does. The first use
; that needs it (P, =COMm, or a shift) leaves a small resident part, which
; later uses of MODE find and change.
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

CR      equ     13
LF      equ     10

start:  jmp     main

; ------------------------------------------------------------------ resident
; Found by later MODEs through the INT 17h vector: the signature at the
; handler's offset - 4.
sig     db      "MODE"
int17:  cmp     dx,3
        jae     .old
        push    bx
        mov     bx,dx
        mov     bl,[cs:lptcom+bx]       ; rerouted to COM n (1-based), or 0
        or      bl,bl
        jnz     .serial
        mov     bl,dl
        cmp     ah,0
        jne     .oldbx
        cmp     byte [cs:lptretry+bx],0
        je      .oldbx
        pop     bx
.retry: push    ax                      ; print, until it is not a time-out
        pushf
        call    far [cs:old17]
        test    ah,1
        jz      .done
        pop     ax
        jmp     .retry
.done:  add     sp,2
        iret
.oldbx: pop     bx
.old:   jmp     far [cs:old17]
.serial:
        ; printer request on a serial port: AH 0 print, 1 init, 2 status
        dec     bl
        xor     bh,bh
        push    dx
        mov     dx,bx
        cmp     ah,0
        jne     .sstat
.sp:    push    ax
        mov     ah,1
        int     14h                     ; (our INT 14h retries if asked)
        test    ah,80h
        pop     ax
        jz      .sok
        cmp     byte [cs:comretry+bx],0
        jne     .sp
        mov     ah,1                    ; time-out
        jmp     .sret
.sok:
.sstat: mov     ah,90h                  ; selected, not busy
.sret:  pop     dx
        pop     bx
        iret

int14:  cmp     ah,1                    ; send, with retry if asked
        jne     .old
        cmp     dx,3
        jae     .old
        push    bx
        mov     bx,dx
        cmp     byte [cs:comretry+bx],0
        pop     bx
        je      .old
.retry: push    ax
        pushf
        call    far [cs:old14]
        test    ah,80h
        jz      .done
        pop     ax
        jmp     .retry
.done:  add     sp,2
        iret
.old:   jmp     far [cs:old14]

old17   dd      0
old14   dd      0
lptcom  db      0,0,0                   ; LPT1-3: COM port, 1-based, or 0
lptretry db     0,0,0
comretry db     0,0,0,0
vidtbl  times 88 db 0                   ; the video parameter table, shiftable
resend:

; ------------------------------------------------------------------ main
main:   mov     ah,30h
        int     21h
        cmp     al,2
        jae     .ver
        mov     dx,m_badver
        call    print
        int     20h
.ver:   ; is MODE already resident?
        mov     ax,3517h
        int     21h
        mov     [rseg],cs
        cmp     bx,int17
        jne     .notres
        cmp     word [es:sig],'MO'
        jne     .notres
        cmp     word [es:sig+2],'DE'
        jne     .notres
        mov     [rseg],es
        mov     byte [isres],1
.notres:
        ; the parameters, upper case, ending in CR
        mov     si,81h
        call    skipsp
        cmp     byte [si],CR
        je      badparm
        mov     [parm],si
        mov     di,si
.up:    lodsb
        cmp     al,'a'
        jb      .upw
        cmp     al,'z'
        ja      .upw
        sub     al,20h
.upw:   stosb
        cmp     al,CR
        jne     .up
        mov     si,[parm]
        cmp     word [si],'LP'
        jne     .notlpt
        cmp     byte [si+2],'T'
        je      lpt
.notlpt:
        cmp     word [si],'CO'
        jne     .notcom
        cmp     byte [si+2],'M'
        je      com
.notcom:
        jmp     display

badparm:
        mov     dx,m_badparm
        call    print
        mov     ax,4C01h
        int     21h
baddev: mov     dx,m_baddev
        call    print
        mov     ax,4C01h
        int     21h

; ------------------------------------------------------------------ LPT
lpt:    mov     al,[si+3]
        sub     al,'1'
        cmp     al,2
        ja      baddev
        mov     [lptn],al
        add     si,4
        cmp     byte [si],':'
        jne     .nc
        inc     si
.nc:    call    skipsp
        cmp     byte [si],'='
        je      reroute
        ; MODE LPTn alone: cancel any rerouting
        cmp     byte [si],CR
        jne     .chars
        call    resident
        mov     es,[rseg]
        mov     bl,[lptn]
        xor     bh,bh
        mov     byte [es:lptcom+bx],0
        call    lptname
        mov     dx,m_notrr
        call    print
        jmp     finish
.chars: cmp     byte [si],','
        je      .lines
        call    getnum
        jc      badparm
        mov     bl,12h                  ; DC2: 80 characters (end condensed)
        cmp     ax,80
        je      .setc
        mov     bl,0Fh                  ; SI: condensed, 132
        cmp     ax,132
        jne     badparm
.setc:  mov     al,bl
        call    toprinter
        call    lptname
        mov     dx,m_setfor
        call    print
        mov     ax,[num]
        call    putnum
        call    crlf
.lines: call    skipsp
        cmp     byte [si],','
        jne     .done
        inc     si
        call    skipsp
        cmp     byte [si],','
        je      .retry
        cmp     byte [si],CR
        je      .done
        call    getnum
        jc      badparm
        mov     bl,'2'                  ; ESC 2: 6 lines an inch
        cmp     ax,6
        je      .setl
        mov     bl,'0'                  ; ESC 0: 8 lines an inch
        cmp     ax,8
        jne     badparm
.setl:  mov     al,27
        call    toprinter
        mov     al,bl
        call    toprinter
        mov     dx,m_lpi
        call    print
.retry: call    skipsp
        cmp     byte [si],','
        jne     .done
        inc     si
        call    skipsp
        cmp     byte [si],'P'
        jne     .done
        call    resident
        mov     es,[rseg]
        mov     bl,[lptn]
        xor     bh,bh
        mov     byte [es:lptretry+bx],1
        mov     dx,m_retry
        call    print
.done:  jmp     finish

; send AL to printer LPTN
toprinter:
        push    dx
        mov     dl,[lptn]
        xor     dh,dh
        mov     ah,0
        int     17h
        pop     dx
        ret

reroute:
        inc     si
        call    skipsp
        cmp     word [si],'CO'
        jne     baddev
        cmp     byte [si+2],'M'
        jne     baddev
        mov     al,[si+3]
        sub     al,'0'
        cmp     al,1
        jb      baddev
        cmp     al,2
        ja      baddev
        mov     [comn],al
        call    resident
        mov     es,[rseg]
        mov     bl,[lptn]
        xor     bh,bh
        mov     al,[comn]
        mov     [es:lptcom+bx],al
        call    lptname
        mov     dx,m_rr
        call    print
        mov     al,[comn]
        add     al,'0'
        mov     [m_comx],al
        mov     dx,m_comname
        call    print
        jmp     finish

lptname:
        mov     al,[lptn]
        add     al,'1'
        mov     [m_lptx],al
        mov     dx,m_lptname
        jmp     print

; ------------------------------------------------------------------ COM
com:    mov     al,[si+3]
        sub     al,'1'
        cmp     al,1
        ja      baddev
        mov     [comn],al
        add     si,4
        cmp     byte [si],':'
        jne     .nc
        inc     si
.nc:    call    skipsp
        ; baud: the first two digits are enough
        mov     ax,[si]
        mov     di,bauds
        mov     cx,8
.b:     cmp     ax,[di]
        je      .bok
        add     di,3
        loop    .b
        jmp     badparm
.bok:   mov     bl,[di+2]               ; the INT 14h bits
        mov     [cfg],bl
        sub     di,bauds
        mov     ax,di
        mov     cl,3
        div     cl
        mov     [baudi],al
.bskip: lodsb                           ; past the rest of the number
        cmp     al,'0'
        jb      .bend
        cmp     al,'9'
        jbe     .bskip
.bend:  dec     si
        mov     byte [parity],'E'
        mov     byte [databits],7
        mov     byte [stopbits],1
        cmp     byte [baudi],0          ; 110 baud: two stop bits
        jne     .p
        mov     byte [stopbits],2
.p:     call    nextfield
        jc      .set
        jz      .d
        cmp     al,'N'
        je      .pset
        cmp     al,'O'
        je      .pset
        cmp     al,'E'
        jne     badparm
.pset:  mov     [parity],al
.d:     call    nextfield
        jc      .set
        jz      .s
        sub     al,'0'
        cmp     al,7
        je      .dset
        cmp     al,8
        jne     badparm
.dset:  mov     [databits],al
.s:     call    nextfield
        jc      .set
        jz      .r
        sub     al,'0'
        cmp     al,1
        je      .sset
        cmp     al,2
        jne     badparm
.sset:  mov     [stopbits],al
.r:     call    nextfield
        jc      .set
        jz      .set
        cmp     al,'P'
        jne     badparm
        mov     byte [comp],1
.set:   ; the ROM's initialization byte: baud | parity | stop | length
        mov     al,[cfg]
        cmp     byte [parity],'O'
        jne     .pe
        or      al,08h
.pe:    cmp     byte [parity],'E'
        jne     .ps
        or      al,18h
.ps:    cmp     byte [stopbits],2
        jne     .st
        or      al,04h
.st:    or      al,02h                  ; 7 bits
        cmp     byte [databits],8
        jne     .ln
        or      al,01h                  ; 8 bits
.ln:    xor     ah,ah
        mov     dl,[comn]
        xor     dh,dh
        int     14h
        cmp     byte [comp],0
        je      .noret
        call    resident
        mov     es,[rseg]
        mov     bl,[comn]
        xor     bh,bh
        mov     byte [es:comretry+bx],1
.noret: ; "COM1: 9600,e,7,1,-"
        mov     al,[comn]
        add     al,'1'
        mov     [m_comy],al
        mov     dx,m_comset
        call    print
        mov     al,[baudi]
        mov     ah,6
        mul     ah
        add     ax,baudtxt
        mov     dx,ax
        call    print
        mov     dl,','
        call    putc
        mov     dl,[parity]
        or      dl,20h
        call    putc
        mov     dl,','
        call    putc
        mov     dl,[databits]
        add     dl,'0'
        call    putc
        mov     dl,','
        call    putc
        mov     dl,[stopbits]
        add     dl,'0'
        call    putc
        mov     dl,','
        call    putc
        mov     dl,'-'
        cmp     byte [comp],0
        je      .pm
        mov     dl,'p'
.pm:    call    putc
        call    crlf
        jmp     finish

; the next field after a comma: CF if there is none (end of line), ZF if it
; is empty (two commas), else AL = its first character, SI past it
nextfield:
        call    skipsp
        cmp     byte [si],','
        je      .comma
        stc
        ret
.comma: inc     si
        call    skipsp
        mov     al,[si]
        cmp     al,','
        je      .empty
        cmp     al,CR
        je      .empty
        inc     si
        or      al,al                   ; ZF clear (AL is not 0)
        clc
        ret
.empty: cmp     al,al                   ; ZF set, CF clear
        ret

; ------------------------------------------------------------------ display
display:
        ; a display mode first?
        mov     di,modes
.m:     cmp     byte [di],0
        je      .shift
        push    si
        mov     bx,di
.mc:    mov     al,[di]
        or      al,al
        jz      .mend
        cmp     al,[si]
        jne     .mno
        inc     di
        inc     si
        jmp     .mc
.mend:  mov     al,[si]                 ; the name must end here
        cmp     al,CR
        je      .mhit
        cmp     al,','
        je      .mhit
        cmp     al,' '
        je      .mhit
.mno:   pop     si
        mov     di,bx
.mskip: inc     di
        cmp     byte [di-1],0
        jne     .mskip
        inc     di                      ; past the mode byte
        jmp     .m
.mhit:  add     sp,2
        mov     al,[di+1]
        mov     [newmode],al
.shift: ; then ,R or ,L and ,T: all read before anything is done, so a
        ; mistake changes nothing
        call    skipsp
        cmp     byte [si],','
        jne     .end
        inc     si
        call    skipsp
        mov     al,[si]
        cmp     al,'R'
        je      .sh
        cmp     al,'L'
        jne     badparm
.sh:    mov     [dir],al
        inc     si
        call    skipsp
        cmp     byte [si],','
        jne     .end
        inc     si
        call    skipsp
        cmp     byte [si],'T'
        jne     badparm
        inc     si
        mov     byte [wanttest],1
.end:   call    skipsp
        cmp     byte [si],CR            ; anything left over is wrong
        jne     badparm
        cmp     byte [newmode],0FDh     ; none named
        je      .nomode
        mov     al,[newmode]
        call    setmode
.nomode:
        cmp     byte [dir],0
        je      .done
        call    shift
        cmp     byte [wanttest],0
        je      .done
        call    testpattern
.done:  jmp     finish
newmode db      0FDh
wanttest db     0

; AL = 0-3 or 7: that mode; 0FEh or 0FFh: 40 or 80 columns, color on if it
; is on now. The equipment flags (0040:0010) say which adapter is used.
setmode:
        cmp     al,0FEh
        jb      .fixed
        mov     bl,al
        mov     ah,0Fh
        int     10h                     ; AL = the current mode
        mov     bh,0                    ; color off
        cmp     al,1
        je      .on
        cmp     al,3
        jne     .off
.on:    mov     bh,1
.off:   mov     al,bh                   ; 40: mode 0 or 1
        cmp     bl,0FEh
        je      .fixed
        add     al,2                    ; 80: mode 2 or 3
.fixed: push    ds
        xor     bx,bx
        mov     ds,bx
        mov     bl,[410h]
        and     bl,0CFh
        mov     ah,30h                  ; monochrome adapter
        cmp     al,7
        je      .eq
        mov     ah,10h                  ; color adapter, 40 columns
        cmp     al,1
        jbe     .eq
        mov     ah,20h                  ; color adapter, 80 columns
.eq:    or      bl,ah
        mov     [410h],bl
        pop     ds
        xor     ah,ah
        int     10h
        ret

; 40 and 80 keep the current color state; the table has 0FEh and 0FFh for
; them, worked out here
modes:  db      "BW40",0,0
        db      "BW80",0,2
        db      "CO40",0,1
        db      "CO80",0,3
        db      "MONO",0,7
        db      "40",0,0FEh
        db      "80",0,0FFh
        db      0

; shift the color display one position (two in 80 columns) R or L, through
; a copy of the ROM's video parameter table, so that it lasts across mode
; changes
shift:  push    si
        call    shift1
        pop     si
        ret
shift1: call    resident
        ; the table: copy the ROM's into ours once
        push    ds
        xor     ax,ax
        mov     ds,ax
        lds     si,[1Dh*4]
        mov     es,[cs:rseg]
        mov     ax,ds
        cmp     ax,[cs:rseg]
        je      .have
        mov     di,vidtbl
        mov     cx,88
        rep     movsb
        xor     ax,ax
        mov     ds,ax
        cli
        mov     word [1Dh*4],vidtbl
        mov     ax,[cs:rseg]
        mov     [1Dh*4+2],ax
        sti
.have:  pop     ds
        mov     ah,0Fh
        int     10h                     ; AL = current mode
        cmp     al,7
        je      .no
        mov     bx,0                    ; 40 columns: table 0
        cmp     al,2
        jb      .t
        mov     bx,16                   ; 80: table 1
        cmp     al,4
        jb      .t
        mov     bx,32                   ; graphics: table 2
.t:     mov     es,[rseg]
        mov     dl,[es:vidtbl+bx+2]     ; R2, horizontal sync position
        mov     cl,1                    ; one character in 40 columns,
        or      bx,bx                   ; two in 80
        jz      .d
        mov     cl,2
.d:     cmp     byte [dir],'R'
        jne     .left
        sub     dl,cl
        jmp     .set
.left:  add     dl,cl
.set:   mov     [es:vidtbl+bx+2],dl
        push    ax
        mov     dx,3D4h                 ; and on the screen now
        mov     al,2
        out     dx,al
        inc     dx
        mov     al,[es:vidtbl+bx+2]
        out     dx,al
        pop     ax
        ret
.no:    mov     dx,m_noshift
        call    print
        ret

testpattern:
.again: mov     ah,0Fh                  ; as many digits as the screen is wide
        int     10h
        mov     cl,ah
        xor     ch,ch
        mov     dx,m_pattern
        mov     bx,1
        mov     ah,40h
        int     21h
        call    crlf
        mov     dx,m_left
        cmp     byte [dir],'L'
        je      .ask
        mov     dx,m_right
.ask:   call    print
        mov     ah,0Ch
        mov     al,1
        int     21h
        push    ax
        call    crlf
        pop     ax
        and     al,0DFh
        cmp     al,'Y'
        je      .done
        call    shift
        jmp     .again
.done:  ret

; ------------------------------------------------------------------ common
; Make sure the resident part is installed: hook INT 17h and 14h, and note
; that the program must stay.
resident:
        cmp     byte [isres],0
        jne     .r
        cmp     byte [staying],0
        jne     .r
        mov     byte [staying],1
        push    es
        mov     ax,3517h
        int     21h
        mov     [old17],bx
        mov     [old17+2],es
        mov     ax,3514h
        int     21h
        mov     [old14],bx
        mov     [old14+2],es
        pop     es
        mov     dx,int17
        mov     ax,2517h
        int     21h
        mov     dx,int14
        mov     ax,2514h
        int     21h
        mov     dx,m_resload
        call    print
.r:     ret

finish: cmp     byte [staying],0
        je      .exit
        mov     dx,resend+15
        mov     cl,4
        shr     dx,cl
        mov     ax,3100h
        int     21h
.exit:  mov     ax,4C00h
        int     21h

skipsp: cmp     byte [si],' '
        je      .s
        cmp     byte [si],9
        jne     .r
.s:     inc     si
        jmp     skipsp
.r:     ret

; a decimal number at SI: AX (and NUM); CF if none
getnum: xor     ax,ax
        xor     cx,cx
.lp:    mov     bl,[si]
        sub     bl,'0'
        cmp     bl,9
        ja      .end
        inc     cx
        inc     si
        mov     bh,10
        mul     bh
        add     al,bl
        adc     ah,0
        jmp     .lp
.end:   mov     [num],ax
        cmp     cx,1
        ret

putnum: mov     bx,10
        xor     cx,cx
.d:     xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     .d
.o:     pop     dx
        add     dl,'0'
        call    putc
        loop    .o
        ret

putc:   mov     ah,2
        int     21h
        ret
crlf:   mov     dx,m_crlf
print:  mov     ah,9
        int     21h
        ret

bauds:  db      "11",000h, "15",020h, "30",040h, "60",060h
        db      "12",080h, "24",0A0h, "48",0C0h, "96",0E0h
baudtxt db      "110$  150$  300$  600$  1200$ 2400$ 4800$ 9600$ "

parm    dw      0
num     dw      0
rseg    dw      0
isres   db      0
staying db      0
lptn    db      0
comn    db      0
cfg     db      0
baudi   db      0
parity  db      'E'
databits db     7
stopbits db     1
comp    db      0
dir     db      0                       ; R or L, if a shift was asked for

m_badver db     "Incorrect DOS version",CR,LF,"$"
m_badparm db    "Invalid parameters",CR,LF,"$"
m_baddev db     "Illegal device name",CR,LF,"$"
m_lptname db    "LPT"
m_lptx  db      "1: $"
m_setfor db     "set for $"
m_lpi   db      "Printer lines per inch set",CR,LF,"$"
m_retry db      "Infinite retry on parallel printer timeout",CR,LF,"$"
m_notrr db      "not rerouted",CR,LF,"$"
m_rr    db      "rerouted to $"
m_comname db    "COM"
m_comx  db      "1:",CR,LF,"$"
m_comset db     "COM"
m_comy  db      "1: $"
m_resload db    "Resident portion of MODE loaded",CR,LF,"$"
m_noshift db    "Unable to shift screen",CR,LF,"$"
m_pattern db    "0123456789012345678901234567890123456789"
        db      "0123456789012345678901234567890123456789"
m_left  db      "Do you see the leftmost 0? (Y/N) $"
m_right db      "Do you see the rightmost 9? (Y/N) $"
m_crlf  db      CR,LF,"$"
