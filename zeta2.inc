;===============================================================================
;
;   Basic definitions for the Zeta2 board
;
;===============================================================================

; allow my additions to the Zeta2
LEDS_EXIST		equ		1		; LEDS fitted
SDC_EXISTS		equ		1		; SDC board fitted
ALLOW_ANSI		equ		1		; Terminal accepts ANSI strings
ALLOW_UTF8		equ		1		; Terminal understands UTF-8 extended chars
LIGHTS_EXIST	equ		1		; switches on PIO_A and lights on PIO_B

ROM_SHIFT	equ		9*1024		; 9K How much of PAGE3 we can give to RAM
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
ROM4		equ		4
ROM5		equ		5
ROM6		equ		6
ROM7		equ		7	; and on to ROM31
RAM0		equ		32
RAM1		equ		33
RAM2		equ		34
RAM3		equ		35
RAM4		equ		36
RAM5		equ		37
RAM6		equ		38
RAM7		equ		39	; and on to RAM31

; The PIO sub ports are needed in both ROM0 and ROM1 so they go here
PIO_A		equ		PIO+0		; bits A7-A0
PIO_B		equ		PIO+1		; bits B7-B0
PIO_C		equ		PIO+2		; bits C7-C0
PIO_CON		equ		PIO+3		; control port
SWITCHES	equ		PIO_A
LIGHTS		equ		PIO_B


