;===============================================================================
;
; stepper.asm		These are the values that need to be common across a ROM
;					Hence any module will link its addresses here
;					It also contains the interrupt table
;
;===============================================================================

; calculate how much filler is required to place this at the top of the image

;							   jmp   debug  goto  itab
gap			equ		0x10000 - (1*3 + 2*13 + 4*7 + 8 + $)
			ds		gap

 if gap>= 0
 	DISPLAY "Spare ROM space: ", /D, gap
 else
 	DISPLAY "ROM overrun: ", /D, -gap
 endif

stepper_start	equ		$

; local jumps
rst20		jp		snapHandler

; debugger RAM switches (see debug.asm for discussion)

 if BIOSRAM != RAM5			; client
gotoRST		MAKET	0
gotoNMI		MAKET	1
 else						; server
gotoRST		MAKET	rstLocal, rstRemote, rstExit
gotoNMI		MAKET	nmiLocal, nmiRemote, nmiExit
 endif

; function RAM switches
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
