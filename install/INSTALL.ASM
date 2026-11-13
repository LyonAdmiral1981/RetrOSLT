; RetrOS/LT Install
; (C) Copyright Republic Lyon Mountain Corporation 2026
;
; Installs RetrOS/LT from its two diskettes, the DOS diskette and the
; Supplemental Programs diskette, onto the first fixed disk of an IBM PC or
; PC XT. Assembles with NASM; the build gives it the master boot record:
;   nasm -f bin -i build/ -o INSTALL.COM install/INSTALL.ASM
; Each diskette holds a hidden file RETROS.DSK naming the edition and the
; diskette's number, which Install checks before copying from it.
;
; Adapted from the RetrOS/x86 Install. What it does, in order. It works out
; where to resume from the state of the fixed disk, so it is simply run
; again after the restart a new partition needs.
;   0. Asks for acceptance of the license (LICENSE.TXT).
;   1. Finds the first fixed disk and reads its partition table.
;   2. With no DOS partition: writes one that fills the disk (as FDISK's
;      "use the entire fixed disk" does), or lets the user run FDISK, then
;      restarts the computer.
;   3. With an unformatted partition: runs FORMAT C:/S.
;      With a formatted one: asks whether to format it or keep its files;
;      keeping them runs SYS C: instead.
;   4. Asks which directory of drive C: to install to (C:\DOS unless
;      changed) and copies every file on the DOS diskette, except its own
;      start-up files, there, and COMMAND.COM to C:\ as well; then asks for
;      the Supplemental Programs diskette and copies it.
;   5. Writes C:\CONFIG.SYS and C:\AUTOEXEC.BAT, keeping any old ones as
;      CONFIG.OLD and AUTOEXEC.OLD.
;
; Only 8086 instructions and attributes 07h/70h/0Fh are used, so it runs
; on any display adapter, monochrome included. DOS's own critical error
; handler stays in place, as PC DOS 2 has no "fail" answer to give it.

        cpu 8086
        org 100h

%define PRODUCT 'RetrOS/LT'
%define CFG_FILES 'FILES=20'
%define CFG_BUFFERS 'BUFFERS='
%define DISKS 2

BUFSIZE equ 16384
DIRMAX  equ 40                          ; longest directory name after the drive
DIRROW  equ 10                          ; screen row of the directory field
K_ESC     equ 27
K_ENTER   equ 13

start:  cld
        mov sp,stack_top
        mov ah,19h                      ; the drive we were started from
        int 21h
        add al,'A'
        mov [src_drive],al
        mov ax,2523h                    ; Ctrl-C does nothing
        mov dx,int23
        int 21h
        mov bx,(prog_end-start+100h+15)/16   ; give memory back for EXEC
        mov ah,4Ah
        int 21h

        call screen
        mov si,t_welcome
        call text
        call wait_enter
        call screen                     ; the license must be accepted
        mov si,t_license
        call text
        call yesno
        jnc licensed
        jmp quit
licensed:

; ---- 1. the fixed disk -----------------------------------------------
        mov ah,8
        mov dl,80h
        int 13h
        jc no_disk
        or dl,dl
        jnz have_disk
no_disk:
        mov si,t_nodisk
        jmp fatal
have_disk:
        call read_mbr
        jnc mbr_read
        mov si,t_mbrerr
        jmp fatal
mbr_read:
        call find_dos_part              ; BX -> table entry, CF if none
        jnc have_part

; ---- 2. no DOS partition ---------------------------------------------
        call screen
        mov si,t_nopart
        call text
.key:   call getkey
        cmp al,K_ESC
        je quit_j
        and al,0DFh
        cmp al,'F'
        je .manual
        cmp al,'W'
        jne .key
        call screen
        mov si,t_fdisking
        call text
        call whole_disk
        jc .failed
        call read_mbr
        jc .failed
        call find_dos_part
        jnc restart
.failed:
        mov si,t_fdiskerr
        jmp fatal
.manual:
        call cls
        mov si,n_fdisk
        mov di,a_none
        call exec
        call read_mbr
        jc restart
        call find_dos_part
        jnc restart
        jmp start_over
