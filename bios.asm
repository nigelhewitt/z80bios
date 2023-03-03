;===============================================================================
;
;	bios.asm	The NigSoft Z80 ROM bios
;				For the Zeta 2.2 board
;				© Nigel Hewitt 2023
;
VERSION	macro :	db "v0.1.7" : endm		; version number for sign on message
;
;	compile with
;			./make.ps1
;
;   update to git repository
;		git add -u					move updates to staging area
;   	git commit -m "0.1.0"		move to local repository, use version number
;   	git push -u origin main		move to github
;
;===============================================================================

; I have two little boards tacked on to the SDC and as they are optional
; it seems right to make them optional in the code too.

LEDS_EXIST		equ		1		; LEDS fitted
DIGITS_EXIST	equ		1		; digit board fitted
SDC_EXISTS		equ		1		; SDC board fitted
ALLOW_ANSI		equ		1		; Terminal accepts ANSI strings

ROM_SHIFT		equ		0x2800	; 10K How much of PAGE3 we can give to RAM

; This code image is in page 0 of the ROM so, on boot, it is replicated in all
; four memory slots of the Zeta2 board. However I want it to run in page 3,
; at C000H to FFFFH, so it needs to hand over smoothly.

; Important notes:
; The RAM used is 512K of CMOS and hence draws little or nothing so it is
; protected by a specialist chip that uses the lithium battery to power it once
; the main supply goes out of spec. Hence non-volatile RAM!
;
; The ROM isn't ROM either in the old sense
; It is 512K of Flash with a rather step-by-step sector (4K) programming
; sequence but can still upload and flash a new bios live.
;
; All this adds up to more than the Z80s 16bit=64K address range. Hence we work
; in 16K pages. We decode the top two bits of the Z80 bus to get that as four
; 16K pages referred to as PAGE0, PAGE1 etc.
; The ROM and RAM chips provide 32 16K pages each and the four mapping
; registers that are selected by A14/15 bits can swap in any page or ROM or RAM
; into those four pages. The ROM and RAM pages are referred to as ROM0, ROM1
; etc. and these are defined in below to the correct value for the page
; registers.
;
; The system boots with ROM0 in all four pages due to the mapping system being
; turned off so you can set up the page registers before you turn it on and you
; have lots of spare space on hand.

; The RTC also stashes 31 bytes of battery backed up RAM if needed

; To program the Flash off line use the TL866 programmer:
;	see
;		D:\Archive\TL866
;		D:\Util\TL866ii\Xgpro\Xgrro.exe
;		dev: SST: SST39SF040
; The ANSI colour code I use are in
;		https://en.wikipedia.org/wiki/ANSI_escape_code
;
;===============================================================================
;
;   Basic definitions about the Zeta2 board
;
;===============================================================================

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

;===============================================================================
;	macros to add things that won't or can't subroutine nicely
;===============================================================================

; Force stdio to go to the serial port and then restore it 'as was' so we can
; just stick debug things in code that may be redirecting
DOUT	macro	target				; target is 0 for stdio
		in		a, (REDIRECT)
		ld 		(spare), a
		ld		a, target
		out		(REDIRECT), a
		endm
; restore previous
ROUT	macro
		ld		a, (spare)
		out		(REDIRECT), a
		endm

; Diagnostic register dump to serial port (all pushed)
SNAP	macro	id
		push	af
		DOUT	0					; force serial op
		xor		a
		ld		(snap_mode), a
		pop		af
		push	af					; get a pristine AF
		call	_snap
		call	stdio_str
		db		id
		db		0
		ROUT
		pop		af
		endm

; Diagnostic memory dump (all pushed)
DUMP	macro	ptr, count
		push	af
		DOUT	0					; force serial op
		push	hl
		push	de
		push	bc
		ld		hl, ptr
		ld		c, 0
		ld		de, count
		call	stdio_dump
		pop		bc
		pop		de
		pop		hl
		ROUT
		pop		af
		endm

; Get some auto variables on the stack C style
; returns IY as pointer to the first byte
AUTO	macro	nbytes
		push	iy
		ld		iy, -nbytes
		add		iy, sp
		ld		sp, iy
		endm
RELEASE	macro	nbytes
		ld		iy, nbytes
		add		iy, sp		; beware DOES NOT preserve flags
		ld		sp, iy
		pop		iy
		endm

; colour sequences
; to eliminate ANSI stuff redefine these as db ""
 if ALLOW_ANSI
WHITE	macro
		db		"\e[37m"
		endm
RED		macro
		db		"\e[91m"			; bright red actually
		endm
GREEN	macro
		db		"\e[92m"
		endm
BLUE	macro
		db		"\e[94m"
		endm
 else
WHITE	macro
		endm
RED		macro
		endm
GREEN	macro
		endm
BLUE	macro
		endm
 endif 
;===============================================================================
;
;	Memory addressing
;
;===============================================================================
;
; The Zeta2 arrangement with 1Mb total over the RAM and ROM means that the
; tools need to reflect this. Normally BIOS software just uses 16 bits and that
; covers it all but I want to be able to address everything.
; I decided that bios addressing is usually 20 bits so 0xffffff
; The top bit 0x80000 is the ROM select. This is actually the opposite way
; round to the board design but it makes far more sense as you think in terms
; of normally working in the base RAM from zero up and accessing the ROM or the
; 'switched out' RAM pages is an infrequent event.
; So if you type in an address the bottom 14 bits ie 0x3fff are just simple
; addressing. The next 5 bits select the pages and the final 20th bit selects
; ROM.
; Hence for most things you are accessing the 'standard fit' of RAM0/1/2 in
; 0-0xbfff but you can go anywhere.
; I will do this by making the BIOS memory R/W functions swap the required
; block into PAGE1 just while they need access the they restore RAM1. I really
; wish I could read the MPGSEL1 registers and restore them to what they were
; but I suspect that for 99%+ of the time this will work.
;
;===============================================================================
;
;	Z80 org 0x0000 Vector table
;
;===============================================================================

			org		PAGE3			; where we are in hardware terms
			jp		rst00			; unmapped start
			
			ds		ROM_SHIFT-3		; filler to move the BIOS up ROM0
			
