        TITLE   IO.SYS for the IBM Personal Computer -- RetrOS/LT

; RetrOS/LT IO.SYS: the BIOS interface of DOS 2 for the IBM Personal
; Computer and Personal Computer XT, and compatibles.
;
; Microsoft's MS-DOS 2 kit gave computer makers SYSINIT and a skeleton BIOS
; for another machine (SKELIO.ASM, the Altos ACS-86C); each maker wrote its
; own. IBM's was never published, so this one is new, written to the device
; driver interface of the kit (DEVDRIV.txt, SYSINIT.txt) and to the ROM BIOS
; of the IBM PC (October 27, 1982) and XT. It behaves as PC DOS 2.10's does.
; A few routines are taken from the IBM-derived BIOS of the MS-DOS 4.0
; source (MSCON.ASM, MSCLOCK.ASM), Copyright Microsoft Corporation, MIT
; License; they are marked where they are used.
;
; IO.SYS is loaded at 0070:0000 by the RetrOS/LT boot sector, which leaves
; its own sector, with the BIOS parameter block of the disk started from,
; at 0000:7C00 and the BIOS drive number in DL. INIT, at the end, finds
; and loads MSDOS.SYS, sets up the drivers and jumps to SYSINIT; everything
; from INIT on is then given back.
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

        .xlist
        INCLUDE DEVSYM.ASM
        .list

BIOSSEG EQU     0070H           ; where the boot sector loads IO.SYS
SECSIZE EQU     512
MAXUNIT EQU     4               ; A: B: and two fixed disks
CR      EQU     13
LF      EQU     10

; Offsets in a request header
RQ_UNIT EQU     1
RQ_CMD  EQU     2
RQ_STAT EQU     3
RQ_MEDIA EQU    13
RQ_TRANS EQU    14              ; DWORD transfer address
RQ_COUNT EQU    18
RQ_START EQU    20
RQ_BPB  EQU     18              ; INIT and BUILD BPB: DWORD BPB (array)
RQ_UNITS EQU    13              ; INIT: number of units
RQ_BREAK EQU    14              ; INIT: DWORD break address
RQ_CHANGED EQU  14              ; MEDIA CHECK: returned byte

; Status words
ST_DONE EQU     0100H
ST_BUSY EQU     0200H
ST_ERROR EQU    8000H

; The segments, in the order LINK must place them: this BIOS, then SYSINIT
; and its messages, then IMAGEEND, which marks the end of IO.SYS.
CODE    SEGMENT PARA PUBLIC 'CODE'
CODE    ENDS
SYSINITSEG      SEGMENT PUBLIC 'SYSTEM_INIT'
        EXTRN   SYSINIT:FAR
        EXTRN   CURRENT_DOS_LOCATION:WORD
        EXTRN   FINAL_DOS_LOCATION:WORD
        EXTRN   DEVICE_LIST:DWORD
        EXTRN   MEMORY_SIZE:WORD
        EXTRN   DEFAULT_DRIVE:BYTE
        EXTRN   BUFFERS:BYTE
        EXTRN   FILES:BYTE
SYSINITSEG      ENDS
IMAGEEND        SEGMENT PARA PUBLIC 'ZZEND'
ENDIMAGE        LABEL   BYTE
IMAGEEND        ENDS

CODE    SEGMENT PARA PUBLIC 'CODE'
ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:NOTHING

        PUBLIC  RE_INIT

        ORG     0

START:  JMP     INIT

        SUBTTL  Device headers
        PAGE

; CON AUX PRN CLOCK$ must be the first four devices, in that order.

DEVSTART LABEL  WORD
CONDEV: DW      AUXDEV,BIOSSEG
        DW      8013H                   ; console in and out, special (INT 29h)
        DW      STRATEGY,CON_INT
        DB      "CON     "

AUXDEV: DW      PRNDEV,BIOSSEG
        DW      8000H
        DW      STRATEGY,AUX_INT
        DB      "AUX     "

PRNDEV: DW      TIMDEV,BIOSSEG
        DW      8000H
        DW      STRATEGY,PRN_INT
        DB      "PRN     "

TIMDEV: DW      DSKDEV,BIOSSEG
        DW      8008H                   ; the clock
        DW      STRATEGY,TIM_INT
        DB      "CLOCK$  "

DSKDEV: DW      COM1DEV,BIOSSEG
        DW      0000H                   ; block device, IBM format
        DW      STRATEGY,DSK_INT
DRVMAX  DB      2                       ; number of units, set by INIT
        DB      7 DUP (0)

COM1DEV: DW     LPT1DEV,BIOSSEG
        DW      8000H
        DW      STRATEGY,AUX_INT
        DB      "COM1    "

LPT1DEV: DW     LPT2DEV,BIOSSEG
        DW      8000H
        DW      STRATEGY,PRN_INT
        DB      "LPT1    "

LPT2DEV: DW     LPT3DEV,BIOSSEG
        DW      8000H
        DW      STRATEGY,LPT2_INT
        DB      "LPT2    "

LPT3DEV: DW     -1,-1
        DW      8000H
        DW      STRATEGY,LPT3_INT
        DB      "LPT3    "

        SUBTTL  Dispatch tables
        PAGE

CONTBL: DW      EXIT            ; 0  init
        DW      EXIT            ; 1  media check
        DW      EXIT            ; 2  build BPB
        DW      CMDERR          ; 3  IOCTL input
        DW      CON_READ        ; 4  read
        DW      CON_RDND        ; 5  non-destructive read
        DW      EXIT            ; 6  input status
        DW      CON_FLSH        ; 7  input flush
        DW      CON_WRIT        ; 8  write
        DW      CON_WRIT        ; 9  write with verify
        DW      EXIT            ; 10 output status
        DW      EXIT            ; 11 output flush
        DW      CMDERR          ; 12 IOCTL output

AUXTBL: DW      EXIT,EXIT,EXIT,CMDERR
        DW      AUX_READ,AUX_RDND,EXIT,AUX_FLSH
        DW      AUX_WRIT,AUX_WRIT,AUX_WRST,EXIT,CMDERR

PRNTBL: DW      EXIT,EXIT,EXIT,CMDERR
        DW      EXIT_ZERO,BUS_EXIT,EXIT,EXIT
        DW      PRN_WRIT,PRN_WRIT,PRN_STAT,EXIT,CMDERR

TIMTBL: DW      EXIT,EXIT,EXIT,CMDERR
        DW      TIM_READ,BUS_EXIT,EXIT,EXIT
        DW      TIM_WRIT,TIM_WRIT,EXIT,EXIT,CMDERR

