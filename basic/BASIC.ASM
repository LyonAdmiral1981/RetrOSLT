; BASIC.COM - runs BASICA.EXE with the same command line.
;
; PC DOS 2.10 had two BASICs, BASIC.COM and BASICA.COM.  RetrOS has one,
; Microsoft's GW-BASIC, as BASICA.EXE; BASIC runs it.  DOS 2 finds a
; program only in the current directory when one program runs another, so
; BASIC looks there first and then in each directory of PATH, as
; COMMAND.COM does.  BASIC /ROM (Cassette BASIC) is handled by BASICA.
;
; Copyright (c) 2026 Republic Lyon Mountain Corporation.  MIT License.

        cpu     8086
        org     100h

start:  mov     sp,stack_top
        mov     bx,(prog_end-start+100h+15)/16
        mov     ah,4Ah                  ; give back the memory not needed
        int     21h
        mov     [parm_tail+2],cs        ; the command line and FCBs are ours
        mov     [parm_fcb1+2],cs
        mov     [parm_fcb2+2],cs
        mov     si,exename              ; 1. the current directory
        mov     di,path
        call    copyz
        call    try
        mov     es,[2Ch]                ; 2. each directory of PATH
        xor     di,di
findp:  cmp     byte [es:di],0
        je      notfound                ; end of the environment
        mov     si,pathvar
        mov     cx,5
        push    di
        repe    cmpsb
        pop     bx
        je      gotpath
        mov     di,bx                   ; skip to the next string
        xor     al,al
        mov     cx,-1
        repne   scasb
        jmp     findp
gotpath:
nextd:  mov     [envpos],di
        cmp     byte [es:di],0
        je      notfound
        mov     bx,path                 ; copy one directory
copyd:  mov     al,[es:di]
        cmp     al,0
        je      endd
        inc     di
        cmp     al,';'
        je      endd
        mov     [bx],al
        inc     bx
        jmp     copyd
endd:   mov     [envpos],di
        cmp     bx,path
        je      nextd2                  ; an empty one
        mov     al,[bx-1]
        cmp     al,'\'
        je      addn
        cmp     al,':'
        je      addn
        mov     byte [bx],'\'
        inc     bx
addn:   mov     si,exename
        mov     di,bx
        push    es
        push    ds
        pop     es
        call    copyz
        pop     es
        push    es
        call    try
        pop     es
nextd2: mov     di,[envpos]
        jmp     nextd

notfound:
        mov     dx,nfmsg
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h

; try - run the program named at path.  Returns only if it is not there.
try:    mov     [save_sp],sp
        mov     dx,path
        push    ds
        pop     es
        mov     bx,parm
        mov     ax,4B00h
        int     21h
        mov     [cs:exerr],ax
        cli                             ; DOS 2's EXEC keeps nothing
        mov     ax,cs
        mov     ss,ax
        mov     sp,[cs:save_sp]
        sti
        mov     ds,ax
        mov     es,ax
        mov     ax,[exerr]
        jc      tryerr
        mov     ah,4Dh                  ; it ran: its exit code is ours
        int     21h
        mov     ah,4Ch
        int     21h
tryerr: cmp     ax,2                    ; file not found
        je      tryx
        cmp     ax,3                    ; path not found
        je      tryx
        aam                             ; the code, in decimal
        add     ax,'00'
        xchg    al,ah
        mov     [ercode],ax
        mov     dx,ermsg                ; anything else: say so
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h
tryx:   ret

; copyz - copy the zero-terminated string at DS:SI to ES:DI
copyz:  lodsb
        stosb
        or      al,al
        jnz     copyz
        ret

exename db      'BASICA.EXE',0
pathvar db      'PATH='
nfmsg   db      'BASICA.EXE not found',13,10,'$'
ermsg   db      'Cannot run BASICA.EXE ('
ercode  db      '??)',13,10,'$'
parm    dw      0                       ; the environment: ours
parm_tail dw    80h,0
parm_fcb1 dw    5Ch,0
parm_fcb2 dw    6Ch,0
save_sp dw      0
exerr   dw      0
envpos  dw      0
path    times 80 db 0
        times 128 db 0
stack_top:
prog_end:
