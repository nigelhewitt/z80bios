;===============================================================================
;	macros to add things that can't or won't subroutine nicely
;===============================================================================

; Force stdio to go to the serial port and then restore it 'as was' so we can
; just stick debug things in code that may be redirecting
DOUT		macro	target				; target is 0 for stdio
			in		a, (REDIRECT)
			ld 		[Z.spare], a
			ld		a, target
			out		(REDIRECT), a
			endm
; restore previous
ROUT		macro
			ld		a, [Z.spare]
			out		(REDIRECT), a
			endm

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
			DOUT	0					; force serial op
			xor		a
			ld		[Z.snap_mode], a
			pop		af
			push	af					; get a pristine AF
			call	_snap
			call	stdio_str
			db		id
			db		0					; 0=NOP
			ROUT
			pop		af
			endm

; Diagnostic memory dump from ptr24 for count (all pushed)
; use 0xff0000+offset to force the mapper off and get whatever is mapped in
DUMP		macro	ptr24, count
			push	af
			DOUT	0					; force serial op
			push	hl, de, bc
			ld		hl, ptr24 & 0xffff
			ld		c, ptr24 >> 16
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl
			ROUT
			pop		af
			endm

; as above but takes a register:double register as the pointer eg C:HL
DUMPrr		macro	r, rr, count
			push	af
			DOUT	0					; force serial op
			push	hl, de, bc
			ld		hl, rr
			ld		c, r
			ld		de, count
			call	stdio_dump
			pop		bc
			pop		de
			pop		hl
			ROUT
			pop		af
			endm

; as above but takes a bunch of parts to find the address
DUMPpg		macro	RAMn, offset, count
			push	af
			DOUT	0					; force serial op
			push	hl, de, bc
			MAKE20	RAMn, offset
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl
			ROUT
			pop		af
			endm

; as above but does not do mapping hence does not reset the mapping registers
; offset is 16 bits

DUMP0		macro	offset16, count
			push	af
			DOUT	0					; force serial op
			push	hl, de, bc
			ld		hl, offset16
			ld		c, 0xff				; local memory
			ld		de, count
			call	stdio_dump
			pop		bc, de, hl
			ROUT
			pop		af
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
 else
WHITE		macro
			endm
RED			macro
			endm
GREEN		macro
			endm
BLUE		macro
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

; call a BIOSn function: number fn in rom
CALLBIOS	macro	ROM, FN
			ld		[Z.cr_a], a		; 13T
			ld		a, FN			; 7T
			ld		[Z.cr_fn], a	; 13T
			ld		a, ROM			; 7T
			ld		[Z.cr_rom], a	; 13T
			call	wedgeROM		; 17T see router.asm
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
; compare 32 bit value in DE:HL with a constant
CP32		macro	value32					; for = return z
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

; Compare DE:HL to IX or IY +offset
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
SET32i		macro	ir, offset
			ld		[ir+offset], l
			ld		[ir+offset+1], h
			ld		[ir+offset+2], e
			ld		[ir+offset+3], d
			endm


; increment DE:HL
INC32		macro
			inc		l
			jr		nc, .z2
			inc		h
			jr		nc,	.z2
			inc		e
			jr		nc, .z2
			inc		d
.z2
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
	define COPYcommand		RAM5,7		// copy command
	define PrintCWD			RAM4,6		// print CWD
	define SetDrive			RAM4,7		// set drive