quit_j: jmp quit
restart:
        call screen
        mov si,t_restart
        call text
        call wait_any
        jmp reboot
start_over:
        jmp have_disk

; ---- 3. a DOS partition exists ---------------------------------------
have_part:
        mov ah,36h                      ; does DOS know drive C: yet?
        mov dl,3
        int 21h
        cmp ax,0FFFFh
        jne .known
        jmp restart                     ; made by an earlier FDISK run
.known: cmp byte [dir_asked],0
        jne .asked
        call ask_dir
        mov byte [dir_asked],1
.asked: call read_boot                  ; boot sector of the partition
        jc do_format_ask
        call boot_valid
        jc do_format_ask
        call screen
        mov si,t_formatted
        call text
.key:   call getkey
        cmp al,K_ESC
        je quit_j
        and al,0DFh
        cmp al,'K'
        je do_keep
        cmp al,'F'
        jne .key
        call screen
        mov si,t_sure
        call text
        call yesno
        jc have_part
        jmp short do_format
do_format_ask:
        call screen
        mov si,t_unformatted
        call text
        call wait_enter
do_format:
        call screen
        mov si,t_formatting
        call text
        call wait_enter
        call cls
        mov si,n_format
        mov di,a_format
        call exec
        jc .bad
        call has_system
        jnc copy_files
.bad:   mov si,t_formaterr
        jmp fatal
do_keep:
        call cls
        mov si,n_sys
        mov di,a_sys
        call exec
        jc .bad
        call has_system
        jnc copy_files
.bad:   mov si,t_syserr
        jmp fatal

; ---- 4. copy the files -----------------------------------------------
copy_files:
        call screen
        mov si,t_copying
        call text
        mov si,instdir
        call text
        mov si,t_file
        call text
        call make_dirs
        jnc .made
        mov si,t_direrr
        jmp fatal
.made:  mov di,p_dst                    ; destination path: directory, "\"
        mov si,instdir
        call cat
        mov al,'\'
        stosb
        mov [dst_name],di
        mov dx,dta
        mov ah,1Ah
        int 21h
        call copy_disk
        mov si,s_command                ; COMMAND.COM goes in the root too
        mov di,dta+1Eh
.c:     lodsb
        stosb
        or al,al
        jnz .c
        mov di,p_root_name
        call copy_one
        jnc next_disk
        mov si,t_copyerr
        jmp fatal

; The other diskettes of a set, in turn. Each must hold RETROS.DSK with the
; edition's name and its own number before anything is copied from it.
next_disk:
%if DISKS > 1
        inc byte [disk_no]
        cmp byte [disk_no],'0'+DISKS
        ja write_config
.ask:   mov al,[disk_no]
        mov [m_digit],al
        call screen
        mov si,t_insert
        call text
        call wait_enter
        mov ah,0Dh                      ; forget what DOS knew of the last one
        int 21h
        call check_disk
        jc .wrong
        call screen
        mov si,t_copying
        call text
        mov si,instdir
        call text
        mov si,t_file
        call text
        call copy_disk
        jmp next_disk
.wrong: call screen
        mov si,t_wrongdisk
        call text
        call wait_any
        jmp .ask
%endif

; ---- 5. CONFIG.SYS and AUTOEXEC.BAT ----------------------------------
write_config:
        mov dx,p_config_old
        mov ah,41h
        int 21h
        mov dx,p_config
        mov di,p_config_old
        mov ah,56h
        int 21h
        mov dx,p_auto_old
        mov ah,41h
        int 21h
        mov dx,p_auto
        mov di,p_auto_old
        mov ah,56h
        int 21h
        int 12h                         ; KB of memory
        cmp ax,384
        jae .bufs
        mov word [cfg_bufs],'10'        ; each buffer is 528 bytes
