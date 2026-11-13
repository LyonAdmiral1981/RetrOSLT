; FDISK -- the RetrOS/LT fixed disk setup program, for NASM:
;       nasm -f bin -o FDISK.COM FDISK.ASM
;
; Creates, deletes, activates and shows the partitions of the fixed disks of
; an IBM Personal Computer XT, or of a Personal Computer with a fixed disk
; adapter, in the manner of PC DOS 2.10's FDISK: a menu, sizes in cylinders,
; a DOS partition (type 01h, 12-bit FAT) of up to 65,535 sectors, the master
; boot record written with each change, and a restart when it is done.
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        cpu     8086
        org     100h

CR      equ     13
LF      equ     10
ESC     equ     27

start:  jmp     main

; ------------------------------------------------------------------ data
drive   db      80h             ; the fixed disk being set up
ndisks  db      0
cyls    dw      0               ; its geometry, from INT 13h function 8
heads   dw      0
spt     dw      0
cylsecs dw      0               ; sectors in a cylinder
maxcyl  dw      0               ; most cylinders a DOS partition may have
changed db      0               ; the partition table was written

mbr     times 512 db 0          ; the master boot record, as read
; The RetrOS/LT master boot record's code, for a disk that has none
%include "MBRCODE.INC"

; ------------------------------------------------------------------ main
main:   mov     ah,8
        mov     dl,80h
        int     13h
        jc      .nodisk
        or      dl,dl
        jz      .nodisk
        mov     [ndisks],dl
        call    geometry
        jnc     menu
.nodisk:
        mov     si,m_nodisk
        call    puts
        mov     ax,4C01h
        int     21h

; Geometry of DRIVE: CYLS, HEADS, SPT, CYLSECS, MAXCYL. CF if it cannot be
; read.
geometry:
        mov     ah,8
        mov     dl,[drive]
        int     13h
        jc      .ret
        mov     al,cl
        and     al,3Fh
        xor     ah,ah
        mov     [spt],ax
        mov     al,dh
        inc     ax
        mov     [heads],ax
        mov     al,ch
        mov     ah,cl
        rol     ah,1
        rol     ah,1
        and     ah,3
        inc     ax                      ; cylinders, from the highest
        mov     [cyls],ax
        mov     ax,[heads]
        mul     word [spt]
        mov     [cylsecs],ax
        mov     cx,ax
        mov     ax,65535                ; the most a DOS 2 volume may hold
        xor     dx,dx
        div     cx
        mov     [maxcyl],ax
        call    readmbr
.ret:   ret

readmbr:
        mov     ax,0201h
        call    mbrio
        jc      .bad
        cmp     word [mbr+510],0AA55h
        je      .ok
        ; no master boot record: a new disk, with an empty table
.bad:   mov     di,mbr
        mov     si,mbrcode
        mov     cx,1BEh
        rep     movsb
        xor     al,al
        mov     cx,64
        rep     stosb
        mov     word [mbr+510],0AA55h
.ok:    clc
        ret

; INT 13h function AH, one sector, MBR <-> cylinder 0 head 0 sector 1
mbrio:  mov     di,3
.try:   push    ax
        mov     bx,mbr
        mov     cx,1
        xor     dh,dh
        mov     dl,[drive]
        int     13h
        pop     ax
        jnc     .ok
        push    ax
        xor     ah,ah
        int     13h
        pop     ax
        dec     di
        jnz     .try
        stc
.ok:    ret

; ------------------------------------------------------------------ menu
menu:   call    cls
        mov     si,m_title
        call    puts
        mov     si,m_options
        call    puts
        mov     al,[drive]
        sub     al,80h-'1'
        call    putc
        mov     si,m_choose
        call    puts
        cmp     byte [ndisks],1
        jbe     .one
        mov     si,m_opt5
        call    puts
.one:   mov     si,m_enter
        call    puts
        mov     al,'1'
        call    getdigit                ; AL = choice, or ESC
        cmp     al,ESC
        je      quit
        cmp     al,'1'
        je      create
        cmp     al,'2'
        je      activate
        cmp     al,'3'
        je      delete
        cmp     al,'4'
        je      display
        cmp     al,'5'
        jne     menu
        cmp     byte [ndisks],1
        jbe     menu
        xor     byte [drive],1          ; 80h <-> 81h
        call    geometry
        jmp     menu

quit:   cmp     byte [changed],0
        je      .exit
        call    cls
        mov     si,m_restart
        call    puts
        xor     ah,ah
        int     16h
        int     19h                     ; start again from drive A
.exit:  call    cls
        mov     ax,4C00h
        int     21h

