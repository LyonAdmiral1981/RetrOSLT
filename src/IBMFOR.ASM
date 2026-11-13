        TITLE   FORMAT for the IBM Personal Computer -- RetrOS/LT

; The OEM part of FORMAT (see FORMAT.txt of the MS-DOS 2.x kit), for the
; IBM Personal Computer and XT: it formats 5-1/4 inch diskettes in the four
; DOS 2 formats, and checks a fixed disk's DOS partition, and writes the
; boot sector and FATs. Linked with Microsoft's FORMAT and FORMES modules:
;
;       LINK FORMAT FORMES IBMFOR;      EXE2BIN FORMAT.EXE FORMAT.COM
;
; Switches, as PC DOS 2.10's FORMAT has them:
;       /S  copy the system          /V  ask for a volume label
;       /1  one side                 /8  8 sectors a track (DOS 1 formats)
;       /B  8 sectors, with room left for the system to be put on later
;
; Copyright The Lyon Mountain Company, Republic Lyon Mountain Corporation 2026

CODE    SEGMENT PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE,ES:CODE

        PUBLIC  FATID,STARTSECTOR,SWITCHLIST,FREESPACE,FATSPACE
        PUBLIC  INIT,DISKFORMAT,BADSECTOR,DONE,WRTFAT,HARDFLAG
        EXTRN   SWITCHMAP:WORD,DRIVE:BYTE

SW_ONE  EQU     00001000B       ; /1
SW_8    EQU     00010000B       ; /8 (and /B)
GET_DPB EQU     32H

; ---------------------------------------------------------------- INIT

INIT:
        ; which address-field buffer: the one not across a 64K boundary
        MOV     AX,DS
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,OFFSET AF1
        ADD     AX,36
        JNC     IN_AF
        MOV     [AFBUF],OFFSET AF2
IN_AF:  INT     11H                     ; diskette drives
        MOV     CL,6
        MOV     BX,AX
        SHR     BX,CL
        AND     BL,3
        INC     BL
        TEST    AL,1
        JNZ     IN_FL
        MOV     BL,1
IN_FL:  MOV     [NUMFLOP],BL
        MOV     AL,[DRIVE]
        CMP     AL,2
        JB      IN_FLOP
        JMP     IN_HARD
IN_FLOP:
        ; a diskette drive: A: and B: are the same drive if there is one
        MOV     [PHYS],AL
        CMP     BL,1
        JNZ     IN_FL2
        MOV     [PHYS],0
IN_FL2: MOV     [HARDFLAG],0
        ; the format, by the switches
        MOV     BX,0                    ; index: 0 = 360K
        TEST    [SWITCHMAP],SW_8
        JZ      IN_9
        ADD     BX,2                    ; 8 sectors
IN_9:   TEST    [SWITCHMAP],SW_ONE
        JZ      IN_2
        ADD     BX,4                    ; one side
IN_2:   MOV     [FMT],BX
        MOV     AL,[FMTID+BX]
        MOV     [FATID],AL
        MOV     AL,[FMTSPT+BX]
        MOV     [SPT],AL
        MOV     AL,[FMTHDS+BX]
        MOV     [HDS],AL
        MOV     AX,[FMTDATA+BX]
        MOV     [STARTSECTOR],AX
        ; the boot sector's BPB
        MOV     SI,[FMTBPB+BX]
        MOV     DI,OFFSET BOOT+11
        MOV     CX,19
        REP     MOVSB
        CLC
        RET

IN_HARD:
        ; a fixed disk: its DPB tells the layout RETBIO.COM gave the partition
        MOV     [HARDFLAG],1
        MOV     DL,[DRIVE]
        INC     DL
        PUSH    DS
        MOV     AH,GET_DPB
        INT     21H
        CMP     AL,-1
        JNZ     IN_HOK
        JMP     IN_BAD