.bufs:
        mov di,buffer                   ; CONFIG.SYS: files, buffers, ANSI.SYS
        mov si,f_config1
        call cat
        mov si,instdir
        call cat
        mov si,f_config2
        call cat
        mov cx,di
        sub cx,buffer
        mov dx,p_config
        mov si,buffer
        call write_file
        jc .bad
        mov di,buffer                   ; AUTOEXEC.BAT puts it on the path
        mov si,f_auto1
        call cat
        mov si,instdir
        call cat
        mov si,f_auto2
        call cat
        mov cx,di
        sub cx,buffer
        mov dx,p_auto
        mov si,buffer
        call write_file
        jnc finished
.bad:   mov si,t_cfgerr
        jmp fatal

finished:
        mov ah,0Dh                      ; flush everything to the disk
        int 21h
        call screen
        mov si,t_done
        call text
        call wait_enter
reboot: mov ah,0Dh
        int 21h
        xor ax,ax
        mov ds,ax
        mov word [472h],1234h           ; warm start, no memory test
        jmp 0FFFFh:0

fatal:  push si
        call screen
        pop si
        call text
        mov si,t_fatal
        call text
        call wait_any
quit:   call cls
        mov ax,4C01h
        int 21h

int23:  iret

; ======================================================================
; copy_disk: copies every normal file on the diskette in the source drive,
; but those on the skip list, to the install directory. Stops on error.
copy_disk:
        mov al,[src_drive]
        mov [p_all],al
        mov dx,p_all
        mov cx,0                        ; normal files only: not RETROS.DSK
        mov ah,4Eh
        int 21h
        jc .done
.next:  mov si,dta+1Eh
        call skip_name
        jc .skip
        mov di,[dst_name]
        call copy_one
        jnc .skip
        mov si,t_copyerr
        jmp fatal
.skip:  mov ah,4Fh
        int 21h
        jnc .next
.done:  ret

%if DISKS > 1
; check_disk: CF clear if the diskette in the source drive is the one
; Install is asking for: its RETROS.DSK begins with the edition's name and
; the diskette's number.
check_disk:
        mov al,[src_drive]
        mov [p_marker],al
        mov dx,p_marker
        mov ax,3D00h
        int 21h
        jc .ret
        mov bx,ax
        mov cx,m_len
        mov dx,buffer
        mov ah,3Fh
        int 21h
        pushf
        push ax
        mov ah,3Eh
        int 21h
        pop ax
        popf
        jc .ret
        cmp ax,m_len
        jb .no
        mov si,m_expect
        mov di,buffer
        mov cx,m_len
        repe cmpsb
        je .ret                         ; CF clear from the equal compare
.no:    stc
.ret:   ret
%endif

; ask_dir: asks for the directory to install to. The field shows C:\ and
; the directory, which can be typed over; Enter accepts it.
ask_dir:
        call screen
        mov si,t_where
        call text
.redraw:
        mov dx,(DIRROW<<8)+2
        call setcur
        mov si,t_field
        call text
        mov dx,(DIRROW<<8)+2
        call setcur
        mov si,instdir
        call text
.key:   call getkey
        mov di,instdir+3                ; DI -> end of the directory
.end:   cmp byte [di],0
        je .got
        inc di
        jmp .end
.got:   cmp al,K_ENTER
        je .check
        cmp al,K_ESC
        jne .edit
        jmp quit
.edit:  cmp al,8
        jne .char
        cmp di,instdir+3
        je .key
        mov byte [di-1],0
        jmp .redraw
.char:  cmp al,'a'
        jb .upper
        cmp al,'z'
        ja .upper
        and al,0DFh
.upper: cmp al,'\'
        je .add
        cmp al,'_'
        je .add
        cmp al,'-'
        je .add
        cmp al,'0'
        jb .key
        cmp al,'9'
        jbe .add
        cmp al,'A'
        jb .key
        cmp al,'Z'
        ja .key
.add:   cmp di,instdir+3+DIRMAX
        jae .key
        mov [di],al
        mov byte [di+1],0
        jmp .redraw
.check: mov si,instdir+3                ; each name 1 to 8 characters
.name:  xor cx,cx
.c:     lodsb
        or al,al
        je .last
        cmp al,'\'
        je .sep
        inc cx
        cmp cx,8
        jbe .c
        jmp short .bad
.sep:   jcxz .bad
        jmp .name