; ------------------------------------------------------------------ 1. create
create: call    cls
        mov     si,m_create
        call    puts
        call    finddos
        jnc     .exists
        call    freeentry
        jc      .full
        ; the largest free run of cylinders
        call    largest                 ; AX = first, CX = count
        or      cx,cx
        jz      .nospace
        mov     [freefirst],ax
        mov     [freecount],cx
        cmp     cx,[maxcyl]
        jbe     .fit
        mov     cx,[maxcyl]
.fit:   mov     [psize],cx
        mov     si,m_whole
        call    puts
        mov     al,'Y'
        call    getyn
        cmp     al,ESC
        je      .back
        cmp     al,'Y'
        jne     .ask
        mov     ax,[freefirst]
        mov     [pstart],ax
        jmp     .make
.ask:   call    cls
        mov     si,m_create
        call    puts
        mov     si,m_total
        call    puts
        mov     ax,[cyls]
        call    putnum
        mov     si,m_cylinders
        call    puts
        mov     si,m_maxavail
        call    puts
        mov     ax,[freecount]
        call    putnum
        mov     si,m_cylat
        call    puts
        mov     ax,[freefirst]
        call    putnum
        mov     si,m_dot
        call    puts
        mov     si,m_entersize
        call    puts
        mov     ax,[psize]
        call    getnum
        jc      .back
        or      ax,ax
        jz      .ask
        cmp     ax,[psize]
        ja      .ask
        mov     [psize],ax
        mov     si,m_enterstart
        call    puts
        mov     ax,[freefirst]
        call    getnum
        jc      .back
        mov     [pstart],ax
        ; it must lie within free cylinders
        mov     cx,[psize]
        call    isfree
        jc      .ask
.make:  call    makeentry
        call    writembr
        jc      .err
        mov     si,m_created
        call    puts
        jmp     .wait
.exists:
        mov     si,m_exists
        jmp     .say
.full:  mov     si,m_nofree
        jmp     .say
.nospace:
        mov     si,m_nospace
.say:   call    puts
.wait:  mov     si,m_esc
        call    puts
        call    waitesc
.back:  jmp     menu
.err:   mov     si,m_writeerr
        jmp     .say

; Fill the free entry BX with a DOS partition: PSTART cylinders, PSIZE long,
; active if no other is.
makeentry:
        mov     di,bx
        mov     byte [di],80h
        call    anyactive
        jnc     .act
        mov     byte [di],0
.act:   ; first sector: cylinder 0 starts on head 1, after the boot record
        mov     ax,[pstart]
        xor     dh,dh
        or      ax,ax
        jnz     .h0
        mov     dh,1
.h0:    mov     [di+1],dh
        call    cylsec
        mov     [di+2],cx
        mov     byte [di+4],1
        mov     ax,[pstart]
        add     ax,[psize]
        dec     ax
        mov     dl,[heads]
        dec     dl
        mov     [di+5],dl
        call    cylsec
        and     cl,0C0h
        or      cl,[spt]                ; last sector of the track
        mov     [di+6],cx
        ; sectors before it, and its length
        mov     ax,[pstart]
        mul     word [cylsecs]
        or      ax,ax
        jnz     .lba
        or      dx,dx
        jnz     .lba
        mov     ax,[spt]                ; cylinder 0: after the first track
.lba:   mov     [di+8],ax
        mov     [di+10],dx
        mov     cx,ax                   ; start
        mov     si,dx
        mov     ax,[pstart]
        add     ax,[psize]
        mul     word [cylsecs]          ; end, exclusive
        sub     ax,cx
        sbb     dx,si
        mov     [di+12],ax
        mov     [di+14],dx
        mov     byte [changed],1
        ret

; AX = cylinder: CX = its ROM form (CH low 8 bits, CL bits 6-7 the high
; two), sector field 1.
cylsec: mov     ch,al
        mov     cl,ah
        ror     cl,1
        ror     cl,1
        and     cl,0C0h
        or      cl,1
        ret

; ------------------------------------------------------------------ 2. activate
activate:
        call    cls
        mov     si,m_actitle
        call    puts
        call    showtable
        jc      .none
        mov     si,m_actask
        call    puts
        mov     al,' '
        call    getdigit
        cmp     al,ESC
        je      .back
        sub     al,'1'
        cmp     al,3
        ja      activate
        mov     bl,16
        mul     bl
        mov     bx,ax
        add     bx,mbr+1BEh
        cmp     byte [bx+4],0
        je      activate
        mov     si,mbr+1BEh
        mov     cx,4
