;===============================================================================
;
; ROM.asm		Program a section of ROM
;				see MX29F040A.pdf
;
;===============================================================================

			db		"<ROM driver>"

; Programming the 39SP1040:
; there are four commands
; 1: Byte program
; 2: Sector erase (64Kx8 sectors) to 0xff
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

; WARNING:	I use ROM in 16K pages as that is our mapping granularity.
;			We can write bytes but only erase 64K pages.
;
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
			ld		[0x555], a
			ld		a, 0x55
			ld		[0x2aa], a
			ld		a, 0x90
			ld		[0x555], a
			ld		a, [0x0000]		; get manufacturer code
			ld		b, a
			ld		a, [0x0001]		; get device code
			ld		c, a
			ld		a, 0xf0			; reset mode
			ld		[0x000], a		; leave manufacturer code mode
			jr		restoreROM		; uses A

;-------------------------------------------------------------------------------
; eraseROMsector	64K Sector erase
;					call sector in A (0-7)
;					uses nothing
;-------------------------------------------------------------------------------

; Call with the address you were writing to in HL and while the internal state
; controller is busy bit Q6 toggles state on every read. Once it goes steady
; the job is finished.

romWait		push	af, bc
.rw1		ld		a, [hl]
			and		0x40			; bit 'Q6' which flashes
			ld		b, a
			ld		a, [hl]
			and		0x40
			cp		b
			jr		nz, .rw1
			pop		bc, af
			ret

eraseROMsector
			push	af, bc, hl
			ld		b, a			; save sector number
			and		0xf8			; must be 0-7
			jr		nz, .er1
			ld		a, b			; recover
			sla		a				; *4 = first ROMn block in that 64K
			sla		a
			call	setROM			; sets up A18-15

; send	0xaa->0x5555(b15), 0x55->0x2aaa(b15), 0x80->0x5555,
;		0xaa->0x5555, 0x55->0x2aaa
; send  0x30->(sector)b19
			ld		a, 0xaa
			ld		[0x555], a
			ld		a, 0x55
			ld		[0x2aa], a
			ld		a, 0x80
			ld		[0x555], a
			ld		a, 0xaa
			ld		[0x555], a
			ld		a, 0x55
			ld		[0x2aa], a
			ld		a, 0x30
			ld		[0x0000], a			; should trigger the erase

			ld		hl, 0
			call	romWait				; wait while busy

			call	stdio_str
			db		"\r\nErased sector: ",0
			ld		a, b
			call	stdio_decimalB
			call	stdio_str
			db		" = ROM",0
			ld		a, b
			sla		a
			sla		a
			ld		c, a
			call	stdio_decimalB
			call	stdio_str
			db		" through ROM",0
			ld		a, c
			add		a, 3
			call	stdio_decimalB

			call	restoreROM
			pop		hl, bc, af
			scf
			ret

.er1		pop		hl, bc, af
			or		a
			ret
;-------------------------------------------------------------------------------
; programROMbyte	write byte in B to HL
;					ASSUMING the ROMn is set so HL is a 0-0x7fff address
;-------------------------------------------------------------------------------
programROMbyte
			ld		a, 0xaa
			ld		[0x555], a
			ld		a, 0x55
			ld		[0x2aa], a
			ld		a, 0xa0
			ld		[0x5555], a
			ld		a, b			; data
			ld		[hl], a
			jp		romWait

;-------------------------------------------------------------------------------
; programROMblock	write BC bytes from (DE) to ROM at (HL) (15 bit address)
;					tests DE not in PAGE0 or PAGE1 as we are using that
;						  and DE+BC <=0xc000 ie all in PAGE2
;					return CY on good ending
;					ASSUMES block already erased and setROM called
;-------------------------------------------------------------------------------
programROMblock
; start with confidence checks
; we only need the 15 bits of the address as the SETROM has already been done
; but I'll check it anyway
; check ROMn
			push	hl

; check source
			bit		7, d			; must be set as we are using PAGE0/1
			jr		nz, .pb4
.pb3		pop		hl
			RETERR	ERR_OUTOFRANGE

.pb4		call	stdio_str
			db		"\r\nWriting from 0x",0
			ld		hl, de
			call	stdio_word

; check for overlap
			ld		hl, de			; source data address
			add		hl, bc			; + count
			jr		c, .pb3			; overflow
			dec		hl				; address of last byte
			ld		a, h			; sum must be <=0xbfff
			cp		0xc0			; C if <=
			jr		nc, .pb3
			call	stdio_str
			db		" count 0x",0
			ld		hl, bc
			call	stdio_word

; loop out the data
			pop		hl
.pb5		push	bc
			ld		a, [de]			; data byte
			ld		b, a
			call	programROMbyte	; B ->[HL] uses A and B
			inc		de
			inc		hl
			pop		bc
			dec		bc
			ld		a, b
			or		c
			jr		nz, .pb5
			scf						; good exit
			ret

;-------------------------------------------------------------------------------
; programROMn	call with ROM number in A
;				16K of data in PAGE2
;				returns CY on good end
;-------------------------------------------------------------------------------

programROMn
; test ROM
			ld		b, a
			and		0xe0			; test ROMn is 0-31
			jr		z, .pn2
			RETERR	ERR_BADROM

; test we are in RAM
.pn2		ld		a, [ram_test]
			or		a
			jr		nz, .pn3		; must be running in RAM
			RETERR	ERR_NOTINRAM

; set ROM
.pn3		ld		a, b			; recover the ROM number
			call	setROM			; uses nothing
			ld		bc, 0x4000		; 16K
			ld		de, 0x8000		; PAGE2
			ld		hl, 0			; destination for even ROM
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
;			(Actually ROM1 is in RAM4 and ROM2 is in RAM5)
;			put the parameters on the registers as the function writeup
;			call this via the MACRO callBIOS
;			if it returns CY all went well
;-------------------------------------------------------------------------------
;
; This function is called by the macro CALLBIOS
; The macro has put the ROM/FN in PAGE0
;
; The whole angst with wedgeRom is the fact that the stack will probably all go
; away when we change the PAGE3 memory. However I really want to keep as many
; of the register values intact for the receiving function both as input and
; output. I can't come up with a way to make it re-entrant.

wedgeROM
; set up the return page
			push	af					; save A
			ld		a, [ram_test]		; 0 for ROM and 1 for RAM
			or		a
			ld		a, ROM0
			jr		z, .cr1				; default is ROM0
			ld		a, RAM3				; return to bios in ram
.cr1		ld		[Z.cr_ret], a
			pop		af
			
; copy the interface wedge into PAGE0
			push	hl, bc, de
			ld		de, Z.bios_wedge	; destination
			ld		hl, .callingWedge	; source
			ld		bc, size_wedgeC		; count
			ldir
			pop		de, bc				; leave HL on stack
; save the SP as it is probably in PAGE3
			ld		hl, 2				; so we miss the pushed HL
			add		hl, sp
			ld		[Z.cr_sp], hl
			pop		hl
			di							; stop the CTC ticking
			ld		sp, Z.cr_stack		; 2 slots!
; and jump in with all registers as when called
			call	Z.bios_wedge		; ie: put return address in [Z.cr_stack]
			ld		sp, [Z.cr_sp]
			ei
			ret
			
; the calling wedge
.callingWedge
			ld		a, [Z.cr_rom]
			out		(MPGSEL3), a		; set which ROM in page3
			jp		PAGE3
size_wedgeC	equ		$-.callingWedge