.last:  jcxz .bad
        ret
.bad:   mov dx,((DIRROW+2)<<8)+2
        call setcur
        mov si,t_baddir
        call text
        jmp .redraw

; make_dirs: makes the install directory, level by level. CF if it is
; not there afterwards.
make_dirs:
        mov si,instdir+3
.l:     lodsb
        or al,al
        je .final
        cmp al,'\'
        jne .l
        mov byte [si-1],0
        push si
        mov dx,instdir
        mov ah,39h
        int 21h
        pop si
        mov byte [si-1],'\'
        jmp .l
.final: mov dx,instdir
        mov ah,39h                      ; it may exist already
        int 21h
        mov dx,dta                      ; is it a directory now?
        mov ah,1Ah
        int 21h
        mov dx,instdir
        mov cx,10h
        mov ah,4Eh
        int 21h
        jc .ret
        test byte [dta+15h],10h
        jnz .ret
        stc
.ret:   ret

; cat: appends the string at SI to the one being built at DI.
cat:    lodsb
        or al,al
        jz .ret
        stosb
        jmp cat
.ret:   mov byte [di],0
        ret

; skip_name: SI -> file name. CF set if the file stays on the diskette.
skip_name:
        push si
        mov bx,skip_list
.entry: cmp byte [bx],0
        je .copy
        pop si
        push si
        mov di,bx
.cmp:   mov al,[di]
        cmp al,[si]
        jne .nextent
        or al,al
        je .found
        inc si
        inc di
        jmp .cmp
.nextent:
        cmp byte [bx],0
        je .adv
        inc bx
        jmp .nextent
.adv:   inc bx
        jmp .entry
.found: pop si
        stc
        ret
.copy:  pop si
        clc
        ret

; copy_one: copies the file named at dta+1Eh from the source drive to the
; path whose name part is at DI ([dst_name] or p_root_name). CF on error.
copy_one:
        push di
        mov si,dta+1Eh                  ; build both paths
        mov bx,p_src_name
.n:     lodsb
        mov [bx],al
        stosb
        inc bx
        or al,al
        jnz .n
        pop di
        mov al,[src_drive]
        mov [p_src],al
        mov si,dta+1Eh                  ; show the name
        call show_name
        mov dx,p_src
        mov ax,3D00h
        int 21h
        jc .err
        mov [h_src],ax
        mov dx,p_root
        cmp di,p_root_name
        je .mk
        mov dx,p_dst
.mk:    xor cx,cx
        mov ah,3Ch
        int 21h
        jc .err_close_src
        mov [h_dst],ax
.loop:  mov bx,[h_src]
        mov cx,BUFSIZE
        mov dx,buffer
        mov ah,3Fh
        int 21h
        jc .err_close
        or ax,ax
        jz .eof
        mov cx,ax
        mov bx,[h_dst]
        mov dx,buffer
        mov ah,40h
        int 21h
        jc .err_close
        cmp ax,cx
        jne .err_close                  ; disk full
        jmp .loop
.eof:   mov bx,[h_src]                  ; keep the file's date and time
        mov ax,5700h
        int 21h
        mov bx,[h_dst]
        mov ax,5701h
        int 21h
        mov ah,3Eh
        int 21h
        mov bx,[h_src]
        mov ah,3Eh
        int 21h
        clc
        ret
.err_close:
        mov bx,[h_dst]
        mov ah,3Eh
        int 21h
.err_close_src:
        mov bx,[h_src]
        mov ah,3Eh
        int 21h
.err:   stc
        ret

; write_file: DX -> path, SI -> text, CX = length. CF on error.
write_file:
        push cx
        push si
        xor cx,cx
        mov ah,3Ch
        int 21h
        pop dx
        pop cx
        jc .ret
        mov bx,ax
        mov ah,40h
        int 21h
        pushf
        mov ah,3Eh
        int 21h
        popf
.ret:   ret

; exec: SI -> program name (no drive), DI -> command tail (length byte
; first). Runs it from the source drive. CF if it could not be run,
; otherwise AL = its exit code.
exec:   push di
        mov di,p_prog_name