.clr:   mov     byte [si],0
        add     si,16
        loop    .clr
        mov     byte [bx],80h
        mov     byte [changed],1
        call    writembr
        jc      .err
        mov     si,m_actdone
        call    puts
        jmp     .wait
.none:  mov     si,m_noparts
        call    puts
.wait:  mov     si,m_esc
        call    puts
        call    waitesc
.back:  jmp     menu
.err:   mov     si,m_writeerr
        call    puts
        jmp     .wait

; ------------------------------------------------------------------ 3. delete
delete: call    cls
        mov     si,m_deltitle
        call    puts
        call    finddos
        jc      .nodos
        push    bx
        call    showtable
        mov     si,m_delwarn
        call    puts
        mov     al,'N'
        call    getyn
        pop     bx
        cmp     al,'Y'
        jne     .back
        mov     di,bx
        xor     al,al
        mov     cx,16
        rep     stosb
        mov     byte [changed],1
        call    writembr
        jc      .err
        mov     si,m_deldone
        call    puts
        jmp     .wait
.nodos: mov     si,m_nodos
        call    puts
.wait:  mov     si,m_esc
        call    puts
        call    waitesc
.back:  jmp     menu
.err:   mov     si,m_writeerr
        call    puts
        jmp     .wait

; ------------------------------------------------------------------ 4. display
display:
        call    cls
        mov     si,m_distitle
        call    puts
        call    showtable
        jnc     .some
        mov     si,m_noparts
        call    puts
.some:  mov     si,m_total
        call    puts
        mov     ax,[cyls]
        call    putnum
        mov     si,m_cylinders
        call    puts
        mov     si,m_esc
        call    puts
        call    waitesc
        jmp     menu

; Show the partition table. CF if it is empty.
showtable:
        mov     si,m_tabhead
        call    puts
        mov     bx,mbr+1BEh
        mov     cl,'1'
        xor     ch,ch                   ; partitions shown
.lp:    cmp     byte [bx+4],0
        je      .next
        inc     ch
        push    cx
        mov     al,' '
        call    putc
        call    putc
        call    putc
        call    putc
        mov     al,cl
        call    putc
        mov     si,m_sp7
        call    puts
        mov     al,' '
        cmp     byte [bx],80h
        jne     .st
        mov     al,'A'
.st:    call    putc
        mov     si,m_sp5
        call    puts
        mov     si,m_dos
        cmp     byte [bx+4],1
        je      .ty
        mov     si,m_nondos
.ty:    call    puts
        mov     al,[bx+3]               ; start cylinder
        mov     ah,[bx+2]
        rol     ah,1
        rol     ah,1
        and     ah,3
        push    ax
        call    putnum5
        mov     al,[bx+7]               ; end cylinder
        mov     ah,[bx+6]
        rol     ah,1
        rol     ah,1
        and     ah,3
        push    ax
        call    putnum5
        pop     ax
        pop     dx
        sub     ax,dx
        inc     ax
        call    putnum5
        call    crlf
        pop     cx
.next:  add     bx,16
        inc     cl
        cmp     cl,'5'
        jb      .lp
        call    crlf
        cmp     ch,1
        ret                             ; CF if none

; ------------------------------------------------------------------ the table
; BX = the DOS partition's entry, CF if there is none.
finddos:
        mov     bx,mbr+1BEh
        mov     cx,4
.lp:    cmp     byte [bx+4],1
        je      .ok
        add     bx,16
        loop    .lp
        stc
        ret
.ok:    clc
        ret

; BX = an empty entry, CF if none.
freeentry:
        mov     bx,mbr+1BEh
        mov     cx,4
.lp:    cmp     byte [bx+4],0
        je      .ok
        add     bx,16
        loop    .lp
        stc
        ret
.ok:    clc
        ret

; CF clear if some partition is active.
anyactive:
        push    bx
        mov     bx,mbr+1BEh
        mov     cx,4
.lp:    cmp     byte [bx],80h
        je      .yes
        add     bx,16
        loop    .lp
        pop     bx
        stc
        ret
.yes:   pop     bx
        clc
        ret

; Is cylinder AX free for CX cylinders (and within the disk)? CF if not.
isfree: push    bx
        mov     dx,ax
        add     dx,cx                   ; end, exclusive
        cmp     dx,[cyls]
        ja      .no
        mov     bx,mbr+1BEh
        mov     si,4
