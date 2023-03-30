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
; ROM command for a bios writing systems
;-------------------------------------------------------------------------------

f_romcommand
			ld		ix, ROM5			; provisional ROM number
; obtain a ROMn number in IXL
			call	skip				; read the first non-space
			jp		z, err_runout		; we must have something
			call	isdigit				; do we have a number?
			jr		nc, .cn1			; no, process as command with default
			dec		e					; unget
			call	getdecimalB			; yes, so it's a ROM number
			jp		nc, err_outofrange	; not a byte
			ld		a, ixl
			cp		32
			jp		nc, err_outofrange	; NC on A>=N
			call	skip				; try again for a command
			jp		z, err_runout

; process a command letter
.cn1		call	islower
			jr		nc, .cn2
			and		~0x20				; to upper
.cn2		cp		'I'					; read the id bytes
			jr		z, .cn3
			cp		'P'					; prep the data
			jr		z, .cn4
			cp		'E'					; erase block
			jr		z, .cn5
			cp		'W'					; write the data
			jp		z, .cn6
			jp		err_unknownaction

; read the ID bytes
.cn3		di							; BEWARE we are taking low RAM away...
			call	getROMid			; manufacturer in B and device in C
			ei
			call	stdio_str			; expected 0xc2 0xa4 or 0xbf 0xb7
			db		"\r\nManufacturer's code: ", 0
			ld		a, b
			call	stdio_byte
			call	stdio_str
			db		"  Device code: ",0
			ld		a, c
			call	stdio_byte
			jp		good_end

; prepare the whole of PAGE2 as a test block
.cn4		ld		hl,	test_block		; source
			ld		de, PAGE2			; dest
			ld		bc, size_test
			ldir
			ld		hl, PAGE2
			ld		de, PAGE2+size_test
			ld		bc, 16*1024 - size_test
			ldir
			call	stdio_str
			db		"\r\nData at: ", 0
			ld		a, 0
			ld		hl, PAGE2
			call	stdio_20bit
			jp		.cn7				; OK

; Erase a 64K block (eg: select ROM9 and erase ROM8,9,10 and 11)
.cn5		call	stdio_str
			db		"\r\nErase sector (4xROM): ",0
			ld		a, ixl
			srl		a					; /4 to convert to a sector value
			srl		a
			call	stdio_decimalB

			di
			call	eraseROMsector
			ei
			jp		.cn7				; OK

; write a block of ROM
.cn6		ld		a, ixl
			di
			call	programROMn			; call with ROM number in A
			ei							; data is the whole of PAGE2 (=RAM2)
			jp		nc, .cn8			; bad return

			call	stdio_str
			db		"\r\nROM at: 0x", 0
			MAKEA20	ixl, 0
			ld		c, a
			call	stdio_20bit			; output C:HL in hex
			jp		good_end			; OK

; exit messages
.cn7		call	stdio_str
			db		"\r\nOK",0
			jp		good_end
.cn8		call	stdio_str
			db		"\r\nFailed", 0
			jp		bad_end

test_block	db		"Test block for ROM programming =0123456789 "
			db		"abcdefghijklmnopqrstuvwxyz "
			db		"ABCDEFGHIJKLMNOPQRSTUVWXYZ "
size_test	equ		$-test_block	; should be 97 which is a prime

