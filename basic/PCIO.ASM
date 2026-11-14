	TITLE	PCIO - GW-BASIC's machine-dependent layer for the IBM PC
	SUBTTL	Definitions
;
; RetrOS: the routines Microsoft's GW-BASIC calls but its published source
; does not contain, written for the IBM Personal Computer, XT and
; compatibles: the screen through interrupt 10h, the keyboard through
; interrupt 16h, the printer through interrupt 17h, the serial ports and
; the speaker through their own chips, and the graphics of the Color/Graphics
; Adapter in video memory.  The interface each routine follows is the one
; its callers in Microsoft's modules expect; the comments at those calls
; are the specification.
;
; Copyright (c) 2026 Republic Lyon Mountain Corporation.  MIT License.
;
	.RADIX	10

CSEG	SEGMENT PUBLIC 'CODESG'
CSEG	ENDS
DSEG	SEGMENT PUBLIC 'DATASG'
DSEG	ENDS

	ASSUME	CS:CSEG,DS:DSEG

;Microsoft's variables
DSEG	SEGMENT PUBLIC 'DATASG'
	EXTRN	CSRX:BYTE,CSRY:BYTE,LINLEN:BYTE,CRTWID:BYTE,LINCNT:BYTE
	EXTRN	KEYSW:BYTE,MSDCCF:BYTE,ATRBYT:BYTE
DSEG	ENDS

;Microsoft's routines
CSEG	SEGMENT PUBLIC 'CODESG'
	EXTRN	SCNSWI:NEAR,SCNCLR:NEAR,ALPTAB:NEAR,ALPTAX:NEAR
	EXTRN	DERDNA:NEAR
CSEG	ENDS

;The routines this module provides
	PUBLIC	GWINI,GWTERM,SEGINI,SETCBF,GETHED,PEKFLT,POKFLT
	PUBLIC	SCROUT,SCRINP,SCROLL,CLRSCN,CLREOL,CSRATR,CSRDSP,SCRSTT
	PUBLIC	SCRATR,SWIDTH,SETCLR,GETFBC,SETFBC,FKYFMT,FKYADV,LCPY
	PUBLIC	EDTMAP,PRTMAP
	PUBLIC	KEYINP,INFMAP,INKMAP,MAPSUP,POLLEV
	PUBLIC	MAPXYC,SCALXY,FETCHC,STOREC,READC,SETATR,SETC,NSETCX
	PUBLIC	UPC,DOWNC,LEFTC,RIGHTC,TUPC,TDOWNC,PIXSIZ,GRPSIZ,GTASPC
	PUBLIC	PNTINI,SCANL,SCANR,PGINIT,NREAD,NWRITE
	PUBLIC	DONOTE,RDPEN,RDSTIK,RDTRIG
	PUBLIC	INICOM,RECCOM,SNDCOM,STACOM,TRMCOM,SNDLPT

;Values
	BIOSDS	EQU	40H		;The BIOS data segment
	CGASEG	EQU	0B800H		;Color/Graphics Adapter memory
	MDASEG	EQU	0B000H		;Monochrome Display Adapter memory
	ODDBNK	EQU	2000H		;Odd scan lines, CGA graphics
	TIMFRQ	EQU	2983		;8253 count for 400 interrupts a second
	NOTEQ	EQU	32		;Notes the music queue holds

	INCLUDE	PCIOID.INC		;BASNAM: the edition's name

	SUBTTL	Data
DSEG	SEGMENT PUBLIC 'DATASG'
;The screen
VMODE	DB	3			;BIOS video mode
VCOLS	DB	80			;Columns
ISMONO	DB	0			;Nonzero on a monochrome adapter
APAGE	DB	0			;Page written to
VPAGE	DB	0			;Page shown
TXTFG	DB	7			;Text foreground, 0-31
TXTBG	DB	0			;Text background, 0-7
TXTATR	DB	07H			;The attribute byte they make
BORDER	DB	0			;Border color
GBACK	DB	0			;Graphics background (COLOR in SCREEN 1)
GPAL	DB	1			;Graphics palette
;The cursor
UCVIS	DB	0			;LOCATE's cursor: nonzero if visible
UCTOP	DB	6			;LOCATE's start and stop lines
UCBOT	DB	7
GCURAT	DW	0			;Graphics cursor drawn here (0 = none)
GCURLN	DB	0			;and this many lines of it
;The function key line: characters a key, keys shown, first key shown
FKFMT	DB	6,10,1
KEYFIR	EQU	BYTE PTR FKFMT+2
;Graphics
CLOC	DW	0			;The current point: its address
CMASK	DB	0			; and its mask
BPP	DB	0			;Bits a pixel, 0 in text modes
PXMAX	DW	639			;Largest X
ATRPAT	DB	0FFH			;Current attribute, as a byte of pixels
BRDPAT	DB	0			;PAINT's border, as a byte of pixels
PGOP	DB	0			;PUT's action
PGBITS	DW	0			;GET and PUT: bits in a line
PGPTR	DW	0			;GET and PUT: where the array is
PGLAST	DB	0			;GET and PUT: mask of the last byte
;Pen and sticks
PENON	DB	0			;PEN ON
PENDWN	DB	0			;Pen was down at the last poll
PENVAL	DW	9 DUP(0)		;PEN(1..9) values, see RDPEN
STKVAL	DW	4 DUP(0)		;STICK(0..3)
TRGLAT	DB	0			;Triggers pressed since last read
POLCNT	DB	0
;The byte before BASIC's program text (LSTVAR, TXTTAB) must stay 0:
;it is the end of the line before the first.
	DB	0
DSEG	ENDS

;Data the interrupt routines use is in the code segment, where they can
;reach it without knowing BASIC's data segment.
CSEG	SEGMENT PUBLIC 'CODESG'
BASDS	DW	0			;BASIC's data segment
OLD1B	DD	0			;Vectors replaced
OLD08	DD	0
;The music queue: frequency, duration pairs
SNDQ	DW	NOTEQ*2 DUP(0)
SNDHD	DW	0			;Next to play
SNDTL	DW	0			;Next free
SNDCNT	DW	0			;Notes queued
SNDREM	DW	0			;Time left of the note playing
SNDFST	DB	0			;Nonzero: the timer runs fast
SNDACC	DW	0			;Fraction of a BIOS tick, fast timer
;The serial ports, one block each
	CPORT	EQU	0		;I/O base, 0 if not open
	CBSEG	EQU	2		;Receive buffer: segment
	CBSIZ	EQU	4		; size
	CBHD	EQU	6		; next to read
	CBTL	EQU	8		; next free
	CBCNT	EQU	10		; bytes held
	COVF	EQU	12		;Overflow (1) or parity (2) seen
	CIRQ	EQU	13		;Interrupt number
	CCTS	EQU	14		;CTS timeout, ticks
	CDSR	EQU	16		;DSR timeout, ticks
	COLDV	EQU	18		;Vector replaced
	CBLEN	EQU	22
COMBLK	DB	2*CBLEN DUP(0)
COMBUF	DW	0			;SETCBF: segment
COMBSZ	DW	0			;SETCBF: bytes
CSEG	ENDS

CSEG	SEGMENT PUBLIC 'CODESG'
	SUBTTL	Starting and ending

;GWINI - called once during initialization, before the heading.
GWINI:	CALL	ROMCHK			;BASIC /ROM: never comes back
	PUSH	AX
	PUSH	BX
	PUSH	DX
	PUSH	ES
	MOV	CS:BASDS,DS
;Ctrl-Break: BASIC's flag, set at once
	MOV	AX,351BH
	INT	21H
	MOV	WORD PTR CS:OLD1B,BX
	MOV	WORD PTR CS:OLD1B+2,ES
	MOV	AX,251BH
	PUSH	DS
	PUSH	CS
	POP	DS
	MOV	DX,OFFSET BRKISR
	INT	21H
;The timer, for music
	MOV	AX,3508H
	INT	21H
	MOV	WORD PTR CS:OLD08,BX
	MOV	WORD PTR CS:OLD08+2,ES
	MOV	AX,2508H
	MOV	DX,OFFSET TMRISR
	INT	21H
	POP	DS
;The screen: keep the text mode BASIC was started in
	MOV	AH,0FH
	INT	10H
	CMP	AL,7
	JE	GWIN2			;Monochrome
	CMP	AL,3
	JBE	GWIN2			;Color text
	MOV	AL,3			;Anything else: 80 columns, color
GWIN2:	CALL	SETMOD
	CALL	CLRSC1			;Clear it, home the cursor
	POP	ES
	POP	DX
	POP	BX
	POP	AX
	RET

;GWTERM - called by SYSTEM before BASIC returns to DOS.
GWTERM:	PUSH	AX
	PUSH	DX
	PUSH	DS
	MOV	AL,255
	CALL	DONOTE			;Silence, slow the timer again
	CLI
	LDS	DX,DWORD PTR CS:OLD08
	MOV	AX,2508H
	INT	21H
	LDS	DX,DWORD PTR CS:OLD1B
	MOV	AX,251BH
	INT	21H
	STI
	POP	DS
	CMP	BYTE PTR BPP,0
	JE	GWTRM2
	MOV	AX,3			;Leave graphics for 80 column text
	INT	10H
GWTRM2:	CMP	BYTE PTR VPAGE,0
	JE	GWTRM3
	MOV	AX,0500H		;Show page 0 again
	INT	10H
GWTRM3:	POP	DX
	POP	AX
	RET

;ROMCHK - BASIC /ROM: Cassette BASIC, from the ROM.  The command line is
; at CS:80h, where BIBOOT copied the program segment prefix.  The IBM PC,
; XT, AT and PS/2 have it at F600:0000, and interrupt 18h points there; a
; computer without it points interrupt 18h elsewhere.  Cassette BASIC
; takes the whole computer: there is no going back to DOS but restarting.
ROMCHK:	PUSH	AX
	PUSH	CX
	PUSH	SI
	MOV	SI,81H
	MOV	CL,BYTE PTR CS:[80H]
	XOR	CH,CH
ROMCK1:	JCXZ	ROMCKX
	DEC	CX
	MOV	AL,BYTE PTR CS:[SI]
	INC	SI
	CMP	AL,"/"
	JNE	ROMCK1
	CMP	CX,3
	JB	ROMCKX
	MOV	AX,WORD PTR CS:[SI]	;"RO"
	AND	AX,0DFDFH		;(upper case)
	CMP	AX,"O"*256+"R"
	JNE	ROMCK1
	MOV	AL,BYTE PTR CS:[SI+2]
	AND	AL,0DFH
	CMP	AL,"M"
	JNE	ROMCK1
	XOR	AX,AX			;/ROM: is there one?
	MOV	ES,AX
	CMP	WORD PTR ES:[18H*4],0
	JNE	NOROM
	CMP	WORD PTR ES:[18H*4+2],0F600H
	JNE	NOROM
	MOV	AX,0F600H
	MOV	ES,AX
	MOV	AL,BYTE PTR ES:[0]	;Empty sockets read FFh, and
	CMP	AL,0FFH
	JE	NOROM
	OR	AL,AL			; memory that is not ROM, often 0
	JZ	NOROM
	INT	18H			;Cassette BASIC
NOROM:	PUSH	CS
	POP	DS
	MOV	DX,OFFSET NOROMM
	MOV	AH,9
	INT	21H
	MOV	AX,4C01H
	INT	21H
ROMCKX:	POP	SI
	POP	CX
	POP	AX
	RET
NOROMM	DB	"No ROM BASIC in this computer",13,10,"$"

;SEGINI - called after BASIC moves its data segment.
SEGINI:	MOV	CS:BASDS,DS
	RET