.n:     lodsb
        stosb
        or al,al
        jnz .n
        pop di
        mov al,[src_drive]
        mov [p_prog],al
        mov [pb_tail],di
        mov [pb_tail+2],cs
        push di                         ; DOS 2 programs take their drives
        lea si,[di+1]                   ; from the two FCBs: fill ours from
        push cs                         ; the command tail, as COMMAND does
        pop es
        mov di,5Ch
        mov ax,2901h
        int 21h
        mov di,6Ch
        mov ax,2901h
        int 21h
        pop di
        mov word [pb_fcb1],5Ch
        mov [pb_fcb1+2],cs
        mov word [pb_fcb2],6Ch
        mov [pb_fcb2+2],cs
        mov [save_sp],sp
        mov dx,p_prog
        mov bx,pblock
        push cs
        pop es
        mov ax,4B00h
        int 21h
        cli
        mov bx,cs                       ; DOS 2-style: all registers are gone
        mov ds,bx
        mov es,bx
        mov ss,bx
        mov sp,[save_sp]
        sti
        cld
        jc .ret
        mov ah,4Dh
        int 21h
        clc
.ret:   ret

; read_mbr: first sector of the first fixed disk into buffer. CF on error.
read_mbr:
        mov cx,1
        xor dh,dh
; read_sector: CX/DH = cylinder, sector and head as INT 13h takes them.
read_sector:
        mov di,3                        ; three tries
.try:   push cx
        push dx
        mov dl,80h
        mov bx,buffer
        mov ax,0201h
        int 13h
        pop dx
        pop cx
        jnc .ok
        push cx
        push dx
        xor ah,ah
        mov dl,80h
        int 13h
        pop dx
        pop cx
        dec di
        jnz .try
        stc
.ok:    ret

; find_dos_part: looks in the partition table in buffer for a DOS
; partition (type 1). Saves where it starts. CF if there is none.
find_dos_part:
        cmp word [buffer+510],0AA55h
        jne .none
        mov bx,buffer+446
        mov cx,4
.e:     mov al,[bx+4]
        cmp al,1                        ; DOS 2: a 12-bit FAT partition
        je .yes
        add bx,16
        loop .e
.none:  stc
        ret
.yes:   mov al,[bx+1]
        mov [part_head],al
        mov ax,[bx+2]
        mov [part_cylsec],ax
        clc
        ret

; read_boot: boot sector of the partition found into buffer. CF on error.
read_boot:
        mov cx,[part_cylsec]
        mov dh,[part_head]
        jmp read_sector

; boot_valid: CF clear if buffer holds the boot sector of a FAT volume.
boot_valid:
        cmp word [buffer+510],0AA55h
        jne .no
        cmp word [buffer+11],512
        jne .no
        mov al,[buffer+13]
        or al,al
        jz .no
        mov ah,al
        dec ah
        test al,ah
        jnz .no
        mov al,[buffer+16]
        dec al
        cmp al,1
        ja .no
        cmp byte [buffer+21],0F0h
        jb .no
        clc
        ret
.no:    stc
        ret

; whole_disk: writes a master boot record with one DOS partition over the
; whole disk (at most 65,535 sectors, the most DOS 2 can use), active,
; starting on head 1 of cylinder 0: what FDISK makes when told to use the
; entire fixed disk. CF on error.
whole_disk:
        mov ah,8
        mov dl,80h
        int 13h
        jc .ret
        mov al,cl
        and al,3Fh
        xor ah,ah
        mov [g_spt],ax
        mov al,dh
        xor ah,ah
        inc ax
        mov [g_heads],ax
        mov al,ch
        mov ah,cl
        rol ah,1
        rol ah,1
        and ah,3
        inc ax
        mov [g_cyls],ax
        mov ax,[g_heads]
        mul word [g_spt]
        mov [g_cylsecs],ax
        mov cx,ax
        mov ax,65535
        xor dx,dx
        div cx
        cmp ax,[g_cyls]
        jbe .size
        mov ax,[g_cyls]