DSKTBL: DW      DSK_INIT,MEDIA_CHK,GET_BPB,CMDERR
        DW      DSK_READ,BUS_EXIT,EXIT,EXIT
        DW      DSK_WRIT,DSK_WRTV,EXIT,EXIT,CMDERR

        SUBTTL  Data
        PAGE

PTRSAV  DD      0               ; the request being served
ALTAH   DB      0               ; a key's second byte, or 3 after Ctrl-Break
PRNUM   DW      0               ; printer of the request: 0, 1 or 2
DAYCNT  DW      0               ; days since 1-1-80

; The disk units. PHYS is the ROM BIOS drive number; for a fixed disk
; HIDDEN is where its DOS partition starts.
NUMFLOP DB      0               ; physical diskette drives (1 means A: and B:
                                ; share one drive)
PHYS    DB      0,1,80H,81H
UNITSPT DW      9,9,17,17       ; sectors per track of the media now in it
UNITHDS DW      2,2,4,4         ; heads
HIDLO   DW      0,0,0,0         ; hidden sectors before the volume
HIDHI   DW      0,0,0,0
UNITBPB DW      BPB360,BPB360,HDBPB0,HDBPB1
LASTUNIT DB     -1              ; last diskette unit used
LASTTICK DW     0               ; and the clock tick count then
ONEDRV  DB      0               ; on a one-drive computer: A: (0) or B: (1)
                                ; is in the drive

; The diskette formats, chosen by the FAT ID byte, which is at the same place
; on every one: the first byte of the sector after the boot sector.
;                 bytes  clu  res  FATs dir  sectors  ID    FAT  spt hds
BPB160  DW      512
        DB      1
        DW      1
        DB      2
        DW      64,320
        DB      0FEH
        DW      1
BPB180  DW      512
        DB      1
        DW      1
        DB      2
        DW      64,360
        DB      0FCH
        DW      2
BPB320  DW      512
        DB      2
        DW      1
        DB      2
        DW      112,640
        DB      0FFH
        DW      1
BPB360  DW      512
        DB      2
        DW      1
        DB      2
        DW      112,720
        DB      0FDH
        DW      2

MEDIAID DB      0FEH,0FCH,0FFH,0FDH
MEDIABPB DW     BPB160,BPB180,BPB320,BPB360
MEDIASPT DW     8,9,8,9
MEDIAHDS DW     1,1,2,2

HDBPB0  DB      13 DUP (0)      ; fixed disk volumes, from their boot sectors
HDBPB1  DB      13 DUP (0)

; The diskette parameter table (INT 1Eh). The ROM's is copied here at INIT
; and given 9 sectors a track, as DOS 2 formats.
DPT     DB      11 DUP (0)

; ROM BIOS error codes and the DOS errors they are reported as (after
; MSBDATA.INC of the MS-DOS 4.0 BIOS).
ERRIN   DB      80H,40H,10H,08H,04H,03H
ERROUT  DB      2,6,4,4,8,0
NUMERR  EQU     ERROUT-ERRIN
        DB      12              ; anything else: general failure

        SUBTTL  Strategy and interrupt entry points
        PAGE

STRATEGY PROC   FAR
        MOV     WORD PTR CS:[PTRSAV],BX
        MOV     WORD PTR CS:[PTRSAV+2],ES
        RET
STRATEGY ENDP

CON_INT:
        PUSH    SI
        MOV     SI,OFFSET CONTBL
        JMP     SHORT ENTRY
AUX_INT:
        PUSH    SI
        MOV     SI,OFFSET AUXTBL
        JMP     SHORT ENTRY
PRN_INT:
        PUSH    SI
        MOV     SI,OFFSET PRNTBL
        MOV     CS:[PRNUM],0
        JMP     SHORT ENTRY
LPT2_INT:
        PUSH    SI
        MOV     SI,OFFSET PRNTBL
        MOV     CS:[PRNUM],1
        JMP     SHORT ENTRY
LPT3_INT:
        PUSH    SI
        MOV     SI,OFFSET PRNTBL
        MOV     CS:[PRNUM],2
        JMP     SHORT ENTRY
TIM_INT:
        PUSH    SI
        MOV     SI,OFFSET TIMTBL
        JMP     SHORT ENTRY
DSK_INT:
        PUSH    SI
        MOV     SI,OFFSET DSKTBL

; Every driver starts here: DS = CS, ES:DI the transfer address, CX the
; count, DX the starting sector, AL the unit, AH the media byte, and the
; command's routine called through the table.
ENTRY:  PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    DI
        PUSH    BP
        PUSH    DS
        PUSH    ES
        CLD
        LDS     BX,CS:[PTRSAV]
ASSUME  DS:NOTHING
        MOV     AL,[BX+RQ_CMD]
        CMP     AL,12
        JA      BADCMD
        CBW
        SHL     AX,1
        ADD     SI,AX
        MOV     AL,[BX+RQ_UNIT]
        MOV     AH,[BX+RQ_MEDIA]
        MOV     CX,[BX+RQ_COUNT]
        MOV     DX,[BX+RQ_START]
        LES     DI,[BX+RQ_TRANS]
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     WORD PTR [SI]

BADCMD: PUSH    CS
        POP     DS
CMDERR: MOV     AL,3                    ; unknown command
        JMP     SHORT ERR_EXIT

; Exits. AL holds the error code for ERR_EXIT; CX the count transferred
; for ERR_CNT.
ERR_CNT:
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     [BX+RQ_COUNT],CX
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
ERR_EXIT:
        MOV     AH,HIGH (ST_ERROR+ST_DONE)
        JMP     SHORT SETSTAT
EXIT_ZERO:
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     WORD PTR [BX+RQ_COUNT],0
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     SHORT EXIT
BUS_EXIT:
        MOV     AH,HIGH (ST_BUSY+ST_DONE)
        JMP     SHORT SETST1
EXIT:   MOV     AH,HIGH ST_DONE
SETST1: XOR     AL,AL
SETSTAT:
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     [BX+RQ_STAT],AX
        POP     ES
        POP     DS
        POP     BP
        POP     DI
        POP     DX
        POP     CX
        POP     BX
        POP     AX
        POP     SI
        RETF                            ; the DOS calls the drivers far
ASSUME  DS:CODE

        SUBTTL  CON: the keyboard and display
        PAGE

; After MSCON.ASM of the MS-DOS 4.0 BIOS. An extended key comes back as
; 0, then its scan code; Ctrl-Break as Ctrl-C; Ctrl-PrtSc as Ctrl-P.