;SETCBF - Where and how big the serial receive buffers are.
; Entry - CX = segment of the space, DX = /C: size, ZF set if no /C:
; Exit  - DX = bytes to keep, CF set if the size is not acceptable
SETCBF:	JNZ	SETCB1
	MOV	DX,512			;Default: 256 bytes for each port
SETCB1:	CMP	DX,32768
	CMC
	JB	SETCBX
	MOV	CS:COMBUF,CX
	MOV	CS:COMBSZ,DX
	CLC
SETCBX:	RET

;GETHED - BX = the first line of the heading, in the code segment.
; ZF set: print it only when no program is named on the command line.
GETHED:	MOV	BX,OFFSET HEDOEM
	CMP	AL,AL
	RET

HEDOEM	DB	BASNAM,0

;PEKFLT, POKFLT - no addresses are treated specially.  ZF clear: do it.
PEKFLT:
POKFLT:	OR	SP,SP
	RET

;Ctrl-Break, from the keyboard interrupt
BRKISR:	PUSH	DS
	MOV	DS,CS:BASDS
	MOV	BYTE PTR MSDCCF,0FFH
	POP	DS
	IRET

	SUBTTL	The screen

;SETMOD - set BIOS mode AL, and everything that follows from it.
SETMOD:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	MOV	BYTE PTR VMODE,AL
	MOV	AH,0
	PUSH	BP
	INT	10H
	POP	BP
	MOV	AL,BYTE PTR VMODE	;(AL is not kept)
	MOV	BYTE PTR APAGE,0
	MOV	BYTE PTR VPAGE,0
	MOV	WORD PTR GCURAT,0
	MOV	BYTE PTR TXTFG,7
	MOV	BYTE PTR TXTBG,0
	MOV	BYTE PTR BORDER,0
	MOV	BYTE PTR GBACK,0
	MOV	BYTE PTR GPAL,1
	CALL	MKATR
	MOV	BYTE PTR ISMONO,0
	MOV	BYTE PTR UCTOP,6
	MOV	BYTE PTR UCBOT,7
	MOV	BYTE PTR BPP,0
	MOV	CL,40
	MOV	BX,319
	CMP	AL,1
	JBE	SETMD2			;40 column text
	MOV	CL,80
	MOV	BX,639
	CMP	AL,3
	JBE	SETMD2			;80 column text
	CMP	AL,7
	JNE	SETMD1
	MOV	BYTE PTR ISMONO,1
	MOV	BYTE PTR UCTOP,11
	MOV	BYTE PTR UCBOT,12
	JMP	SHORT SETMD2
SETMD1:	MOV	BYTE PTR BPP,1		;Mode 6, 640 by 200
	CMP	AL,6
	JE	SETMD2
	MOV	BYTE PTR BPP,2		;Modes 4 and 5, 320 by 200
	MOV	CL,40
	MOV	BX,319
SETMD2:	MOV	PXMAX,BX
	MOV	BYTE PTR VCOLS,CL
	MOV	AL,CL
	MOV	CL,25
	CALL	SCNSWI			;Tell the screen editor
	MOV	AH,1			;No cursor until one is asked for
	MOV	CX,2000H
	INT	10H
	MOV	KEYFIR,1	;Keys shown from F1
	CALL	FKSET
	MOV	AL,1			;PSET's color: the last one there is
	CMP	BYTE PTR BPP,1
	JBE	SETMD3
	MOV	AL,3
SETMD3:	CALL	SETATR
	MOV	BYTE PTR ATRBYT,AL
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET


;FKSET - the function key line's format for the width
FKSET:	MOV	BYTE PTR FKFMT,6
	MOV	BYTE PTR FKFMT+1,10
	CMP	BYTE PTR VCOLS,40
	JNE	FKSETX
	MOV	BYTE PTR FKFMT+1,5	;40 columns: five keys at a time
FKSETX:	RET

;MKATR - the text attribute from TXTFG and TXTBG
MKATR:	PUSH	AX
	MOV	AL,BYTE PTR TXTBG
	AND	AL,7
	MOV	AH,BYTE PTR TXTFG
	TEST	AH,16
	JZ	MKATR1
	OR	AL,8			;Blinking
MKATR1:	SHL	AL,1
	SHL	AL,1
	SHL	AL,1
	SHL	AL,1
	AND	AH,15
	OR	AL,AH
	MOV	BYTE PTR TXTATR,AL
	POP	AX
	RET

;FILATR - BH = what a cleared cell gets
FILATR:	MOV	BH,BYTE PTR TXTATR
	AND	BH,7FH
	CMP	BYTE PTR BPP,0
	JE	FILAT1
	XOR	BH,BH			;Graphics: color 0
FILAT1:	RET

;SCROUT - write the character in AL at column DH, line DL.
; Exit  - CF clear (no escape sequences); all registers preserved
SCROUT:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	AX
	XCHG	DH,DL
	SUB	DX,0101H
	MOV	BH,BYTE PTR APAGE
	MOV	AH,2
	INT	10H
	POP	AX
	MOV	AH,9
	MOV	BL,BYTE PTR TXTATR
	CMP	BYTE PTR BPP,0
	JE	SCROU1
	MOV	BL,1			;Graphics: the brightest color
	CMP	BYTE PTR BPP,1
	JE	SCROU1
	MOV	BL,3
SCROU1:	MOV	CX,1
	INT	10H
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	CLC
	RET

;SCRINP - the character at column DH, line DL, into AX.
SCRINP:	PUSH	BX
	PUSH	DX
	XCHG	DH,DL
	SUB	DX,0101H
	MOV	BH,BYTE PTR APAGE
	MOV	AH,2
	INT	10H
	MOV	AH,8
	INT	10H
	XOR	AH,AH
	POP	DX
	POP	BX
	CLC
	RET

;SCRATR - the attribute at column AL, line BL, into BX.
SCRATR:	PUSH	AX
	PUSH	DX
	MOV	DH,BL
	MOV	DL,AL
	SUB	DX,0101H
	MOV	BH,BYTE PTR APAGE
	MOV	AH,2
	INT	10H
	MOV	AH,8
	INT	10H
	XOR	BX,BX
	CMP	BYTE PTR BPP,0
	JNE	SCRAT1			;Graphics modes have none
	MOV	BL,AH
SCRAT1:	POP	DX
	POP	AX
	RET

;SCROLL - move CL lines of CH columns from column AH, line AL to
; column BH, line BL (one line up or down).  All registers preserved.
SCROLL:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	MOV	DL,AH			;DL = first column, 0-relative
	DEC	DL
	MOV	DH,DL
	ADD	DH,CH
	DEC	DH			;DH = last column
	CMP	DH,BYTE PTR VCOLS
	JB	SCRL1
	MOV	DH,BYTE PTR VCOLS
	DEC	DH
SCRL1:	CMP	AL,BL
	JA	SCRLUP
	MOV	CH,AL			;Down: lines AL to BL+CL-1
	MOV	AH,BL
	ADD	AH,CL
	SUB	AH,2			;(0-relative)
	MOV	AL,7
	JMP	SHORT SCRL2
SCRLUP:	MOV	CH,BL			;Up: lines BL to AL+CL-1
	MOV	AH,AL
	ADD	AH,CL
	SUB	AH,2
	MOV	AL,6
SCRL2:	DEC	CH			;CH = top line, 0-relative
	MOV	CL,DL			;CL = first column
	MOV	DL,DH			;DL = last column
	MOV	DH,AH			;DH = bottom line
	MOV	AH,AL
	MOV	AL,1
	CALL	BOXOP
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET

;BOXOP - BIOS scroll AH (6 up, 7 down) by AL lines (0 = clear) of the
; window CH,CL to DH,DL, on the page written to.
BOXOP:	PUSH	BX
	CALL	FILATR
	PUSH	AX
	MOV	AL,BYTE PTR APAGE
	CMP	AL,BYTE PTR VPAGE
	POP	AX
	JNE	BOXOP2			;Not the page shown: do it ourselves
	PUSH	BP			;(some BIOSes lose BP)
	INT	10H
	POP	BP
	POP	BX
	RET
BOXOP2:	CALL	TXTBOX
	POP	BX
	RET

;TXTBOX - BOXOP for a text page not shown, in video memory.
TXTBOX:	PUSH	AX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	ES
	PUSH	DS
	PUSH	AX
	CALL	TXTSEG			;ES = the page
	POP	AX
	MOV	BL,DL
	SUB	BL,CL
	INC	BL			;BL = columns
	MOV	BYTE PTR CS:TBCOLS,BL
	MOV	BL,BYTE PTR VCOLS
	SHL	BL,1
	MOV	BYTE PTR CS:TBROW,BL	;bytes a line
	OR	AL,AL
	JZ	TBCLR
	CMP	AH,6
	JE	TBUP
;Down: copy lines DH-1 .. CH to the line below, from the bottom
	MOV	BL,DH
TBDN1:	CMP	BL,CH
	JBE	TBDNX
	MOV	AL,BL
	DEC	AL
	CALL	TBADR			;SI = line AL, column CL
	MOV	DI,SI
	MOV	AL,BYTE PTR CS:TBROW
	XOR	AH,AH
	ADD	DI,AX
	CALL	TBCPY
	DEC	BL
	JMP	SHORT TBDN1
TBDNX:	MOV	BL,CH			;Clear the top line
	JMP	SHORT TBCL1
;Up: copy lines CH+1 .. DH to the line above
TBUP:	MOV	BL,CH
TBUP1:	CMP	BL,DH
	JAE	TBUPX
	MOV	AL,BL
	CALL	TBADR
	MOV	DI,SI
	MOV	AL,BYTE PTR CS:TBROW
	XOR	AH,AH
	ADD	SI,AX
	CALL	TBCPY
	INC	BL
	JMP	SHORT TBUP1
TBUPX:	MOV	BL,DH			;Clear the bottom line
TBCL1:	MOV	DH,BL
	MOV	CH,BL
;Clear lines CH .. DH
TBCLR:	MOV	BL,CH
TBCL2:	CMP	BL,DH
	JA	TBX
	MOV	AL,BL
	CALL	TBADR
	MOV	DI,SI
	PUSH	CX
	MOV	CL,BYTE PTR CS:TBCOLS
	XOR	CH,CH
	MOV	AL," "
	MOV	AH,BH
	CLD
	REP	STOSW
	POP	CX
	INC	BL
	JMP	SHORT TBCL2
TBX:	POP	DS
	POP	ES
	POP	DI
	POP	SI
	POP	DX
	POP	CX
	POP	AX
	RET
TBADR:	PUSH	AX			;SI = line AL, column CL
	PUSH	DX
	MUL	BYTE PTR CS:TBROW
	MOV	SI,AX
	MOV	AL,CL
	XOR	AH,AH
	SHL	AX,1
	ADD	SI,AX
	POP	DX
	POP	AX
	RET
TBCPY:	PUSH	CX			;copy one line's columns, ES:SI to ES:DI
	PUSH	DS
	PUSH	ES
	POP	DS
	MOV	CL,BYTE PTR CS:TBCOLS
	XOR	CH,CH
	CLD
	REP	MOVSW
	POP	DS
	POP	CX
	RET
TBCOLS	DB	0
TBROW	DB	0

;TXTSEG - ES = the text page written to
TXTSEG:	PUSH	AX
	PUSH	CX
	MOV	AX,MDASEG
	CMP	BYTE PTR ISMONO,0
	JNE	TXTSG1
	MOV	AX,CGASEG
	MOV	CL,BYTE PTR APAGE
	XOR	CH,CH
	JCXZ	TXTSG1
