;===============================================================================
;
; ROM.asm		Program a section of ROM
;				see SST39SF010A.pdf
;
;===============================================================================

			db		"<ROM driver>"

; Programming the 39SP1040:
; there are four commands
; 1: Byte program
; 2: Sector erase (4Kx8 sectors) to 0xff
; 3: Chip erase   (512Kx8) to 0xff
; 4: Read the on chip ID values (Manufacturer and Device)

; Managing the ROM write address means having control of the address bus 0-14
; and we have 0-13 direct but 14 and 15 are controlled by the mapper.
; Hence I work in pairs of ROMn ROMn+1 space aka even and odd
; map ROMn into PAGE0, ROMn+1 into PAGE1 and RAM into PAGE2 and PAGE3.
; So the address bus 0-0x7fff corresponds to the datasheet addresses (0-14)
; and other CPU operations (execution and memory access) are restricted to
; 0x8000-0xffff which will not activate the ROM CE

; SO: This code runs copied into RAM (ie: JP1 fitted boot to RAM mode)
;	  With interrupts OFF
;	  With the stack moved in PAGE3
;	  Use PAGE2 as the buffer to hold code to burn
; 	  Then consider the ROM as 16 x 32K blocks (not 32 x 16K)
;	  use PAGE0 as ROMeven
;	  use PAGE1 as ROModd

;-------------------------------------------------------------------------------
; setROM	Set the right blocks of ROM in pages 0 and 1
;			call with ROMn block in A
;			uses nothing
;-------------------------------------------------------------------------------
setROM		push	bc				; ROMn = 0-31 aka 0x00-0x1f
			ld		c, a			; save
			and		0x1e			; mask to even ROMn (0-30 in even numbers)
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
;			must run with interrupts off
;-------------------------------------------------------------------------------
getROMid	xor		a				; map in ROM0/ROM1
			call	setROM

// send 0xaa -> 0x5555(15b), 0x55 -> 0x2aaa(15b), 0x90 -> 0x5555(15b)
// read 0x00000(19b)->Manufacturers ID (19b requires BIOS0 selected)
// read 0x00001(19b)->Device code
// send 0xf0 -> anywhere

			ld		a, 0xaa			; run the ID sequence
			ld		[0x5555], a
			ld		a, 0x55
			ld		[0x2aaa], a
			ld		a, 0x90
			ld		[0x5555], a
			ld		a, [0x0000]		; get manufacturer code
			ld		b, a
			ld		a, [0x0001]		; get device code
			ld		c, a
			ld		a, 0xf0
			ld		[0], a			; leave manufacturer code mode
			jr		restoreROM		; uses A

;-------------------------------------------------------------------------------
; eraseROMsector	4K Sector erase
;					call sector in A (0-127)
;					uses nothing and doesn't know if it succeeded
;-------------------------------------------------------------------------------
delay1ms			; ie CPUCLK (10000) T states
					; the routine adds up to 63+(ND-1)*13+MD*3323+OD*4
					;		= 50+ND*13+MD*3323
MD			equ		(CPUCLK-50)/3323
ND			equ		((CPUCLK-50)%3323)/13
OD			equ		(((CPUCLK-50)%3323)%13)/4
					; so that should get us within 3T of 1mS in 11 bytes

							; the call cost T=17
			push	bc		; T=11
			ld		b, ND	; T=7
			djnz	$		; T=(N-1)*13+8
 if MD > 0
	.(MD)	djnz	$		; T=MD*(255*13+8) = MD*3323
 endif
 if OD > 0
 	.(OD)	nop				; T=4
 endif
			pop		bc		; T=10
			ret				; T=10

eraseROMsector
			push	af, bc, hl
			ld		b, a			; save
			and		0x80			; must be 0-127
			jr		nz, .er2
			ld		a, b			; recover
			srl		a				; /4 = ROMn block
			srl		a
			call	setROM			; sets up A18-15

; send	0xaa->0x5555(b15), 0x55->0x2aaa(b15), 0x80->0x5555,
;		0xaa->0x5555, 0x55->0x2aaa
; send  0x30->(sector)b19
			ld		a, 0xaa
			ld		[0x5555], a
			ld		a, 0x55
			ld		[0x2aaa], a
			ld		a, 0x80
			ld		[0x5555], a
			ld		a, 0xaa
			ld		[0x5555], a
			ld		a, 0x55
			ld		[0x2aaa], a

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
			ld		[hl], a				; should trigger the erase
; wait 25mS
			push	bc
			ld		b, 25
.er1		call	delay1ms
			djnz	.er1
			pop		bc

			call	stdio_str
			db		"\r\nErased sector ",0
			ld		a, b
			call	stdio_decimalB
			call	restoreROM
.er2		pop		hl, bc, af
			ret
;-------------------------------------------------------------------------------
; programROMbyte	write byte in B to HL
;					ASSUMING the ROMn is set so HL is a 0-0x7fff address
;-------------------------------------------------------------------------------
programROMbyte
			ld		a, 0xaa
			ld		[0x5555], a
			ld		a, 0x55
			ld		[0x2aaa], a
			ld		a, 0xa0
			ld		[0x5555], a
			ld		a, b			; data
			ld		[hl], a
			and		0x80			; bit7
			ld		b, a

.prb1		ld		a, [hl]
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
.pb1		RETERR	ERR_BADROM
			ret
.pb2		bit		7, d			; must be set as we are using PAGE0/1
			jr		nz, .pb4
.pb3		RETERR	ERR_OUTOFRANGE
.pb4		push	hl
			ld		hl, de
			add		hl, bc
			pop		hl
			jr		c, .pb3
			ld		a, h
			and		0xc0
			jr		nz, .pb3

.pb5		ld		a, [de]			; data byte
			ld		b, a
			call	programROMbyte
			inc		de
			inc		hl
			dec		bc
			ld		a, b
			or		c
			jr		nz, .pb5
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
			and		0xe0			; test ROMn is 0-31
			jr		z, .pn2
.pn1		RETERR	ERR_BADROM
.pn2		ld		a, [ram_test]
			or		a
			jr		nz, .pn3		; must be running in RAM
			RETERR	ERR_NOTINRAM
.pn3		ld		a, b			; recover ROMn
			sla		a				; convert to sector number 0-124
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
			jr		z, .pn4			; jump if even
			ld		hl, 0x4000
.pn4		call	programROMblock
			push	af				; save CY if OK
			call	restoreROM
			pop		af
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
			ld		a, [ram_test]		; 0 for ROM and 1 for RAM
			or		a
			ld		a, ROM0
			jr		z, .cr1				; default is ROM0
			ld		a, RAM3				; return to bios in ram
			ld		[Z.cr_ret], a
.cr1
			pop		af
; save the SP as it is probably in PAGE3
			push	hl
			ld		hl, 2				; so we miss the push hl
			add		hl, sp
			ld		[Z.cr_sp], hl
			pop		hl
			ld		sp, PAGE3
			di							; stop the CTC ticking
; and jump in
	;		SNAP	"call wedge"
	;		DUMP	Z.bios1_wedge, size_wedge
			call	Z.bios1_wedge
	;		SNAP	"return wedge"
			ld		sp, [Z.cr_sp]
			ret
; the wedge
.cr2		push	af
			ld		a, [Z.cr_rom]
			out		(MPGSEL3), a	; set which ROM in page3
			pop		af
			call	PAGE3
			push	af
			ld		a, [Z.cr_ret]
			out		(MPGSEL3), a
			pop		af
			ret
size_wedge	equ		$-.cr2
	endif

