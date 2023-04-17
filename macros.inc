;===============================================================================
;	macros to add things that can't or won't subroutine nicely
;===============================================================================

; Take the current RAM number and the offset in that  RAM and return C:HL
; offset in RAM/ROM = offset16 & 0x3fff
; I swap RAM and ROM in the mapper to make ROM addresses low by complementing
; the RAM/ROM CS bit 0x20
; start of ROM/RAM = (RAM ^ 0x20)*0x4000
; so address = (RAM^0x20)*0x4000 + offset

MAKE20		macro	RAMn, offset16
			ld		c, (RAMn ^ 0x20) >> 2
			ld		hl, ((offset16 & 0x3fff) | (RAMn << 14)) & 0xffff
			endm

; Diagnostic register dump to serial port (all pushed)
SNAP		macro	id
			push	af
			xor		a
			ld		[Z.snap_mode], a
			pop		af
			push	af					; get a pristine AF
			call	_snap
			call	stdio_str
			db		id,0
			pop		af
			endm

; Pause until a key is pressed
PAUSE		macro	text
			push	af
			call	stdio_str
			db		text,0
			call	stdio_getc
			pop		af
			endm

; Diagnostic memory dump from ptr24 for count (all pushed)
; use 0xff0000+offset to force the mapper off and get whatever is mapped in
DUMP		macro	ptr24, count
			push	af, hl, de, bc
			ld		hl, ptr24 & 0xffff
			ld		c, ptr24 >> 16
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl, af
			endm

; as above but takes a register:double register as the pointer eg C:HL
DUMPrr		macro	r, rr, count
			push	af, hl, de, bc
			ld		hl, rr
			ld		c, r
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl, af
			endm

; as above but takes a bunch of parts to find the address
DUMPpg		macro	RAMn, offset, count
			push	af, hl, de, bc
			MAKE20	RAMn, offset
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl, af
			endm

; as above but does not do mapping hence does not reset the mapping registers
; offset is 16 bits

DUMP0		macro	offset16, count
			push	af, hl, de, bc
			ld		hl, offset16
			ld		c, 0xff				; local memory
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl ,af
			endm

; Crash And Burn
CAB			macro	obituary
			SNAP	obituary
			jp		good_end			; reset stack
			endm

; Get some auto variables on the stack C style
; returns IY as pointer to the first byte
AUTO		macro	nbytes
			push	iy
			ld		iy, -nbytes
			add		iy, sp
			ld		sp, iy
			endm
RELEASE		macro	nbytes
			ld		iy, nbytes
			add		iy, sp		; beware DOES NOT preserve flags
			ld		sp, iy
			pop		iy
			endm

; A rather last ditch trick to swap two registers when I have totally run out
; of space for whatever it is I am doing
SWAP		macro	r1, r2
	rept
			rr		r1			; eight shifts and it even puts carry back
			rr		r2
	endr
			endm

; colour sequences
; to eliminate ANSI stuff redefine these as nothing
 if ALLOW_ANSI
WHITE		macro
			db		"\e[97m"
			endm
RED			macro
			db		"\e[91m"			; bright red actually
			endm
GREEN		macro
			db		"\e[92m"
			endm
BLUE		macro
			db		"\e[94m"
			endm
YELLOW		macro
			db		"\e[93m"
			endm
 else
WHITE		macro
			endm
RED			macro
			endm
GREEN		macro
			endm
BLUE		macro
			endm
YELLOW		macro
			endm
 endif

; return NC (=err) putting N in Z.last_error
RETERR		macro	nerr
			push	hl
			ld		hl, nerr
			ld		[Z.last_error], hl
			pop		hl
			or		a				; clear carry
			ret
			endm

; call a function: number fn in rom
CALLFAR		macro	RAM, FN
			push	hl					; 11T
			ld		hl, RAM | (FN<<8)	; 10T
			ld		[Z.cr_ram], hl		; 20T H goes in Z.cr_fn
			pop		hl					; 10T
			call	wedgeROM			; 17T see router.asm
			endm

; make an address20 in A:HL from a ROMn/RAMn code and a 14 bit address:
MAKEA20		macro	PAGE, ADDR14
			ld		hl, ADDR14
			sla		h			; push bits 14-15 out of H
			sla		h
			ld		a, PAGE		; get the ROM/RAM id
			xor		0x20		; toggle the ROM/RAM bit
			rr		a			; slide the address bits back down
			rr		h
			rr		a
			rr		h
			endm

;-------------------------------------------------------------------------------
; a simple conveniences with maths
;-------------------------------------------------------------------------------

; DJNZ but far not relative
djnzF		macro	target
			dec		b
			jp		nz, target
			endm

; compare HL to N : return Z for HL==N, NC for HL>=N CY for HL<N uses A
; (same results as with A in CP N)
CPHL		macro	n
			ld		a, h
			cp		high n
			jr		nz, .cphl1	; n<HL so return NC and NZ
			ld		a, l		; we get here on h == high n
			cp		low n		; setCY and Z flags on L