TXTSG0:	ADD	AX,80H			;2 KB a page, 40 columns
	CMP	BYTE PTR VCOLS,40
	JE	TXTSG2
	ADD	AX,80H			;4 KB, 80 columns
TXTSG2:	LOOP	TXTSG0
TXTSG1:	MOV	ES,AX
	POP	CX
	POP	AX
	RET

;CLREOL - clear from column DH, line DL, to the end of the line.
CLREOL:	PUSH	AX
	PUSH	CX
	PUSH	DX
	MOV	CX,DX
	XCHG	CH,CL			;CH = line, CL = column
	SUB	CX,0101H
	MOV	DH,CH
	MOV	DL,BYTE PTR VCOLS
	DEC	DL
	MOV	AX,0600H
	CALL	BOXOP
	POP	DX
	POP	CX
	POP	AX
	RET

;CLRSCN - CLS, and the editor's clear screen.
; Entry - CF set: AL = CLS's parameter
CLRSCN:	JNB	CLRSC1
	CMP	AL,2
	JBE	CLRSC1
	JMP	FCERRP			;CLS 3 and up
CLRSC1:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CALL	GCUROF
	MOV	AX,0600H
	XOR	CX,CX
	MOV	DH,24
	MOV	DL,BYTE PTR VCOLS
	DEC	DL
	CMP	BYTE PTR KEYSW,0
	JE	CLRSC2
	DEC	DH			;Keep the function key line
CLRSC2:	CALL	BOXOP
	CALL	SCNCLR			;Home the cursors, redraw the keys
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET

;SWIDTH - WIDTH AL,CL.  CF set if not possible.
SWIDTH:	PUSH	AX
	PUSH	BX
	CMP	CL,25
	JNE	SWIDE
	MOV	BL,AL
	MOV	AL,BYTE PTR VMODE
	CMP	BL,40
	JE	SWID40
	CMP	BL,80
	JNE	SWIDE
;80 columns
	CMP	AL,7
	JE	SWIDOK			;Monochrome: always
	CMP	AL,4
	JB	SWID1
	MOV	AL,6			;Medium resolution becomes high
	JMP	SHORT SWIDSM
SWID1:	OR	AL,2			;0->2, 1->3
	JMP	SHORT SWIDSM
SWID40:	CMP	AL,7
	JE	SWIDE			;Monochrome has no 40 columns
	CMP	AL,6
	JNE	SWID2
	MOV	AL,4			;High resolution becomes medium
	JMP	SHORT SWIDSM
SWID2:	CMP	AL,4
	JAE	SWIDOK			;Already 40
	AND	AL,1			;2->0, 3->1
SWIDSM:	CMP	AL,BYTE PTR VMODE
	JE	SWIDOK
	CALL	SETMOD
	CALL	CLRSC1
SWIDOK:	POP	BX
	POP	AX
	CLC
	RET
SWIDE:	POP	BX
	POP	AX
	STC
	RET

;SCRSTT - SCREEN mode,burst,apage,vpage.  BX = parameter list:
; byte count, then two bytes each, nonzero first byte if given.
SCRSTT:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	MOV	SI,BX
	MOV	CL,BYTE PTR [SI]
	OR	CL,CL
	JNZ	SHORT ??J685
	JMP	SCRERR
??J685:
	CMP	CL,4
	JBE	SHORT ??J687
	JMP	SCRERR
??J687:
	INC	SI
	MOV	AL,BYTE PTR VMODE	;AL = mode wanted
	MOV	DH,BYTE PTR APAGE	;DH = page written, DL = shown
	MOV	DL,BYTE PTR VPAGE
;Mode
	CMP	BYTE PTR [SI],0
	JE	SCRS2
	MOV	AH,BYTE PTR [SI+1]
	CMP	AH,2
	JBE	SHORT ??J697
	JMP	SCRERR
??J697:
	CMP	BYTE PTR ISMONO,0
	JE	SCRS1
	OR	AH,AH
	JZ	SHORT ??J701			;Monochrome: text only
	JMP	SCRERR
??J701:
	JMP	SHORT SCRS2
SCRS1:	OR	AH,AH
	JNZ	SCRS1G
	CMP	AL,4			;Text: keep the width
	JB	SCRS2
	MOV	AL,1			;From medium resolution: 40 columns
	CMP	BYTE PTR VMODE,6
	JNE	SCRS2
	MOV	AL,3			;From high: 80
	JMP	SHORT SCRS2
SCRS1G:	MOV	AL,4
	CMP	AH,1
	JE	SCRS2
	MOV	AL,6
SCRS2:	DEC	CL
	JZ	SCRSM
	ADD	SI,2
;Burst: text 0 = no color; medium resolution nonzero = no color
	CMP	BYTE PTR [SI],0
	JE	SCRS3
	CMP	AL,7
	JE	SCRS3
	CMP	AL,6
	JE	SCRS3
	MOV	AH,BYTE PTR [SI+1]
	CMP	AL,4
	JAE	SCRS2G
	AND	AL,0FEH			;0 or 2: no color
	OR	AH,AH
	JZ	SCRS3
	INC	AL			;1 or 3: color
	JMP	SHORT SCRS3
SCRS2G:	MOV	AL,4
	OR	AH,AH
	JZ	SCRS3
	MOV	AL,5
SCRS3:	DEC	CL
	JZ	SCRSM
	ADD	SI,2
;Page written to
	CMP	BYTE PTR [SI],0
	JE	SCRS4
	MOV	DH,BYTE PTR [SI+1]
	MOV	DL,DH			;Page shown follows unless given
SCRS4:	DEC	CL
	JZ	SCRSM
	ADD	SI,2
	CMP	BYTE PTR [SI],0
	JE	SCRSM
	MOV	DL,BYTE PTR [SI+1]
;Check the pages against the mode
SCRSM:	MOV	AH,7			;Highest page
	CMP	AL,1
	JBE	SCRSM1
	MOV	AH,3
	CMP	AL,3
	JBE	SCRSM1
	MOV	AH,0			;Graphics and monochrome: one page
SCRSM1:	CMP	DH,AH
	JA	SCRERR
	CMP	DL,AH
	JA	SCRERR
	CMP	AL,BYTE PTR VMODE
	JE	SCRSP
	CALL	SETMOD			;A new mode: everything starts again
	CALL	CLRSC1
SCRSP:	MOV	BYTE PTR APAGE,DH
	CMP	DL,BYTE PTR VPAGE
	JE	SCRSX
	MOV	BYTE PTR VPAGE,DL
	MOV	AL,DL
	MOV	AH,5
	INT	10H
SCRSX:	POP	SI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	CLC
	RET
SCRERR:	POP	SI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	STC
	RET

;SETCLR - COLOR.  BX = parameter list, as SCRSTT's.  CF set if wrong.
SETCLR:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	SI
	MOV	SI,BX
	MOV	CL,BYTE PTR [SI]
	INC	SI
	CMP	CL,3
	JBE	SHORT ??J799
	JMP	CLRERR
??J799:
	CMP	BYTE PTR BPP,0
	JNE	CLRGR
;Text: foreground 0-31, background 0-15, border 0-15
	MOV	AL,BYTE PTR TXTFG
	MOV	AH,BYTE PTR TXTBG
	MOV	BL,BYTE PTR BORDER
	OR	CL,CL
	JZ	CLRTX
	CMP	BYTE PTR [SI],0
	JE	CLRT1
	MOV	AL,BYTE PTR [SI+1]
	CMP	AL,31
	JBE	SHORT ??J812
	JMP	CLRERR
??J812:
CLRT1:	DEC	CL
	JZ	CLRTX
	CMP	BYTE PTR [SI+2],0
	JE	CLRT2
	MOV	AH,BYTE PTR [SI+3]
	CMP	AH,15
	JA	CLRERR
CLRT2:	DEC	CL
	JZ	CLRTX
	CMP	BYTE PTR [SI+4],0
	JE	CLRTX
	MOV	BL,BYTE PTR [SI+5]
	CMP	BL,15
	JA	CLRERR
CLRTX:	MOV	BYTE PTR TXTFG,AL
	AND	AH,7
	MOV	BYTE PTR TXTBG,AH
	CALL	MKATR
	CMP	BL,BYTE PTR BORDER
	JE	CLROK
	MOV	BYTE PTR BORDER,BL
	CMP	BYTE PTR ISMONO,0
	JNE	CLROK
	MOV	BH,0
	MOV	AH,0BH
	INT	10H
	JMP	SHORT CLROK
;Medium resolution: background 0-15, palette (even 0, odd 1)
CLRGR:	CMP	BYTE PTR BPP,1
	JE	CLRERR			;None in high resolution
	CMP	CL,2
	JA	CLRERR
	OR	CL,CL
	JZ	CLROK
	CMP	BYTE PTR [SI],0
	JE	CLRG1
	MOV	BL,BYTE PTR [SI+1]
	CMP	BL,15
	JA	CLRERR
	MOV	BYTE PTR GBACK,BL
	MOV	BH,0
	MOV	AH,0BH
	INT	10H
CLRG1:	DEC	CL
	JZ	CLROK
	CMP	BYTE PTR [SI+2],0
	JE	CLROK
	MOV	BL,BYTE PTR [SI+3]
	AND	BL,1
	MOV	BYTE PTR GPAL,BL
	MOV	BH,1
	MOV	AH,0BH
	INT	10H
CLROK:	POP	SI
	POP	CX
	POP	BX
	POP	AX
	CLC
	RET
CLRERR:	POP	SI
	POP	CX
	POP	BX
	POP	AX
	STC
	RET

;GETFBC - CF set: graphics colors, else text.  AL = foreground,
; BL = background.
GETFBC:	JNB	GETFB1
	XOR	BL,BL
	MOV	AL,1
	CMP	BYTE PTR BPP,2
	JNE	GETFBX
	MOV	AL,3
GETFBX:	RET
GETFB1:	MOV	AL,BYTE PTR TXTFG
	MOV	BL,BYTE PTR TXTBG
	RET

;SETFBC - text colors AL foreground, BL background (the key line's
; reverse video).
SETFBC:	MOV	BYTE PTR TXTFG,AL
	MOV	BYTE PTR TXTBG,BL
	JMP	MKATR

;CSRATR - LOCATE's cursor,start,stop: AL,BL,CL, each with AH,BH,CH
; nonzero if given.  CF set if wrong.
CSRATR:	OR	AH,AH
	JZ	CSRAT1
	MOV	BYTE PTR UCVIS,AL
CSRAT1:	OR	BH,BH
	JZ	CSRAT3
	CMP	BL,31
	JA	CSRATE
	MOV	BYTE PTR UCTOP,BL
	OR	CH,CH
	JNZ	CSRAT3
	MOV	BYTE PTR UCBOT,BL	;Start given, stop not: the same
CSRAT3:	OR	CH,CH
	JZ	CSRAT4
	CMP	CL,31
	JA	CSRATE
	MOV	BYTE PTR UCBOT,CL
CSRAT4:	CLC
	RET
CSRATE:	STC
	RET

;CSRDSP - show cursor type AL at column DH, line DL:
; 0 none, 1 insert, 2 overwrite, 3 LOCATE's.  All registers preserved.
CSRDSP:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CALL	GCUROF
	MOV	CH,20H			;None
	CMP	AL,3
	JNE	CSRDS1
	CMP	BYTE PTR UCVIS,0
	JE	CSRDS4
	MOV	CH,BYTE PTR UCTOP
	MOV	CL,BYTE PTR UCBOT
	JMP	SHORT CSRDS4
CSRDS1:	OR	AL,AL
	JZ	CSRDS4
	MOV	CX,0607H		;Overwrite: a line at the bottom
	CMP	BYTE PTR ISMONO,0
	JE	CSRDS2
	MOV	CX,0B0CH
