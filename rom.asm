;===============================================================================
;
; ROM.asm		Program a section of ROM
;				see SST39SF010A.pdf
;
;===============================================================================

			db		"<ROM driver>"

; Programming the 39SP1040:
; there are three commands
; 1: Byte program
; 2: Sector erase (4Kx8 sectors) to 0xff
; 3: Chip erase   (512Kx8) to 0xff

; Managing the ROM write address means having control of the address bus 0-14
; and we have 0-13 direct but 14 and 15 are controlled by the mapper.
; Hence I work in pairs of ROMn ROMn+1 space
; so the address bus 0-0x7fff corresponds to the datasheet addresses
; and other CPU operations are restricted to 0x8000-0xffff which will not
; activate the ROM CE

; SO: This code runs copied into RAM (ie: JP1 fitted boot mode)
;	  With interrupts OFF
;	  With the stack moved in PAGE3
;	  Use PAGE2 as the buffer to hold code to burn
; 	  Then consider the ROM as 16 x 32K blocks (not 32 x 16K)
;	  use page0 as ROMeven
;	  use page1 as ROModd

;-------------------------------------------------------------------------------
; setROM	Set the right blocks of ROM in pages 0 and 1
;			call with ROMn block in A
;			uses nothing
;-------------------------------------------------------------------------------
setROM		push	bc
			and		0x1e			; mask to even ROMn
			ld		c, a
			out		(MPGSEL0), a	; ROMn in PAGE0
			inc		a
			out		(MPGSEL1), a	; ROMn+1 in PAGE1
			ld		a, c
			pop		bc
			ret

;-------------------------------------------------------------------------------
; restoreROM	restore normal service on PAGE0 and PAGE1
;				uses A
;-------------------------------------------------------------------------------
restoreROM	ld		a, RAM0
			out		(MPGSEL0), a
			ld		a, RAM1
			out		(MPGSEL1), a
			ret

;-------------------------------------------------------------------------------
; getROMid	Use the sequence to return the Manufacturer ID in B and
;			the Device ID in  C
;			uses A
;-------------------------------------------------------------------------------
getROMid
			xor		a				; map ROM0
			call	setROM

// send 0xaa -> 0x5555(15b), 0x55 -> 0x2aaa(15b), 0x90 -> 0x5555(15b)
// read 0x00000(19b)->Manufacturers ID
// read 0x00001(19b)->Device code (this requires BIOS0 selected)
// send 0xf0 -> anywhere

			ld		a, 0xaa		; get ID sequence
			ld		(0x5555), a
			ld		a, 0x55
			ld		(0x2aaa), a
			ld		a, 0x90
			ld		(0x5555), a
			ld		b, (0)			; get manufacturer code
			ld		c, (1)			; get device code
			ld		a, 0xf0
			ld		(0), a			; leave manufacturer code mode
			jr		restoreROM

;-------------------------------------------------------------------------------
; eraseROMsector	4K Sector erase
;					call sector in A (0-127)
;					uses A, BC
;-------------------------------------------------------------------------------
eraseROMsector
			ld		b, a			; save
			and		0x80
			ret		nz
			ld		a, b			; recover
			srl		a				; /4 = ROMn block
			srl		a
			call	setROM			; sets up A18-15

; send	0xaa->0x5555(b15), 0x55->0x2aaa(b15), 0x80->0x5555,
;		0xaa->0x5555, 0x55->0x2aaa
; send  0x30->(sector)b19
			ld		a, 0xaa
			ld		(0x5555), a
			ld		a, 0x55
			ld		(0x2aaa), a
			ld		a, 0x80
			ld		(0x5555), a
			ld		a, 0xaa
			ld		(0x5555), a
			ld		a, 0x55
			ld		(0x2aaa), a

			ld		a, b				; block in b6-0
			and		0x07				; bits b2-0 select the 4K slot in 32K
			sla		a					; *16
			sla		a
			sla		a
			sla		a					; b6-4 are a 4K address
			ld		h, a				; sector address
			xor		a
			ld		l, 0
			ld		a, 0x30
			ld		(hl), a

			; wait 25mS

			jr		restoreROM


