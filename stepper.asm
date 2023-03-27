;===============================================================================
;
; stepper.asm		This is the table of jumps to switch between BIOS in RAM
;					pages
;
;===============================================================================

gap			equ		0x10000 - 9*3 - 14 - $
			ds		gap

	DISPLAY "Spare ROM space: ", /D, gap

			db		"STEPPER TABLE",0		; 14 chars

gotoRAM3	ex		af, af'
			ld		a, RAM3
			out		(MPGSEL3), a
			ex		af, af'
			jp		bios			; this instruction executes in RAM3

gotoRAM4	ex		af, af'
			ld		a, RAM4
			out		(MPGSEL3), a
			ex		af, af'
			jp		bios

gotoRAM5	ex		af, af'
			ld		a, RAM5
			out		(MPGSEL3), a
			ex		af, af'
			jp		bios