CHRIN   PROC    NEAR
        XOR     AX,AX
        XCHG    AL,[ALTAH]              ; a byte held back?
        OR      AL,AL
        JNZ     KEYRET
        INT     16H
        OR      AX,AX                   ; nothing, after a Break
        JZ      CHRIN
        CMP     AX,7200H                ; Ctrl-PrtSc
        JNZ     CHRIN1
        MOV     AL,16
        RET
CHRIN1: OR      AL,AL
        JNZ     KEYRET
        MOV     [ALTAH],AH              ; an extended key: its scan code next
KEYRET: RET
CHRIN   ENDP

CON_READ:
        JCXZ    CON_RD9
CON_RD1:
        CALL    CHRIN
        STOSB
        LOOP    CON_RD1
CON_RD9:
        JMP     EXIT

CON_RDND:
        MOV     AL,[ALTAH]
        OR      AL,AL
        JNZ     RDEXIT
CON_RDN1:
        MOV     AH,1
        INT     16H
        JZ      CON_BUSY
        OR      AX,AX                   ; a null after a Break: discard it
        JNZ     CON_RDN2
        XOR     AH,AH
        INT     16H
        JMP     CON_RDN1
CON_RDN2:
        CMP     AX,7200H
        JNZ     RDEXIT
        MOV     AL,16
RDEXIT: LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     [BX+RQ_MEDIA],AL
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     EXIT
CON_BUSY:
        JMP     BUS_EXIT

CON_FLSH:
        MOV     [ALTAH],0
CON_FL1:
        MOV     AH,1
        INT     16H
        JZ      CON_FL9
        XOR     AH,AH
        INT     16H
        JMP     CON_FL1
CON_FL9:
        JMP     EXIT

CON_WRIT:
        JCXZ    CON_WR9
CON_WR1:
        MOV     AL,ES:[DI]
        INC     DI
        INT     29H
        LOOP    CON_WR1
CON_WR9:
        JMP     EXIT

; INT 29h, the fast console output the DOS uses for CON (the SPECIAL bit):
; AL to the screen at the cursor, through the ROM's teletype routine.
OUTCHR  PROC    FAR
        PUSH    AX
        PUSH    BX
        PUSH    SI
        PUSH    DI
        PUSH    BP
        MOV     AH,14
        MOV     BX,7
        INT     10H
        POP     BP
        POP     DI
        POP     SI
        POP     BX
        POP     AX
        IRET
OUTCHR  ENDP

; INT 1Bh, Ctrl-Break: the next character read from CON is Ctrl-C.
CBREAK  PROC    FAR
        MOV     CS:[ALTAH],3
        IRET
CBREAK  ENDP

        SUBTTL  AUX and COM1: the first serial port
        PAGE

AUXCHR  DB      0               ; a character read ahead
AUXHAVE DB      0

AUX_GET PROC    NEAR            ; AL = the next character, waiting for it
        CMP     [AUXHAVE],0
        JZ      AUXG1
        MOV     [AUXHAVE],0
        MOV     AL,[AUXCHR]
        RET
AUXG1:  MOV     AH,2
        XOR     DX,DX
        INT     14H
        TEST    AH,80H                  ; timed out: try again
        JNZ     AUXG1
        RET
AUX_GET ENDP

AUX_READ:
        JCXZ    AUX_RD9
AUX_RD1:
        PUSH    CX
        CALL    AUX_GET
        POP     CX
        STOSB
        LOOP    AUX_RD1
AUX_RD9:
        JMP     EXIT

AUX_RDND:
        CMP     [AUXHAVE],0
        JNZ     AUX_RN2
        MOV     AH,3
        XOR     DX,DX
        INT     14H
        TEST    AH,1                    ; data ready?
        JZ      AUX_RN1
        MOV     AH,2
        INT     14H
        TEST    AH,80H
        JNZ     AUX_RN1
        MOV     [AUXCHR],AL
        MOV     [AUXHAVE],1
AUX_RN2:
        MOV     AL,[AUXCHR]
        JMP     RDEXIT
AUX_RN1:
        JMP     BUS_EXIT

AUX_FLSH:
        MOV     [AUXHAVE],0
        JMP     EXIT

AUX_WRIT:
        JCXZ    AUX_WR9
AUX_WR1:
        MOV     AL,ES:[DI]
        INC     DI
        MOV     AH,1
        XOR     DX,DX
        INT     14H
        TEST    AH,80H
        JNZ     AUX_WRE
        LOOP    AUX_WR1
AUX_WR9:
        JMP     EXIT
AUX_WRE:
        MOV     AL,10                   ; write fault
        JMP     ERR_EXIT

AUX_WRST:
        MOV     AH,3
        XOR     DX,DX
        INT     14H
        TEST    AH,20H                  ; transmit holding register empty?
        JZ      AUX_WRB
        JMP     EXIT
AUX_WRB:
        JMP     BUS_EXIT

        SUBTTL  PRN, LPT1, LPT2, LPT3: the printers
        PAGE

PRN_WRIT:
        JCXZ    PRN_WR9
        XOR     BX,BX                   ; characters written
PRN_WR1:
        MOV     AL,ES:[DI]
        MOV     SI,3                    ; tries
PRN_WR2:
        MOV     AH,0
        MOV     DX,[PRNUM]
        INT     17H
        TEST    AH,29H                  ; timed out, I/O error, out of paper?
        JZ      PRN_WR3
        TEST    AH,1
        JZ      PRN_WRE                 ; not a time-out: report it
        DEC     SI
        JNZ     PRN_WR2
PRN_WRE:
        PUSH    BX
        CALL    PRNERR
        POP     CX
        JMP     ERR_CNT
PRN_WR3:
        INC     DI
        INC     BX
        LOOP    PRN_WR1
PRN_WR9:
        JMP     EXIT

PRN_STAT:
        MOV     AH,2
        MOV     DX,[PRNUM]
        INT     17H
        TEST    AH,29H
        JNZ     PRN_ST2
        TEST    AH,80H                  ; not busy?
        JZ      PRN_ST1
        JMP     EXIT
PRN_ST1:
        JMP     BUS_EXIT
PRN_ST2:
        CALL    PRNERR
        JMP     ERR_EXIT

PRNERR  PROC    NEAR            ; AH = printer status, to AL = DOS error
        MOV     AL,9                    ; out of paper
        TEST    AH,20H
        JNZ     PRNE9
        MOV     AL,2                    ; not ready (timed out)
        TEST    AH,1
        JNZ     PRNE9
        MOV     AL,10                   ; write fault
PRNE9:  RET
PRNERR  ENDP

        SUBTTL  CLOCK$: the date and time
        PAGE

; The ROM keeps the time of day as ticks of 1/18.2 second since midnight,
; and says when midnight has passed. The routines are those of MSCLOCK.ASM
; of the MS-DOS 4.0 BIOS, without its AT real-time clock.

