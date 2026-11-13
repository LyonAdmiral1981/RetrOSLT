;
; IO.ASM -- Standard device IO for MSDOS (first 12 function calls)
;
; RetrOS/LT: Microsoft's MS-DOS 2.x source names this file (STDIO.ASM
; includes it) but it is not among the published files. This is a
; reconstruction. Its structure and names follow CPMIO.ASM and CPMIO2.ASM of
; the MS-DOS 4.0 source, which grew from it, with the 4.0 additions (DBCS,
; networks, the system file table) taken out; its code follows the console
; functions of the MS-DOS 2.00 MSDOS.SYS published with the 2.x source,
; instruction for instruction. Both are Copyright Microsoft Corporation and
; released under the MIT License.
;
; The buffered input editor, function 10, is STRIN.ASM, included at the end.
;

CODE    SEGMENT BYTE PUBLIC  'CODE'
ASSUME  SS:DOSGROUP,CS:DOSGROUP

.xlist
.xcref
INCLUDE DOSSYM.ASM
INCLUDE DEVSYM.ASM
.cref
.list

; The following routines form the console I/O group (funcs 1,2,6,7,8,9,10,11).
; They assume ES and DS NOTHING, while not strictly correct, this forces data
; references to be SS or CS relative which is desired.

        i_need  CARPOS,BYTE
        i_need  STARTPOS,BYTE
        i_need  INBUF,128
        i_need  INSMODE,BYTE
        i_need  CHARCO,BYTE
        i_need  PFLAG,BYTE
        EXTRN   ESCCHAR:BYTE

SUBTTL $STD_CON_INPUT -- System call 1
PAGE
        procedure   $STD_CON_INPUT,NEAR   ;System call 1
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       None
; Function:
;       Input character from console, echo
; Returns:
;       AL = character

        invoke  $STD_CON_INPUT_NO_ECHO
        PUSH    AX
        invoke  OUT
        POP     AX
        return
$STD_CON_INPUT  ENDP

SUBTTL $STD_CON_OUTPUT -- System call 2
PAGE
        procedure   $STD_CON_OUTPUT,NEAR   ;System call 2
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       DL = character
; Function:
;       Output character to console
; Returns:
;       None

        MOV     AL,DL

        entry   OUT
        CMP     AL,20H
        JB      CTRLOUT
        CMP     AL,c_DEL
        JZ      OUTCH
        INC     BYTE PTR [CARPOS]
OUTCH:
        PUSH    DS
        PUSH    SI
        INC     BYTE PTR [CHARCO]               ;invoke  statchk...
        AND     BYTE PTR [CHARCO],00000011B     ; every fourth char
        JNZ     OUTSKIP
        PUSH    AX
        invoke  STATCHK
        POP     AX
OUTSKIP:
        invoke  RAWOUT                          ;output the character
        POP     SI
        POP     DS
        TEST    BYTE PTR [PFLAG],-1
        retz
        PUSH    BX
        PUSH    DS
        PUSH    SI
        MOV     BX,1
        invoke  GET_IO_FCB
        JC      TRIPOPJ
        TEST    [SI.fcb_DEVID],080H             ; output to file?
        JZ      TRIPOPJ                         ; if so, no echo
        MOV     BX,4
        JMP     SHORT LISSTRT2

TRIPOPJ:
        JMP     SHORT TRIPOP

CTRLOUT:
        CMP     AL,c_CR
        JZ      ZERPOS
        CMP     AL,c_BS
        JZ      BACKPOS
        CMP     AL,c_HT
        JNZ     OUTCH
        MOV     AL,[CARPOS]
        OR      AL,0F8H
        NEG     AL

        entry   TAB
        PUSH    CX
        MOV     CL,AL
        MOV     CH,0
        JCXZ    POPTAB
TABLP:
        MOV     AL," "
        invoke  OUT
        LOOP    TABLP
POPTAB:
        POP     CX
        return

ZERPOS:
        MOV     BYTE PTR [CARPOS],0
        JMP     OUTCH
OUTJ:   JMP     OUT

BACKPOS:
        DEC     BYTE PTR [CARPOS]
        JMP     OUTCH

        entry   BUFOUT
        CMP     AL," "
        JAE     OUTJ            ;Normal char
        CMP     AL,9
        JZ      OUTJ            ;OUT knows how to expand tabs
        PUSH    AX
        MOV     AL,"^"
        invoke  OUT             ;Print '^' before control chars
        POP     AX
        OR      AL,40H          ;Turn it into Upper case mate
        invoke  OUT
        return
$STD_CON_OUTPUT ENDP