BIOS_START	equ		$				; where we actually start

RAM_TOP		equ		PAGE3			; will be top of RAM when we run in ROM
									; push is to (SP-1) and (SP-2)
RAM_TOPEX	equ		$				; RAM 'top' when running in RAM

; This is the vector table that will be in PAGE0 at address 0
; However as we boot with ROM0 there it seems good to mimic it in ROM to copy

; First the 'rst' vectors (each is 8 bytes)
start_table
; 0x00
			jp		rst00			; the rst routines match the RST n opcode
spare		equ		$-start_table
			dw		0				; spare used by diagnostics
; 0x05
			jp		cpm				; if emulating CPM jump to the handler
; 0x08
			jp		rst08

def_address	equ		$-start_table
			d24		0				; 3 byte bios default address
def_port	equ		$-start_table
			dw		0				; bios default port
; 0x10
			jp		rst10
preTick		equ		$-start_table	; uint8	 ticks per second
			db		0
Ticks		equ		$-start_table	; uint32 time in seconds
			dd		0
; 0x18
			jp		rst18
led_buffer	equ		$-start_table
			db		0				; led buffer LD1=b3 LD2=b0 (active low)
snap_mode	equ		$-start_table
			db		0				; 0=SNAP macro, 1=RST 0x08
			db		0,0,0			; spare
; 0x20
			jp		rst20
			db		0,0,0,0,0
; 0x28
			jp		rst28
			db		0,0,0,0,0
; 0x30
			jp		rst30
			db		0,0,0,0,0
; 0x38
			jp		rst38
			ds		43
; 0x66
			jp		nmi				; NMI handler

size_table	equ	$ - start_table		; table size for copy

; it only take a simple typo to mess this alignment up so
 assert 	size_table == 0x69, Problem with definitions at PAGE0

;===============================================================================
;
;	Bootstrapper		Power up from cold with no assumptions
;
;===============================================================================

signon		db		"\r"
			RED
			db		"Nigsoft Z80 BIOS "
			VERSION
			db		" "
			db		__DATE__
			db		" "
			db		__TIME__
			db		" ", 0

ram_test	db		0				; set to 1 if we are running in RAM
rst00		di						; interrupts off
			xor		a				; mapper off while we get things restarted
			out		(MPGEN), a
			
; WARNING: Until we have some RAM set up we have no stack so don't call subs
; Assume we only have ROM0 at 0xc000 as we might be soft restarting

; I want to set up the memory in two different ways:
; We start from a power-up reset with ROM0 mapped into all four pages
; Hence when we execute the instruction at 0x0000 in PAGE0 which is the first
; instruction of ROM0 it jumps to rst0 in PAGE3 also ROM0 but in page3

; The first map is simple. I want RAM0-2 in PAGE0-2 and ROM0 in PAGE3
; the second is more complex as I want to copy BIOS0 into RAM3 and map RAM0-3
; in PAGE0-3 so I have BIOS in RAM. This will allow me to place the BIOS higher
; in the address ma giving more space AND have local variables.
; Also I want to switch between these with the jumper JP1 so I must manage it
; with a discontinuity in the addressing as I switch. It might be possible to
; swap the ROM as the CPU executes in it but I'd rather play it very safe.

; The manual warns you that the mapping registers are not reset on restart so
; they can be random trash. You need to set them all to something sensible
; before enabling the mapper.
; Also if we are warm starting the mapper might be active so be careful...
;
; Initially map PAGE0=ROM0, PAGE1=RAM0, PAGE2=ROM0, PAGE3=ROM0
; so only page 1 changes from unmapped.
; Due to the JP on RST 0x00 we should be executing in PAGE3 and ROM0
			ld		a, ROM0			; ROM0
			out		(MPGSEL0), a	; into PAGE0
			out		(MPGSEL2), a	; into PAGE2
			out		(MPGSEL3), a	; also PAGE3
			ld		a, RAM0			; RAM0
			out		(MPGSEL1), a	; into PAGE1
			ld		a, 1			; all four pages are set so allow mapping
			out		(MPGEN), a

; Copy the vector table into RAM0 at PAGE1
; Do not copy more we need as we might be on a mission to see what just blew up
 			ld		hl, start_table	; source pointer (ROM0 in page 3)
			ld		de, PAGE1		; destination pointer (RAM0 in page 1)
			ld		bc, size_table	; byte counter
			ldir					; block move (HL)->(DE) for BC counts

; Now put the RAM0-2 in the correct places
			ld		a, RAM0			; page RAM0
			out		(MPGSEL0), a	; into page 0
			ld		a, RAM1			; page RAM1
			out		(MPGSEL1), a	; into page 1
			ld		a, RAM2			; page RAM2
			out		(MPGSEL2), a	; into page 2
; OK now we are running ROM0 in PAGE3 with RAM0,1,2 in PAGE0,1,2
			ld		sp, RAM_TOP		; set the stack pointer to the top of page2
									; now we can call subroutines