.lp:    cmp     byte [bx+4],0
        je      .next
        push    ax
        mov     al,[bx+3]
        mov     ah,[bx+2]
        rol     ah,1
        rol     ah,1
        and     ah,3
        mov     di,ax                   ; its first cylinder
        mov     al,[bx+7]
        mov     ah,[bx+6]
        rol     ah,1
        rol     ah,1
        and     ah,3
        inc     ax                      ; its end, exclusive
        mov     cx,ax
        pop     ax
        cmp     ax,cx                   ; ours starts after it ends?
        jae     .next
        cmp     dx,di                   ; ours ends before it starts?
        jbe     .next
.no:    pop     bx
        stc
        ret
.next:  add     bx,16
        dec     si
        jnz     .lp
        pop     bx
        clc
        ret

; The largest run of free cylinders: AX = first, CX = count.
largest:
        xor     ax,ax
        mov     [bestfirst],ax
        mov     [bestcount],ax
        mov     [runfirst],ax
.cyl:   cmp     ax,[cyls]
        jae     .end
        push    ax
        mov     cx,1
        call    isfree
        pop     ax
        jc      .used
        inc     ax
        jmp     .cyl
.used:  call    .close
        inc     ax
        mov     [runfirst],ax
        jmp     .cyl
.end:   call    .close
        mov     ax,[bestfirst]
        mov     cx,[bestcount]
        ret
.close: mov     cx,ax
        sub     cx,[runfirst]
        cmp     cx,[bestcount]
        jbe     .cret
        mov     [bestcount],cx
        mov     dx,[runfirst]
        mov     [bestfirst],dx
.cret:  ret

writembr:
        mov     ax,0301h
        jmp     mbrio

; ------------------------------------------------------------------ the screen
cls:    mov     ax,0600h                ; scroll the whole screen away
        mov     bh,7
        xor     cx,cx
        mov     dx,184Fh
        int     10h
        mov     ah,2                    ; cursor home
        xor     bh,bh
        xor     dx,dx
        int     10h
        ret

putc:   push    ax
        push    bx
        mov     ah,14
        mov     bx,7
        int     10h
        pop     bx
        pop     ax
        ret

puts:   lodsb
        or      al,al
        jz      .done
        call    putc
        jmp     puts
.done:  ret

crlf:   mov     al,CR
        call    putc
        mov     al,LF
        jmp     putc

; AX in decimal
putnum: push    ax
        push    bx
        push    cx
        push    dx
        xor     cx,cx
        mov     bx,10
.div:   xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     .div
.out:   pop     ax
        add     al,'0'
        call    putc
        loop    .out
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX in decimal, right-aligned in 8 columns
putnum5:
        push    bx
        push    cx
        push    dx
        push    ax
        mov     cx,8
        mov     bx,10
.cnt:   xor     dx,dx
        div     bx
        dec     cx
        or      ax,ax
        jnz     .cnt
.pad:   mov     al,' '
        call    putc
        loop    .pad
        pop     ax
        call    putnum
        pop     dx
        pop     cx
        pop     bx
        ret

; [D] at the cursor; one digit 1-5, Enter for D, or Esc. AL = it.
getdigit:
        mov     [dflt],al
        call    showdef
.key:   xor     ah,ah
        int     16h
        cmp     al,ESC
        je      .ret
        cmp     al,CR
        je      .enter
        cmp     al,'1'
        jb      .key
        cmp     al,'5'
        ja      .key
        mov     [dflt],al
        call    redraw
        jmp     .key
.enter: mov     al,[dflt]
        cmp     al,' '
        je      .key
        push    ax
        call    crlf
        pop     ax
.ret:   ret

; [Y] or [N]: AL = 'Y' or 'N' after Enter, or ESC.
getyn:  mov     [dflt],al
        call    showdef
.key:   xor     ah,ah
        int     16h
        cmp     al,ESC
        je      .ret
        cmp     al,CR
        je      .enter
        and     al,0DFh
        cmp     al,'Y'
        je      .set
        cmp     al,'N'
        jne     .key
.set:   mov     [dflt],al
        call    redraw
        jmp     .key
.enter: call    crlf
        mov     al,[dflt]
.ret:   ret

showdef:
        mov     al,'['
        call    putc
        mov     al,[dflt]
        call    putc
        mov     al,']'
        call    putc
        mov     al,8
        call    putc
        mov     al,8
        jmp     putc
redraw: mov     al,[dflt]
        call    putc
        mov     al,8
        jmp     putc

; A number, default AX, up to 5 digits, in [ ]. AX = it; CF if Esc.
getnum: mov     [numval],ax
        mov     al,'['
        call    putc
        mov     ah,3                    ; where the field starts
        xor     bh,bh
        int     10h
        mov     [fieldpos],dx
        mov     ax,[numval]
        call    putnum
        mov     al,']'
        call    putc
        mov     byte [ndig],0
        mov     word [typed],0
