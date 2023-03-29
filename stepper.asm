;===============================================================================
;
; stepper.asm		This is the table of jumps to switch between BIOS in RAM
;					pages
;
;===============================================================================

gap			equ		0x10000 - 7*3 - 14 - $
			ds		gap

 if gap>= 0
 	DISPLAY "Spare ROM space: ", /D, gap
 else
 	DISPLAY "ROM overrun: ", /D, -gap
 endif
			db		"STEPPER TABLE",0		; 14 chars

gotoRAM3	ld		a, RAM3			; 7T
			out		(MPGSEL3), a	; 11T
			jp		bios			; 10T this instruction executes in RAM3

gotoRAM4	ld		a, RAM4
			out		(MPGSEL3), a
			jp		bios

gotoRAM5	ld		a, RAM5
			out		(MPGSEL3), a
			jp		bios