;-------------------------------------------------------------------------------
; The next thing to do is to read our jumper and switch the BIOS from ROM to
; RAM1 if required
;-------------------------------------------------------------------------------
; so test the jumper JP1 (pulls high if no jumper)
			in		a, (RTC)		; read the jumper port
			and		40H				; set NZ if no jumper is fitted to bit 6
			jr		nz, .k3			; stick with ROM0
			
; put RAM3 in PAGE1
			ld		a, RAM3
			out		(MPGSEL1), a
; copy BIOS0 in PAGE3 to RAM3 in PAGE1
			ld		hl, PAGE3		; source pointer 
			ld		de, PAGE1		; destination pointer
			ld		bc, PAGE_SIZE	; Page size
			ldir
; restore RAM1 to PAGE1
			ld		a, RAM1
			out		(MPGSEL1), a
			jr		.k2				; skip over the switch routine
			
; These three opcodes are the code I will copy into RAM to execute the switch:
.k1			ld		a, RAM3			; select RAM3
			out		(MPGSEL3), a	; into PAGE3
			jp		.k3				; continue in RAM
			
; copy and switch
.WEDGE		equ		0xbf00			; place to put the wedge in RAM2 (PAGE2)
.k2			ld		hl, .k1			; source pointer
			ld		de, .WEDGE		; destination pointer
			ld		bc, .k2 - .k1	; byte counter for move
			ldir					; block move
			jp		.WEDGE			; jump to the switch code in RAM
.k3
; do the ram test
			ld		a, 1
			ld		(ram_test), a	; fails in ROM

;===============================================================================
; Time to set things up
;===============================================================================
 if LEDS_EXIST
			ld		a, 0x01			; RH LED on only
			call	set_led
 endif

; UART and serial stuff in serial.asm
			call	serial_init		; 19200,8,1,N
			; !!!! from now on the stdio and debug outputs will work !!!!
			xor		a
			out		(REDIRECT), a	; default stdio to serial port
; Counter Timer in ctc.asm
			call	ctc_init
; Parallel port
			call	pio_init		;
; Real Time Clock (and leds)
			ld		a, 0x09			; both leds off
			ld		(led_buffer), a
			call	rtc_init		; set default state and leds
; Floppy Disk Controller
;;			call	fdc_init		; manana
; Interrupts
			call	int_init		; at the bottom of this module

; Put a 3 on the number display
 if DIGITS_EXIST
			ld		a, 3
			call	progress
 endif
 if LEDS_EXIST
			ld		a, 0x09			; both leds off
			call	set_led
 endif

;===============================================================================
; Sign on at the stdio port
;===============================================================================

TEXT_BUFFER		equ		0x80		; arbitrary place for a text input buffer
SIZEOF_BUFFER	equ		80

; before we sign on send some zeros to ensure everything is in sync
			ld		b, 5
			xor		a
.j1			call	serial_sendW
			djnz	.j1
			ld		hl, signon		; sign on with version info
			call	stdio_text		; leaves text in RED
; do the ram/rom test
			ld		de, RAM_TOP		; top of RAM if bios in ROM
			ld		a, (ram_test)
			or		a
			jr		z, .j2			; running in ROM
			call	stdio_str
			BLUE
			db		"in RAM at ", 0
			ld		hl, BIOS_START
			call	stdio_word
			ld		a, ' '
			call	stdio_putc
			ld		de, RAM_TOPEX
.j2			call	stdio_str
			WHITE
			db		0
			ld		a, d			; ram size/256
			srl		a
			srl		a				; ram_size/1024
			call	stdio_decimalB
			call	stdio_str
			db		"K bytes free", 0
			jr		good_end		; skip the error return

; Respond with an error message and re-prompt
bad_end		ld		sp, RAM_TOP		; reset to a known value
			call	stdio_str
			RED
			db		"  ?? not understood"
			WHITE
			db		0

; This is the point we return to after executing a command
good_end	ld		a, (ram_test)	; running in RAM?
			or		a
			jr		z, .j2			; no
			ld		sp, RAM_TOPEX	; yes, grab some more space
.j2			call	stdio_str
			db		"\r\n"
			GREEN
			db		"> "
			WHITE
			db		0

			ld		hl, TEXT_BUFFER
			ld		b, SIZEOF_BUFFER
			call	getline			; returns buffer count in D
			ld		a, d			; if an empty line fail politely
			or		a
			jr		z, good_end

; Now we want to interpret the command line
			jp		do_commandline

;===============================================================================
; Decode the command line
;===============================================================================

; The jump table matches a letter to an address
cmd_list	db	'E'					; echo command
			dw	cmd_e
			db	'H'					; hex test
			dw	cmd_h
			db	'R'					; read memory
			dw	cmd_r
			db	'W'					; write memory
			dw	cmd_w
			db	'F'					; fill memory
			dw	cmd_f
			db	'I'					; input from a port
			dw	cmd_i
			db	'O'					; output to a port
			dw	cmd_o
			db	'X'					; execute from an address
			dw	cmd_x
			db	'D'					; dump from an address
			dw	cmd_d
			db	'B'					; read a block of data to an address
			dw	cmd_b
			db	'T'					; time set/get
			dw	cmd_t
			db	'Z'					; anything test
			dw	cmd_z
			db	'K'					; kill
			dw	cmd_k
 if ALLOW_ANSI
 			db	'C'					; clear screen
			dw	cmd_c
 endif
 if LEDS_EXIST
			db	'L'					; set the LEDs
			dw	cmd_l
 endif
 if DIGITS_EXIST
			db	'P'					; panel command
			dw	cmd_p
 endif
			db	'S'					; save command
			dw	cmd_s
			db	0

