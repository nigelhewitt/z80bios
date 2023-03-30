;===============================================================================
;
;	ctc.asm		Manage a Z84C30 CTC
;
;===============================================================================

CTC0		equ		CTC
CTC1		equ		CTC+1
CTC2		equ		CTC+2
CTC3		equ		CTC+3
; control bits
CTC_IE		equ		0x80		; 0=disable interrupt, 1=enable interrupt
CTC_CMODE	equ		0x40		; 0=timer mode, 1=counter mode
CTC_P256	equ		0x20		; 0=pre-scale by 16, 1=pre-scale by 256
CTC_RETRIG	equ		0x10		; 0=falling edge, 1=rising edge
CTC_PULSE	equ		0x08		; 0=automatic trigger, 1=pulse starts
CTC_TC		equ		0x04		; 0=no time constant, 1=time constant follows
CTC_RST		equ		0x02		; 0=continue, 1=software reset
CTC_CW		equ		0x01		; 0=interrupt vector, 1=control word

; the Zeta board is wired with
;			CTC0		input is CTC_CLOCK = UART_CLK/2 = 921.6KHz
;			CTC1		input is CTC0 output
;			CTC2		input is the UART_INT line
;			CTC3		input is PC3 line on the PPI its mode 1 and 2 interrupt

			db		"<CTC driver>"

ctc_init
; CTC0 to divide by 256 no interrupt gives 921.6KHz/256 = 3600Hz
			ld		a, %01010111 ; no int, counter, p16, re, auto, tc, sr, cw
			out		(CTC0), a
			xor		a			 ; 0 = 256 counter
			out		(CTC0), a
; CTC1 to divide by 72 interrupt at 50Hz
			ld		a, %11010111 ; int, counter, p16, re, auto, tc, sr, cw
			out		(CTC1), a
			ld		a, 72		 ; to give 50Hz
			out		(CTC1), a
; CTC2 interrupt on tick
			ld		a, %11010111 ; int, counter, p16, re, auto, tc, sr, cw
			out		(CTC2), a
			ld		a, 1		 ; so every time
			out		(CTC2), a
; CTC3 interrupt on tick
			ld		a, %11010111 ; no int, counter, p16, re, auto, tc, sr, cw
			out		(CTC3), a
			ld		a, 1		 ; so every time
			out		(CTC3), a
; set the interrupt vector
			ld		a, iVector	 ; iTable masked with 0x00f8
			out		(CTC0), a
			ret
