;===============================================================================
;
;	bios2		code to go in the ROM2 page that can be called
;
;===============================================================================

		DEVICE	NOSLOT64K
		PAGE	5
		SLDOPT	COMMENT WPMEM

			include		"zeta2.inc"		; common definitions
 			include		"macros.inc"
			include		"vt.inc"

BIOSROM		equ			2				; which ROM page are we compiling
BIOSRAM		equ			RAM5

			org		PAGE3
logo		db		"BIOS2 ", __DATE__, " ", __TIME__, 0

; the works of the calling mechanism is in the share file router.asm
; but it wants a table of functions and a count supplied here

bios_functions
			dw		f_biosver				; 0
			dw		f_stacktest				; 1
			dw		f_error					; 2 interpret last_error
			dw		f_help					; 3 show command help
			dw		f_romcommand			; 4 ROM command
			dw		f_hexcommand			; 5 HEX command
			dw		f_waitcommand			; 6 WAIT command
			dw		f_copycommand			; 7 COPY command
			dw		f_debug					; 8 DEBG command
bios_count	equ		($-bios_functions)/2


ram_test	db		0

f_biosver	ld		a, 1
			ld		[ram_test], a
			call	stdio_str			; uses nothing
			RED
			db		"\r\nBIOS2 loaded "
			db		__DATE__
			db		" "
			db		__TIME__
			db		0
			ld		a, [ram_test]
			or		a
			jr		z, .fb1
			call	stdio_str
			YELLOW
			db		" in RAM",0
.fb1		call	stdio_str
			WHITE
			db		0
			jp		good_end

;-------------------------------------------------------------------------------
; test dump the stack
;-------------------------------------------------------------------------------
f_stacktest
			ld		hl, [Z.cr_sp]
			DUMPrr	0xff, hl, 32
			scf
			ret						; should go to return

;-------------------------------------------------------------------------------
; HEX command
;-------------------------------------------------------------------------------
f_hexcommand
			ld		ix, [Z.def_address]		; default value
			ld		bc, [Z.def_address+2]	; !! not ld c,(...) which compiles
			call	gethex32				; in BC:IX
			jp		nc, err_badaddress		; value syntax
			ld		[Z.def_address], ix
			ld		[Z.def_address+2], bc

			push	hl						; preserve command string stuff
			call	stdio_str
			db		"\r\nhex: ",0
			ld		hl, ix
			call	stdio_32bit				; output BC:HL
			call	stdio_str
			db		" decimal: ",0
			call	stdio_decimal32			; BC:HL again
			pop		hl

			call	skip					; more data on line?
			jp		z, good_end				; none so ok
			call	stdio_str
			db		" delimited by: ",0
			dec		e						; unget

.ch1		call	getc					; echo
			jp		nc, good_end			; end of buffer
			call	stdio_putc
			jr		.ch1

;-------------------------------------------------------------------------------
; WAIT command
;-------------------------------------------------------------------------------
f_waitcommand
			in		a, (SWITCHES)
		if	LIGHTS_EXIST
			ld		b, a
			bit		6, b
			jr		z, .fw1
			ld		a, 0xff				; trigger the led strobe
			ld		[led_countdown], a	; running on the interrupts
.fw1		ld		a, b
		endif
			bit		7, a
			jr		nz, f_waitcommand
			scf
			ret

;-------------------------------------------------------------------------------
; COPY command  destination20 source 20 count16
;-------------------------------------------------------------------------------
f_copycommand
			ld		ix, 0					; default value
			ld		bc, 0
			call	gethex32				; in BC:IX
			ld		[.source], ix
			ld		a, c
			ld		[.source+2], a
			ld		ix, 0					; default value
			ld		bc, 0
			call	gethex32				; in BC:IX
			ld		[.dest], ix
			ld		a, c
			ld		[.dest+2], a
			ld		ix, 0					; default value
			call	gethexW					; in IX
			ld		[.count], ix
			ld		hl, [.source]
			ld		a, [.source+2]
			ld		c, a
			ld		de, [.dest]
			ld		a, [.dest+2]
			ld		b, a
			ld		ix, [.count]
			call	bank_ldir				; copy from C:HL to B:DE for IX counts
			jr		nc, .cc1
			scf
			ret
.cc1		or		a
			ret

; local variables
.source		d24		0
.dest		d24		0
.count		dw		0

;-------------------------------------------------------------------------------
; copied from bios.asm  - probably need thinking about
;-------------------------------------------------------------------------------

err_outofrange
			ld		a, ERR_OUTOFRANGE
cmd_err		ld		[Z.last_error], a
			jp		bad_end
err_runout
			ld		a, ERR_RUNOUT
			jr		cmd_err
err_unknownaction
			ld		a, ERR_UNKNOWNACTION
			jr		cmd_err
err_badaddress
			ld		a, ERR_BAD_ADDRESS
			jr		cmd_err

;-------------------------------------------------------------------------------
;  DEBG command
;-------------------------------------------------------------------------------
f_debug		call	stdio_str
			RED
			db		"\r\nDebug module loaded"
			WHITE
			db		0

			xor		a
			out		(LIGHTS), a

			ld		a, 0xa0
			ex		af, af'
			ld		a, 0xaf
			ex		af, af
			ld		bc, 0xbcb0
			ld		de, 0xded0
			ld		hl, 0x1234
			exx
			ld		bc, 0xcbcf
			ld		de, 0xedef
			ld		hl, 0x4321
			exx
			ld		ix, 0x2345
			ld		iy, 0x3456
			nop
			SNAPT	"prior"
			nop
			SNAP
			nop
			call	debugSetup		; enter debug control mode
			nop
			SNAP
			nop
			ld		a, 0x55
			out		(LIGHTS), a
			nop
			nop
			rst		0x28
			nop
			SNAPT	"post2"
			nop
			xor		a
			inc		a
			inc		a
			inc		a
			inc		a
			ld		ix, 1234	; 4 byte instruction
			inc		a
.back		inc		a
			inc		a
			inc		a
			inc		a
			inc		a
			SNAPT	"loop"
			inc		a
			inc		a
			inc		a
			inc		a
			inc		a
			inc		a
			in		a, (SWITCHES)
			and		0x80
			jr		nz, .back
			jp		good_end

 if SHOW_MODULE
	 	DISPLAY "bios2 size: ", /D, $-logo
 endif
