;===============================================================================
;
;	bios2		code to go in the ROM2 page that can be called
;
;===============================================================================

BIOSROM		equ			2				; which ROM page are we compiling
			include		"zeta2.inc"		; common definitions
 			include		"macros.inc"
			include		"vt.inc"

			org		PAGE3
			jp		bios2
			db		"BIOS2 ", __DATE__, " ", __TIME__, 0


bios2		push	hl, bc, af
			ld		a, [Z.cr_fn]		; function number
			cp		bios2_count			; number of functions
			jp		nc, f_bad
			ld		hl, bios2_functions
			ld		b, 0				; function number in BC
			ld		c, a				; then double it to word pointer
			sla		c					; 0->b0, b7->cy
			rl		b					; through carry
			add		hl, bc
			ld		a, [hl]				; ld  hl, (hl)
			inc		hl
			ld		h, [hl]
			ld		l, a
			pop		af, bc				; restore AF and BC
			ex		[sp], hl			; restore HL, put 'goto' address on SP
			ret							; aka POP PC

bios2_functions
			dw		f_biosver			; 0
			dw		f_trap				; 2
			dw		f_kill				; 3
bios2_count	equ		($-bios2_functions)/2

ram_test	db		0
f_biosver	ld		a, 1
			ld		[ram_test], a
			call	stdio_str			; uses nothing
			RED
			db		"BIOS2 loaded "
			db		__DATE__
			db		" "
			db		__TIME__
			db		0
			ld		a, [ram_test]
			or		a
			jr		z, .fb1
			call	stdio_str
			BLUE
			db		" in RAM",0
.fb1		call	stdio_str
			WHITE
			db		"\r\n", 0
			
; exit paths from handlers
f_good		scf
			ret

f_trap		jr		f_good

f_kill
f_bad
			or		a					; clear carry
			ret