TIM_READ:
        XOR     AH,AH
        INT     1AH
        OR      AL,AL                   ; past midnight since last asked?
        JZ      NOROLL
        INC     [DAYCNT]
NOROLL: MOV     SI,[DAYCNT]
        MOV     AX,CX
        MOV     BX,DX
        SHL     DX,1
        RCL     CX,1                    ; times 2
        SHL     DX,1
        RCL     CX,1                    ; times 4
        ADD     DX,BX
        ADC     AX,CX                   ; times 5
        XCHG    AX,DX
        MOV     CX,59659
        DIV     CX
        MOV     BX,AX
        XOR     AX,AX
        DIV     CX                      ; BX:AX = time in 1/100 seconds
        MOV     DX,BX
        MOV     CX,200                  ; extract 1/100s
        DIV     CX
        CMP     DL,100
        JB      NOADJ
        SUB     DL,100
NOADJ:  CMC
        MOV     BL,DL                   ; 1/100s
        RCL     AX,1
        MOV     DL,0
        RCL     DX,1
        MOV     CX,60                   ; seconds
        DIV     CX
        MOV     BH,DL
        DIV     CL                      ; hours and minutes
        XCHG    AL,AH
        PUSH    AX
        MOV     AX,SI
        STOSW
        POP     AX
        STOSW
        MOV     AX,BX
        STOSW
        JMP     EXIT

TIM_WRIT:
        MOV     AX,ES:[DI]
        PUSH    AX                      ; the day count
        MOV     CX,ES:[DI+2]
        MOV     DX,ES:[DI+4]
        CALL    TIME_TO_TICKS
        CLI
        MOV     AH,1
        INT     1AH
        POP     [DAYCNT]
        STI
        JMP     EXIT

TIME_TO_TICKS PROC NEAR         ; CH:CL:DH:DL = h:m:s:1/100, to CX:DX ticks
        MOV     AL,60
        MUL     CH                      ; hours to minutes
        MOV     CH,0
        ADD     AX,CX                   ; total minutes
        MOV     CX,6000
        MOV     BX,DX
        MUL     CX                      ; to 1/100 seconds
        MOV     CX,AX
        MOV     AL,100
        MUL     BH                      ; seconds to 1/100
        ADD     CX,AX
        ADC     DX,0
        MOV     BH,0
        ADD     CX,BX                   ; and the 1/100s
        ADC     DX,0
        XCHG    AX,DX
        XCHG    AX,CX                   ; time is in CX:AX
        MOV     BX,59659
        MUL     BX
        XCHG    DX,CX
        XCHG    AX,DX
        MUL     BX
        ADD     AX,CX
        ADC     DX,0
        XCHG    AX,DX                   ; AX:DX = time * 59659
        MOV     BX,5
        DIV     BL
        MOV     CL,AL
        MOV     CH,0
        MOV     AL,AH
        CBW
        XCHG    AX,DX
        DIV     BX
        MOV     DX,AX
        RET
TIME_TO_TICKS ENDP

        SUBTTL  The disks
        PAGE

; Unit numbers: diskette drives first (always two, A: and B:, even with one
; drive), then the fixed disks.

DSK_INIT:                       ; nothing left to do; INIT did it
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     AL,CS:[DRVMAX]
        MOV     [BX+RQ_UNITS],AL
        MOV     WORD PTR [BX+RQ_BREAK],OFFSET RESEND
        MOV     WORD PTR [BX+RQ_BREAK+2],CS
        MOV     WORD PTR [BX+RQ_BPB],OFFSET UNITBPB
        MOV     WORD PTR [BX+RQ_BPB+2],CS
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     EXIT

; BX = unit*2 for the tables, or a jump to unknown-unit.
GETUNIT PROC    NEAR
        CMP     AL,[DRVMAX]
        JAE     GETU_BAD
        MOV     BL,AL
        XOR     BH,BH
        SHL     BX,1
        RET
GETU_BAD:
        POP     AX                      ; not back to the caller
        MOV     AL,1
        JMP     ERR_EXIT
GETUNIT ENDP

TICKS   PROC    NEAR            ; AX = low word of the ROM's tick count
        PUSH    DS
        XOR     AX,AX
        MOV     DS,AX
        MOV     AX,DS:[046CH]
        POP     DS
        RET
TICKS   ENDP

; MEDIA CHECK. A fixed disk never changes. The PC's diskette drives cannot
; tell, so a diskette used in the last two seconds is taken as unchanged,
; and otherwise the DOS is told "don't know", as PC DOS 2 does.
MEDIA_CHK:
        CALL    GETUNIT
        MOV     SI,BX
        SHR     SI,1
        MOV     AH,1                    ; not changed
        TEST    [PHYS+SI],80H
        JNZ     MC_DONE
        CALL    ONEDRIVE
        MOV     AH,-1                   ; changed: the other diskette is in
        JC      MC_DONE
        MOV     AX,SI
        CMP     AL,[LASTUNIT]
        MOV     AH,0                    ; don't know
        JNZ     MC_DONE
        CALL    TICKS
        SUB     AX,[LASTTICK]
        CMP     AX,37                   ; two seconds
        MOV     AH,0
        JAE     MC_DONE
        MOV     AH,1
MC_DONE:
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     [BX+RQ_CHANGED],AH
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     EXIT

; BUILD BPB. For a diskette, the FAT ID byte, the first byte of the buffer
; the DOS passes, names the format. A fixed disk's BPB was read at INIT.
GET_BPB:
        CALL    GETUNIT
        MOV     SI,BX
        SHR     SI,1
        TEST    [PHYS+SI],80H
        JNZ     GB_HARD
        MOV     AL,ES:[DI]              ; the FAT ID
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET MEDIAID
        MOV     CX,4
        REPNE   SCASB
        JNZ     GB_BAD
        SUB     DI,OFFSET MEDIAID+1
        SHL     DI,1
        MOV     AX,[MEDIABPB+DI]
        MOV     [UNITBPB+BX],AX
        MOV     AX,[MEDIASPT+DI]
        MOV     [UNITSPT+BX],AX
        MOV     AX,[MEDIAHDS+DI]
        MOV     [UNITHDS+BX],AX
GB_HARD:
        MOV     AX,[UNITBPB+BX]
        LDS     BX,[PTRSAV]
ASSUME  DS:NOTHING
        MOV     [BX+RQ_BPB],AX
        MOV     [BX+RQ_BPB+2],CS
        PUSH    CS
        POP     DS
ASSUME  DS:CODE
        JMP     EXIT