.size:  mov [g_size],ax
        push ds
        pop es
        mov di,buffer                   ; the code, an empty table, signature
        mov si,mbrcode
        mov cx,1BEh
        rep movsb
        xor al,al
        mov cx,64
        rep stosb
        mov word [buffer+510],0AA55h
        mov di,buffer+1BEh
        mov byte [di],80h               ; active
        mov byte [di+1],1               ; head 1
        mov word [di+2],0001h           ; cylinder 0, sector 1
        mov byte [di+4],1               ; DOS, 12-bit FAT
        mov al,[g_heads]
        dec al
        mov [di+5],al
        mov ax,[g_size]
        dec ax
        mov ch,al
        mov cl,ah
        ror cl,1
        ror cl,1
        and cl,0C0h
        or cl,[g_spt]
        mov [di+6],cx
        mov ax,[g_spt]
        mov [di+8],ax                   ; sectors before it: the first track
        mov word [di+10],0
        mov ax,[g_size]
        mul word [g_cylsecs]
        sub ax,[g_spt]
        sbb dx,0
        mov [di+12],ax
        mov [di+14],dx
        mov di,3                        ; write it
.try:   mov ax,0301h
        mov bx,buffer
        mov cx,1
        xor dh,dh
        mov dl,80h
        int 13h
        jnc .ret
        xor ah,ah
        mov dl,80h
        int 13h
        dec di
        jnz .try
        stc
.ret:   ret

; has_system: CF clear if C:\RETBIO.COM is there, after FORMAT or SYS
has_system:
        mov dx,dta
        mov ah,1Ah
        int 21h
        mov dx,p_retbio
        mov cx,7                        ; hidden, system, read-only
        mov ah,4Eh
        int 21h
        ret

; ---- screen and keyboard ---------------------------------------------
cls:    mov ax,0600h
        mov bh,07h
        xor cx,cx
        mov dx,184Fh
        int 10h
        xor dx,dx
        jmp setcur

; screen: clears, draws the title bar and puts the cursor at row 3.
screen: call cls
        mov ax,0600h                    ; title bar in reverse video
        mov bh,70h
        xor cx,cx
        mov dx,004Fh
        int 10h
        mov dx,0002h
        call setcur
        mov si,t_title
        call text
        mov dx,0300h
setcur: xor bh,bh
        mov ah,2
        int 10h
        ret

; text: writes the string at SI through the BIOS. A line feed also
; returns to column 2, so the text has a left margin.
text:   lodsb
        or al,al
        jz .ret
        cmp al,10
        je .nl
        mov ah,0Eh
        xor bh,bh
        int 10h
        jmp text
.nl:    mov ah,3
        xor bh,bh
        int 10h
        inc dh
        mov dl,2
        call setcur
        jmp text
.ret:   ret

; show_name: writes the file name at SI on the progress line.
show_name:
        push si
        mov dx,0902h
        call setcur
        mov si,t_blank
        call text
        mov dx,0902h
        call setcur
        pop si
        jmp text

getkey: xor ah,ah
        int 16h
        ret

wait_any:
        mov si,t_anykey
        call text
        jmp getkey

; wait_enter: Enter continues, Esc leaves Install.
wait_enter:
        mov si,t_enter
        call text
.k:     call getkey
        cmp al,K_ENTER
        je .ret
        cmp al,K_ESC
        jne .k
        jmp quit
.ret:   ret

; yesno: CF clear for Y, set for N or Esc.
yesno:  call getkey
        cmp al,K_ESC
        je .no
        and al,0DFh
        cmp al,'Y'
        je .yes
        cmp al,'N'
        jne yesno
.no:    stc
        ret
.yes:   clc
        ret

; ---- text ------------------------------------------------------------
t_title: db PRODUCT,' Version 1.0 Install',0
t_welcome:
        db 10,'Welcome to ',PRODUCT,'.',10,10
        db 'Install puts ',PRODUCT,' on the fixed disk of this computer,',10
        db 'drive C:, so that the computer starts from it.',10,10
        db 'Before any change is made to the fixed disk you are asked first.',10
        db 'You can leave Install at any question by pressing Esc.',10,0
