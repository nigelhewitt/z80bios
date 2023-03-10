;===============================================================================
;
; PIO.asm		Provide the parallel port access
;
;===============================================================================

PIO_A		equ		PIO+0		; bits A7-A0
PIO_B		equ		PIO+1		; bits B7-B0
PIO_C		equ		PIO+2		; bits C7-C0
PIO_CON		equ		PIO+3		; control port

; At reset the control byte is 0x9b
; mode 0 is simple IO
PIO_MODESET	equ		0x80		; setting modes (not setting bits)
PIO_AMODE	equ		0x60		; zero for PORT A mode 0
PIO_AIN		equ		0x10		; PORT A to input mode
PIO_CUIN	equ		0x08		; PORT C upper to input mode
PIO_BMODE	equ		0x04		; zero for PORT B mode 0
PIO_BIN		equ		0x02		; PORT B input mode
PIO_CLIN	equ		0x01		; PORT C upper bits to input mode

; single bit in C set/reset
; PIO_MODESET is zer
; b0 is the set/reset
; b3-1 encode the bit number 0-7

; Beware: writing the control word zeros the output data

			db		"<PIO driver>"

pio_init
; port A and B as outputs, port C as inputs
;			ld		a, PIO_MODESET+PIO_CUIN+PIO_CLIN

; A as inputs (switches), B as outputs (LEDs), CU as outputs, CL as inputs
			ld		a, PIO_MODESET+PIO_AIN+PIO_CLIN
			out		(PIO_CON), a
			xor		a
			out		(PIO_A), a
			out		(PIO_B), a
			out		(PIO_C), a
			ret