IN_HOK:
        MOV     AL,[BX+4]               ; sectors per cluster - 1
        INC     AL
        MOV     AH,[BX+8]               ; FATs
        MOV     CL,[BX+0FH]             ; sectors in a FAT
        MOV     DX,[BX+9]               ; root directory entries
        MOV     SI,[BX+0BH]             ; first data sector
        MOV     DI,[BX+0DH]             ; clusters + 1
        POP     DS
        MOV     [STARTSECTOR],SI
        MOV     BYTE PTR [BOOT+13],AL   ; the boot sector's BPB
        MOV     BYTE PTR [BOOT+16],AH
        MOV     BYTE PTR [BOOT+22],CL
        MOV     BYTE PTR [BOOT+23],0
        MOV     WORD PTR [BOOT+17],DX
        MOV     BYTE PTR [FATSZ],CL
        MOV     [FATID],0F8H
        MOV     BYTE PTR [BOOT+21],0F8H
        ; the geometry and where the partition starts, from the disk
        MOV     DL,[DRIVE]
        SUB     DL,2
        OR      DL,80H
        MOV     [PHYS],DL
        MOV     AH,8
        INT     13H
        JC      IN_BAD1
        MOV     AL,DH
        INC     AL
        MOV     [HDS],AL
        AND     CL,3FH
        MOV     [SPT],CL
        MOV     BYTE PTR [BOOT+24],CL
        MOV     BYTE PTR [BOOT+26],AL
        XOR     AX,AX
        XOR     DX,DX
        MOV     BX,OFFSET SECBUF
        MOV     CX,1
        MOV     BP,2
        CALL    DISKIO                  ; the master boot record
        JC      IN_BAD1
        MOV     SI,OFFSET SECBUF+1BEH
        MOV     CX,4
IN_PT:  CMP     BYTE PTR [SI+4],1
        JZ      IN_PTOK
        ADD     SI,16
        LOOP    IN_PT
        JMP     SHORT IN_BAD1
IN_PTOK:
        MOV     AX,[SI+12]              ; its length: the volume's sectors
        MOV     WORD PTR [BOOT+19],AX
        MOV     [TOTAL],AX
        MOV     AX,[SI+8]
        MOV     [HIDLO],AX
        MOV     WORD PTR [BOOT+28],AX
        MOV     AX,[SI+10]
        MOV     [HIDHI],AX
        CLC
        RET
IN_BAD: POP     DS
IN_BAD1:
        STC
        RET

; ---------------------------------------------------------------- DISKFORMAT