; Called with HL pointer to line, D buffer count, use E as index
do_commandline
			ld		a, (hl)			; preserve HL and DE for routine to process
			ld		c, a			; save the command letter
; If a lower case letter convert to upper case
			call	islower			; test for a-z set CY if true
			jr		nc, .d1
			and		~0x20			; convert to upper case
			ld		c, a			; and update the copy
.d1
; Look for match in the table
			ld		ix, cmd_list	; table of commands and functions
; Check for end of table
.d2			ld		a, (ix)
			or		a				; end of list?
			jp		z, bad_end		; yes, so not recognised
; Test for match
			cp		c				; test command letter
			jr		z, .d3			; we have a match
; No match
			inc		ix				; ix += 3
			inc		ix
			inc		ix
			jr		.d2
; Match
.d3			ld		c, (ix+1)		; lsbyte
			ld		b, (ix+2)		; msbyte
			ld		ix, bc
			ld		e, 1			; set index to second character
			jp		(ix)

;===============================================================================
; Memory page addressing
;===============================================================================
; Called with a 20 bit address in C:IX
; b0-13 are just address bus stuff
; b14-18 are the 0-31 page
; bit 19 is ROM select
; bits 20-23 are an error
; uses AF, returns value in IX
; fixes IX to point to the correct CPU address16 to access the memory
setPage		push	ix
			ld		a, c			; bits 16-23
			and		0x0f			; mask to 16-19
			push	hl
			ld		hl, ix
			rl		h				; move bits 14-15 into A b0-1
			rl		a
			rl		h
			rl		a				; giving bits 19-14 in A b5-0
			pop		hl
			xor		0x20			; swap ROM and RAM
			out		(MPGSEL1), a	; swap the page in
			pop		ix
			ld		a, ixh			; !
			and		a, 0x3f			; mask out the page address
			or		a, 0x40			; set for PAGE1
			ld		ixh, a
			ret

; restore the usual RAM1 to PAGE1
; uses AF
resPage		ld		a, RAM1			; page RAM1
			out		(MPGSEL1), a	; back into PAGE1
			ret

; get a byte from C:IX in A leaving everything unchanged
getPageByte	push	ix
			call	setPage
			ld		a, (IX)
			push	af
			call	resPage
			pop		af
			pop		ix
			ret

; set the byte in C:IX to A
putPageByte	push	ix
			push	af
			call	setPage
			pop		af
			ld		(IX), a
			push	af
			call	resPage
			pop		af
			pop		ix
			ret

; increment C:IX  a useful utility
incCIX		push	de
			ld		de, 1
			add		ix, de
			ld		d, a		; preserve A
			ld		a, c
			adc		0
			ld		c, a
			ld		a, d
			pop		de
			ret

;===============================================================================
; E text echo test			E anything you like
;===============================================================================
cmd_e		call	stdio_str
			db		"\r\n\e[94mecho:\e[37m ", 0
ce1			call	getc						; called from cmd_h
			jp		z, good_end
			cp		0x20		; control?
			jr		c, .ce2		; < 0x20
			cp		0x07f
			jr		nc, .ce2	; >= 0x7f
			call	stdio_putc
			jr		ce1
.ce2		push	af
			ld		a, '\'
			call	stdio_putc
			pop		af
			call	stdio_byte
			jr		ce1

;===============================================================================
; H hex echo test	H value24  outputs hex and decimal
;					H          output the current default address
;===============================================================================
cmd_h		ld		ix, (def_address)		; default value
			ld		a, (def_address+2)		; !! not ld c,(...) which compiles
			ld		c, a					; but wrong
			call	gethex					; in C:IX
			jp		nc, bad_end				; value syntax
			ld		(def_address), ix
			ld		a, c					; no ld (addr),c in Z80 speak
			ld		(def_address+2), a

			push	hl						; preserve command string stuff
			call	stdio_str
			db		"\r\nhex: ",0
			ld		hl, ix
			call	stdio_24bit				; output C:HL
			call	stdio_str
			db		" decimal: ",0
			call	stdio_decimal24			; C:HL again
			pop		hl
			
			call	skip					; more data on line?
			jp		z, good_end				; none so ok
			call	stdio_str
			db		" delimited by: ",0
			dec		e						; unget
			jr		ce1						; use cmd_e

;===============================================================================
; R read memory command		R address20  (not 24)
;===============================================================================
cmd_r		ld		ix, (def_address)		; default value
			ld		a, (def_address+2)
			ld		c, a
			call	gethex20				; in C:IX
			jp		nc, bad_end				; address syntax
			call	skip					; more data on line?
			jp		z, bad_end
			ld		a, c
			and		0xf0					; bad address
			jp		nz, bad_end
			ld		(def_address), ix		; save as default
			ld		a, c
			ld		(def_address+2), a

			call	stdio_str
			db		"\r\n",0
			ld		hl, ix
			call	stdio_24bit				; C:HL requested address
			ld		a, ' '
			call	stdio_putc
			call	getPageByte				; aka ld a, (C:IX)
			call	stdio_byte
			jp		good_end

;===============================================================================
; W write memory command 	W address20 data8 [data8] ...
;	NB: if the third data item is bad the first two have already been written
;		so I do not complain on data errors, they are just terminators
;===============================================================================
cmd_w		ld		ix, (def_address)		; default value
			ld		a, (def_address+2)
			ld		c, a
			call	gethex20				; in C:IX
			jp		nc, bad_end				; address syntax
			ld		a, c
			and		0xf0					; illegal for an address
			jp		nz, bad_end
			ld		(def_address), ix		; useful so I can use R to check it
			ld		a, c
			ld		(def_address+2), a
			ld		iy, ix					; save the address in B:IY
			ld		b, c

