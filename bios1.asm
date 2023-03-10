;===============================================================================
;
;	bios1		code to go in the ROM1 page that can be called
;
;===============================================================================

BIOSROM		equ			1				; which ROM page are we compiling
			include		"zeta2.inc"		; common definitions
 			include		"macros.inc"
			include		"vt.inc"

			org		PAGE3
			jp		bios1
logo		db		"BIOS1 ", __DATE__, " ", __TIME__, 0

bios1_functions
			dw		f_biosver			; 0	show signon
			dw		f_error				; 1 interpret last_error
			dw		f_help				; 2 show command help
bios1_count	equ		($-bios1_functions)/2

;-------------------------------------------------------------------------------
; function router
;-------------------------------------------------------------------------------
bios1		push	hl, bc, af
			ld		a, [Z.cr_fn]		; function number
			cp		bios1_count			; number of functions
			jp		nc, f_bad
			ld		hl, bios1_functions
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

f_biosver	call	stdio_str			; uses nothing
			RED
			db		"BIOS1 loaded\r\n"
			WHITE
			db		0

; exit paths from handlers
f_good		scf
			ret

f_bad		or		a					; clear carry
			ret