; A diskette: format and verify each track, noting the bad ones. A fixed
; disk is not formatted (its maker's low-level format stands); its sectors
; are checked by BADSECTOR.
DISKFORMAT:
        MOV     DX,OFFSET MSG_FMTING    ; as PC DOS 2's FORMAT says, then
        MOV     AH,9                    ; "Format complete" after the FATs
        INT     21H
        MOV     [SAIDDONE],0
        MOV     [NEXTSEC],0
        MOV     [NBAD],0
        CMP     [HARDFLAG],0
        JZ      DF_FLOP
        CLC
        RET
DF_FLOP:
        ; the diskette parameter table: this format's sectors per track
        PUSH    DS
        XOR     AX,AX
        MOV     DS,AX
        LDS     SI,DS:[1EH*4]
        MOV     AL,CS:[SPT]
        MOV     [SI+4],AL               ; last sector on a track
        POP     DS
        XOR     AH,AH                   ; reset
        MOV     DL,[PHYS]
        INT     13H
        MOV     [CYL],0
DF_CYL: MOV     [HEAD],0
DF_HEAD:
        CALL    FMTTRACK
        JNC     DF_NEXT
        ; a bad track: note it, unless it holds the boot sector, FATs or
        ; directory, which FORMAT will be told about by BADSECTOR
        CALL    NOTEBAD
DF_NEXT:
        INC     [HEAD]
        MOV     AL,[HEAD]
        CMP     AL,[HDS]
        JB      DF_HEAD
        INC     [CYL]
        CMP     [CYL],40
        JB      DF_CYL
        ; the boot sector
        CALL    WRTBOOT
        PUSH    AX
        PUSHF
        CALL    RESTDPT
        POPF
        POP     AX
        RET

; Format and verify the track CYL, HEAD. CF set if it is bad.
FMTTRACK:
        ; the address fields: C, H, R, N for each sector
        MOV     DI,[AFBUF]
        MOV     CL,1
FT_AF:  MOV     AL,[CYL]
        STOSB
        MOV     AL,[HEAD]
        STOSB
        MOV     AL,CL
        STOSB
        MOV     AL,2                    ; 512 bytes
        STOSB
        INC     CL
        CMP     CL,[SPT]
        JBE     FT_AF
        MOV     [TRIES],3
FT_TRY: MOV     AH,5
        MOV     AL,[SPT]
        MOV     CH,[CYL]
        MOV     CL,1
        MOV     DH,[HEAD]
        MOV     DL,[PHYS]
        MOV     BX,[AFBUF]
        INT     13H
        JC      FT_ERR
        MOV     AH,4                    ; verify the whole track
        MOV     AL,[SPT]
        MOV     CH,[CYL]
        MOV     CL,1
        MOV     DH,[HEAD]
        MOV     DL,[PHYS]
        MOV     BX,OFFSET SECBUF
        INT     13H
        JNC     FT_OK
FT_ERR: CMP     AH,3                    ; write-protected: give up at once
        JZ      FT_WP
        CMP     AH,80H                  ; no response: not ready
        JZ      FT_NR
        XOR     AH,AH
        MOV     DL,[PHYS]
        INT     13H
        DEC     [TRIES]
        JNZ     FT_TRY
        STC
        RET
FT_OK:  CLC
        RET
FT_WP:  MOV     DX,OFFSET MSG_WP
        JMP     SHORT FT_FATAL
FT_NR:  MOV     DX,OFFSET MSG_NR
FT_FATAL:
        POP     AX                      ; out of FMTTRACK and DISKFORMAT:
        CALL    RESTDPT                 ; FORMAT says "Format failure"
        MOV     AH,9
        INT     21H
        STC
        RET

; The bad track CYL, HEAD: its first sector and count, for BADSECTOR.
NOTEBAD:
        MOV     AL,[CYL]
        MUL     [HDS]
        ADD     AL,[HEAD]
        ADC     AH,0
        MUL     [SPT]                   ; first sector of the track
        MOV     BX,[NBAD]
        CMP     BX,BADMAX
        JAE     NB_RET
        SHL     BX,1
        MOV     [BADLIST+BX],AX
        INC     [NBAD]
NB_RET: RET

RESTDPT:
        PUSH    DS
        XOR     AX,AX
        MOV     DS,AX
        LDS     SI,DS:[1EH*4]
        MOV     BYTE PTR [SI+4],9
        POP     DS
        RET

; ---------------------------------------------------------------- BADSECTOR

; A diskette: report the bad tracks DISKFORMAT noted, a track at a time.
; A fixed disk: read every sector of the partition, a track at a time (a
; verify, which moves no data), and report each bad one.
BADSECTOR:
        CMP     [HARDFLAG],0
        JNZ     BS_HARD
        MOV     BX,[NEXTBAD]
        CMP     BX,[NBAD]
        JAE     BS_DONE
        INC     [NEXTBAD]
        SHL     BX,1
        MOV     BX,[BADLIST+BX]
        MOV     AL,[SPT]
        CBW
        CLC
        RET
BS_DONE:
        MOV     [NEXTBAD],0
        XOR     AX,AX
        CLC
        RET

BS_HARD:
        MOV     AX,[NEXTSEC]
        CMP     AX,[TOTAL]
        JAE     BS_HDONE
        ; to the end of this track
        XOR     DX,DX
        ADD     AX,[HIDLO]
        ADC     DX,[HIDHI]
        PUSH    AX
        PUSH    DX
        MOV     BL,[SPT]
        XOR     BH,BH
        DIV     BX                      ; (fits: cylinders * heads < 64K)
        MOV     CX,BX
        SUB     CX,DX                   ; sectors left in the track
        MOV     AX,[TOTAL]
        SUB     AX,[NEXTSEC]
        CMP     CX,AX
        JBE     BS_H1
        MOV     CX,AX
BS_H1:  POP     DX
        POP     AX
        MOV     BP,4                    ; verify
        PUSH    CX
        MOV     BX,OFFSET SECBUF
        CALL    DISKIO
        POP     CX
        JC      BS_HBAD
        ADD     [NEXTSEC],CX
        JMP     BS_HARD
BS_HBAD:
        ; the track has a bad sector: try them one at a time
        MOV     AX,[NEXTSEC]
        MOV     [BADFIRST],AX
BS_H2:  MOV     AX,[NEXTSEC]
        XOR     DX,DX
        ADD     AX,[HIDLO]
        ADC     DX,[HIDHI]
        PUSH    CX
        MOV     CX,1
        MOV     BX,OFFSET SECBUF
        CALL    DISKIO
        POP     CX
        INC     [NEXTSEC]
        JC      BS_H3
        LOOP    BS_H2
        JMP     BS_HARD                 ; (it read the second time)
BS_H3:  MOV     BX,[NEXTSEC]
        DEC     BX
        MOV     AX,1
        CLC
        RET
BS_HDONE:
        XOR     AX,AX
        CLC
        RET

; ---------------------------------------------------------------- WRTFAT

; Write both FATs from FATSPACE, and the boot sector, straight to the disk:
; until the FAT ID byte is on it, the DOS cannot know what the disk is.
WRTFAT:
        CALL    WRTBOOT
        JC      WF_RET
        MOV     AL,BYTE PTR [BOOT+16]   ; FATs
        MOV     [CURCNT],AL
        MOV     AX,1                    ; the first FAT follows the boot sector
        MOV     [COUNT],AX
WF_LP:  MOV     AX,[COUNT]
        XOR     DX,DX
        ADD     AX,[HIDLO]
        ADC     DX,[HIDHI]
        MOV     CL,BYTE PTR [BOOT+22]   ; sectors in a FAT
        XOR     CH,CH
        MOV     BX,[FATSPACE]
        MOV     BP,3
        CALL    DISKIO
        JC      WF_RET
        MOV     AL,BYTE PTR [BOOT+22]
        XOR     AH,AH
        ADD     [COUNT],AX
        DEC     [CURCNT]
        JNZ     WF_LP
        CMP     [SAIDDONE],0            ; the first time for this disk
        JNZ     WF_OK
        MOV     [SAIDDONE],1
        MOV     DX,OFFSET MSG_FMTDONE
        MOV     AH,9
        INT     21H
WF_OK:  CLC
WF_RET: RET

WRTBOOT:
        MOV     AX,[HIDLO]
        MOV     DX,[HIDHI]
        MOV     CX,1
        MOV     BX,OFFSET BOOT
        MOV     BP,3
        JMP     DISKIO

; ---------------------------------------------------------------- DONE

DONE:
        CLC
        RET

; ---------------------------------------------------------------- DISKIO

; DISKIO: INT 13h function BP (2 read, 3 write, 4 verify) on CX sectors
; from absolute sector DX:AX of drive PHYS, geometry SPT and HDS, at DS:BX,
; one sector at a time. CF set if any fails after three tries.
DISKIO:
        PUSH    SI
DIO_LP: JCXZ    DIO_OK
        PUSH    AX
        PUSH    DX
        PUSH    CX
        PUSH    BX
        MOV     SI,AX                   ; the sector: to cylinder, head, sector
        MOV     AX,DX
        MOV     CL,[SPT]
        XOR     CH,CH
        XOR     DX,DX
        DIV     CX
        MOV     DI,AX
        MOV     AX,SI
        DIV     CX                      ; DI:AX = track, DX = sector - 1
        INC     DL
        MOV     [D_SEC],DL
        MOV     DX,DI
        MOV     CL,[HDS]
        XOR     CH,CH
        DIV     CX                      ; AX = cylinder, DL = head
        MOV     DH,DL
        MOV     CH,AL
        MOV     CL,AH
        ROR     CL,1
        ROR     CL,1
        AND     CL,0C0H
        OR      CL,[D_SEC]
        MOV     DL,[PHYS]
        POP     BX
        PUSH    BX
        CALL    BOUNCE                  ; BX: a buffer the DMA can use
        MOV     SI,3
DIO_TRY:
        PUSH    DS
        POP     ES
        MOV     AX,BP
        MOV     AH,AL
        MOV     AL,1
        PUSH    CX
        PUSH    DX
        INT     13H
        POP     DX
        POP     CX
        JNC     DIO_DONE
        XOR     AH,AH
        INT     13H
        DEC     SI
        JNZ     DIO_TRY
        POP     BX
        POP     CX
        POP     DX
        POP     AX
        POP     SI
        STC
        RET
DIO_DONE:
        CALL    UNBOUNCE                ; a read: to where it was asked for
        POP     BX
        POP     CX
        POP     DX
        POP     AX
        CMP     BP,4
        JZ      DIO_SAME                ; a verify: the buffer does not move
        ADD     BX,512
DIO_SAME:
        ADD     AX,1
        ADC     DX,0
        DEC     CX
        JMP     DIO_LP
DIO_OK: POP     SI
        CLC
        RET

; The DMA controller cannot cross a 64K boundary of memory, and the ROM
; refuses a transfer that would. BOUNCE: if the sector at DS:BX would cross
; one, BX is changed to whichever of BNC1 and BNC2 does not (only one can),
; after copying the sector there for a write. UNBOUNCE copies it back after
; a read. ORIGBX holds the caller's buffer, or 0.
BOUNCE: MOV     [ORIGBX],0
        PUSH    AX
        PUSH    CX
        MOV     AX,DS
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,BX
        ADD     AX,511
        POP     CX
        JNC     BN_RET                  ; it does not cross
        MOV     [ORIGBX],BX
        PUSH    SI
        PUSH    DI
        PUSH    CX
        MOV     AX,DS
        MOV     CL,4
        SHL     AX,CL
        ADD     AX,OFFSET BNC1
        ADD     AX,511
        MOV     DI,OFFSET BNC1
        JNC     BN_1
        MOV     DI,OFFSET BNC2
BN_1:   MOV     [BNCBUF],DI
        CMP     BP,3
        JNZ     BN_2
        MOV     SI,BX                   ; a write: the data in first
        PUSH    DS
        POP     ES
        MOV     CX,256
        REP     MOVSW
BN_2:   MOV     BX,[BNCBUF]
        POP     CX
        POP     DI
        POP     SI
BN_RET: POP     AX
        RET
UNBOUNCE:
        CMP     [ORIGBX],0
        JZ      UB_RET
        CMP     BP,2
        JNZ     UB_RET
        PUSH    SI
        PUSH    DI
        PUSH    CX
        PUSH    DS
        POP     ES
        MOV     SI,[BNCBUF]
        MOV     DI,[ORIGBX]
        MOV     CX,256
        REP     MOVSW
        POP     CX
        POP     DI
        POP     SI
UB_RET: RET
ORIGBX  DW      0
BNCBUF  DW      0

; ---------------------------------------------------------------- data

;                       360K  320K  180K  160K
FMTID   DB      0FDH,0, 0FFH,0, 0FCH,0, 0FEH,0
FMTSPT  DB      9,0,    8,0,    9,0,    8,0
FMTHDS  DB      2,0,    2,0,    1,0,    1,0
FMTDATA DW      12,     10,     9,      7       ; first data sector
FMTBPB  DW      BPB360, BPB320, BPB180, BPB160
; BPB, sectors a track, heads, hidden sectors: 19 bytes from offset 11
BPB360  DW      512
        DB      2
        DW      1
        DB      2
        DW      112,720
        DB      0FDH
        DW      2,9,2,0
BPB320  DW      512
        DB      2
        DW      1
        DB      2
        DW      112,640
        DB      0FFH
        DW      1,8,2,0
BPB180  DW      512
        DB      1
        DW      1
        DB      2
        DW      64,360
        DB      0FCH
        DW      2,9,1,0
BPB160  DW      512
        DB      1
        DW      1
        DB      2
        DW      64,320
        DB      0FEH
        DW      1,8,1,0

FMT     DW      0
NUMFLOP DB      1
PHYS    DB      0
SPT     DB      9
HDS     DB      2
CYL     DB      0
HEAD    DB      0
TRIES   DB      0
D_SEC   DB      0
HIDLO   DW      0               ; where a fixed disk's partition starts
HIDHI   DW      0
TOTAL   DW      0               ; sectors in the partition
FATSZ   DB      0
NEXTSEC DW      0               ; the next fixed disk sector to check
BADFIRST DW     0
COUNT   DW      0
CURCNT  DB      0
BADMAX  EQU     80
NBAD    DW      0
NEXTBAD DW      0
BADLIST DW      BADMAX DUP (0)

MSG_FMTING DB   "Formatting...$"
MSG_FMTDONE DB  "Format complete",13,10,"$"
SAIDDONE DB     0
MSG_WP  DB      13,10,"Write protect error",13,10,"$"
MSG_NR  DB      13,10,"Drive not ready",13,10,"$"

HARDFLAG DB     0
FATID   DB      0FDH
STARTSECTOR DW  12
SWITCHLIST DB   6,"B81OVS"      ; "OVS" must be last

; The address fields of a track, for INT 13h function 5, in whichever of two
; places does not cross a 64K boundary of memory (the DMA controller cannot).
AFBUF   DW      AF1
AF1     DB      36 DUP (0)
AF2     DB      36 DUP (0)

        INCLUDE BOOTSECT.INC    ; BOOT: the RetrOS/LT boot sector, 512 bytes

SECBUF  DB      512 DUP (0)
BNC1    DB      512 DUP (0)         ; for BOUNCE
BNC2    DB      512 DUP (0)
FATSPACE DW     FATBUF
FREESPACE DW    ENDFOR
FATBUF  DB      6*1024 DUP (0)
ENDFOR  LABEL   BYTE

CODE    ENDS
        END
