;===============================================================================
;
; PIO.asm		Provide the parallel port access
;
;===============================================================================

; At reset the control byte is 0x9b all inputs
; mode 0 is simple IO
PIO_MODESET	equ		0x80		; setting modes (not setting bits)
PIO_AMODE	equ		0x60		; zero for PORT A mode 0
PIO_AIN		equ		0x10		; PORT A to input mode
PIO_CUIN	equ		0x08		; PORT C upper to input mode
PIO_BMODE	equ		0x04		; zero for PORT B mode 0
PIO_BIN		equ		0x02		; PORT B input mode
PIO_CLIN	equ		0x01		; PORT C upper bits to input mode

; single bit in C set/reset
; PIO_MODESET is zero
; b0 is the set/reset
; b3-1 encode the bit number 0-7

; Beware: writing the control word zeros the output data

			db		"<PIO driver>"

pio_init
; A as inputs (switches), B as outputs (LIGHTs), CU as outputs, CL as inputs
			ld		a, PIO_MODESET+PIO_AIN+PIO_CLIN
			out		(PIO_CON), a
			xor		a
			out		(PIO_A), a
			out		(PIO_B), a
			ld		a, %10100000	; SD select inactive. MOSI high
			out		(PIO_C), a
			ret
