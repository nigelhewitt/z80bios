;===============================================================================
;
;   Basic definitions about the Zeta2 board
;
;===============================================================================

LEDS_EXIST		equ		0		; LEDS fitted
DIGITS_EXIST	equ		0		; digit board fitted
SDC_EXISTS		equ		1		; SDC board fitted
ALLOW_ANSI		equ		1		; Terminal accepts ANSI strings

ROM_SHIFT	equ		10*1024		; 8K How much of PAGE3 we can give to RAM
CPUCLK		equ		10000		; master clock in kHz

; IO groups base address

CTC			equ		20H			; counter timer module (Z84C30)
FDC			equ		30H			; floppy disk controller (WD37C65)
PIO			equ		60H			; Parallel Port (CP82C55A) 3 x 8 bits
UART		equ		68H			; UART (16550)
REDIRECT	equ		UART+7		; 0=stdio goes to serial 1 to (IY++)
RTC			equ		70H			; RTC (DC1302)

MPGSEL		equ		78H			; memory select registers
MPGSEL0		equ		MPGSEL+0	; page 0 0000H-3FFFH  (16K pages)
MPGSEL1		equ		MPGSEL+1	; page 1 4000H-7FFFH
MPGSEL2		equ		MPGSEL+2	; page 2 8000H-BFFFH
MPGSEL3		equ		MPGSEL+3	; page 3 C000H-FFFFH

; the 32 ROM pages are 0-31, 32 RAM pages are 32-63
MPGEN		equ		7CH			; b0 memory page enable
								; if zero all pages are ROM0
; useful page numbers
; Z80 address pages - breaking the 64K space into 4 x 16K blocks
PAGE_SIZE	equ		0x4000		; 16K
PAGE0		equ		0x0000		; 0000-3fff
PAGE1		equ		0x4000		; 4000-7fff
PAGE2		equ		0x8000		; 8000-bfff
PAGE3		equ		0xc000		; c000-ffff

; The values for the ROM/RAM pages to put into the four page select registers

ROM0		equ		0
ROM1		equ		1
ROM2		equ		2
ROM3		equ		3
ROM4		equ		4	; and on to ROM31
RAM0		equ		32
RAM1		equ		33
RAM2		equ		34
RAM3		equ		35
RAM4		equ		36	; and on to RAM31