.key:   xor     ah,ah
        int     16h
        cmp     al,ESC
        je      .esc
        cmp     al,CR
        je      .enter
        cmp     al,8
        je      .key
        cmp     al,'0'
        jb      .key
        cmp     al,'9'
        ja      .key
        cmp     byte [ndig],5
        jae     .key
        cmp     byte [ndig],0
        jne     .more
        push    ax                      ; the first digit: clear the field
        mov     ah,2
        xor     bh,bh
        mov     dx,[fieldpos]
        int     10h
        mov     si,m_blank
        call    puts
        mov     ah,2
        xor     bh,bh
        mov     dx,[fieldpos]
        int     10h
        pop     ax
.more:  inc     byte [ndig]
        call    putc
        sub     al,'0'
        xor     ah,ah
        push    ax
        mov     ax,[typed]
        mov     bx,10
        mul     bx
        pop     bx
        add     ax,bx
        mov     [typed],ax
        jmp     .key
.enter: call    crlf
        mov     ax,[numval]
        cmp     byte [ndig],0
        je      .ok
        mov     ax,[typed]
.ok:    clc
        ret
.esc:   stc
        ret

waitesc:
        xor     ah,ah
        int     16h
        cmp     al,ESC
        jne     waitesc
        ret

; ------------------------------------------------------------------ words
dflt    db      0
numval  dw      0
typed   dw      0
ndig    db      0
fieldpos dw     0
psize   dw      0
pstart  dw      0
freefirst dw    0
freecount dw    0
bestfirst dw    0
bestcount dw    0
runfirst dw     0

m_title db      "            RetrOS/LT Fixed Disk Setup Program Version 1.00",CR,LF
        db      "        (C) Copyright Republic Lyon Mountain Corporation 2026",CR,LF,LF,0
m_options db    "                              FDISK Options",CR,LF,LF
        db      "Current Fixed Disk Drive: ",0
m_choose db     CR,LF,LF,"Choose one of the following:",CR,LF,LF
        db      "     1. Create DOS Partition",CR,LF
        db      "     2. Change Active Partition",CR,LF
        db      "     3. Delete DOS Partition",CR,LF
        db      "     4. Display Partition Information",CR,LF,0
m_opt5  db      "     5. Select Next Fixed Disk Drive",CR,LF,0
m_enter db      LF,LF,"Enter choice: ",0
m_create db     "                         Create DOS Partition",CR,LF,LF,0
m_whole db      "Do you wish to use the entire fixed disk for DOS (Y/N).....? ",0
m_total db      "Total fixed disk space is ",0
m_cylinders db  " cylinders.",CR,LF,0
m_maxavail db   "Maximum available space is ",0
m_cylat db      " cylinders at cylinder ",0
m_dot   db      ".",CR,LF,LF,0
m_entersize db  "Enter partition size............................: ",0
m_enterstart db "Enter starting cylinder number..................: ",0
m_blank db      "     ]",0
m_created db    CR,LF,"DOS partition created.",CR,LF,0
m_exists db     "DOS partition already exists.",CR,LF,0
m_nofree db     "No partition table entry is free.",CR,LF,0
m_nospace db    "No space for a DOS partition.",CR,LF,0
m_actitle db    "                       Change Active Partition",CR,LF,LF,0
m_actask db     "Enter the number of the partition you",CR,LF
        db      "want to make active.............................: ",0
m_actdone db    CR,LF,"Partition made active.",CR,LF,0
m_noparts db    "No partitions defined.",CR,LF,LF,0
m_deltitle db   "                         Delete DOS Partition",CR,LF,LF,0
m_delwarn db    "Warning! Data in the DOS partition will be lost.",CR,LF
        db      "Do you wish to continue..........................? ",0
m_deldone db    CR,LF,"DOS partition deleted.",CR,LF,0
m_nodos db      "No DOS partition to delete.",CR,LF,0
m_distitle db   "                    Display Partition Information",CR,LF,LF,0
m_tabhead db    "Partition  Status   Type    Start     End    Size",CR,LF,0
m_sp7   db      "       ",0
m_sp5   db      "      ",0
m_dos   db      "DOS     ",0
m_nondos db     "non-DOS ",0
m_esc   db      CR,LF,"Press Esc to return to FDISK Options",0
m_writeerr db   CR,LF,"Error writing fixed disk.",CR,LF,0
m_restart db    "System will now restart",CR,LF,LF
        db      "Insert RetrOS/LT diskette in drive A:",CR,LF
        db      "Press any key when ready . . .",0
m_nodisk db     "No fixed disks present.",CR,LF,0
