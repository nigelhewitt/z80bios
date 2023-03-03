;===============================================================================
;
; ROM.asm		Program a section of ROM
;				see SST39SF010A.pdf
;
;===============================================================================

			db		"<ROM driver>"

; Managing the ROM address means having control of the address bus 0-14
; and we have 0-13 direct but 14 and 15 are controlled by the mapper

; SO: This code runs copied into page0
;	  With interrupts OFF
;	  With the stack also moved into page0
;	  Use page1 as the buffer to hold code to burn
; 	  The consider the ROM as 16 x 32K blocks (not 32 x 16K)
;	  use page2 as ROMeven
;	  use page3 as ROModd

remap
; Set the right blocks of ROM in pages 2 and 3
; call with block in A, uses BC
setROM		ld		c, a			; required ROM block 0-15
			ld		a, RAM0
			out		(MPGSEL0), a
			ld		a, RAM1
			out		(MPGSEL1), a
			ld		a, c			; ROM N/2
			out		(MPGSEL2), a
			inc		a				; ROM N/2 + 1
			out		(MPGSEL3), a
			ret

restoreROM	ld		a, RAM0
			out		(MPGSEL0), a
			ld		a, RAM1
			out		(MPGSEL1), a
			ld		a, RAM3
			out		(MPGSEL2), a
			ld		a, ROM0
			out		(MPGSEL3), a
			ret

; Use the sequence to read the Manufacturer ID (b) and Device ID (c)
getROMid
			xor		a				; map ROM0
			call	setROM

			ld		hl, 0x5555 + 0x8000	; get ID sequence
			ld		a, 0xaa
			ld		(hl), a
			ld		hl, 0x2aaa + 0x8000
			ld		a, 0x55
			ld		(hl), a
			ld		hl, 0x5555 + 0x8000
			ld		a, 0x90
			ld		(hl), a
			ld		a, (0)			; get manufacturer code
			ld		b, a
			ld		a, (1)			; get size code
			ld		c, a
			ld		a, 0xf0
			ld		(0), a			; leave manufacturer code mode
			jr		restoreROM

; 4K Sector erase (0-127 in A)
eraseROMsector
			ld		b, a
			and		0x80
			ret		nz
			ld		a, b
			srl		a				; /4 = rom block
			srl		a
			call	setROM			; sets up A18-15, with A14 as page2/3

			ld		hl, 0x5555 + 0x8000	; sector erase sequence
			ld		a, 0xaa
			ld		(hl), a
			ld		hl, 0x2aaa + 0x8000
			ld		a, 0x55
			ld		(hl), a
			ld		hl, 0x5555 + 0x8000
			ld		a, 0x80
			ld		(hl), a
			ld		hl, 0x5555 + 0x8000	; sector erase sequence
			ld		a, 0xaa
			ld		(hl), a
			ld		hl, 0x2aaa + 0x8000
			ld		a, 0x55
			ld		(hl), a

			ld		a, b				; block in b6-0
			and		0x07				; bits b2-0 select the 4K slot in 32K
			sla		a
			sla		a
			sla		a
			sla		a					; b6-4 are a 4K address
			or		0x80				; page 2/3
			ld		h, a
			xor		a
			ld		l, 0
			ld		a, 0x30
			ld		(hl), a

			; wait for stuff

			jr		restoreROM