GB_BAD: MOV     AL,7                    ; unknown media
        JMP     ERR_EXIT

; READ, WRITE, WRITE WITH VERIFY.
DSK_READ:
        MOV     BP,2                    ; INT 13h: read
        JMP     SHORT DSK_RW
DSK_WRIT:
        MOV     BP,3                    ; write
        JMP     SHORT DSK_RW
DSK_WRTV:
        MOV     BP,103H                 ; write, then verify
DSK_RW:
        CALL    GETUNIT
        MOV     SI,BX
        SHR     SI,1
        JCXZ    RW_DONE
        CALL    ONEDRIVE
        MOV     AX,DX                   ; DX:AX = the volume's sector + hidden
        XOR     DX,DX
        ADD     AX,[HIDLO+BX]
        ADC     DX,[HIDHI+BX]
        PUSH    AX
        MOV     AX,[UNITSPT+BX]
        MOV     [RW_SPT],AX
        MOV     AX,[UNITHDS+BX]
        MOV     [RW_HDS],AX
        MOV     AL,[PHYS+SI]
        MOV     [RW_DRV],AL
        POP     AX
        PUSH    CX                      ; the count asked for
        PUSH    SI
        CALL    DISKIO                  ; CX sectors, from DX:AX, at ES:DI
        POP     SI
        POP     BX
        PUSHF
        PUSH    AX
        TEST    [PHYS+SI],80H
        JNZ     RW_NOTIME
        MOV     AX,SI
        MOV     [LASTUNIT],AL
        CALL    TICKS
        MOV     [LASTTICK],AX
RW_NOTIME:
        POP     AX
        POPF
        JNC     RW_DONE
        SUB     BX,CX                   ; sectors done before the error
        MOV     CX,BX
        JMP     ERR_CNT                 ; AL = the error
RW_DONE:
        JMP     EXIT

; On a computer with one diskette drive, A: and B: are the same drive. When
; the other letter is asked for, ask for its diskette, as PC DOS does.
; SI = unit.
ONEDRIVE PROC   NEAR            ; CF set if the diskette had to be changed
        CMP     [NUMFLOP],1
        JNZ     OD_RET
        CMP     SI,1
        JA      OD_RET
        PUSH    AX
        PUSH    BX
        MOV     AX,SI
        CMP     AL,[ONEDRV]
        JZ      OD_SAME
        MOV     [ONEDRV],AL
        PUSH    DS
        XOR     BX,BX
        MOV     DS,BX
        MOV     DS:[0504H],AL           ; where PC DOS keeps it, for the ROM
        POP     DS
        ADD     AL,"A"
        MOV     [ODLET],AL
        PUSH    SI
        MOV     SI,OFFSET ODMSG
OD_LP:  LODSB
        OR      AL,AL
        JZ      OD_KEY
        INT     29H
        JMP     OD_LP
OD_KEY: POP     SI
        CALL    CON_FL_NOEXIT
        XOR     AH,AH
        INT     16H
        MOV     [LASTUNIT],-1           ; whatever was there is gone
        POP     BX
        POP     AX
        STC
        RET
OD_SAME:
        POP     BX
        POP     AX
OD_RET: CLC
        RET
ONEDRIVE ENDP

CON_FL_NOEXIT PROC NEAR
        MOV     [ALTAH],0
CFN1:   MOV     AH,1
        INT     16H
        JZ      CFN9
        XOR     AH,AH
        INT     16H
        JMP     CFN1
CFN9:   RET
CON_FL_NOEXIT ENDP

ODMSG   DB      CR,LF,"Insert diskette for drive "
ODLET   DB      "A: and strike",CR,LF,"any key when ready",CR,LF,LF,0

        SUBTTL  DISKIO: sectors through the ROM BIOS
        PAGE

; DISKIO reads or writes CX sectors starting at absolute sector DX:AX of
; drive RW_DRV, whose geometry is RW_SPT and RW_HDS, at ES:DI. BP is 2 to
; read, 3 to write, 103h to write and verify. A track at a time, never
; across a 64K boundary of physical memory (the DMA controller cannot); a
; sector that would straddle one goes through SECBUF. Returns CF clear, or
; CF set, AL = the DOS error and CX = the sectors not done.
; Uses AX BX CX DX; ES:DI advanced past what was done.

RW_DRV  DB      0
RW_SPT  DW      9
RW_HDS  DW      2
RW_LO   DW      0               ; the current absolute sector
RW_HI   DW      0
RW_LEFT DW      0               ; sectors still to do
RW_N    DW      0               ; sectors in this transfer
RW_SEC  DB      0               ; sector in the track, from 0
RW_HEAD DB      0
RW_CYL  DW      0
RW_TRY  DB      0
RIO_CNT DB      0
RIO_STAT DB     0

DISKIO  PROC    NEAR
        MOV     [RW_LO],AX
        MOV     [RW_HI],DX
        MOV     [RW_LEFT],CX
        CALL    NORMDI
DIO_LP: CMP     [RW_LEFT],0
        JNZ     DIO_1
        CLC
        RET
DIO_1:  ; sector in the track, head and cylinder
        MOV     AX,[RW_HI]
        XOR     DX,DX
        DIV     [RW_SPT]
        MOV     BX,AX
        MOV     AX,[RW_LO]
        DIV     [RW_SPT]                ; BX:AX = track, DX = sector
        MOV     [RW_SEC],DL
        MOV     DX,BX
        DIV     [RW_HDS]                ; AX = cylinder, DX = head
        MOV     [RW_HEAD],DL
        MOV     [RW_CYL],AX
        ; the rest of the track, at most what is left
        MOV     AX,[RW_SPT]
        SUB     AL,[RW_SEC]
        SBB     AH,0
        CMP     AX,[RW_LEFT]
        JBE     DIO_N1
        MOV     AX,[RW_LEFT]
DIO_N1: MOV     [RW_N],AX
        ; and not across a 64K boundary of memory
        MOV     AX,ES
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,DI
        NEG     AX                      ; bytes to the boundary (0 = 64K)
        JZ      DIO_N2
        MOV     CL,9
        SHR     AX,CL                   ; whole sectors before it
        CMP     AX,[RW_N]
        JAE     DIO_N2
        MOV     [RW_N],AX
DIO_N2: ; the ROM's CH CL DH DL
        MOV     AX,[RW_CYL]
        MOV     CH,AL
        MOV     CL,AH
        ROR     CL,1
        ROR     CL,1
        AND     CL,0C0H
        OR      CL,[RW_SEC]
        INC     CL
        MOV     DH,[RW_HEAD]
        MOV     DL,[RW_DRV]
        CMP     [RW_N],0
        JZ      DIO_BOUNCE
        MOV     BX,DI
        MOV     AL,BYTE PTR [RW_N]
        CALL    ROMIO
        JC      DIO_ERR
        MOV     AX,[RW_N]
        JMP     SHORT DIO_NEXT