CSRDS2:	CMP	AL,2
	JE	CSRDS4
	MOV	CH,CL			;Insert: the lower half
	SHR	CH,1
CSRDS4:	CMP	BYTE PTR BPP,0
	JNE	CSRDGR
	PUSH	DX
	MOV	AH,1
	INT	10H
	POP	DX
	CALL	CSRPOS
	JNE	CSRDSX
	MOV	BH,BYTE PTR APAGE
	MOV	AH,2
	INT	10H
CSRDSX:	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET
;Graphics: there is no cursor; draw lines CH to the bottom of the cell
CSRDGR:	TEST	CH,20H
	JNZ	CSRDSX
	CALL	CSRPOS
	JNE	CSRDSX
	MOV	AL,8
	SUB	AL,CH
	CMP	AL,1
	JGE	CSRDG1
	MOV	AL,1
CSRDG1:	CMP	AL,8
	JLE	CSRDG2
	MOV	AL,8
CSRDG2:	MOV	BYTE PTR GCURLN,AL
	MOV	AL,DH			;Address of the cell's bottom line
	MOV	BL,8
	MUL	BL
	ADD	AX,7
	MOV	BX,AX			;BX = y
	MOV	AL,DL
	XOR	AH,AH
	CMP	BYTE PTR BPP,1
	JE	CSRDG3
	SHL	AX,1			;2 bytes a character in 320 by 200
CSRDG3:	PUSH	AX
	CALL	YADDR			;AX = address of line BX
	POP	DX
	ADD	AX,DX
	INC	AX			;(stored + 1, so 0 means none)
	MOV	GCURAT,AX
	CALL	GCURXR
	JMP	SHORT CSRDSX

;CSRPOS - DX (column, line) to the BIOS's DH line, DL column, 0-relative.
; ZF clear if off the screen.
CSRPOS:	XCHG	DH,DL
	SUB	DX,0101H
	CMP	DL,BYTE PTR VCOLS
	JB	CSRPS1
	MOV	DL,BYTE PTR VCOLS
	DEC	DL
CSRPS1:	CMP	DH,25
	JAE	CSRPS2
	CMP	AL,AL
	RET
CSRPS2:	OR	SP,SP
	RET

;GCUROF - remove the graphics cursor, if drawn
GCUROF:	CMP	WORD PTR GCURAT,0
	JE	GCUROX
	CALL	GCURXR
	MOV	WORD PTR GCURAT,0
GCUROX:	RET

;GCURXR - exclusive-or the graphics cursor at GCURAT-1
GCURXR:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	ES
	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	BX,GCURAT
	DEC	BX
	MOV	CL,BYTE PTR GCURLN
	XOR	CH,CH
GCURX1:	XOR	BYTE PTR ES:[BX],0FFH
	CMP	BYTE PTR BPP,1
	JE	GCURX2
	XOR	BYTE PTR ES:[BX+1],0FFH
GCURX2:	CALL	YUPB			;up one line
	LOOP	GCURX1
	POP	ES
	POP	CX
	POP	BX
	POP	AX
	RET

;FKYFMT - BX = the function key line's format: characters a key,
; keys shown, first key shown.
FKYFMT:	MOV	BX,OFFSET FKFMT
	RET

;FKYADV - ZF set: start the line at F1; else show the next keys.
; ZF set on return when there are no more (the line goes off).
FKYADV:	PUSH	AX
	JNZ	FKYAD1
	MOV	KEYFIR,1
	OR	SP,SP
	POP	AX
	RET
FKYAD1:	MOV	AL,KEYFIR
	ADD	AL,BYTE PTR FKFMT+1
	CMP	AL,10
	JA	FKYAD2
	MOV	KEYFIR,AL
	OR	SP,SP
	POP	AX
	RET
FKYAD2:	MOV	KEYFIR,1
	CMP	AL,AL
	POP	AX
	RET

;LCPY - LCOPY: print the screen.
LCPY:	PUSH	BP
	INT	5
	POP	BP
	CLC
	RET