.cw1		call	skip					; step over spaces
			jp		z, good_end				; we have finished
			dec		e						; 'unget'
			ld		ix, 0					; default data
			call	gethexB					; in C:IX
			jp		nc, bad_end				; syntax error
			ld		a, ixl					; data in a

			ld		c, b					; recover address B:IY->C:IX
			ld		ix, iy
			call	putPageByte				; ld (C:IX),a

			push	de						; B:IY++
			ld		de, 1
			add		iy, de					; inc iy does not set CY
			ld		a, b
			adc		0
			ld		b, a
			pop		de
			jr		.cw1

;===============================================================================
; F fill memory command 	F address20 count16 data8
;===============================================================================
cmd_f		ld		ix, (def_address)		; default value
			ld		a, (def_address+2)
			ld		c, a
			call	gethex20					; in C:IX
			jp		nc, bad_end				; address syntax
			ld		a, c
			and		0xf0					; legal address?
			jp		nz, bad_end				; no
			ld		a, c
			ld		(def_address), ix		; useful so I can use R to check it
			ld		(def_address+2), a

			ld		ix, 0					; default count (0=error)
			call	gethexW
			jp		nc, bad_end
			ld		bc, ix					; BC = count
			ld		a, b					; !=0 safety trap
			or		c
			jp		z, bad_end
			ld		iy, bc					; save it as gethex uses BC

			ld		ix, 0					; default data
			call	gethexB
			jp		nc, bad_end

			call	skip					; any data left?
			jp		nz, bad_end				; that's wrong
			ld		b, ixl

; right we have data in B, count in IY and address in (default buffer)
			ld		ix, (def_address)
			ld		a, (def_address+2)
			ld		c, a
			ld		a, b

.cf1		ld		a, b
			call	putPageByte				; A->C:IX
			ld		de, 1					; C:IX++
			add		ix, de
			ld		a, c
			adc		0
			ld		c, a
			dec		iy						; djnz iy
			ld		a, iyh
			or		iyl
			jr		nz, .cf1
			jp		good_end

;===============================================================================
; I input command			I port
;===============================================================================
cmd_i		ld		ix, (def_port)			; default address
			call	gethexB					; in IXL
			jp		nc, bad_end				; address syntax
			call	skip					; more data on line?
			jp		nz, bad_end
			ld		(def_port), ix

			call	stdio_str
			db		"\r\n",0
			in		a, (C)					; get the byte
			call	stdio_byte
			jp		good_end

;===============================================================================
; O output command			O port data
;===============================================================================
cmd_o		ld		ix, (def_port)			; default address
			call	gethexB					; port in IXL
			jp		nc, bad_end				; syntax in address
			ld		iy,	ix					; save port

			ld		ix, 0					; default data
			call	gethexB					; data in IXL
			jp		nc, bad_end				; syntax in data
			call	skip					; more data on line?
			jp		nz, bad_end
			ld		hl, ix					; data in L

			ld		bc, iy					; recover port in C
			ld		(def_port), bc
			ld		a, l
			out		(c), a
			jp		good_end

;===============================================================================
; X execute command    X address16 in Z80 memory NOT address20
;===============================================================================
cmd_x		ld		ix, BIOS_START			; BIOS0 start is default address
			call	gethexW					; port in IX
			jp		nc, bad_end				; syntax in address
			call	skip					; more on line?
			jp		nz, bad_end
			ld		iy, good_end			; make a 'return address'
			push	iy						; so the command can just 'ret'
			jp		(ix)

;===============================================================================
; D dump command    D address20 count16 (default=256)
;===============================================================================
cmd_d		ld		ix, (def_address)		; default address
			ld		a, (def_address+2)
			ld		c, a
			call	gethex20				; in C:IX
			jp		nc, bad_end				; address syntax
			ld		iy, ix					; address in B:IY
			ld		b, c

			ld		ix, 256					; default on count is 0x100
			call	gethexW
			jp		nc, bad_end				; count syntax
			call	skip					; more on line?
			jp		nz, bad_end

			ld		(def_address), iy		; all details OK
			ld		a, b
			ld		(def_address), a

			; we have the address in B:IY and count in IX
			; Add a quick decode to stop mistakes
			ld		a, b
			and		a, 0x08					; set for ROM
			jr		z, .cd1
			call	stdio_str
			db		"  ROM",0
			jr		.cd2
.cd1		call	stdio_str
			db		"  RAM", 0
.cd2		ld		c, iyh					; get top two bits
			ld		a, b
			rl		c						; left slide C into A
			rl		a
			rl		c
			rl		a
			and		0x1f
			call	stdio_decimalB
			; and output
			ld		hl, iy					; address in C:HL
			ld		c, b
			ld		de, ix					; count in DE
			call	stdio_dump
			jp		good_end

;===============================================================================
; B block command    B address20 count16	then read data from serial port
;===============================================================================
STX			equ		0x02					; 'term' sends STX to start block
ACK			equ		0x06					; checksum OK send next block
NAK			equ		0x15					; checksum bad resend block

;; UNTESTED

cmd_b		ld		ix, (def_address)		; default address
			ld		a, (def_address+2)
			ld		c, a
			call	gethex20					; in C:IX
			jp		nc, bad_end				; address syntax
			push	ix						;						SP+2
			ld		ix, 0					; no default
			call	gethexW
			jp		nc, bad_end				; count syntax
			call	skip					; more on line?
			jp		nz, bad_end				; pop ix, bad_end
			ld		(def_address), ix
			push	ix						;						SP+4
			pop		de						; count					SP+2
			pop		hl						; address				SP+0
			ld		a, d					; test count
			or		e
			jp		z, bad_end