DIO_BOUNCE:                             ; one sector, through SECBUF
        PUSH    ES
        PUSH    DI
        PUSH    CX
        CMP     BP,2
        JZ      DIO_B1
        PUSH    DS                      ; writing: copy it in first
        PUSH    ES
        POP     DS
        MOV     SI,DI
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET SECBUF
        MOV     CX,SECSIZE/2
        REP     MOVSW
        POP     DS
DIO_B1: POP     CX
        PUSH    CX
        PUSH    CS
        POP     ES
        MOV     BX,OFFSET SECBUF
        MOV     AL,1
        CALL    ROMIO
        POP     CX
        POP     DI
        POP     ES
        JC      DIO_ERR
        CMP     BP,2
        JNZ     DIO_B2
        MOV     SI,OFFSET SECBUF        ; reading: copy it out
        MOV     CX,SECSIZE/2
        REP     MOVSW
        SUB     DI,SECSIZE
DIO_B2: MOV     AX,1
DIO_NEXT:
        SUB     [RW_LEFT],AX
        ADD     [RW_LO],AX
        ADC     [RW_HI],0
        MOV     CL,9
        SHL     AX,CL
        ADD     DI,AX
        CALL    NORMDI
        JMP     DIO_LP
DIO_ERR:
        MOV     CX,[RW_LEFT]            ; AL = the DOS error
        STC
        RET
DISKIO  ENDP

; ES:DI with DI below 16, the same address.
NORMDI  PROC    NEAR
        PUSH    AX
        PUSH    CX
        MOV     AX,DI
        MOV     CL,4
        SHR     AX,CL
        MOV     CX,ES
        ADD     CX,AX
        MOV     ES,CX
        AND     DI,0FH
        POP     CX
        POP     AX
        RET
NORMDI  ENDP

; ROMIO: INT 13h function BP (low byte), AL sectors at ES:BX, CH CL DH DL
; as the ROM wants them, with up to five tries and a reset between. Then,
; if BP is 103h, verifies. CF set and AL = the DOS error if it fails.
ROMIO   PROC    NEAR
        MOV     [RW_TRY],5
        MOV     [RIO_CNT],AL
RIO_GO: MOV     AX,BP
        MOV     AH,AL                   ; 2 or 3
        MOV     AL,[RIO_CNT]
        PUSH    DX
        PUSH    CX
        PUSH    BX
        INT     13H
        POP     BX
        POP     CX
        POP     DX
        JNC     RIO_OK
        MOV     [RIO_STAT],AH
        CMP     AH,3                    ; write-protected: no use trying again
        JZ      RIO_FAIL
        XOR     AH,AH                   ; reset, and try again
        INT     13H
        DEC     [RW_TRY]
        JNZ     RIO_GO
RIO_FAIL:
        MOV     AL,[RIO_STAT]
        JMP     SHORT RIO_MAP
RIO_OK: CMP     BP,103H
        JNZ     RIO_RET
        MOV     [RW_TRY],5
RIO_V:  MOV     AH,4                    ; verify
        MOV     AL,[RIO_CNT]
        PUSH    DX
        PUSH    CX
        PUSH    BX
        INT     13H
        POP     BX
        POP     CX
        POP     DX
        JNC     RIO_RET
        MOV     [RIO_STAT],AH
        XOR     AH,AH
        INT     13H
        DEC     [RW_TRY]
        JNZ     RIO_V
        MOV     AL,[RIO_STAT]
RIO_MAP:                                ; AL = ROM status: to the DOS error
        PUSH    CX
        PUSH    DI
        PUSH    ES
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET ERRIN
        MOV     CX,NUMERR
        REPNE   SCASB
        MOV     AL,12                   ; general failure
        JNZ     RIO_E1
        MOV     AL,[DI+NUMERR-1]
RIO_E1: POP     ES
        POP     DI
        POP     CX
        STC
        RET
RIO_RET:
        CLC
        RET
ROMIO   ENDP

SECBUF  DB      SECSIZE DUP (0)         ; for a sector across a 64K boundary

        SUBTTL  RE_INIT
        PAGE

; Called by SYSINIT after the DOS is initialized. Nothing to do.
RE_INIT PROC    FAR
        RET
RE_INIT ENDP

        EVEN
RESEND  LABEL   BYTE            ; everything after this is given back

        SUBTTL  INIT: start the system
        PAGE

; Here from the boot sector, at 0070:0000, with DL = the drive started from
; and the boot sector, with its BPB, at 0000:7C00.

BOOTDRV DB      0
BS_SPC  DB      0
BS_RES  DW      0
BS_FATS DB      0
BS_DIR  DW      0
BS_FATSZ DW     0
BS_SPT  DW      0
BS_HDS  DW      0
BS_HID  DW      0
ROOTLO  DW      0               ; absolute sector of the root directory
DATALO  DW      0               ; of the first cluster

MSG_NODOS DB    CR,LF,"Missing MSDOS.SYS",CR,LF,0
MSG_DOSERR DB   CR,LF,"Error loading MSDOS.SYS",CR,LF,0
DOSNAME DB      "MSDOS   SYS"

INIT:   CLI
        MOV     AX,CS
        MOV     DS,AX
        MOV     SS,AX
        MOV     SP,OFFSET INITSTK
        STI
        CLD
        MOV     [BOOTDRV],DL
        ; what the boot sector knew
        XOR     AX,AX
        MOV     ES,AX
        MOV     AL,ES:[7C00H+13]
        MOV     [BS_SPC],AL
        MOV     AX,ES:[7C00H+14]
        MOV     [BS_RES],AX
        MOV     AL,ES:[7C00H+16]
        MOV     [BS_FATS],AL
        MOV     AX,ES:[7C00H+17]
        MOV     [BS_DIR],AX
        MOV     AX,ES:[7C00H+22]
        MOV     [BS_FATSZ],AX
        MOV     AX,ES:[7C00H+24]
        MOV     [BS_SPT],AX
        MOV     AX,ES:[7C00H+26]
        MOV     [BS_HDS],AX
        MOV     AX,ES:[7C00H+28]
        MOV     [BS_HID],AX

        ; the vectors: INT 1Bh Ctrl-Break, INT 29h fast console
        CLI
        MOV     WORD PTR ES:[1BH*4],OFFSET CBREAK
        MOV     WORD PTR ES:[1BH*4+2],CS
        MOV     WORD PTR ES:[29H*4],OFFSET OUTCHR
        MOV     WORD PTR ES:[29H*4+2],CS
        ; the diskette parameters: the ROM's, with 9 sectors a track
        PUSH    DS
        LDS     SI,ES:[1EH*4]