;PRTMAP, EDTMAP - what a character sent to the screen does.
; Entry - AX = character (AH = 0FFH: an editing key's function)
; Exit  - ZF set: nothing.  AH = 0FFH: function AL.  Else print AX.
PRTMAP:	OR	AH,AH
	JNZ	MAPPR
	PUSH	DI
	PUSH	CX
	PUSH	ES
	PUSH	CS
	POP	ES
	MOV	DI,OFFSET PRTFUN
	MOV	CX,PRTFNN
	CLD
	REPNE	SCASB
	POP	ES
	POP	CX
	POP	DI
	JNE	MAPPR
	MOV	AH,0FFH
MAPPR:	OR	SP,SP
	RET
EDTMAP:	CMP	AH,0FFH
	JE	MAPPR
	OR	AH,AH
	JNZ	MAPPR
	CMP	AL,7FH
	JE	EDTFN
	CMP	AL,20H
	JAE	MAPPR
	PUSH	DI
	PUSH	CX
	PUSH	ES
	PUSH	CS
	POP	ES
	MOV	DI,OFFSET EDTFUN
	MOV	CX,EDTFNN
	CLD
	REPNE	SCASB
	POP	ES
	POP	CX
	POP	DI
	JE	EDTFN
	CMP	AL,AL			;Other control characters: nothing
	RET
EDTFN:	MOV	AH,0FFH
	OR	SP,SP
	RET
PRTFUN	DB	7,9,10,11,12,13,28,29,30,31
	PRTFNN	EQU	$-PRTFUN
EDTFUN	DB	2,3,5,6,7,8,9,10,11,12,13,14,18,20,21,28,29,30,31
	EDTFNN	EQU	$-EDTFUN

	SUBTTL	The keyboard

;KEYINP - the next key, if there is one.
; Exit  - ZF set: none.  Else AX = the key in Microsoft's codes:
;         CF clear: AL a character, or AL = 0FEH and DL = scan code;
;         CF set: two bytes, AH 0FFH (an editing key) or 80H (a function
;         key, or Alt and a letter: a keyword).
KEYINP:	PUSH	BX
KEYIN1:	MOV	AH,1
	INT	16H
	JNZ	SHORT ??J1135
	JMP	KEYNON
??J1135:
	XOR	AH,AH
	INT	16H
	OR	AX,AX
	JZ	KEYIN1			;Ctrl-Break's empty key
	OR	AL,AL
	JZ	KEYEXT
	CMP	AL,0E0H			;Enhanced keyboard's gray keys
	JNE	KEYIN2
	OR	AH,AH
	JNZ	KEYEXT
KEYIN2:	CMP	AX,011BH		;Esc: the editor's line delete
	JNE	KEYIN3
	MOV	AX,0FF15H
	JMP	SHORT KEYTWO
KEYIN3:	CMP	AL,80H			;A character 128: two of them
	JNE	KEYIN4
	MOV	AH,AL
	JMP	SHORT KEYTWO
KEYIN4:	CMP	AL,0FEH
	JAE	KEYIN1			;254 and 255 cannot be typed
	XOR	AH,AH
	OR	AL,AL			;NZ, NC
	POP	BX
	RET
KEYEXT:	MOV	AL,AH			;AL = scan code
	CMP	AL,3BH
	JB	KEYEX1
	CMP	AL,44H
	JA	KEYEX1
	SUB	AL,3BH-20H		;F1-F10
	MOV	AH,80H
	JMP	SHORT KEYTWO
KEYEX1:	PUSH	CX
	PUSH	DI
	PUSH	ES
	PUSH	CS
	POP	ES
	MOV	DI,OFFSET EDKSCN	;Editing keys
	MOV	CX,EDKN
	CLD
	REPNE	SCASB
	JNE	KEYEX2
	MOV	AL,BYTE PTR CS:[DI+EDKN-1]
	MOV	AH,0FFH
	JMP	SHORT KEYEX3
KEYEX2:	MOV	DI,OFFSET ALTSCN	;Alt and a letter
	MOV	CX,26
	REPNE	SCASB
	JNE	KEYEX4
	MOV	AX,DI
	SUB	AX,OFFSET ALTSCN+1
	ADD	AL,"A"
	MOV	AH,80H
KEYEX3:	POP	ES
	POP	DI
	POP	CX
KEYTWO:	OR	SP,SP			;NZ
	STC
	POP	BX
	RET
KEYEX4:	POP	ES			;Any other: 0FEH and the scan code
	POP	DI
	POP	CX
	MOV	DL,AL
	XOR	DH,DH
	MOV	AX,00FEH
	OR	AL,AL
	POP	BX
	RET
KEYNON:	XOR	AX,AX			;ZF, NC
	POP	BX
	RET

;Editing keys: scan codes, then the function each gives
EDKSCN	DB	48H,4BH,4DH,50H,47H,4FH,52H,53H,77H,75H,74H,73H
	EDKN	EQU	$-EDKSCN
	DB	30,29,28,31,11,14,18,127,12,5,6,2
;Alt and A to Z: scan codes
ALTSCN	DB	1EH,30H,2EH,20H,12H,21H,22H,23H,17H,24H,25H,26H,32H
	DB	31H,18H,19H,10H,13H,1FH,14H,16H,2FH,11H,2DH,15H,2CH

;INKMAP, INFMAP - a key for INKEY$ and INPUT$, in the IBM PC's codes.
; Entry - AX, CF, DX as from KEYINP (by way of the keyboard queue)
; Exit  - ZF set: no character.  CF set: two bytes AH, AL.  Else AL.
INKMAP:
INFMAP:	JB	INKM2
	CMP	AL,0FEH
	JNE	INKMX1
	MOV	AL,DL			;0 and the scan code
	XOR	AH,AH
	JMP	SHORT INKMX2
INKMX1:	XOR	AH,AH			;One byte
	OR	SP,SP
	RET
INKM2:	CMP	AH,80H
	JNE	INKM3
	CMP	AL,AH
	JE	INKMX1			;128
	CMP	AL,20H			;Function keys (with nothing defined)
	JB	INKMZ
	CMP	AL,29H
	JA	INKM2A
	ADD	AL,3BH-20H
	XOR	AH,AH
	JMP	SHORT INKMX2
INKM2A:	CMP	AL,"A"			;Alt and a letter
	JB	INKMZ
	CMP	AL,"Z"
	JA	INKMZ
	PUSH	BX
	MOV	BL,AL
	SUB	BL,"A"
	XOR	BH,BH
	MOV	AL,BYTE PTR CS:ALTSCN[BX]
	POP	BX
	XOR	AH,AH
	JMP	SHORT INKMX2
INKM3:	CMP	AH,0FFH
	JNE	INKMZ
	CMP	AL,15H			;Esc
	JNE	INKM3A
	MOV	AL,1BH
	JMP	SHORT INKMX1
INKM3A:	PUSH	CX
	PUSH	DI
	PUSH	ES
	PUSH	CS
	POP	ES
	MOV	DI,OFFSET EDKSCN+EDKN
	MOV	CX,EDKN
	CLD
	REPNE	SCASB
	JNE	INKM3B
	MOV	AL,BYTE PTR CS:[DI-EDKN-1]
	XOR	AH,AH
	POP	ES
	POP	DI
	POP	CX
	JMP	SHORT INKMX2
INKM3B:	POP	ES
	POP	DI
	POP	CX
INKMZ:	CMP	AL,AL			;Nothing
	RET
INKMX2:	OR	SP,SP			;Two bytes: 0 and AL
	STC
	RET

;MAPSUP - Alt and the letter AL: CH = which of the keywords starting
; with that letter (counting ALPTAB, then ALPTAX), 0 for none.
MAPSUP:	PUSH	AX
	PUSH	BX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	MOV	CH,0
	SUB	AL,"A"
	CMP	AL,25
	JA	MAPSUX
	XOR	AH,AH
	MOV	BX,AX
	SHL	BX,1
	MOV	DI,WORD PTR CS:ALTWRD[BX]	;The keyword, less its letter
	OR	DI,DI
	JZ	MAPSUX
	MOV	SI,WORD PTR CS:ALPTAB[BX]
	CALL	MAPSCN
	JE	MAPSUX
	MOV	SI,WORD PTR CS:ALPTAX[BX]
	CALL	MAPSCN
	JE	MAPSUX
	MOV	CH,0
MAPSUX:	POP	DI
	POP	SI
	POP	DX
	POP	BX
	POP	AX
	RET
;MAPSCN - look for DI's word in the table at SI, counting in CH.
; ZF set if found.
MAPSCN:	TEST	BYTE PTR CS:[SI],0FFH
	JZ	MAPSNO			;End of this letter's words
	INC	CH
	MOV	DX,DI
MAPSC1:	MOV	AL,BYTE PTR CS:[SI]
	PUSH	BX
	MOV	BX,DX
	MOV	AH,BYTE PTR CS:[BX]
	POP	BX
	INC	SI
	INC	DX
	CMP	AL,AH
	JNE	MAPSC2
	OR	AL,AL
	JNS	MAPSC1
	CMP	AL,AL			;All of it matched: ZF set
	RET
MAPSC2:	OR	AL,AL			;Skip the rest of this word
	JS	MAPSC3
	MOV	AL,BYTE PTR CS:[SI]
	INC	SI
	JMP	SHORT MAPSC2
MAPSC3:	INC	SI			;and its token
	JMP	SHORT MAPSCN
MAPSNO:	OR	SP,SP
	RET

;The keywords Alt gives, as in IBM BASIC: the letters after the first,
;the last with its top bit set
ALTWRD	DW	ALTA,ALTB,ALTC,ALTD,ALTE,ALTF,ALTG,ALTH,ALTI,0,ALTK,ALTL
	DW	0,ALTN,ALTO,ALTP,0,ALTR,ALTS,ALTT,ALTU,ALTV,ALTW,ALTX,0,0
ALTA	DB	"UT","O"+128
ALTB	DB	"SAV","E"+128
ALTC	DB	"OLO","R"+128
ALTD	DB	"ELET","E"+128
ALTE	DB	"LS","E"+128
ALTF	DB	"O","R"+128
ALTG	DB	"OT","O"+128
ALTH	DB	"EX","$"+128
ALTI	DB	"NPU","T"+128
ALTK	DB	"E","Y"+128
ALTL	DB	"OCAT","E"+128
ALTN	DB	"EX","T"+128
ALTO	DB	"PE","N"+128
ALTP	DB	"RIN","T"+128
ALTR	DB	"U","N"+128
ALTS	DB	"CREE","N"+128
ALTT	DB	"HE","N"+128
ALTU	DB	"SIN","G"+128
ALTV	DB	"A","L"+128
ALTW	DB	"IDT","H"+128
ALTX	DB	"O","R"+128

;POLLEV - ZF clear if an event may have happened (a key, serial data, the
; pen, a trigger).  All registers preserved.
POLLEV:	PUSH	AX
	CMP	WORD PTR CS:COMBLK+CPORT,0
	JNE	POLLV1
	CMP	WORD PTR CS:COMBLK+CBLEN+CPORT,0
	JNE	POLLV1
	CMP	BYTE PTR PENON,0
	JNE	POLLV1
	INC	BYTE PTR POLCNT
	TEST	BYTE PTR POLCNT,15
	JZ	POLLV1			;Triggers, now and then
	MOV	AH,1
	INT	16H
	JNZ	POLLV1
	POP	AX
	CMP	AX,AX
	RET
POLLV1:	POP	AX
	OR	SP,SP
	RET

	SUBTTL	Graphics
;
; The current point, "C", is a byte of video memory (CLOC) and a mask of
; the pixel's bits in it (CMASK).  Screen 1: two bits a pixel, 320 by 200.
; Screen 2: one bit, 640 by 200.  Even lines at B800:0000, odd at
; B800:2000, 80 bytes a line.
;

;PIXSIZ - AL = bits a pixel, 0 in text modes.
PIXSIZ:	MOV	AL,BYTE PTR BPP
	RET

;GRPSIZ - CX = largest X, DX = largest Y.
GRPSIZ:	MOV	CX,PXMAX
	MOV	DX,199
	RET

;GTASPC - BX = the screen's aspect ratio times 256, DX = its inverse.
GTASPC:	MOV	BX,213			;Screen 1: 5/6
	MOV	DX,307
	CMP	BYTE PTR BPP,1
	JNE	GTASPX
	MOV	BX,107			;Screen 2: 5/12
	MOV	DX,614
GTASPX:	RET

;SCALXY - X in CX, Y in DX, kept within the screen.
; CF set if they were already; clear if either was changed.
SCALXY:	PUSH	AX
	MOV	AL,1			;AL = 1 while nothing changed
	OR	CX,CX
	JNS	SCLX1
	XOR	CX,CX
	MOV	AL,0
SCLX1:	CMP	CX,PXMAX
	JLE	SCLX2
	MOV	CX,PXMAX
	MOV	AL,0
SCLX2:	OR	DX,DX
	JNS	SCLX3
	XOR	DX,DX
	MOV	AL,0
SCLX3:	CMP	DX,199
	JLE	SCLX4
	MOV	DX,199
	MOV	AL,0
SCLX4:	SHR	AL,1			;CF = AL
	POP	AX
	RET

;YADDR - AX = the address of line BX
YADDR:	PUSH	DX
	MOV	AX,BX
	SHR	AX,1
	MOV	DX,80
	MUL	DX
	TEST	BL,1
	JZ	YADDR1
	ADD	AX,ODDBNK
YADDR1:	POP	DX
	RET

;MAPXYC - make (CX,DX) the current point.
MAPXYC:	PUSH	AX
	PUSH	BX
	PUSH	CX
	MOV	BX,DX
	CALL	YADDR
	MOV	BX,AX
	MOV	AX,CX			;X
	CMP	BYTE PTR BPP,1
	JE	MAPXY1
	MOV	CL,AL			;Two bits: X/4, mask C0h >> 2*(X mod 4)
	AND	CL,3
	SHL	CL,1
	SHR	AX,1
	SHR	AX,1
	MOV	CH,0C0H
	JMP	SHORT MAPXY2
MAPXY1:	MOV	CL,AL			;One bit: X/8, mask 80h >> (X mod 8)
	AND	CL,7
	SHR	AX,1
	SHR	AX,1
	SHR	AX,1
	MOV	CH,80H
MAPXY2:	ADD	BX,AX
	SHR	CH,CL
	MOV	CLOC,BX
	MOV	BYTE PTR CMASK,CH
	POP	CX
	POP	BX
	POP	AX
	RET

;FETCHC - AL = mask, BX = address of the current point.
FETCHC:	MOV	AL,BYTE PTR CMASK
	MOV	BX,CLOC
	RET

;STOREC - AL = mask, BX = address: make it the current point.
STOREC:	MOV	BYTE PTR CMASK,AL
	MOV	CLOC,BX
	RET

;SETATR - AL = attribute for SETC.  CF set if out of range.
SETATR:	PUSH	AX
	CALL	ATRBYT2
	JB	SETATX
	MOV	BYTE PTR ATRPAT,AH
SETATX:	POP	AX
	RET

;ATRBYT2 - AL = attribute: AH = a byte of pixels of it; CF set if
; out of range.
ATRBYT2:CMP	BYTE PTR BPP,1
	JA	ATRB2
	CMP	AL,1
	JA	ATRBE
	MOV	AH,0
	OR	AL,AL
	JZ	ATRBX
	MOV	AH,0FFH
	JMP	SHORT ATRBX
ATRB2:	CMP	AL,3
	JA	ATRBE
	MOV	AH,AL			;Repeat the two bits four times
	SHL	AH,1
	SHL	AH,1
	OR	AH,AL
	MOV	AL,AH
	SHL	AH,1
	SHL	AH,1
	SHL	AH,1
	SHL	AH,1
	OR	AH,AL
	AND	AL,3
ATRBX:	CLC
	RET
ATRBE:	STC
	RET

;SETC - set the current point to the current attribute.
SETC:	PUSH	AX
	PUSH	BX
	PUSH	ES
	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	BX,CLOC
	MOV	AL,BYTE PTR CMASK
	MOV	AH,AL
	AND	AL,BYTE PTR ATRPAT
	NOT	AH
	AND	AH,ES:[BX]
	OR	AL,AH
	MOV	ES:[BX],AL
	POP	ES
	POP	BX
	POP	AX
	RET

;READC - AL = the attribute of the current point.
READC:	PUSH	BX
	PUSH	CX
	PUSH	ES
	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	BX,CLOC
	MOV	AL,ES:[BX]
	MOV	AH,BYTE PTR CMASK
	AND	AL,AH
READC1:	TEST	AH,1			;Shift down to bit 0
	JNZ	READC2
	SHR	AH,1
	SHR	AL,1
	JMP	SHORT READC1
READC2:	POP	ES
	POP	CX
	POP	BX
	RET

;NSETCX - set BX points from the current point to the right.
; The current point moves.
NSETCX:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	DI
	PUSH	ES
	MOV	CX,BX
	JCXZ	NSETX
	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	DI,CLOC
	MOV	DL,BYTE PTR CMASK
	MOV	DH,BYTE PTR ATRPAT
	MOV	BL,0C0H			;BL = a byte's first pixel's mask
	CMP	BYTE PTR BPP,2
	JE	NSET1
	MOV	BL,80H
NSET1:	CMP	DL,BL			;At a byte's start, with a byte to go?
	JNE	NSET2
	MOV	AL,8
	CMP	BYTE PTR BPP,2
	JNE	NSET1A
	MOV	AL,4
NSET1A:	XOR	AH,AH
	CMP	CX,AX
	JB	NSET2
	MOV	ES:[DI],DH		;Whole byte
	INC	DI
	SUB	CX,AX
	JNZ	NSET1
	JMP	SHORT NSETX1
NSET2:	MOV	AL,DL			;One pixel
	AND	AL,DH
	MOV	AH,DL
	NOT	AH
	AND	AH,ES:[DI]
	OR	AL,AH
	MOV	ES:[DI],AL
	CALL	RTMASK			;DL, DI one to the right
	LOOP	NSET1
NSETX1:	MOV	CLOC,DI
	MOV	BYTE PTR CMASK,DL
NSETX:	POP	ES
	POP	DI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET

;RTMASK, LTMASK - move mask DL, address DI one pixel right or left
RTMASK:	SHR	DL,1
	CMP	BYTE PTR BPP,1
	JE	RTMSK1
	SHR	DL,1
RTMSK1:	JNZ	RTMSKX
	MOV	DL,0C0H
	CMP	BYTE PTR BPP,2
	JE	RTMSK2
	MOV	DL,80H
RTMSK2:	INC	DI
RTMSKX:	RET
LTMASK:	SHL	DL,1
	CMP	BYTE PTR BPP,1
	JE	LTMSK1
	SHL	DL,1
LTMSK1:	JNZ	LTMSKX
	MOV	DL,3
	CMP	BYTE PTR BPP,2
	JE	LTMSK2
	MOV	DL,1
LTMSK2:	DEC	DI
LTMSKX:	RET

;RIGHTC, LEFTC - the current point moves one right or left.
RIGHTC:	PUSH	DX
	PUSH	DI
	MOV	DI,CLOC
	MOV	DL,BYTE PTR CMASK
	CALL	RTMASK
	JMP	SHORT LRCX
LEFTC:	PUSH	DX
	PUSH	DI
	MOV	DI,CLOC
	MOV	DL,BYTE PTR CMASK
	CALL	LTMASK
LRCX:	MOV	CLOC,DI
	MOV	BYTE PTR CMASK,DL
	POP	DI
	POP	DX
	RET

;YUPB, YDNB - BX, an address, moves one line up or down
YUPB:	CMP	BX,ODDBNK
	JB	YUPB1
	SUB	BX,ODDBNK		;Odd line: the even one above
	RET
YUPB1:	ADD	BX,ODDBNK-80		;Even line: the odd one above
	RET
YDNB:	CMP	BX,ODDBNK
	JB	YDNB1
	SUB	BX,ODDBNK-80		;Odd line: the even one below
	RET
YDNB1:	ADD	BX,ODDBNK		;Even line: the odd one below
	RET

;UPC, DOWNC - the current point moves one line up or down.
UPC:	PUSH	BX
	MOV	BX,CLOC
	CALL	YUPB
	MOV	CLOC,BX
	POP	BX
	RET
DOWNC:	PUSH	BX
	MOV	BX,CLOC
	CALL	YDNB
	MOV	CLOC,BX
	POP	BX
	RET

;TUPC, TDOWNC - as UPC and DOWNC, but CF set, and no move, at the top or
; bottom line.
TUPC:	CMP	WORD PTR CLOC,80
	JB	TOFF			;Line 0
	CALL	UPC
	CLC
	RET
TDOWNC:	CMP	WORD PTR CLOC,ODDBNK+99*80
	JAE	TOFF			;Line 199
	CALL	DOWNC
	CLC
	RET
TOFF:	STC
	RET

;CXPOS - DI, DL = the current point; CX = its X.
CXPOS:	PUSH	AX
	PUSH	DX
	MOV	DI,CLOC
	MOV	AX,DI
	AND	AX,ODDBNK-1
	XOR	DX,DX
	MOV	CX,80
	DIV	CX			;DX = byte in the line
	MOV	AX,DX
	MOV	DL,BYTE PTR CMASK
	MOV	CL,3			;X = byte * 8 + bit
	CMP	BYTE PTR BPP,2
	JNE	CXPOS1
	MOV	CL,2			; or byte * 4 + pixel
CXPOS1:	SHL	AX,CL
	MOV	CX,AX
	MOV	DH,80H			;Count the pixels before this one
	CMP	BYTE PTR BPP,2
	JNE	CXPOS2
	MOV	DH,0C0H
CXPOS2:	CMP	DH,DL
	JE	CXPOS3
	INC	CX
	SHR	DH,1
	CMP	BYTE PTR BPP,2
	JNE	CXPOS2
	SHR	DH,1
	JMP	SHORT CXPOS2
CXPOS3:	POP	DX
	POP	AX
	MOV	DL,BYTE PTR CMASK
	RET

;PNTINI - AL = PAINT's border attribute.  CF set if out of range.
PNTINI:	PUSH	AX
	CALL	ATRBYT2
	JB	PNTINX
	MOV	BYTE PTR BRDPAT,AH
PNTINX:	POP	AX
	RET

;ISBRD - ZF set if the point at ES:DI, mask DL, is the border color
ISBRD:	PUSH	AX
	MOV	AL,ES:[DI]
	XOR	AL,BYTE PTR BRDPAT
	AND	AL,DL
	POP	AX
	RET

;PAINT1 - paint the point at ES:DI, mask DL.  AL nonzero if it changed.
PAINT1:	PUSH	BX
	MOV	BL,ES:[DI]
	MOV	BH,BL
	XOR	BH,BYTE PTR ATRPAT
	AND	BH,DL			;Bits that differ
	JZ	PAINT2
	OR	AL,1
	XOR	BL,BH
	MOV	ES:[DI],BL
PAINT2:	POP	BX
	RET

;SCANR - PAINT's scan to the right.
; Entry - DX = border points that may be skipped first
; Exit  - DX = skip count left, BX = points painted, CL nonzero if any
;         changed.  CSAVEA, CSAVEM = the first point painted; the
;         current point is the one after the last painted.
DSEG	SEGMENT PUBLIC 'DATASG'
	EXTRN	CSAVEA:WORD,CSAVEM:BYTE
DSEG	ENDS
SCANR:	PUSH	AX
	PUSH	SI
	PUSH	DI
	PUSH	ES
	PUSH	CX
	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	SI,DX			;SI = skip count
	CALL	CXPOS			;CX = X, DI and DL the point
	XOR	BX,BX
	XOR	AL,AL
;Skip border points
SCNR1:	OR	SI,SI
	JZ	SCNRX			;No skip left: nothing painted
	CALL	ISBRD
	JNZ	SCNR2
	DEC	SI
	CMP	CX,PXMAX
	JAE	SCNRE			;The right edge
	INC	CX
	CALL	RTMASK
	JMP	SHORT SCNR1
SCNRE:	XOR	SI,SI
	JMP	SHORT SCNRX
;Paint to the next border point or the edge
SCNR2:	MOV	CSAVEA,DI
	MOV	BYTE PTR CSAVEM,DL
SCNR3:	CALL	PAINT1
	INC	BX
	CMP	CX,PXMAX
	JAE	SCNR4			;Painted the last point of the line
	INC	CX
	CALL	RTMASK
	CALL	ISBRD
	JNZ	SCNR3
	JMP	SHORT SCNRX
SCNR4:	CMP	SI,BX			;At the edge: nothing more to the right
	JBE	SCNRX
	MOV	SI,BX
SCNRX:	MOV	CLOC,DI
	MOV	BYTE PTR CMASK,DL
	MOV	DX,SI
	POP	CX
	MOV	CL,AL
	POP	ES
	POP	DI
	POP	SI
	POP	AX
	RET

;SCANL - PAINT's scan to the left, from the point before the current one.
; Exit  - BX = points painted, CL nonzero if any changed.  The current
;         point is the leftmost painted (or where it was, if none).
SCANL:	PUSH	AX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	ES
	PUSH	CX
	MOV	AX,CGASEG
	MOV	ES,AX
	CALL	CXPOS
	XOR	BX,BX
	XOR	AL,AL
SCNL1:	JCXZ	SCNLX			;The left edge
	MOV	SI,DI			;Keep the last point painted
	MOV	AH,DL
	DEC	CX
	CALL	LTMASK
	CALL	ISBRD
	JZ	SCNLB
	CALL	PAINT1
	INC	BX
	JMP	SHORT SCNL1
SCNLB:	MOV	DI,SI			;Back to the last one painted
	MOV	DL,AH
SCNLX:	MOV	CLOC,DI
	MOV	BYTE PTR CMASK,DL
	POP	CX
	MOV	CL,AL
	POP	ES
	POP	DI
	POP	SI
	POP	DX
	POP	AX
	RET

;PGINIT - GET (CF clear) or PUT (CF set, AL = action: 0 OR, 1 AND,
; 2 PRESET, 3 PSET, 4 XOR) of lines of CX bits, at the array at BX.
PGINIT:	MOV	BYTE PTR PGOP,AL
	MOV	PGBITS,CX
	MOV	PGPTR,BX
	PUSH	CX
	AND	CL,7			;The last byte's bits
	MOV	AL,0FFH
	JZ	PGIN1
	SHR	AL,CL
	NOT	AL
PGIN1:	MOV	BYTE PTR PGLAST,AL
	POP	CX
	RET

;PGSET - for NREAD and NWRITE: ES = video, DI = address, CL = shift
; (bit of the first pixel in its byte), DX = bytes in the line.
PGSET:	MOV	AX,CGASEG
	MOV	ES,AX
	MOV	DI,CLOC
	MOV	AL,BYTE PTR CMASK
	XOR	CL,CL
PGSET1:	TEST	AL,80H
	JNZ	PGSET2
	SHL	AL,1
	INC	CL
	JMP	SHORT PGSET1
PGSET2:	MOV	DX,PGBITS
	ADD	DX,7
	SHR	DX,1
	SHR	DX,1
	SHR	DX,1
	RET

;NREAD - GET one line from the current point into the array.
NREAD:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	ES
	CALL	PGSET
	MOV	SI,PGPTR
	MOV	CH,8
	SUB	CH,CL			;CH = 8 - shift
NREAD1:	MOV	AL,ES:[DI]
	SHL	AL,CL
	OR	CL,CL
	JZ	NREAD2
	MOV	AH,ES:[DI+1]
	XCHG	CL,CH
	SHR	AH,CL
	XCHG	CL,CH
	OR	AL,AH
NREAD2:	CMP	DX,1
	JNE	NREAD3
	AND	AL,BYTE PTR PGLAST	;Unused bits of the last byte: 0
NREAD3:	MOV	[SI],AL
	INC	SI
	INC	DI
	DEC	DX
	JNZ	NREAD1
	MOV	PGPTR,SI
	JMP	SHORT PGEXIT

;NWRITE - PUT one line of the array at the current point.
NWRITE:	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	ES
	CALL	PGSET
	MOV	SI,PGPTR
NWRT1:	MOV	BL,[SI]			;BL = data, BH = its mask
	INC	SI
	MOV	BH,0FFH
	CMP	DX,1
	JNE	NWRT2
	MOV	BH,BYTE PTR PGLAST
NWRT2:	MOV	AL,BL			;The part in this byte
	MOV	AH,BH
	SHR	AL,CL
	SHR	AH,CL
	CALL	PUTOP
	OR	CL,CL
	JZ	NWRT3
	MOV	AL,BL			;The part in the next
	MOV	AH,BH
	PUSH	CX
	NEG	CL
	ADD	CL,8
	SHL	AL,CL
	SHL	AH,CL
	POP	CX
	INC	DI
	CALL	PUTOP
	DEC	DI
NWRT3:	INC	DI
	DEC	DX
	JNZ	NWRT1
	MOV	PGPTR,SI
PGEXIT:	POP	ES
	POP	DI
	POP	SI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET

;PUTOP - combine AL into ES:[DI] where AH has bits, by PUT's action
PUTOP:	OR	AH,AH
	JZ	PUTOPX
	PUSH	BX
	MOV	BL,ES:[DI]
	MOV	BH,BYTE PTR PGOP
	CMP	BH,1
	JE	PUTAN			;1 AND
	JB	PUTOR			;0 OR
	CMP	BH,3
	JE	PUTST			;3 PSET
	JB	PUTPR			;2 PRESET
	XOR	AL,BL			;4 XOR
	JMP	SHORT PUTST
PUTPR:	NOT	AL
	JMP	SHORT PUTST
PUTOR:	OR	AL,BL
	JMP	SHORT PUTST
PUTAN:	AND	AL,BL
PUTST:	AND	AL,AH			;New bits where AH, old elsewhere
	NOT	AH
	AND	BL,AH
	OR	AL,BL
	MOV	ES:[DI],AL
	POP	BX
PUTOPX:	RET

	SUBTTL	Sound

;DONOTE - AL = 0: play CX hertz for DX 2.5 ms, waiting until done;
;         AL = 1: queue it and go on; AL = 255: silence, empty the queue.
; CF set if the parameters are wrong.  All registers preserved.
DONOTE:	PUSH	AX
	PUSH	BX
	CMP	AL,255
	JNE	DONOT1
	CLI
	MOV	CS:SNDCNT,0
	MOV	CS:SNDHD,0
	MOV	CS:SNDTL,0
	MOV	CS:SNDREM,0
	CALL	SPKOFF
	CALL	TMRSLW
	STI
	JMP	SHORT DONOTX
DONOT1:	CMP	AL,1
	JA	DONOTE2
	OR	DX,DX
	JZ	DONOTX			;Nothing to play
DONOT2:	CMP	CS:SNDCNT,NOTEQ		;Wait for room
	JB	DONOT3
	TEST	BYTE PTR MSDCCF,0FFH
	JNZ	DONOTX			;Ctrl-Break
	JMP	SHORT DONOT2
DONOT3:	CLI
	MOV	BX,CS:SNDTL
	MOV	WORD PTR CS:SNDQ[BX],CX
	MOV	WORD PTR CS:SNDQ[BX+2],DX
	ADD	BX,4
	AND	BX,NOTEQ*4-1
	MOV	CS:SNDTL,BX
	INC	CS:SNDCNT
	CALL	TMRFST			;Start the timer, if it is slow
	STI
	OR	AL,AL
	JNZ	DONOTX			;Background: done
DONOT4:	CMP	CS:SNDCNT,0		;Foreground: wait for it to finish
	JNE	DONOT5
	CMP	CS:SNDREM,0
	JE	DONOTX
DONOT5:	TEST	BYTE PTR MSDCCF,0FFH
	JZ	DONOT4
DONOTX:	POP	BX
	POP	AX
	CLC
	RET
DONOTE2:POP	BX
	POP	AX
	STC
	RET

;SPKOFF - the speaker off
SPKOFF:	IN	AL,61H
	AND	AL,0FCH
	OUT	61H,AL
	RET

;TMRFST, TMRSLW - channel 0 at 400 a second, or back at 18.2.
; Interrupts off.
TMRFST:	CMP	CS:SNDFST,0
	JNE	TMRFX
	MOV	CS:SNDFST,1
	MOV	CS:SNDACC,0
	MOV	AL,36H
	OUT	43H,AL
	MOV	AL,TIMFRQ AND 255
	OUT	40H,AL
	MOV	AL,TIMFRQ/256
	OUT	40H,AL
TMRFX:	RET
TMRSLW:	CMP	CS:SNDFST,0
	JE	TMRFX
	MOV	CS:SNDFST,0
	MOV	AL,36H
	OUT	43H,AL
	XOR	AL,AL
	OUT	40H,AL
	OUT	40H,AL
	RET

;TMRISR - the timer interrupt.  While music plays it comes 400 times a
; second; the BIOS's own routine still gets 18.2 a second.
TMRISR:	CMP	CS:SNDFST,0
	JNE	TMRI1
	JMP	DWORD PTR CS:OLD08		;Slow: only the BIOS's
TMRI1:	PUSH	AX
	PUSH	BX
	PUSH	DX
	CMP	CS:SNDREM,0
	JE	TMRI2
	DEC	CS:SNDREM
	JNZ	TMRI5			;The note goes on
TMRI2:	CMP	CS:SNDCNT,0		;Next note
	JNE	TMRI3
	CALL	SPKOFF			;None: silence, slow down
	JMP	SHORT TMRI5
TMRI3:	MOV	BX,CS:SNDHD
	MOV	DX,WORD PTR CS:SNDQ[BX+2]
	MOV	CS:SNDREM,DX
	MOV	BX,WORD PTR CS:SNDQ[BX]	;Frequency, 0 = pause
	ADD	CS:SNDHD,4
	AND	CS:SNDHD,NOTEQ*4-1
	DEC	CS:SNDCNT
	CALL	SPKOFF
	OR	BX,BX
	JZ	TMRI5
	CMP	BX,19			;(below 19 Hz the count overflows)
	JB	TMRI5
	MOV	DX,12H			;1193180 / frequency
	MOV	AX,34DCH
	DIV	BX
	MOV	BX,AX
	MOV	AL,0B6H
	OUT	43H,AL
	MOV	AL,BL
	OUT	42H,AL
	MOV	AL,BH
	OUT	42H,AL
	IN	AL,61H
	OR	AL,3
	OUT	61H,AL
TMRI5:	ADD	CS:SNDACC,TIMFRQ	;Time for the BIOS's tick?
	JB	TMRI7
	CMP	CS:SNDREM,0
	JNE	TMRI6
	CMP	CS:SNDCNT,0
	JNE	TMRI6
	CALL	TMRSLW			;All played: slow again
TMRI6:	MOV	AL,20H
	OUT	20H,AL
	POP	DX
	POP	BX
	POP	AX
	IRET
TMRI7:	POP	DX
	POP	BX
	POP	AX
	JMP	DWORD PTR CS:OLD08

	SUBTTL	Light pen and joysticks

;RDPEN - AL = 254: PEN ON, 255: PEN OFF.  AL = 0: BX nonzero if the pen
; has been down since the last time.  AL = 1-9: BX = PEN(AL).
RDPEN:	CMP	AL,254
	JB	RDPEN1
	SUB	AL,255
	NEG	AL			;254 -> 1, 255 -> 0
	MOV	BYTE PTR PENON,AL
	RET
RDPEN1:	PUSH	AX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	AX
	MOV	AH,4
	PUSH	BP
	INT	10H
	POP	BP
	OR	AH,AH
	JZ	RDPEN2
;Down: PEN 1,2 and 6,7 (where it was activated) and 4,5 and 8,9 (last
; valid) all become this position.
	MOV	BYTE PTR PENDWN,1
	XOR	CL,CL			;CH = Y
	XCHG	CH,CL
	INC	DH			;Rows and columns from 1
	INC	DL
	MOV	SI,OFFSET PENVAL
	MOV	[SI],BX			;1: X
	MOV	[SI+2],CX		;2: Y
	MOV	[SI+6],BX		;4: X
	MOV	[SI+8],CX		;5: Y
	XOR	AH,AH
	MOV	AL,DH
	MOV	[SI+10],AX		;6: row
	MOV	[SI+14],AX		;8: row
	MOV	AL,DL
	MOV	[SI+12],AX		;7: column
	MOV	[SI+16],AX		;9: column
	MOV	AL,0FFH
	JMP	SHORT RDPEN3
RDPEN2:	XOR	AL,AL
RDPEN3:	POP	CX			;CL = function
	CMP	CL,3
	JNE	RDPEN4
	CBW				;3: -1 down now, 0 up
	MOV	BX,AX
	JMP	SHORT RDPENX
RDPEN4:	OR	CL,CL
	JNZ	RDPEN5
	XOR	BX,BX			;0: down since last time
	XCHG	BL,BYTE PTR PENDWN
	JMP	SHORT RDPENX
RDPEN5:	MOV	BL,CL
	XOR	BH,BH
	DEC	BX
	SHL	BX,1
	MOV	BX,PENVAL[BX]
RDPENX:	POP	SI
	POP	DX
	POP	CX
	POP	AX
	RET

;RDTRIG - AL = trigger 0-3 (A1, B1, A2, B2), AH = 1 for "pressed since
; last read".  AL = 1 if pressed, else 0.
RDTRIG:	PUSH	BX
	PUSH	CX
	PUSH	DX
	MOV	BL,AL
	XOR	BH,BH
	MOV	CL,BYTE PTR CS:TRGBIT[BX]
	MOV	DX,201H
	IN	AL,DX
	NOT	AL			;Pressed reads 0
	AND	AL,0F0H
	OR	BYTE PTR TRGLAT,AL	;Remember any pressed
	OR	AH,AH
	JZ	RDTRG1
	MOV	AL,BYTE PTR TRGLAT
	MOV	CH,CL
	NOT	CH
	AND	BYTE PTR TRGLAT,CH	;Read: forget
RDTRG1:	AND	AL,CL
	JZ	RDTRG2
	MOV	AL,1
RDTRG2:	POP	DX
	POP	CX
	POP	BX
	RET
TRGBIT	DB	10H,40H,20H,80H

;RDSTIK - AL = 0: read both joysticks, BX = A's X.  1, 2, 3: BX = A's Y,
; B's X, B's Y, as read then.  CF set if AL is more than 3.
RDSTIK:	CMP	AL,3
	JA	RDSTKE
	OR	AL,AL
	JNZ	RDSTK3
	PUSH	AX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	MOV	DX,201H
	CLI
	OUT	DX,AL			;Start the four timers
	XOR	CX,CX
	MOV	SI,OFFSET STKVAL
	MOV	WORD PTR [SI],0
	MOV	WORD PTR [SI+2],0
	MOV	WORD PTR [SI+4],0
	MOV	WORD PTR [SI+6],0
RDSTK1:	IN	AL,DX
	AND	AL,0FH
	JZ	RDSTK2			;All four done
	TEST	AL,1
	JZ	RDSTKA
	INC	WORD PTR [SI]
RDSTKA:	TEST	AL,2
	JZ	RDSTKB
	INC	WORD PTR [SI+2]
RDSTKB:	TEST	AL,4
	JZ	RDSTKC
	INC	WORD PTR [SI+4]
RDSTKC:	TEST	AL,8
	JZ	RDSTKD
	INC	WORD PTR [SI+6]
RDSTKD:	LOOP	RDSTK1			;(no joystick: give up)
RDSTK2:	STI
	POP	SI
	POP	DX
	POP	CX
	POP	AX
RDSTK3:	MOV	BL,AL
	XOR	BH,BH
	SHL	BX,1
	MOV	BX,STKVAL[BX]
	CLC
	RET
RDSTKE:	STC
	RET

	SUBTTL	The printer

;SNDLPT - AL to printer AH (0-2).  AH = 0, or 1 not there, 2 timed out,
; 3 out of paper.  A time-out is tried three times, as RETBIO.COM's PRN does.
SNDLPT:	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	ES
	MOV	BL,AH
	MOV	BH,0
	MOV	DX,BX
	SHL	BX,1
	MOV	CX,BIOSDS
	MOV	ES,CX
	MOV	AH,1
	CMP	WORD PTR ES:[BX+8],0
	JE	SNDLPX			;No such port
	MOV	CX,3
SNDLP0:	PUSH	AX
	MOV	AH,0
	INT	17H
	MOV	BL,AH
	POP	AX
	MOV	AH,3
	TEST	BL,20H
	JNZ	SNDLPX			;Out of paper
	MOV	AH,1
	TEST	BL,8
	JNZ	SNDLPX			;I/O error: not there
	MOV	AH,0
	TEST	BL,1
	JZ	SNDLPX
	MOV	AH,2			;Timed out
	LOOP	SNDLP0
SNDLPX:	POP	ES
	POP	DX
	POP	CX
	POP	BX
	RET

	SUBTTL	The serial ports
;
; Received bytes go into a buffer for each port, filled by the port's
; interrupt; bytes are sent as soon as the port is ready.
;

;COMPTR - SI = port AH's block in the code segment
COMPTR:	MOV	SI,OFFSET COMBLK
	OR	AH,AH
	JZ	COMPTX
	ADD	SI,CBLEN
COMPTX:	RET

;MSTICK - AX milliseconds as BIOS ticks (0 stays 0)
MSTICK:	OR	AX,AX
	JZ	MSTCKX
	PUSH	DX
	PUSH	CX
	XOR	DX,DX
	MOV	CX,55
	DIV	CX
	INC	AX
	POP	CX
	POP	DX
MSTCKX:	RET

;INICOM - open a serial port.  BX = the device control block.
; Exit  - AH = 0, or an error (3 timed out), or 255 (bad file name)
INICOM:	PUSH	SI
	PUSH	DI
	PUSH	ES
	MOV	AH,BYTE PTR [BX]	;Unit
	CMP	AH,1
	JBE	SHORT ??J2358
	JMP	ICBAD
??J2358:
	CALL	COMPTR
	MOV	AL,AH
	XOR	AH,AH
	MOV	DI,AX
	SHL	DI,1
	MOV	AX,BIOSDS
	MOV	ES,AX
	MOV	DX,ES:[DI]		;The port's address
	OR	DX,DX
	JNZ	IC1
	POP	ES
	POP	DI
	POP	SI
	JMP	DERDNA			;"Device unavailable"
IC1:	MOV	CX,WORD PTR [BX+1]	;Speed: one the 8250 can be set to
	MOV	DI,OFFSET BAUDS
ICB1:	MOV	AX,CS:[DI]
	OR	AX,AX
	JNZ	SHORT ??J2377
	JMP	ICBAD
??J2377:
	CMP	AX,CX
	JE	ICB2
	ADD	DI,4
	JMP	SHORT ICB1
ICB2:	MOV	CX,CS:[DI+2]		;CX = divisor
	MOV	AL,BYTE PTR [BX+3]	;Data bits 5-8
	SUB	AL,5
	CMP	AL,3
	JBE	SHORT ??J2386
	JMP	ICBAD
??J2386:
	MOV	AH,BYTE PTR [BX+5]	;Stop bits: 0 is one
	OR	AH,AH
	JZ	ICS1
	OR	AL,4
ICS1:	MOV	AH,BYTE PTR [BX+4]	;Parity: none, odd, even, mark, space
	CMP	AH,4
	JBE	SHORT ??J2393
	JMP	ICBAD
??J2393:
	PUSH	BX
	MOV	BL,AH
	XOR	BH,BH
	OR	AL,BYTE PTR CS:PARBIT[BX]
	POP	BX
	MOV	CS:[SI+CPORT],DX
	MOV	AH,AL			;AH = line control
	ADD	DX,3			;Divisor, then line control
	MOV	AL,80H
	OUT	DX,AL
	SUB	DX,3
	MOV	AL,CL
	OUT	DX,AL
	INC	DX
	MOV	AL,CH
	OUT	DX,AL
	ADD	DX,2
	MOV	AL,AH
	OUT	DX,AL
;Timeouts, as BIOS ticks
	MOV	AX,WORD PTR [BX+8]	;CTS
	CALL	MSTICK
	MOV	CS:[SI+CCTS],AX
	MOV	AX,WORD PTR [BX+10]	;DSR
	CALL	MSTICK
	MOV	CS:[SI+CDSR],AX
	MOV	BYTE PTR CS:CMMCR,0BH	;RTS unless RS
	TEST	BYTE PTR [BX+12],2
	JZ	ICRTS
	MOV	BYTE PTR CS:CMMCR,09H
ICRTS:
;The buffer: half the space for each port
	MOV	AX,CS:COMBSZ
	SHR	AX,1
	MOV	CS:[SI+CBSIZ],AX
	MOV	CX,CS:COMBUF
	CMP	SI,OFFSET COMBLK
	JE	ICBF1
	MOV	DX,AX			;Port 2: the second half
	ADD	DX,15
	SHR	DX,1
	SHR	DX,1
	SHR	DX,1
	SHR	DX,1
	ADD	CX,DX
ICBF1:	MOV	CS:[SI+CBSEG],CX
	XOR	AX,AX
	MOV	CS:[SI+CBHD],AX
	MOV	CS:[SI+CBTL],AX
	MOV	CS:[SI+CBCNT],AX
	MOV	BYTE PTR CS:[SI+COVF],AL
;The interrupt: 0Ch (IRQ 4) for the first port, 0Bh (IRQ 3) the second
	MOV	AL,0CH
	MOV	DX,OFFSET COMIS1
	CMP	SI,OFFSET COMBLK
	JE	ICI1
	MOV	AL,0BH
	MOV	DX,OFFSET COMIS2
ICI1:	MOV	BYTE PTR CS:[SI+CIRQ],AL
	PUSH	DX
	MOV	AH,35H
	INT	21H
	MOV	CS:[SI+COLDV],BX
	MOV	CS:[SI+COLDV+2],ES
	POP	DX
	PUSH	DS
	PUSH	CS
	POP	DS
	MOV	AL,BYTE PTR CS:[SI+CIRQ]
	MOV	AH,25H
	INT	21H
	POP	DS
	MOV	DX,CS:[SI+CPORT]
	ADD	DX,4			;Modem control: DTR, RTS, OUT2
	MOV	AL,BYTE PTR CS:CMMCR
	OUT	DX,AL
	SUB	DX,4
	IN	AL,DX			;Clear what is waiting
	ADD	DX,5
	IN	AL,DX
	SUB	DX,4			;Interrupt on data received
	MOV	AL,1
	OUT	DX,AL
	MOV	CL,BYTE PTR CS:[SI+CIRQ]	;Unmask it
	SUB	CL,8
	MOV	AH,1
	SHL	AH,CL
	NOT	AH
	IN	AL,21H
	AND	AL,AH
	OUT	21H,AL
;DSR, within its timeout
	MOV	CX,CS:[SI+CDSR]
	MOV	AH,20H
	CALL	CMWAIT
	JB	ICTO
	XOR	AH,AH
	JMP	SHORT ICX
ICTO:	MOV	AH,3
	JMP	SHORT ICX
ICBAD:	MOV	AH,255
ICX:	POP	ES
	POP	DI
	POP	SI
	RET

CMMCR	DB	0
BAUDS	DW	75,1536,110,1047,150,768,300,384,600,192,1200,96
	DW	1800,64,2400,48,4800,24,9600,12,0
PARBIT	DB	0,08H,18H,28H,38H

;CMWAIT - wait up to CX ticks (0: not at all) for modem status bits AH,
; port SI.  CF set if they did not come.
CMWAIT:	JCXZ	CMWTOK
	PUSH	AX
	PUSH	BX
	PUSH	DX
	PUSH	DI
	PUSH	ES
	MOV	BX,BIOSDS
	MOV	ES,BX
	MOV	DI,ES:[6CH]		;Ticks at the start
	MOV	DX,CS:[SI+CPORT]
	ADD	DX,6			;Modem status
CMWT1:	IN	AL,DX
	AND	AL,AH
	CMP	AL,AH
	JE	CMWT2
	MOV	BX,ES:[6CH]
	SUB	BX,DI
	CMP	BX,CX
	JB	CMWT1
	STC
CMWT2:	POP	ES
	POP	DI
	POP	DX
	POP	BX
	POP	AX
	RET
CMWTOK:	CLC
	RET

;TRMCOM - close serial port AH.  AH = 0.
TRMCOM:	PUSH	CX
	PUSH	DX
	PUSH	SI
	CALL	COMPTR
	MOV	DX,CS:[SI+CPORT]
	OR	DX,DX
	JZ	TRMCX
	CLI
	MOV	CL,BYTE PTR CS:[SI+CIRQ]	;Mask the interrupt
	SUB	CL,8
	MOV	AH,1
	SHL	AH,CL
	IN	AL,21H
	OR	AL,AH
	OUT	21H,AL
	INC	DX			;No interrupts from the port
	XOR	AL,AL
	OUT	DX,AL
	ADD	DX,3			;DTR, RTS off
	OUT	DX,AL
	PUSH	DS
	MOV	AL,BYTE PTR CS:[SI+CIRQ]
	LDS	DX,DWORD PTR CS:[SI+COLDV]
	MOV	AH,25H
	INT	21H
	POP	DS
	MOV	WORD PTR CS:[SI+CPORT],0
	STI
TRMCX:	POP	SI
	POP	DX
	POP	CX
	XOR	AH,AH
	RET

;RECCOM - from serial port AH: ZF set if nothing, else AL = byte.
; AH = 0, or 1 if the buffer overflowed, 2 a parity error.
RECCOM:	PUSH	BX
	PUSH	SI
	PUSH	ES
	CALL	COMPTR
	XOR	AH,AH
	XCHG	AH,BYTE PTR CS:[SI+COVF]
	CLI
	CMP	WORD PTR CS:[SI+CBCNT],0
	JE	RECCX
	MOV	BX,CS:[SI+CBHD]
	MOV	ES,CS:[SI+CBSEG]
	MOV	AL,ES:[BX]
	INC	BX
	CMP	BX,CS:[SI+CBSIZ]
	JB	RECC1
	XOR	BX,BX
RECC1:	MOV	CS:[SI+CBHD],BX
	DEC	WORD PTR CS:[SI+CBCNT]
	OR	SP,SP			;NZ
RECCX:	STI
	POP	ES
	POP	SI
	POP	BX
	RET

;SNDCOM - AL to serial port AH.  AH = 0, or 3 timed out.
SNDCOM:	PUSH	CX
	PUSH	DX
	PUSH	SI
	CALL	COMPTR
	PUSH	AX
	MOV	CX,CS:[SI+CDSR]		;DSR, then CTS
	MOV	AH,20H
	CALL	CMWAIT
	JB	SNDCTO
	MOV	CX,CS:[SI+CCTS]
	MOV	AH,10H
	CALL	CMWAIT
	JB	SNDCTO
	MOV	DX,CS:[SI+CPORT]
	ADD	DX,5
SNDC1:	IN	AL,DX			;Wait for the transmitter
	TEST	AL,20H
	JZ	SNDC1
	SUB	DX,5
	POP	AX
	OUT	DX,AL
	XOR	AH,AH
	JMP	SHORT SNDCX
SNDCTO:	POP	AX
	MOV	AH,3
SNDCX:	POP	SI
	POP	DX
	POP	CX
	RET

;STACOM - serial port AH: DX = bytes received, CX = room left, AH = error.
STACOM:	PUSH	SI
	CALL	COMPTR
	XOR	AH,AH
	XCHG	AH,BYTE PTR CS:[SI+COVF]
	MOV	DX,CS:[SI+CBCNT]
	MOV	CX,CS:[SI+CBSIZ]
	SUB	CX,DX
	POP	SI
	RET

;The ports' interrupts
COMIS1:	PUSH	SI
	MOV	SI,OFFSET COMBLK
	JMP	SHORT COMIS
COMIS2:	PUSH	SI
	MOV	SI,OFFSET COMBLK+CBLEN
COMIS:	PUSH	AX
	PUSH	BX
	PUSH	DX
	PUSH	ES
	MOV	DX,CS:[SI+CPORT]
	OR	DX,DX
	JZ	COMISX
COMIS3:	ADD	DX,5			;Line status
	IN	AL,DX
	SUB	DX,5
	TEST	AL,1
	JZ	COMISX			;Nothing more
	TEST	AL,4
	JZ	COMIS4
	MOV	BYTE PTR CS:[SI+COVF],2	;Parity
COMIS4:	IN	AL,DX
	MOV	BX,CS:[SI+CBCNT]
	CMP	BX,CS:[SI+CBSIZ]
	JB	COMIS5
	MOV	BYTE PTR CS:[SI+COVF],1	;No room
	JMP	SHORT COMIS3
COMIS5:	MOV	BX,CS:[SI+CBTL]
	MOV	ES,CS:[SI+CBSEG]
	MOV	ES:[BX],AL
	INC	BX
	CMP	BX,CS:[SI+CBSIZ]
	JB	COMIS6
	XOR	BX,BX
COMIS6:	MOV	CS:[SI+CBTL],BX
	INC	WORD PTR CS:[SI+CBCNT]
	JMP	SHORT COMIS3
COMISX:	MOV	AL,20H
	OUT	20H,AL
	POP	ES
	POP	DX
	POP	BX
	POP	AX
	POP	SI
	IRET

;FCERRP - Illegal function call, from a routine called with the text
; pointer on the stack
	EXTRN	FCERR:NEAR
FCERRP:	JMP	FCERR

CSEG	ENDS
	END
