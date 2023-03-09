;===============================================================================
;	macros to add things that can't or won't subroutine nicely
;===============================================================================

; Force stdio to go to the serial port and then restore it 'as was' so we can
; just stick debug things in code that may be redirecting
DOUT		macro	target				; target is 0 for stdio
			in		a, (REDIRECT)
			ld 		(Z.spare), a
			ld		a, target
			out		(REDIRECT), a
			endm
; restore previous
ROUT		macro
			ld		a, (Z.spare)
			out		(REDIRECT), a
			endm

; Diagnostic register dump to serial port (all pushed)
SNAP		macro	id
			push	af
			DOUT	0					; force serial op
			xor		a
			ld		(Z.snap_mode), a
			pop		af
			push	af					; get a pristine AF
			call	_snap
			call	stdio_str
			db		id
			db		0					; 0=NOP
			ROUT
			pop		af
			endm

; Diagnostic memory dump (all pushed)
DUMP		macro	ptr, count
			push	af
			DOUT	0					; force serial op
			push	hl
			push	de
			push	bc
			ld		hl, ptr
			ld		c, 0
			ld		de, count
			call	stdio_dump
			pop		bc
			pop		de
			pop		hl
			ROUT
			pop		af
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

; colour sequences
; to eliminate ANSI stuff redefine these as nothing
 if ALLOW_ANSI
WHITE		macro
			db		"\e[37m"
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
			ld		(Z.last_error), hl
			pop		hl
			or		a				; clear carry
			ret
			endm

; call a BIOSn function: number fn in rom
CALLBIOS	macro	ROM, FN
			push	af
			ld		a, ROM
			cp		a, 32
			jp		nc, err_badrom
			ld		(Z.cr_rom), a
			ld		a, FN
			ld		(Z.cr_fn), a
			pop		af
			di
			call	wedgeROM
			ei
			endm

// Error codes
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

; ROM functions
	define ShowLogo1		ROM1,0
	define ShowLogo2		ROM2,0
	define ShowError		ROM1,1
	define ShowHelp			ROM1,2