ASSUME  DS:NOTHING
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET DPT
        MOV     CX,11
        REP     MOVSB
        POP     DS
ASSUME  DS:CODE
        MOV     [DPT+4],9
        XOR     AX,AX
        MOV     ES,AX
        MOV     WORD PTR ES:[1EH*4],OFFSET DPT
        MOV     WORD PTR ES:[1EH*4+2],CS
        STI

        ; the diskette drives: INT 11h
        INT     11H
        MOV     CL,6
        MOV     BX,AX
        SHR     BX,CL
        AND     BX,3
        INC     BX
        TEST    AL,1
        JNZ     HAVEFLOP
        MOV     BX,1                    ; none reported: assume one
HAVEFLOP:
        MOV     [NUMFLOP],BL
        MOV     [DRVMAX],2              ; A: and B: always
        CMP     BL,1
        JNZ     TWOFLOP
        MOV     [PHYS+1],0              ; B: is the same drive
TWOFLOP:

        ; the fixed disks
        MOV     DL,80H
        CALL    FIXEDDISK
        JC      NOFIXED
        MOV     DL,81H
        CALL    FIXEDDISK
NOFIXED:
        ; the clock starts at 1-1-80; the boot sector's work is done
        MOV     [DAYCNT],0

        ; load MSDOS.SYS just above the whole of IO.SYS
        CALL    LOADDOS

        ; SYSINIT's variables
        MOV     AX,SEG SYSINIT
        MOV     ES,AX
ASSUME  ES:SYSINITSEG
        MOV     AX,[DOSPARA]
        MOV     ES:[CURRENT_DOS_LOCATION],AX
        MOV     AX,OFFSET RESEND+15
        MOV     CL,4
        SHR     AX,CL
        MOV     BX,CS
        ADD     AX,BX
        MOV     ES:[FINAL_DOS_LOCATION],AX
        MOV     WORD PTR ES:[DEVICE_LIST],OFFSET DEVSTART
        MOV     WORD PTR ES:[DEVICE_LIST+2],CS
        INT     12H                     ; memory, in KB
        MOV     CL,6
        SHL     AX,CL
        MOV     ES:[MEMORY_SIZE],AX
        MOV     AL,1                    ; 1 = A:
        TEST    [BOOTDRV],80H
        JZ      DEFDRV
        MOV     AL,3                    ; started from the fixed disk: C:
DEFDRV: MOV     ES:[DEFAULT_DRIVE],AL
ASSUME  ES:NOTHING
        JMP     SYSINIT

; FIXEDDISK: DL = 80h or 81h. If there is such a disk with a DOS partition
; whose boot sector has a BPB, add a unit for it. CF set if there is no such
; disk (then there is no later one either).
FIXEDDISK PROC  NEAR
        PUSH    DX
        MOV     AH,8                    ; drive parameters
        INT     13H
        POP     AX                      ; AL = drive
        JC      FD_NONEJ
        MOV     AH,DL                   ; number of fixed disks
        AND     AL,7FH
        CMP     AL,AH
        JB      FD_THERE
FD_NONEJ:
        JMP     FD_NONE
FD_THERE:
        OR      AL,80H
        MOV     [FD_DRV],AL
        MOV     BL,DH
        XOR     BH,BH
        INC     BX
        MOV     [FD_HDS],BX
        AND     CL,3FH
        XOR     CH,CH
        MOV     [FD_SPT],CX
        ; the partition table
        MOV     [RW_SPT],CX
        MOV     [RW_HDS],BX
        MOV     AL,[FD_DRV]
        MOV     [RW_DRV],AL
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET SECBUF
        MOV     BP,2
        MOV     CX,1
        XOR     AX,AX
        XOR     DX,DX
        CALL    DISKIO
        JC      FD_NONE_OK
        CMP     WORD PTR [SECBUF+510],0AA55H
        JNZ     FD_NONE_OK
        MOV     SI,OFFSET SECBUF+1BEH
        MOV     CX,4
FD_PART:
        CMP     BYTE PTR [SI+4],1       ; DOS, 12-bit FAT
        JZ      FD_FOUND
        ADD     SI,16
        LOOP    FD_PART
        JMP     SHORT FD_NONE_OK
FD_FOUND:
        MOV     AX,[SI+8]               ; where it starts
        MOV     DX,[SI+10]
        MOV     [FD_LO],AX
        MOV     [FD_HI],DX
        MOV     AX,[SI+12]              ; its length: at most 65535 sectors,
        CMP     WORD PTR [SI+14],0      ; all a DOS 2 volume can hold
        JZ      FD_LEN
        MOV     AX,0FFFFH