; do a block of 80 or less
.cb1		push	hl						; address
			push	de						; count
; limit the count to 1-80
			ld		a, d					; count msbyte
			or		a
			jr		nz, .cb2				; D>1 so DE>256
			ld		a, e
			cp		81						; set cy if a<=80
			jr		c, .cb3
.cb2		ld		a, 80
.cb3		ld		c, a					; save for subtract at the end
			ld		b, 0
			call	stdio_getc				; blocks start with STX
			cp		STX
			jr		z, .cb4					; OK, let's go!
			pop		hl
			pop		de
			jp		bad_end
.cb4		call	stdio_getc
			ld		(hl), a
			add		c						; accumulate checksum in C
			ld		c, a
			inc		hl
			dec		de
			djnz	.cb4					; using B as down counter
			call	stdio_getc
			cp		c						; checksum
			jr		z, .cb5					; OK
; fail
			ld		a, NAK
			call	stdio_putc
			pop		hl
			pop		de
			jr		.cb1
; OK
.cb5		ld		a, ACK
			call	stdio_putc
			pop		ix						; discard last block pointer
			pop		ix
			ld		a, d
			or		a, e
			jr		nz, .cb1				; get next block
			jp		good_end

;===============================================================================
; T  Time set/get    T hh:mm:ss  dd/mm/yy
;===============================================================================

cmd_t		AUTO	7				; 7 bytes of stack please
									; IY points to the first byte
; read the RDC to give us a baseline in the buffer
			push	hl				; preserve command line stuff
			ld		hl, iy
			call	rtc_rdclk		; burst mode read (7 bytes)
			pop		hl
; test command line for data
			call	skip
			jr		z, .ct3			; nothing so just do display
; read the command line into the buffer and write it
			dec		e				; unget
			call	packRTC			; from command line to IY
			jr		c, .ct2			; good string
.ct1		RELEASE	7				; error exit
			jp		bad_end
.ct2		ld		hl, iy
			call	rtc_wrclk		; write to clock
; unpack buffer to stdio
.ct3		call	stdio_str
			db		"\r\n",0
			ld		ix, iy
			call	unpackRTC		; unpacks (IX)
			RELEASE 7
			
; put the CTC dump here
			call	stdio_str
			db		"\n\rCTC time since reboot: ", 0
			ld		hl, (Ticks)
			ld		a, (Ticks+2)
			ld		c, a
			call	stdio_decimal24
			ld		a, '.'
			call	stdio_putc
			ld		a, (preTick)		// @50Hz
			add		a					// as hundredths of a second
			call	stdio_decimalB3
			call	stdio_str
			db		" secs",0
			jp		good_end

;===============================================================================
; Z  the anything test Z for temporary
;===============================================================================
cmd_z		rst		0x08			; SNAP alternative
			ld		ix, 0
			ld		c, 0
			call	getdecimal
			jp		nc, bad_end
			ld		iy, ix
			ld		ix, 1
			call	getdecimal
			jp		nc, bad_end
; mul8x8		; multiply H by E, 16 bit result in HL
			ld		de, ix			; second argument in E
			ld		hl, iy			; first argument in L
			ld		h, l
			call	stdio_str
			db		"\r\n8x8 mply: ", 0
			ld		a, h
			call	stdio_decimalB
			call	stdio_str
			db		" x ", 0
			ld		a, e
			call	stdio_decimalB
			call	stdio_str
			db		" = ", 0
			call	mul8x8
			call	stdio_decimalW
			jp		good_end

;===============================================================================
; K  the kill command
;===============================================================================
cmd_k		di
			halt				; push the reset button kiddo
			jr		cmd_k

;===============================================================================
; C  clear screen command
;===============================================================================
 if ALLOW_ANSI
cmd_c		call	stdio_str
			db		"\e[H\e[2J", 0
			jp		rst00
 endif
;===============================================================================
; L  LED command	eg:	L 01 = LED1 off, LED2 on  L x1 = leave LED1, LED2 on
;===============================================================================
 if LEDS_EXIST
cmd_l		ld		a, (led_buffer)		; previous state
			ld		b, a				; hold in B
			call	skip				; skip blanks return next char
			jp		z, bad_end			; EOL so got nothing
			cp		'0'					; LED1 off?
			jr		nz, .cl1
			ld		a, b
			or		0x08				; set b3
			ld		b, a
			jr		.cl2
.cl1		cp		'1'					; LED1 on?
			jr		nz, .cl2
			ld		a, b
			and		~0x08				; clear b3
			ld		b, a
.cl2		call	skip				; get second character
			jr		z, .cl5				; clearly only doing LED1 today
			cp		'0'					; LED2 off?
			jr		nz, .cl3
			ld		a, b
			or		0x01				; set b0
			ld		b, a
			jr		.cl4
.cl3		cp		'1'					; LED2 on?
			jr		nz, .cl4
			ld		a, b
			and		~0x01				; clear b0
			ld		b, a
.cl4		call	skip
			jp		nz, bad_end			; more stuff on line is error
.cl5		ld		a, b
			ld		(led_buffer), a
			call	rtc_init
			jp		good_end
 endif

;===============================================================================
; P  panel command : display a code
;===============================================================================
 if DIGITS_EXIST
cmd_p		call	skip
			jp		z, bad_end
			call	dodigit
			jp		good_end
 endif

