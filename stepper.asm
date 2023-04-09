;===============================================================================
;
; stepper.asm		These are the values that need to be common across a ROM
;					Hence any module will link its addresses here
;					It also contains the interrupt table
;
;===============================================================================

; calculate how much filler is required to place this at the top of the image

;							  sig   rst   goto  itab
gap			equ		0x10000 - (14 + 9*3 + 4*7 + 8 + $)
			ds		gap

 if gap>= 0
 	DISPLAY "Spare ROM space: ", /D, gap
 else
 	DISPLAY "ROM overrun: ", /D, -gap
 endif

stepper_start	equ		$

			db		"STEPPER TABLE",0		; 14 bytes

rst00		jp		rst00h					; 3 bytes each
rst08		jp		rst08h
rst10		jp		rst10h
rst18		jp		rst18h
rst20		jp		rst20h
rst28		jp		rst28h
rst30		jp		rst30h
rst38		jp		rst38h
nmi			jp		nmih

gotoRAM3	ld		a, RAM3			; 7T
			out		(MPGSEL3), a	; 11T
			jp		transfer		; 10T this instruction executes in RAM3

gotoRAM4	ld		a, RAM4
			out		(MPGSEL3), a
			jp		transfer

gotoRAM5	ld		a, RAM5
			out		(MPGSEL3), a
			jp		transfer

reboot		ld		a, 0
			out		(MPGEN), a
			jp		0

;-------------------------------------------------------------------------------
; interrupt table
;-------------------------------------------------------------------------------

			align	8			; 4 entries * 2 bytes per entry
iTable
			dw		int0		; CTC0	not used
			dw		int1		; CTC1  20Hz tick
			dw		int2		; UART
			dw		int3		; PPI

iVector		equ		iTable & 0xf8
			assert	(iTable & 0x07)	== 0, Interrupt vector table alignment
 if SHOW_MODULE
	 	DISPLAY "stepper size: ", /D, $-stepper_start
 endif