FD_LEN: ; its BPB, worked out from its size as PC DOS 2 does (the BPB in a
        ; fixed disk's boot sector is not used: FORMAT writes the same one)
        CALL    CALCBPB
        ; a unit for it
        MOV     BL,[DRVMAX]
        XOR     BH,BH
        MOV     AL,[FD_DRV]
        MOV     [PHYS+BX],AL
        SHL     BX,1
        MOV     AX,[FD_SPT]
        MOV     [UNITSPT+BX],AX
        MOV     AX,[FD_HDS]
        MOV     [UNITHDS+BX],AX
        MOV     AX,[FD_LO]
        MOV     [HIDLO+BX],AX
        MOV     AX,[FD_HI]
        MOV     [HIDHI+BX],AX
        MOV     DI,[UNITBPB+BX]         ; HDBPB0 or HDBPB1
        PUSH    CS
        POP     ES
        MOV     SI,OFFSET CB_BPB
        MOV     CX,13
        REP     MOVSB
        INC     [DRVMAX]
FD_NONE_OK:
        CLC
        RET
FD_NONE:
        STC
        RET
FIXEDDISK ENDP

; CALCBPB: AX = sectors in a fixed disk's DOS partition, to CB_BPB: 512
; root directory entries, two FATs, and the smallest cluster that keeps the
; 12-bit FAT within 4,084 clusters. (scripts/mkhd.py does the same.)
CALCBPB PROC    NEAR
        MOV     [CB_SECS],AX
        MOV     [CB_SPC],1
CB_SPCL:
        MOV     [CB_FAT],1
CB_FATL:
        MOV     AX,[CB_SECS]
        SUB     AX,1+32                 ; boot sector, root directory
        SUB     AX,[CB_FAT]
        SUB     AX,[CB_FAT]
        XOR     DX,DX
        DIV     [CB_SPC]
        MOV     [CB_CLUS],AX
        ADD     AX,2                    ; bytes the FAT needs: (n+2) * 1.5
        MOV     CX,3
        MUL     CX
        SHR     DX,1
        RCR     AX,1
        MOV     CX,[CB_FAT]             ; bytes it has: sectors * 512
        MOV     BX,CX
        MOV     CL,7
        SHR     BX,CL                   ; high word
        MOV     CX,[CB_FAT]
        PUSH    AX
        MOV     AX,CX
        MOV     CL,9
        SHL     AX,CL                   ; low word
        MOV     CX,AX
        POP     AX
        CMP     DX,BX
        JB      CB_FITS
        JA      CB_MORE
        CMP     AX,CX
        JBE     CB_FITS
CB_MORE:
        INC     [CB_FAT]
        JMP     CB_FATL
CB_FITS:
        CMP     [CB_CLUS],4084
        JBE     CB_DONE
        SHL     [CB_SPC],1
        JMP     CB_SPCL
CB_DONE:
        MOV     WORD PTR [CB_BPB],SECSIZE
        MOV     AL,BYTE PTR [CB_SPC]
        MOV     [CB_BPB+2],AL
        MOV     WORD PTR [CB_BPB+3],1
        MOV     [CB_BPB+5],2
        MOV     WORD PTR [CB_BPB+6],512
        MOV     AX,[CB_SECS]
        MOV     WORD PTR [CB_BPB+8],AX
        MOV     [CB_BPB+10],0F8H
        MOV     AX,[CB_FAT]
        MOV     WORD PTR [CB_BPB+11],AX
        RET
CALCBPB ENDP

CB_SECS DW      0
CB_SPC  DW      0
CB_FAT  DW      0
CB_CLUS DW      0
CB_BPB  DB      13 DUP (0)

FD_DRV  DB      0
FD_SPT  DW      0
FD_HDS  DW      0
FD_LO   DW      0
FD_HI   DW      0
DOSPARA  DW      0

; LOADDOS: find MSDOS.SYS, the second entry of the root directory of the
; disk started from, and read it, a cluster at a time along its FAT chain
; (it need not be contiguous), to the paragraph after IO.SYS.
LOADDOS PROC    NEAR
        MOV     AL,[BOOTDRV]
        MOV     [RW_DRV],AL
        MOV     AX,[BS_SPT]
        MOV     [RW_SPT],AX
        MOV     AX,[BS_HDS]
        MOV     [RW_HDS],AX
        ; the root directory and the data area
        MOV     AL,[BS_FATS]
        XOR     AH,AH
        MUL     [BS_FATSZ]
        ADD     AX,[BS_RES]
        ADD     AX,[BS_HID]
        MOV     [ROOTLO],AX
        MOV     AX,[BS_DIR]
        MOV     CL,4
        SHR     AX,CL                   ; 16 entries a sector
        ADD     AX,[ROOTLO]
        MOV     [DATALO],AX
        ; the first sector of the root directory
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET SECBUF
        MOV     AX,[ROOTLO]
        XOR     DX,DX
        MOV     CX,1
        MOV     BP,2
        CALL    DISKIO
        JC      LD_ERR
        PUSH    CS
        POP     ES
        MOV     SI,OFFSET SECBUF+32
        MOV     DI,OFFSET DOSNAME
        MOV     CX,11
        REPE    CMPSB
        JNZ     LD_MISS
        MOV     AX,WORD PTR [SECBUF+32+26]
        MOV     [LD_CLUS],AX
        ; where it goes
        MOV     AX,SEG ENDIMAGE         ; the paragraph after all of IO.SYS
        MOV     [DOSPARA],AX
        MOV     ES,AX
        XOR     DI,DI
LD_LP:  MOV     AX,[LD_CLUS]
        CMP     AX,0FF8H
        JAE     LD_DONE
        CMP     AX,2
        JB      LD_ERR
        ; read the cluster
        SUB     AX,2
        MOV     CL,[BS_SPC]
        XOR     CH,CH
        MUL     CX
        ADD     AX,[DATALO]
        ADC     DX,0
        CALL    DISKIO                  ; CX = sectors per cluster
        JC      LD_ERR
        ; the next cluster, from the FAT
        CALL    NEXTCLUS
        JC      LD_ERR
        JMP     LD_LP
LD_DONE:
        RET
LD_MISS:
        MOV     SI,OFFSET MSG_NODOS
        JMP     SHORT LD_STOP
LD_ERR: MOV     SI,OFFSET MSG_DOSERR
LD_STOP:
        LODSB
        OR      AL,AL
        JZ      LD_HALT
        MOV     AH,14
        MOV     BX,7
        INT     10H
        JMP     LD_STOP
LD_HALT:
        STI
        JMP     LD_HALT
LOADDOS ENDP

LD_CLUS DW      0
FATSEC  DW      -1              ; the FAT sector in FATBUF (two, for a 12-bit
                                ; entry across a sector boundary)

; NEXTCLUS: LD_CLUS = the cluster after it, from the first FAT. 12-bit FAT.
NEXTCLUS PROC   NEAR
        PUSH    ES
        PUSH    DI
        MOV     AX,[LD_CLUS]
        MOV     BX,AX
        SHR     BX,1
        ADD     BX,AX                   ; byte offset in the FAT: n * 1.5
        MOV     AX,BX
        XOR     DX,DX
        MOV     CX,SECSIZE
        DIV     CX                      ; AX = FAT sector, DX = offset
        PUSH    DX
        CMP     AX,[FATSEC]
        JZ      NC_HAVE
        MOV     [FATSEC],AX
        ADD     AX,[BS_RES]
        ADD     AX,[BS_HID]
        XOR     DX,DX
        PUSH    CS
        POP     ES
        MOV     DI,OFFSET FATBUF
        MOV     CX,2                    ; this sector and the next
        CALL    DISKIO
        JC      NC_ERR
NC_HAVE:
        POP     BX
        MOV     AX,WORD PTR [FATBUF+BX]
        TEST    [LD_CLUS],1
        JZ      NC_EVEN
        MOV     CL,4
        SHR     AX,CL
NC_EVEN:
        AND     AX,0FFFH
        MOV     [LD_CLUS],AX
        POP     DI
        POP     ES
        CLC
        RET
NC_ERR: POP     BX
        POP     DI
        POP     ES
        STC
        RET
NEXTCLUS ENDP

FATBUF  DB      2*SECSIZE DUP (0)
        DB      256 DUP (0)
INITSTK LABEL   WORD


CODE    ENDS
        END     START