;===============================================================================
; S  read/write the rtc's ram		S address16 (not 20) R|W
;===============================================================================
cmd_s		ld		ix, (def_address)		; default address
			call	gethexW					; in IX
			jp		nc, bad_end				; address syntax

			call	skip					; get the command letter
			jp		z, bad_end
			call	islower					; lower case
			jr		nc, .cp1				; no
			and		~0x20					; to uppercase
.cp1		ld		b, a					; save the 'R' or 'W'
			call	skip					; end of line
			jp		nz, bad_end				; oops, no
			ld		hl, ix					; address for transfer
			ld		a, b
			cp		'R'
			jr		z, .cp2					; write ram
			cp		'W'
			jr		z, .cp3					; read ram
			cp		'T'
			jr		z, .cp4					; read clock
			cp		'S'
			jr		z, .cp5					; set clock
			jp		bad_end
			
.cp2		call	rtc_rdram				; read ram
			jp		good_end
.cp3		call	rtc_wrram				; write ram
			jp		good_end
.cp4		call	rtc_rdclk				; read clock
			jp		good_end
.cp5		call	rtc_wrclk				; write clock
			jp		good_end

;===============================================================================
;
;  Interrupt handlers
;
;===============================================================================
; handlers for RST N opcodes
rst08	push	af
		DOUT	0					; force serial op
		ld		a, 1
		ld		(snap_mode), a
		pop		af
		push	af
		call	_snap
		ROUT
		pop		af
		ret
rst10
rst18
rst20
rst28
rst30
rst38
			ret
nmi
			retn

;===============================================================================
;
; Z80 IM2 smart vectored interrupts
;
; The interrupt vector table needs to be aligned as the CPU knows the top
; eight bits of its address b15-b8, the CTC knows bits b7-b3 and the actual
; interrupt hardware supplies the bottom bits b2-0
;
;===============================================================================
			align	8			; 4 entries * 2 bytes per entry
iTable
			dw		int0		; CTC0	not used
			dw		int1		; CTC1  20Hz tick
			dw		int2		; UART
			dw		int3		; PPI

iVector		equ		iTable & 0xf8
			assert	(iTable & 0x07)	== 0, Interrupt vector table alignment

; This assumes the ctc_int has been run to set up the vectors
int_init
; first build the interrupt vector parts
			ld		a, iTable >> 8		; top 8 bits of table address
			ld		i, a				; the special 'i' register
			im		2
			ei
			ret

;-------------------------------------------------------------------------------
; CTC0		should not trigger (CTC0)
;-------------------------------------------------------------------------------
int0		reti

;-------------------------------------------------------------------------------
; CTC1		50Hz = 20mS
;-------------------------------------------------------------------------------
int1		di
			push	af
			push	hl
			ld		a, (preTick)		; uint8 counts 0-49
			inc		a
			ld		(preTick), a
			cp		50
			jr		nz, .q1
			xor		a
			ld		(preTick), a

			ld		hl, Ticks			; unit32 counts seconds
			inc		(hl)				; b0-7
			jr		nz, .q1				; beware, inc does not set carry
			inc		hl
			inc		(hl)				; b8-15
			jr		nz, .q1
			inc		hl
			inc		(hl)				; b16-23
			jr		nz, .q1
			inc		hl
			inc		(hl)				; b24-31	2^32 seconds is 136 years
.q1			pop		hl
			pop		af
			ei
			reti

;-------------------------------------------------------------------------------
; CTC2		Wired trigger from UART
;-------------------------------------------------------------------------------
int2		jp		serial_interrupt

;-------------------------------------------------------------------------------
; CTC3		Wired to PC3 which is an interrupt output in a smart mode
;-------------------------------------------------------------------------------
int3		reti

;===============================================================================
;
;		diagnostic flasher
;
;===============================================================================

; put numbers on my 7 segment plug in
 if DIGITS_EXIST
MAKED		macro	V, A,B,C,D,E,F,G,DP
			db		V, ~(A<<7 | B | C<<2 | D<<4 | E<<5 | F<<6 | G<<1 | DP<<3)
			endm
; numbers						;   afed.cgb
digits		;			 A B C D E F G DP
			MAKED	'0', 1,1,1,1,1,1,0,0	; O
			MAKED	'1', 0,1,1,0,0,0,0,0	; 1			====A====
			MAKED	'2', 1,1,0,1,1,0,1,0	; 2			|		|
			MAKED	'3', 1,1,1,1,0,0,1,0	; 3			|		|
			MAKED	'4', 0,1,1,0,0,1,1,0	; 4			F		B
			MAKED	'5', 1,0,1,1,0,1,1,0	; 5			|		|
			MAKED	'6', 1,0,1,1,1,1,1,0	; 6			|		|
			MAKED	'7', 1,1,1,0,0,0,0,0	; 7			====G====
			MAKED	'8', 1,1,1,1,1,1,1,0	; 8			|		|
			MAKED	'9', 1,1,1,1,0,1,1,0	; 9			|		|
			MAKED	'A', 1,1,1,0,1,1,1,0	; A			E		C
			MAKED	'b', 0,0,1,1,1,1,1,0	; b			|		|
			MAKED	'C', 1,0,0,1,1,1,0,0	; C			|		|	DP
			MAKED	'c', 0,0,0,1,1,0,1,0	; c			====D====
			MAKED	'd', 0,1,1,1,1,0,1,0	; d
			MAKED	'E', 1,0,0,1,1,1,1,0	; E
			MAKED	'F', 1,0,0,0,1,1,1,0	; F
			MAKED	'H', 0,1,1,0,1,1,1,0	; H
			MAKED	'h', 0,0,1,0,1,1,1,0	; h
			MAKED	'i', 0,0,1,0,0,0,0,0	; i
			MAKED	'J', 0,1,1,1,1,0,0,0	; J
			MAKED	'L', 0,0,0,1,1,1,0,0	; L
			MAKED	'o', 0,0,1,1,1,0,1,0	; o
			MAKED	'P', 1,1,0,0,1,1,1,0	; P
			MAKED	't', 0,0,0,1,1,1,1,0	; t
			MAKED	'U', 0,1,1,1,1,1,0,0	; U
			MAKED	'u', 0,0,1,1,1,0,0,0	; u
			MAKED	'[', 1,0,0,1,1,1,0,0	; [
			MAKED	']', 1,1,1,1,0,0,0,0	; ]
			MAKED	'_', 0,0,0,1,0,0,0,0	; _
			MAKED	'=', 0,0,0,1,0,0,1,0	; =
			MAKED	'-', 0,0,0,0,0,0,1,0	; -
			MAKED	'.', 0,0,0,0,0,0,0,1	; .