.cphl1
			endm
CPDE		macro	n
			ld		a, d
			cp		high n
			jr		nz, .cphl1	; n<DE so return NC and NZ
			ld		a, e		; we get here on h == high n
			cp		low n		; setCY and Z flags on L
.cphl1
			endm

SUBDE		macro	n
			ld		a, e
			sub		a, low n
			ld		e, a
			ld		a, d
			sbc		a, high n
			ld		d, a
			endm
;-------------------------------------------------------------------------------
;	Now a bunch of things to mange 32 bit
;		all use DE:HL
;-------------------------------------------------------------------------------
; Load DE:HL from addr16
GET32		macro	addr16
			ld		hl, [addr16]
			ld		de, [addr16+2]
			endm

; save DE:HL to addr16
PUT32		macro	addr16
			ld		[addr16], hl
			ld		[addr16+2], de
			endm

; compare 32 bit value in DE:HL with a constant
CP32n		macro	value32					; for = return z
			ld		a, d					; for < return NZ+C
			cp		(value32 >> 24) & 0xff	; for > return NZ+NC
			jr		nz, .ex
			ld		a, e
			cp		(value32 >> 16) & 0xff
			jr		nz, .ex
			ld		a, h
			cp		(value32 >> 8) & 0xff
			jr		nz, .ex
			ld		a, l
			cp		value32 & 0xff
.ex
			endm
; compare 32 bit value with a fixed addr16
CP32v		macro	addr16					; for = return z
			ld		a, [addr16+3]			; for < return NZ+C
			cp		d						; for > return NZ+NC
			jr		nz, .ex
			ld		a, [addr16+2]
			cp		e
			jr		nz, .ex
			ld		a, [addr16+1]
			cp		h
			jr		nz, .ex
			ld		a, [addr16]
			cp		l
.ex			ccf								; as I reversed the compare
			endm

; Compare DE:HL to IX or IY + offset
CP32i		macro	ir, offset
			ld		a, d
			cp		[ir+offset+3]
			jr		nz, .z1
			ld		a, e
			cp		[ir+offset+2]
			jr		nz, .z1
			ld		a, h
			cp		[ir+offset+1]
			jr		nz, .z1
			ld		a, l
			cp		[ir+offset]
.z1
			endm

; Load DE:HL from IX or IY +offset
GET32i		macro	ir, offset
			ld		l, [ir+offset]
			ld		h, [ir+offset+1]
			ld		e, [ir+offset+2]
			ld		d, [ir+offset+3]
			endm

; save DE:HL	to IX or IY +offset
PUT32i		macro	ir, offset
			ld		[ir+offset], l
			ld		[ir+offset+1], h
			ld		[ir+offset+2], e
			ld		[ir+offset+3], d
			endm


; increment DE:HL
INC32		macro
			ld		a, l
			add		a, 1
			ld		l, a
			ld		a, h
			adc		0
			ld		h, a
			ld		a, e
			adc		0
			ld		e, a
			ld		a, d
			adc		0
			ld		d, a
			endm

;-------------------------------------------------------------------------------
; Error codes
;-------------------------------------------------------------------------------

ERR_NO_ERROR			equ		0
ERR_UNKNOWN_COMMAND		equ		1
ERR_BAD_ADDRESS			equ		2
ERR_TOOMUCH				equ		3
ERR_BADBYTE				equ		4
ERR_OUTOFRANGE			equ		5
ERR_BADCOUNT			equ		6
ERR_BADPORT				equ		7
ERR_RUNOUT				equ		8
ERR_BADBLOCK			equ		9
ERR_BADDATETIME			equ		10
ERR_UNKNOWNACTION		equ		11
ERR_MANANA				equ		12
ERR_BADROM				equ		13
ERR_NOTINRAM			equ		14
ERR_BADFUNCTION			equ		15

;-------------------------------------------------------------------------------
; ROM functions
;-------------------------------------------------------------------------------
	define ShowLogo1		RAM4,0		// Show "BIOS1 loaded"
	define ShowLogo2		RAM5,0		// Show "BIOS2 loaded"
	define ShowError		RAM5,2		// Interpret error code
	define ShowHelp			RAM5,3		// Show command help
	define ReadSector		RAM4,1		// read sector BC:HL to DE
	define DIRcommand		RAM4,2		// DIR command
	define CDcommand		RAM4,3		// CD command
	define TYPEcommand		RAM4,4		// TYPE command
	define LOADcommand		RAM4,5		// LOAD command
	define ShowStack		RAM5,1		// data on stack text
	define ROMcommand		RAM5,4		// ROM programming command
	define HEXcommand		RAM5,5		// HEX command
	define WAITcommand		RAM5,6		// WAIT command
	define COPYcommand		RAM5,7		// COPY command
	define PrintCWD			RAM4,6		// print CWD
	define SetDrive			RAM4,7		// set drive
	define DEBGcommand		RAM5,8		// DEBG command