t_license:
        db 10,PRODUCT,' is licensed, not sold.',10,10
        db 'The terms of the RetrOS/LT License are in the file LICENSE.TXT on',10
        db 'this diskette. To read them on the screen, answer N, and type:',10,10
        db '    TYPE LICENSE.TXT | MORE',10,10
        db PRODUCT,' is derived from MS-DOS 2 source code released by',10
        db 'Microsoft Corporation under the MIT License. The notice for that',10
        db 'code is in the file NOTICE.TXT.',10,10
        db 'Do you accept the terms of the RetrOS/LT License (Y/N)? ',0
t_enter: db 10,10,'Press Enter to continue, or Esc to leave Install. ',0
t_anykey: db 10,10,'Press any key to continue. ',0
t_nodisk:
        db 10,'This computer has no fixed disk that Install can use.',10,10
        db PRODUCT,' runs from this diskette as it is. To make another',10
        db 'startup diskette, use FORMAT A: /S.',0
t_mbrerr:
        db 10,'The fixed disk could not be read.',10,10
        db 'Check that the fixed disk adapter and its cable are seated, and',10
        db 'that the disk has been low-level formatted.',0
t_nopart:
        db 10,'The fixed disk has no DOS partition.',10,10
        db 'A fixed disk must be partitioned before it can be used.',10,10
        db '  W   Use the whole disk for ',PRODUCT,'.',10
        db '      Anything on the disk now will be lost.',10,10
        db '  F   Run FDISK, to set up the partitions yourself.',10,10
        db '  Esc Leave Install without changing the disk.',10,10
        db 'Press W, F or Esc. ',0
t_fdisking: db 10,'Creating the DOS partition...',0
t_fdiskerr:
        db 10,'The DOS partition could not be created.',10,10
        db 'Run FDISK from this diskette to look at the disk.',0
t_restart:
        db 10,'The fixed disk now has a DOS partition.',10,10
        db 'The computer must restart before the partition can be used.',10
        db 'Leave this diskette in drive A:. Install continues by itself',10
        db 'after the restart.',0
t_formatting:
        db 10,'FORMAT will now prepare drive C:. When it asks, press a key',10
        db 'to begin formatting. Formatting a fixed disk takes some minutes.',0
t_unformatted:
        db 10,'Drive C: is not formatted.',10,10
        db 'Install will now format drive C: and copy ',PRODUCT,' to it.',10
        db 'Anything on drive C: will be lost.',0
t_formatted:
        db 10,'Drive C: is already formatted and may hold files.',10,10
        db '  K   Keep the files on drive C: and add ',PRODUCT,' to them.',10
        db '      An existing CONFIG.SYS and AUTOEXEC.BAT are kept as',10
        db '      CONFIG.OLD and AUTOEXEC.OLD.',10,10
        db '  F   Format drive C:. Everything on it will be lost.',10,10
        db '  Esc Leave Install without changing the disk.',10,10
        db 'Press K, F or Esc. ',0
t_sure:
        db 10,'Formatting erases everything on drive C:.',10,10
        db 'Format drive C: (Y/N)? ',0
t_formaterr:
        db 10,'Drive C: could not be formatted.',10,10
        db 'Run FORMAT C:/S from this diskette to see what is wrong.',0
t_syserr:
        db 10,'The system files could not be put on drive C:.',10,10
        db 'There may be no room for them at the start of the disk. Run',10
        db 'Install again and choose to format drive C:, after saving',10
        db 'the files you need.',0
t_copying: db 10,'Copying ',PRODUCT,' to ',0
%if DISKS > 1
t_insert:
        db 10,'Insert the ',PRODUCT,' Supplemental Programs diskette in',10
        db 'drive A:.',0
t_wrongdisk:
        db 10,'That is not the diskette Install asked for, or it cannot be',10
        db 'read. Check that it is the ',PRODUCT,' Supplemental Programs',10
        db 'diskette, and that it is in drive A: with the door closed.',0