max_digit	equ		($-digits)/2

;===============================================================================
;	progress  character on the display panel
;===============================================================================

dodigit		push	hl			; character in A
			ld		hl, digits
			ld		b, max_digit
.p1			cp		(hl)
			jr		z, .p2
			inc		hl
			inc		hl
			djnz	.p1
			ld		a, 0xff		; all off
			jr		.p3
.p2			inc		hl
			ld		a, (hl)
.p3			out		(PIO_A), a
			pop		hl
			ret

progress	and		0x0f
			add		a, '0'
			call	dodigit
			; fall through into the delay
 endif
;===============================================================================
; diagnostic delay of 1/2 second
;===============================================================================

ddelay		push	hl
			push	bc
			ld		b, 4
.d1			ld		hl, 43103	; 29T per loop = 1/8 secs
.d2			dec		hl			; 6T
			ld		a, h		; 4T
			or		l			; 7T
			jr		nz, .d2		; 12T if jumps else 7T
			djnz	.d1
			pop		bc
			pop		hl
			ret
;===============================================================================
; flasher		die with style
;===============================================================================
 if LEDS_EXIST
flasher		ld		de, 0
			; read the jumper write the port
.j1			in		a, (RTC)	; read jumper
			and		0x40		; in bit 6
			ld		a, 0x01		; out bit 0 RH led (off)
			jr		z, .j2
			ld		a, 0x09		; plus bit 4 LH led (off)
.j2			or		a, 0x20		; turn odd WE for the RTC
			out		(RTC), a

			call	ddelay

			; read jumper but change LH led
			in		a, (RTC)	; read jumper
			and		0x40		; in bit 6
			ld		a, 0x00		; out bit 0 RH led (on)
			jr		z, .j3
			ld		a, 0x08		; plus bit 4 LH led (off)
.j3			or		a, 0x20		; turn odd WE for the RTC
			out		(RTC), a

			call	ddelay

			ld		hl, digits
			add		hl, de
			ld		a, (hl)
			out		(PIO_A), a
			inc		de
			ld		a, e
			cp		20
			jr		c, .j1
			ld		de, 0
			jr		.j1
 endif

;===============================================================================
; dump the registers
;===============================================================================

_snap		push	af
			push	bc
			push	hl
			push	af				; a copy to dismantle
			push	hl				; a copy to output
			call	stdio_str
			db		"\r\nA:", 0
			call	stdio_byte
			call	stdio_str
			db		" BC:", 0
			ld		hl, bc
			call	stdio_word
			call	stdio_str
			db		" DE:", 0
			ld		hl, de
			call	stdio_word
			call	stdio_str
			db		" HL:", 0
			pop		hl
			call	stdio_word
			call	stdio_str
			db		" IX:", 0
			ld		hl, ix
			call	stdio_word
			call	stdio_str
			db		" IY:", 0
			ld		hl, iy
			call	stdio_word
			call	stdio_str
			db		" SP:", 0
			; we now need two different versions of the constants
			;							snap_mode==0	snap_mode=1
			; stack depth since last call	12				14
			; return address				8				12
			; back to start of snap			-19				-1
			ld		a, (snap_mode)
			or		a
			ld		hl, 12			; stack depth since call (14)
			jr		z, .sn1
			ld		hl, 14
.sn1		add		hl, sp
			call	stdio_word
			call	stdio_str
			db		" PC:", 0
			ld		a, (snap_mode)
			or		a
			ld		hl, 8			; return address (12)
			jr		z, .sn2
			ld		hl, 12
.sn2		add		hl, sp
			ld		a, (hl)
			inc		hl
			ld		h, (hl)
			ld		l, a			; return address of _snap
			ld		a, (snap_mode)
			or		a
			ld		bc, -19			; back to the start of SNAP (-1)
			jr		z, .sn3
			ld		bc, -1
.sn3		add		hl, bc
			call	stdio_word
			ld		a, ' '
			call	stdio_putc

			pop		hl			; saved as AF so flags in L

; I shall show the flags as " V" or "-V" for true false

doFlag		macro	mask, char
			ld		a, mask
			and		l
			ld		a, ' '
			jr		nz, .df1	; yup, flags are saved inverted
			ld		a, '-'
.df1		call	stdio_putc
			ld		a, char
			call	stdio_putc
			endm

			doFlag	0x80, 'S'
			doFlag	0x40, 'Z'
			doFlag	0x10, 'H'
			doFlag	0x04, 'P'
			doFlag	0x02, 'N'
			doFlag	0x01, 'C'
			ld		a, ' '
			call	stdio_putc
			pop		hl
			pop		bc
			pop		af
			ret