;-------------------------------------------------------------------------------
; programROMbyte	write byte in B to HL
;					ASSUMING the ROMn is set so HL is a 0-0x7fff address
;-------------------------------------------------------------------------------
programROMbyte
			ld		a, 0xaa
			ld		(0x5555), a
			ld		a, 0x55
			ld		(0x2aaa), a
			ld		a, 0xa0
			ld		(0x5555), a
			ld		a, b			; data
			ld		(hl), a
			and		0x80			; bit7
			ld		b, a

.prb1		ld		a, (hl)
			and		0x80			; bit7
			cp		b
			jr		nz, .prb1		; wait for match
			ret
;-------------------------------------------------------------------------------
; programROMblock	write BC bytes from (DE) to ROM at A:HL
;					tests DE not in PAGE0 or PAGE1 as we are using that
;						  and DE+BC <=0xc000 ie all in PAGE2
;					return CY on good ending
;					ASSUMES block already erased
;-------------------------------------------------------------------------------
programROMblock
; start with confidence checks
			and		0xf8			; must not be set for legal ROM address
			jr		z, .pb2			; must be legal ROMn address
.pb1		or		a				; clear carry = bad end
			ret
.pb2		bit		7, d			; must be set as we are using PAGE0/1
			jr		z, .pb1
			push	hl
			ld		hl, de
			add		hl, bc
			pop		hl
			jr		c, .pb1
			ld		a, h
			and		0xc0
			jr		nz, .pb1

.pb3		ld		a, (de)			; data byte
			ld		b, a
			call	programROMbyte
			inc		de
			inc		hl
			dec		bc
			ld		a, b
			or		c
			jr		nz, .pb3
			scf
			ret

;-------------------------------------------------------------------------------
; programROMn	call with ROM number in A
;				16K of data in PAGE2
;				returns CY on good end
;-------------------------------------------------------------------------------

programROMn
; erase the 4 sectors
			ld		b, a
			and		0xe0			; ROMn is 0-31
			jr		z, .pn2
.pn1		or		a				; clear CY
			ret						; bad end
.pn2		sla		a				; convert to sector number 0-124
			sla		a
			call	eraseROMsector
			inc		a
			call	eraseROMsector
			inc		a
			call	eraseROMsector
			inc		a
			call	eraseROMsector

			ld		a, b			; recover the ROM number
			call	setROM
			ld		bc, 0x4000		; 16K
			ld		de, 0x8000		; PAGE2
			ld		hl, 0
			bit		0, a			; odd or even?
			jr		z, .pn3
			ld		hl, 0x4000
.pn3		call	programROMblock
			call	restoreROM
			scf
			ret

;-------------------------------------------------------------------------------
; wedgeROM	call a function in ROMn
;			put the parameters on the registers as the function writeup
;			call this via the MACRO callBIOS
;			if it returns CY all went well
;-------------------------------------------------------------------------------
	if BIOSROM == 0		; only wanted in BIOS0

; this function is called by the macro CALLBIOS
wedgeROM	; copy the interface wedge into PAGE0
	;		SNAP	"wedgeROM"
			push	bc, de, hl
			ld		de, Z.bios1_wedge	; destination
			ld		hl, .cr2			; source
			ld		bc, size_wedge		; count
			ldir
			pop		hl, de, bc
; set up the return page
			push	af
			ld		a, (ram_test)		; 0 for ROM and 1 for RAM
			or		a
			ld		a, ROM0
			jr		z, .cr1				; default is ROM0
			ld		a, RAM3				; return to bios in ram
			ld		(Z.cr_ret), a
.cr1
			pop		af
; save the SP as it is probably in PAGE3
			push	hl
			ld		hl, 2				; so we miss the push hl
			add		hl, sp
			ld		(Z.cr_sp), hl
			pop		hl
			ld		sp, PAGE3
			di							; stop the CTC ticking
; and jump in
	;		SNAP	"call wedge"
	;		DUMP	Z.bios1_wedge, size_wedge
			call	Z.bios1_wedge
	;		SNAP	"return wedge"
			ld		sp, (Z.cr_sp)
			ret
; the wedge
.cr2		push	af
			ld		a, (Z.cr_rom)
			out		(MPGSEL3), a	; set which ROM in page3
			pop		af
			call	PAGE3
			push	af
			ld		a, (Z.cr_ret)
			out		(MPGSEL3), a
			pop		af
			ret
size_wedge	equ		$-.cr2
	endif

