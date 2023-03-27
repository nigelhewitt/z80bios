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
			jp		bios
logo		db		"BIOS1 ", __DATE__, " ", __TIME__, 0

bios_functions
			dw		f_biosver			; 0	show signon
			dw		f_error				; 1 interpret last_error
			dw		f_help				; 2 show command help
			dw		f_readsector		; 3 read media
			dw		f_spi_test			; 4 spi test
bios_count	equ		($-bios_functions)/2


ram_test	db		0
f_biosver	ld		a, 1
			ld		[ram_test], a
			call	stdio_str			; uses nothing
			RED
			db		"\r\nBIOS1 loaded "
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
			db		0
			jr		good_end