m_expect: db PRODUCT,' '
m_digit: db '2'
m_len   equ $-m_expect
p_marker: db 'A:\RETROS.DSK',0
%endif
t_file: db 10,10,'File:',0
t_where:
        db 10,'Where should ',PRODUCT,' be installed?',10,10
        db 'The programs and drivers go in one directory of drive C:.',10
        db 'C:\DOS is the usual place. To use another, type over the name',10
        db 'below. The files that start the computer always go in C:\.',10,10,10,10,10
        db 'Press Enter to accept, or Esc to leave Install.',0
t_field: db '                                              ',0
t_baddir: db 'Each name must be 1 to 8 letters or digits.',0
t_direrr:
        db 10,10,10,'The directory could not be made on drive C:.',10,10
        db 'A file with the same name may be in the way.',0
t_blank: db '                    ',0
t_copyerr:
        db 10,10,10,'A file could not be copied to drive C:.',10,10
        db 'Drive C: may be full, or this diskette may be damaged.',0
t_cfgerr: db 10,'CONFIG.SYS and AUTOEXEC.BAT could not be written to drive C:.',0
t_done:
        db 10,PRODUCT,' is installed on drive C:.',10,10
        db 'Remove the diskette from drive A:, then press Enter to restart',10
        db 'the computer from the fixed disk.',0
t_fatal: db 10,10,'Install has stopped. Nothing further was changed.',0

; ---- files Install leaves on the diskette ----------------------------
skip_list:
        db 'INSTALL.COM',0
        db 'AUTOEXEC.BAT',0
        db 'CONFIG.SYS',0
        db 0
s_command: db 'COMMAND.COM',0

; ---- programs and their command tails --------------------------------
n_fdisk: db 'FDISK.COM',0
n_format: db 'FORMAT.COM',0
n_sys:  db 'SYS.COM',0
a_none: db 0,13
a_format: db a_format_end-a_format-1,' C:/S'
a_format_end: db 13
a_sys:  db a_sys_end-a_sys-1,' C:'
a_sys_end: db 13

; ---- paths -----------------------------------------------------------
p_all:  db 'A:\*.*',0
p_retbio: db 'C:\RETBIO.COM',0
p_config: db 'C:\CONFIG.SYS',0
p_config_old: db 'C:\CONFIG.OLD',0
p_auto: db 'C:\AUTOEXEC.BAT',0
p_auto_old: db 'C:\AUTOEXEC.OLD',0
p_src:  db 'A:\'
p_src_name: times 13 db 0
p_dst:  times 3+DIRMAX+1+13 db 0         ; install directory, "\", name
p_root: db 'C:\'
p_root_name: times 13 db 0
p_prog: db 'A:\'
p_prog_name: times 13 db 0

; ---- the files Install writes ----------------------------------------
f_config1:
        db CFG_FILES,13,10
        db CFG_BUFFERS
cfg_bufs: db '15'                       ; 10 when there is less than 384 KB
        db 13,10
        db 'DEVICE=',0
f_config2: db '\ANSI.SYS',13,10,0
f_auto1:                                ; the PC and XT keep no time: ask
        db 'DATE',13,10
        db 'TIME',13,10
        db 'PROMPT $P$G',13,10
        db 'PATH ',0
f_auto2: db 13,10,0

; ---- data ------------------------------------------------------------
src_drive: db 'A'
disk_no: db '1'
dir_asked: db 0
dst_name: dw 0                          ; where the file name goes in p_dst
instdir: db 'C:\DOS'
        times DIRMAX-3+1 db 0
part_head: db 0
part_cylsec: dw 0
h_src:  dw 0
h_dst:  dw 0
save_sp: dw 0
g_spt:  dw 0
g_heads: dw 0
g_cyls: dw 0
g_cylsecs: dw 0
g_size: dw 0
pblock: dw 0                            ; environment: a copy of ours
pb_tail: dw 0,0
pb_fcb1: dw 0,0
pb_fcb2: dw 0,0
dta:    times 64 db 0

%include "MBRCODE.INC"

        align 2
        times 512 db 0
stack_top:
buffer  equ $                           ; (not part of the file)
prog_end equ buffer+BUFSIZE