SUBTTL $STD_AUX_INPUT -- System call 3
PAGE
        procedure   $STD_AUX_INPUT,NEAR   ;System call 3
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       None
; Function:
;       Returns character from aux input
; Returns:
;       Character in AL

        invoke  STATCHK
        MOV     BX,3
        invoke  GET_IO_FCB
        retc
        JMP     SHORT TAISTRT
AUXILP:
        invoke  SPOOLINT
TAISTRT:
        MOV     AH,1
        invoke  IOFUNC
        JZ      AUXILP
        XOR     AH,AH
        invoke  IOFUNC
        return
$STD_AUX_INPUT  ENDP

SUBTTL $STD_AUX_OUTPUT -- System call 4
PAGE
        procedure   $STD_AUX_OUTPUT,NEAR   ;System call 4
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       Character in DL
; Function:
;       Output character to aux output
; Returns:
;       Nothing

        PUSH    BX
        MOV     BX,3
        JMP     SHORT SENDOUT
$STD_AUX_OUTPUT ENDP

SUBTTL $STD_PRINTER_OUTPUT -- System call 5
PAGE
        procedure   $STD_PRINTER_OUTPUT,NEAR   ;System call 5
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       DL = Character
; Function:
;       Output the character to the list device
; Returns:
;       None

        PUSH    BX
        MOV     BX,4
SENDOUT:
        MOV     AL,DL
        PUSH    AX
        invoke  STATCHK
        POP     AX
        PUSH    DS
        PUSH    SI
LISSTRT2:
        invoke  RAWOUT2
TRIPOP:
        POP     SI
        POP     DS
        POP     BX
        return
$STD_PRINTER_OUTPUT     ENDP

SUBTTL $STD_CON_INPUT_NO_ECHO -- System call 8
PAGE
        procedure   $STD_CON_INPUT_NO_ECHO,NEAR   ;System call 8
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       None
; Function:
;       Input character from console, no echo
; Returns:
;       AL = character

        PUSH    DS
        PUSH    SI
INTEST:
        invoke  STATCHK
        JZ      INTEST
        XOR     AH,AH
        invoke  IOFUNC
        POP     SI
        POP     DS
        return
$STD_CON_INPUT_NO_ECHO  ENDP

SUBTTL $STD_CON_STRING_OUTPUT -- System call 9
PAGE
        procedure   $STD_CON_STRING_OUTPUT,NEAR   ;System call 9
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       DS:DX Point to output string '$' terminated
; Function:
;       Print the string on the console device
; Returns:
;       None

        MOV     SI,DX
STRING_OUT1:
        LODSB
        CMP     AL,"$"
        retz
        invoke  OUT
        JMP     SHORT STRING_OUT1
$STD_CON_STRING_OUTPUT  ENDP

SUBTTL $STD_CON_STRING_INPUT -- System call 10
PAGE
        INCLUDE STRIN.ASM

SUBTTL $STD_CON_INPUT_STATUS -- System call 11
PAGE
        procedure   $STD_CON_INPUT_STATUS,NEAR   ;System call 11
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       None
; Function:
;       Check console input status
; Returns:
;       AL = -1 character available, = 0 no character

        invoke  STATCHK
        MOV     AL,0                    ; no xor!!
        retz
        OR      AL,-1
        return
$STD_CON_INPUT_STATUS   ENDP

SUBTTL $STD_CON_INPUT_FLUSH -- System call 12
PAGE
        procedure   $STD_CON_INPUT_FLUSH,NEAR   ;System call 12
ASSUME  DS:NOTHING,ES:NOTHING

; Inputs:
;       AL = DOS function to be called after flush (1,6,7,8,10)
; Function:
;       Flush console input buffer and perform call in AL
; Returns:
;       Whatever call in AL returns or AL=0 if AL was not 1,6,7,8 or 10

        PUSH    AX
        PUSH    DX
        XOR     BX,BX
        invoke  GET_IO_FCB
        JC      BADJFNCON
        MOV     AH,4
        invoke  IOFUNC

BADJFNCON:
        POP     DX
        POP     AX
        MOV     AH,AL
        CMP     AL,1
        JZ      REDISPJ
        CMP     AL,6
        JZ      REDISPJ
        CMP     AL,7
        JZ      REDISPJ
        CMP     AL,8
        JZ      REDISPJ
        CMP     AL,10
        JZ      REDISPJ
        MOV     AL,0
        return

REDISPJ:
        CLI
        transfer    REDISP
$STD_CON_INPUT_FLUSH    ENDP

do_ext

CODE    ENDS
        END
