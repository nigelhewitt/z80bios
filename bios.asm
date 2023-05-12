;===============================================================================
;
;	bios.asm	The NigSoft Z80 ROM bios
;				For the Zeta 2.2 board
;				© Nigel Hewitt 2023
;
	define	VERSION	"v0.1.38"		; version number for sign on message
;									  also used for the git commit message
;
;
;	compile with
;			./make.ps1
;
;   update to git repository
;		git add -u					move updates to staging area
;   	git commit -m "0.1.35"		move to local repository, use version number
;   	git push -u origin main		move to github
;
; NB: From v0.1.10 onwards I use the alternative [] form for an address
;     as LD C, (some_address) looks OK and compiles IF LOAD_ADDRESS<256
;	  but the () is taken as arithmetic and it is load C with a constant
;	  However LD C, [some_address] is a compile error.
;	  Don't ask how long it took me to work that one out...
;
;===============================================================================

		DEVICE	NOSLOT64K
		PAGE	3
		SLDOPT	COMMENT WPMEM

		include		"zeta2.inc"		; hardware definitions and code options
		include		"macros.inc"	; macro library
		include		"vt.inc"		; definitions of Z80 base memory

BIOSROM		equ		ROM0			; which ROM page we are compiling
BIOSRAM		equ		RAM3

; This code image is in page 0 of the ROM so, on boot, it is replicated in all
; four memory slots of the Zeta2 board. However I want it to run in page 3,
; at C000H to FFFFH, so it needs to hand over smoothly.

; Important notes:
; The RAM used is 512K of CMOS and hence draws little or nothing so it is
; protected by a specialist chip that uses the lithium battery to power it once
; the main supply goes out of spec. Hence non-volatile RAM!
; It is, however, slightly tardy at starting up so I wait for it. See below.
;
; The ROM isn't ROM either in the old sense
; It is 512K of Flash with a rather step-by-step sector (64K) programming
; sequence but can still upload and flash a new bios live.
;
; All this adds up to more than the Z80s 16bit=64K address range. Hence we work
; in 16K pages. We decode the top two bits of the Z80 bus to get that as four
; 16K pages referred to as PAGE0, PAGE1 etc.
; The ROM and RAM chips provide 32 16K pages each and the four mapping
; registers that are selected by A14/15 bits can swap in any page of ROM or RAM
; into those four pages. The ROM and RAM pages are referred to as ROM0, ROM1
; etc. and these are defined in below to the correct value for the page
; registers.
;
; The system boots with ROM0 in all four pages due to the mapping system being
; turned off so you can set up the page registers before you turn it on and you
; have lots of spare space on hand.
;
; The RTC also stashes 31 bytes of battery backed up RAM if needed
;
; To program the Flash off line use the TL866 programmer:
;	see
;		D:\Archive\TL866
;		D:\Util\TL866ii\Xgpro\Xgrro.exe
;		dev: SST: SST39SF040
; The ANSI colour and position codes I use are in
;		https://en.wikipedia.org/wiki/ANSI_escape_code
;
;===============================================================================
;
;	Memory addressing
;
; The Zeta2 arrangement with 1Mb total over the RAM and ROM means that the
; tools need to reflect this. Normally BIOS software just uses 16 bits and that
; covers it all but I want to be able to address everything.
;
; address16
; This is Z80 addressing, what it sees with whatever the current state of the
; mapping system is. For a lot of applications this is all you care about.
;
; address20
; The board is designed with an 8 bit port remapping the top two bits of the
; address bus. However the A21 bit isn't connected to anything and A20 selects
; the non-existent RAM1 and ROM1 chips (see note below). I decided that for
; bios addressing terms I would consider this as usually 20 bits so 0xfffff
;
; The top bit 0x80000 is the ROM select. This is actually the opposite way
; round to the board hardware design but it makes far more sense as you think
; in terms of normally working in the base RAM from zero up and accessing the
; ROM or the 'switched out' RAM pages is an infrequent event.
; Basically it helps my brain run cool.
;
; So if you type in an address20 the bottom 14 bits ie 0x3fff are just simple
; addressing. The next 5 bits select the pages and the final 20th bit selects
; ROM.
; Hence for most things you are accessing the 'standard fit' of RAM0/1/2 in
; 0-0xbfff but you can go anywhere.
; I will implement this by making the BIOS memory R/W functions swap the
; required block into PAGE1 just while they need access to them and then they
; restore RAM1.
; I really wish I could read the MPGSELn registers before writing them and then
; restore them 'as was' but I suspect that for 99+% of the time this will just
; work.
;
; address21
; like address20 but if you set bit20 then I ignore the page selection parts
; and just give you address 16. This is done so you can type 10nnnn into an
; address20 handler and get results for nnnn as an unmapped address16
;
; Interestingly the board decodes two more addresses so if you wanted to
; 'piggy back' another 512K of RAM and another 512K or RAM and hook their CS
; lines to pins 6 and 7 of U11 you could. However the address20 would become
; address22 and the bit for address23 would need to be rearranged.

; address24
; this is a transient state, a 6 bit 'page number' and a 14bit address
; The page number is the usual 5bits to select the page and bit5 to select ROM.
; REMEMBER that this is not the number in the Page select register ^0x20
;===============================================================================
;
;	Z80 org 0x0000 Vector table
;
;===============================================================================

			org		PAGE3			; where we are in hardware terms

; This is the vector table that will be in PAGE0 at address 0
; However as we cold boot with ROM0 there it seems good to mimic it in ROM

start_table
; 0x00
			jp		rst00			; the rst routines match the RST n opcode
	.2		db		0				; notice the repeat count
; 0x05
			jp		cpm				; if emulating CPM jump to the handler
; 0x08
			ret: nop: nop			; RST 0x08 (packed to take a JP addr16)
	.5		db		0
; 0x10
			ret: nop: nop			; RST 0x10
	.5		db		0
; 0x18
			ret: nop: nop			; RST 0x18
	.5		db		0
; 0x20
			jp		rst20			; RST 0x20
	.5		db		0
; 0x28
			jp		gotoRST			; debug handler
	.5		db		0
; 0x30
			ret: nop: nop			; RST 0x30
	.5		db		0
; 0x38
			ret: nop: nop			; RST 0x38
	.43		db		0
; 0x66
			jp		gotoNMI			; debug NMI handler

size_table	equ	$ - start_table		; table size for copy

; It only take a simple typo to mess this alignment up so
	assert 	size_table == 0x69, Problem with definitions at PAGE0
	assert	Z == 0x69, 			Problems with Z structure

;===============================================================================
;
;  Now we move up the memory space to a convenient 1K border so when in RAM
; we can release a lot of good usable memory to programs
;
;===============================================================================

			ds		ROM_SHIFT-size_table	; filler to move the BIOS up ROM0
											; ROM_SHIFT defined in "zeta2.inc"

RAM_TOP		equ		PAGE3			; top of RAM when we run the bios in ROM
RAM_TOPEX	equ		$				; RAM 'top' when running in RAM

BIOS_START	equ		$				; where we actually start
			jp		rst00			; reboot

;===============================================================================
;
;	Bootstrapper		Power up from cold with no assumptions
;
;===============================================================================

signon		db		0x1e, "[0?"				; switch out the debugger
			db		"\r"
			RED								; optional ANSI colour coded
			db		"Nigsoft Z80 BIOS Λ "	; note the UTF-8 extended character
			db		VERSION					; so I can get an instant check on
			db		" "						; the terminal program
			db		__DATE__
			db		" "
			db		__TIME__
			db		" ", 0

			db		"https://github.com/nigelhewitt/z80bios.git",0

ram_test	db		0				; set to 1 if we are running in RAM

; The system powers up with the PC set to zero where we have a jump chain to here
rst00		di						; interrupts off
			xor		a				; ensure the memory mapper is off
			out		(MPGEN), a		;		 while we get things restarted

; WARNING: Until we have some RAM set up we have no writable memory and no
; stack and no subroutines

; I want to set up the memory in two different ways:
; We start from a power-up reset with the mapper off so with ROM0 mapped into
; all four pages. Hence when we execute the instruction at 0x0000 in PAGE0
; which is the first instruction of ROM0 and it jumps to rst00 in PAGE3 also
; ROM0 but in PAGE3

; The first map is simple. I want RAM0-2 in PAGE0-2 and ROM0 in PAGE3.
; The second is slightly more complex as I want to copy BIOS0 into RAM3 and map
; RAM0-3 in PAGE0-3 so I have BIOS in RAM. This will allow me to place the BIOS
; higher in the address map giving more space AND allowing the bios to have
; local variables.
; Also I want to switch between these with the jumper JP1 so I must manage it
; with a discontinuity in the addressing as I switch.
;
; The manual warns you that the mapping registers are not reset on restart so
; they can be random trash. You need to set them all to something sensible
; before enabling the mapper.
;
; Initially map PAGE0=ROM0, PAGE1=RAM0, PAGE2=ROM0, PAGE3=ROM0
; so only PAGE1 changes from unmapped.
; Due to the JP on RST 0x00 we should be executing in ROM0 mapped to PAGE3
			ld		a, ROM0			; ROM0
			out		(MPGSEL0), a	; into PAGE0
			out		(MPGSEL2), a	; into PAGE2
			out		(MPGSEL3), a	; also PAGE3
			ld		a, RAM0			; RAM0
			out		(MPGSEL1), a	; into PAGE1
			ld		a, 1			; all four pages are set so allow mapping
			out		(MPGEN), a

; I have a problem with slow power up and it seems to be the RAM not coming on
; line via the backup power control chip (U22 DS1210) quite as fast as the rest
; of the system. So I wait until the RAM0 in PAGE1 is responding.
.k1			ld		a, 0xa5
			ld		[PAGE1], a
			nop
			ld		a, [PAGE1]
			cp		0xa5
			jr		nz, .k1

			ld		a, 0x5a
			ld		[PAGE1], a
			nop
			ld		a, [PAGE1]
			cp		0x5a
			jr		nz, .k1

; Copy the vector table into RAM0 at PAGE1
; Do not copy more we need as we might currently be on a mission to work out
; what just blew up
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
									; now we can do subroutines

; save the pages
			ld		hl, Z.savePage
			ld		[hl], RAM0
			inc		hl
			ld		[hl], RAM1
			inc		hl
			ld		[hl], RAM2
			inc		hl
			ld		[hl], ROM0

;-------------------------------------------------------------------------------
; The next thing to do is to read our jumper and see if we are required to
; switch the BIOS from ROM0 to RAM3
;-------------------------------------------------------------------------------
; so test the jumper JP1 (pulls high if no jumper)
			in		a, (RTC)		; read the jumper port
			and		40H				; set NZ if no jumper is fitted to bit 6
			jr		nz, .k2			; stick with ROM0

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

; now remap the memory we are running in live (gulp)
			ld		a, RAM3			; select RAM3
			out		(MPGSEL3), a	; into PAGE3
			ld		[Z.savePage+3], a

; do the ram test
.k2			ld		a, 1
			ld		[ram_test], a	; naturally this fails in ROM

;-------------------------------------------------------------------------------
;  More mapping
;  Put ROM1 in RAM4 and ROM2 in RAM5 for 'sideways' bios extensions
;-------------------------------------------------------------------------------

; RAM4 in PAGE1 and ROM1 in PAGE2
			ld		a, RAM4
			out		(MPGSEL1), a
			ld		a, ROM1
			out		(MPGSEL2), a
; copy
			ld		hl, PAGE2		; source pointer
			ld		de, PAGE1		; destination pointer
			ld		bc, PAGE_SIZE	; Page size
			ldir
; RAM5 in PAGE1 and ROM2 in PAGE2
			ld		a, RAM5
			out		(MPGSEL1), a
			ld		a, ROM2
			out		(MPGSEL2), a
; copy
			ld		hl, PAGE2		; source pointer
			ld		de, PAGE1		; destination pointer
			ld		bc, PAGE_SIZE	; Page size
			ldir
; restore RAM1 to PAGE1 and RAM2 to PAGE2
			ld		a, RAM1
			out		(MPGSEL1), a
			ld		a, RAM2
			out		(MPGSEL2), a

; read the cmd_flags from the RTC ram
			ld		hl, Z.rtc_buffer
			call	rtc_rdram
			ld		a, [Z.rtc_buffer]
			ld		[cmd_bits], a
			ld		a, [Z.rtc_buffer+1]
			ld		[cmd_bits+1], a
			ld		a, [Z.rtc_buffer+2]
			ld		[cmd_bits+2], a

;===============================================================================
; Time to set the hardware things up
;===============================================================================

; UART and serial stuff in serial.asm
			call	serial_init		; 19200,8,1,N
			; !!!! from now on the stdio and debug outputs will work !!!!

; Counter Timer in ctc.asm
			call	ctc_init

; Parallel port
			call	pio_init		; includes initialising the SD slot to off

; Real Time Clock (and leds)
			xor		a				; both leds off
			ld		[Z.led_buffer], a
			call	rtc_init		; set default state and leds

; Floppy Disk Controller
;;			call	fdc_init		; manana

; Interrupts
			call	int_init		; does not EI
			ei						; let the good times roll

;===============================================================================
; Sign on at the stdio port
;===============================================================================

TEXT_BUFFER		equ		0x80		; arbitrary place for a text input buffer
SIZEOF_BUFFER	equ		80

	if	LIGHTS_EXIST
			ld		a, 0xff				; trigger the led strobe
			ld		[led_countdown], a	; running on the interrupts
	endif

; before we sign on send some zeros to ensure everything is in sync
			ld		b, 5
			xor		a
.j1			call	serial_sendW
			djnz	.j1

			ld		hl, signon		; sign on with version info
			call	stdio_text		; leaves text in RED

; do the ram/rom test
			ld		de, RAM_TOP		; top of RAM if bios is in ROM
			ld		a, [ram_test]
			or		a
			jr		z, .j2			; running in ROM
			call	stdio_str
			YELLOW
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

; Only test the BIOS states if SW0 is not set
; (this escapes the lockout if there is sideways rom problem.
			in		a, (SWITCHES)
			and		1
			jp		nz, good_end
			CALLFAR ShowLogo1		; see macros.inc and rom.asm
			CALLFAR ShowLogo2
			xor		a				; clear the default drive
			CALLFAR SetDrive
			jr		good_end		; skip the error return

; Come here to respond with an error message and re-prompt
bad_end		ld		sp, RAM_TOP		; reset to a known value
			call	stdio_str
			RED
			db		"  ?? not understood."
			WHITE
			db		"err: "
			db		0
			ld		a, [Z.last_error]
			call	stdio_decimalB
			ld		a, ' '
			call	stdio_putc

; This is the point we return to after executing a command
good_end	ld		e, 0			; use \r\n
			jr		.j2
.j1			ld		e, 1			; clear screen entry without \n
.j2			ld		sp, RAM_TOP		; reset to a known value
			ld		a, [ram_test]	; running in RAM?
			or		a
			jr		z, .j3			; no
			ld		sp, RAM_TOPEX	; yes, grab some more space
.j3

; do the stack overflow test
			ld		hl, [Z.overflow]
			ld		a, h
			or		l
			jr		z, .j4
			call	stdio_str
			RED
			db		"\r\nPossible stack overflow"
			WHITE
			db		0
			ld		hl, 0
			ld		[Z.overflow], hl
.j4

; show the prompt
			ld		a, e
			or		a
			jr		nz, .j5
			ld		a, 0x0a			; aka '\n'
			call	stdio_putc
.j5			call	stdio_str
			db		"\r"
			GREEN
			db		0
			CALLFAR PrintCWD
			call	stdio_str
			db		"> "
			WHITE
			db		0

; get a line of input from the user
			ei
			ld		hl, TEXT_BUFFER
			ld		b, SIZEOF_BUFFER
			call	getline			; returns buffer count in D
			ld		a, d			; if an empty line fail politely
			or		a
			jp		z, good_end

; Now we want to interpret the command line
			ld		e, 0			; start from the beginning
			jp		do_commandline

;===============================================================================
; Decode the command line
;===============================================================================

; The jump table matches a command to a jump address
cmd_list	db	"BOOT"
			dw	reboot
 			db	"CD",0,0			; cd command
 			dw	cmd_cd
 if ALLOW_ANSI
 			db	"CLS",0				; clear screen
			dw	cmd_cls
 endif
 			db	"COPY"				; copy command
 			dw	cmd_copy
 			db	"CORE"				; clear memory to 0
 			dw	cmd_core
			db	"DBG",0				; DEBUG system
			dw	cmd_debug
			db	"DIR",0				; SD interface
			dw	cmd_dir
			db	"DUMP"				; dump from an address
			dw	cmd_dump
			db	"ERR",0				; error command
			dw	cmd_error
			db	"EXEC"				; execute from an address
			dw	cmd_exec
			db	"FILL"				; fill memory
			dw	cmd_fill
			db	"FLAG"				; set bitflags
			dw	cmd_flag
			db	"FLOP"				; FDC tests
			dw	cmd_flop
			db	"HEX",0				; hex test
			dw	cmd_hex
			db	"IN",0,0			; input from a port
			dw	cmd_in
			db	"KILL"				; kill
			dw	cmd_kill
 if LEDS_EXIST
			db	"LED",0				; set the LEDs
			dw	cmd_led
 endif
 			db	"LOAD"				; load command
 			dw	cmd_load
			db	"OUT",0				; output to a port
			dw	cmd_out
			db	"READ"				; read memory
			dw	cmd_read
			db	"ROM",0				; program ROM
			dw	cmd_rom
			db	"SAVE"				; save command
			dw	cmd_save
			db	"TIME"				; time set/get
			dw	cmd_time
 			db	"TYPE"				; type command
 			dw	cmd_type
			db	"W",0,0,0			; write memory
			dw	cmd_w
			db	"WAIT"				; wait command
			dw	cmd_wait
			db	"Y",0,0,0
			dw	cmd_y
			db	"Z",0,0,0			; anything test
			dw	cmd_z
			db	"?",0,0,0			; display command cheat sheet
			dw	cmd_hlp
			db	0

	assert	(($-cmd_list) % 6) == 1

; Called with HL pointer to line, D buffer count, use E as index
do_commandline

; gather up 1-4 characters in Z.cmd_exp
			ld		b, 4			; max command size
			ld		ix, Z.cmd_exp	; 4 character buffer

			call	skip			; get the first character on the line
			jp		z, .d9			; end of line (just spaces?)
			jr		.d2				; first character

.d1			call	getc			; get next character (not first)
			jp		z, .d4			; end of line
			cp		' '				; end of command?
			jp		z, .d4
			cp		0x09			; tab
			jp		z, .d4
.d2			call	islower			; test for a-z set CY if true
			jr		nc, .d3
			and		~0x20			; convert to upper case
.d3			ld		[ix], a
			inc		ix
			djnz	.d1

; we have 4 characters
			jr		.d6

; we have an end of command (either white space or the input ran out)
.d4			xor		a				; zero fill the buffer
.d5			ld		[ix], a
			inc		ix
			djnz	.d5

; first check for a drive select eg: C:
.d6			ld		a, [Z.cmd_exp+1]
			cp		':'
			jr		nz, .d7
			ld		a, [Z.cmd_exp]
			CALLFAR SetDrive
			jp		c, good_end
			jp		bad_end

; Look for match in the table
.d7			ld		iy, cmd_list	; table of commands and functions
			ld		ix, Z.cmd_exp

; Check for end of table
.d8			ld		a, [iy]			; read command list first char of a command
			or		a				; end of list?
			jr		nz, .d10		; no, so keep going

; bad end
.d9			ld		a, ERR_UNKNOWN_COMMAND
			ld		[Z.last_error], a
			jp		bad_end

; Test for match
.d10		ld		b, 4
			ld		ix, Z.cmd_exp
.d11		ld		a, [iy]			; test command letter
			cp		[ix]
			jr		nz, .d12		; fail
			inc		ix
			inc		iy
			djnz	.d11

; Match
			ld		c, [iy]			; lsbyte
			ld		b, [iy+1]		; msbyte
			ld		iy, bc
			jp		[iy]

; No match
.d12		inc		iy				; move over rest of command
			djnz	.d12
			inc		iy				; move over jump address
			inc		iy
			jp		.d8

;===============================================================================
; ?  Display help text
;===============================================================================
cmd_hlp		CALLFAR		ShowHelp
			jp			good_end

;===============================================================================
; ERR interpret last error value
;===============================================================================
cmd_error	call		stdio_str
			db			"\r\nLast error: ",0
			ld			a, [Z.last_error]
			call		stdio_decimalB
			ld			a, ' '
			call		stdio_putc
			CALLFAR		ShowError
			jp			good_end

;===============================================================================
; HEX hex echo test	HEX value24  outputs hex and decimal
;					HEX          output the current default address
;===============================================================================
cmd_hex		CALLFAR		HEXcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; COPY
;===============================================================================
cmd_copy	CALLFAR		COPYcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; DEBG
;===============================================================================
cmd_debug	CALLFAR		DEBGcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; DIR
;===============================================================================
cmd_dir		CALLFAR		DIRcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; CD
;===============================================================================
cmd_cd		CALLFAR		CDcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; TYPE
;===============================================================================
cmd_type	CALLFAR		TYPEcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; FLOP
;===============================================================================
cmd_flop	CALLFAR		FLOPcommand
			jp			c, good_end
			jp			bad_end
;===============================================================================
; LOAD
;===============================================================================
cmd_load	CALLFAR		LOADcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; READ read memory command		READ address24
;===============================================================================
cmd_read	ld		ix, [Z.def_address]		; default value
			ld		bc, [Z.def_address+2]
			call	gethex24				; in C:IX
			call	skip					; more data on line?
			jp		z, err_toomuch
			ld		[Z.def_address], ix		; save as default
			ld		[Z.def_address+2], bc

			call	stdio_str
			db		"\r\n",0
			ld		hl, ix
			call	stdio_24bit				; C:HL requested address
			ld		a, ' '
			call	stdio_putc
			call	XgetPageByte				; aka ld a, (C:IX)
			call	stdio_byte
			jp		good_end

;===============================================================================
; W write memory command 	W address24 data8 [data8] ...
;	NB: if the third data item is bad the first two have already been written
;		so I do not complain on data errors, they are just terminators
;===============================================================================
cmd_w		ld		ix, [Z.def_address]		; default value
			ld		bc, [Z.def_address+2]
			call	gethex24				; in C:IX
			ld		[Z.def_address], ix		; useful so I can use R to check it
			ld		[Z.def_address+2], bc
			ld		iy, ix					; save the address in B:IY
			ld		b, c

.cw1		call	skip					; step over spaces
			jp		z, good_end				; we have finished
			dec		e						; 'unget'
			ld		ix, 0					; default data
			call	gethexB					; in C:IX
			jp		nc, .cw2				; syntax error
			ld		a, ixl					; data in a

			ld		c, b					; recover address B:IY->C:IX
			ld		ix, iy
			call	XputPageByte				; ld (C:IX),a

			push	de						; B:IY++
			ld		de, 1
			add		iy, de					; inc iy does not set CY
			ld		a, b
			adc		0
			ld		b, a
			pop		de
			jr		.cw1

.cw2		ld		a, ERR_BADBYTE
			jp		cmd_err

;===============================================================================
; FILL fill memory command 	FILL address24 count16 data8
;===============================================================================
cmd_fill	ld		ix, [Z.def_address]		; default value
			ld		bc, [Z.def_address+2]
			call	gethex24				; in C:IX
			ld		[Z.def_address], ix		; useful so I can use R to check it
			ld		[Z.def_address+2], bc

			ld		ix, 0					; default count (0=error)
			call	gethexW
			jr		nc, .cf3
			ld		bc, ix					; BC = count
			ld		a, b					; !=0 safety trap
			or		c
			jp		z, err_outofrange
			ld		iy, bc					; save it as gethex uses BC

			ld		ix, 0					; default data
			call	gethexB
			jr		nc, cmd_w.cw2

			call	skip					; any data left?
			jp		nz, err_toomuch			; that's wrong
			ld		b, ixl

; right we have data in B, count in IY and address in (default buffer)
			ld		ix, [Z.def_address]
			ld		a, [Z.def_address+2]
			ld		c, a
			ld		a, b

.cf1		ld		a, b
			call	XputPageByte				; A->C:IX
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

.cf2		ld		a, ERR_OUTOFRANGE
			jp		cmd_err
.cf3		ld		a, ERR_BADCOUNT
			jp		cmd_err

;===============================================================================
; IN input command			IN port
;===============================================================================
cmd_in		ld		a, [Z.def_port]			; default address
			ld		ixh, 0
			ld		ixl, a
			call	gethexB					; in IXL
			jp		nc, .ci1				; address syntax
			call	skip					; more data on line?
			jp		nz, err_toomuch
			ld		a, ixl
			ld		[Z.def_port], a

			call	stdio_str
			db		"\r\n",0
			ld		c, a
			in		a, (C)					; get the byte
			call	stdio_byte
			jp		good_end

.ci1		ld		a, ERR_BADPORT
			jp		cmd_err

;===============================================================================
; OUT output command			OUT port8 data8
;===============================================================================
cmd_out		ld		ixh, 0
			ld		a, [Z.def_port]			; default address
			ld		ixl, a
			call	gethexB					; port in IXL
			jp		nc, cmd_in.ci1			; syntax in address
			ld		iy,	ix					; save port

			ld		ix, 0					; default data
			call	gethexB					; data in IXL
			jp		nc, cmd_w.cw2			; syntax in data
			call	skip					; more data on line?
			jp		nz, err_toomuch
			ld		hl, ix					; data in L

			ld		bc, iy					; recover port in C
			ld		a, c
			ld		[Z.def_port], a
			ld		a, l
			out		(c), a
			jp		good_end

;===============================================================================
; EXEC execute command    EXEC address16 in Z80 memory NOT address20
;===============================================================================
cmd_exec	ld		ix, BIOS_START			; BIOS0 start is default address
			call	gethexW					; port in IX
			jp		nc, err_badaddress		; syntax in address
			call	skip					; more on line?
			jp		nz, err_toomuch
			ld		iy, good_end			; make a 'return address'
			push	iy						; so the command can just 'ret'
			jp		[ix]

;===============================================================================
; DUMP command    DUMP address20 count16 (default=256)
;				  DUMP +  (defaddress += 256)
;===============================================================================
cmd_dump	call	skip					; start by handling the + option
			jr		z, .cd3					; no text anyway
			cp		'+'
			jr		z, .cd1
			dec		e						; unget
			jr		.cd3					; normal operation
; + option
.cd1		ld		ix, [Z.def_address]		; default address
			ld		bc, [Z.def_address+2]
			inc		ixh						; +=256
			jr		nz, .cd2				; no C on inc
			inc		bc
			ld		[Z.def_address+2], bc
.cd2		ld		[Z.def_address], ix		; all details OK
			jr		.cd4

.cd3		ld		ix, [Z.def_address]		; default address
			ld		bc, [Z.def_address+2]
			call	gethex24				; in C:IX
			jp		nc, err_badaddress		; address syntax
.cd4		ld		iy, ix					; address in C:IY

			ld		ix, 256					; default on count is 0x100
			call	gethexW
			jp		nc, err_badcount		; count syntax
			call	skip					; more on line?
			jp		nz, err_toomuch

			ld		[Z.def_address], iy		; all details OK so save
			ld		[Z.def_address+2], bc

; we have the address in C:IY and count in IX
; Add a quick heading to stop mistakes
			ld		a, c
			cp		0xff
			jr		nz, .cd4a
			call 	stdio_str
			db		"  LOCAL",0
			jr		.cd7

.cd4a		and		0x08					; set for ROM
			jr		z, .cd5
			call	stdio_str
			db		"  ROM",0
			jr		.cd6
.cd5		call	stdio_str
			db		"  RAM", 0
.cd6		ld		a, c					; get the top bits
			ld		b, iyh					; get top two bits of IY
			rl		b						; left slide B into A
			rl		a
			rl		b
			rl		a
			and		0x1f					; 0-31
			call	stdio_decimalB

; and output
.cd7		ld		hl, iy					; address in C:HL
			ld		de, ix					; count in DE
			call	stdio_dump
			jp		good_end

;===============================================================================
; CORE	clear memory
;===============================================================================
; NB: Z is the structure defining the base page of RAM that really should not be
;	  overwritten and hence Z as a value is its size in bytes
cmd_core
; blank all user RAM
			ld		bc, RAM_TOP - Z		; top of RAM if bios is in ROM
			ld		a, [ram_test]
			or		a
			jr		z, .co1				; running in ROM
			ld		bc, RAM_TOPEX - Z

.co1		ld		hl, Z
			ld		e, 0
.co2		ld		[hl], e
			inc		hl
			dec		bc
			ld		a, b
			or		c
			jr		nz, .co2

; refresh the first memory block
 			ld		hl, start_table
			ld		de, 0
			ld		bc, size_table
			ldir

			ld		hl, Z.savePage
			ld		[hl], RAM0
			inc		hl
			ld		[hl], RAM1
			inc		hl
			ld		[hl], RAM2
			inc		hl

			ld		a, 1
			ld		[ram_test], a
			ld		a, [ram_test]
			or		a
			ld		a, ROM0
			jr		z, .co3
			ld		a, RAM3
.co3		ld		[hl], a
			jp		good_end

;===============================================================================
; TIME  set/get    TIME hh:mm:ss  dd/mm/yy
;===============================================================================
cmd_time	AUTO	7				; 7 bytes of stack please
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
			jp		err_baddatetime
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
			ld		hl, [Z.Ticks]
			ld		a, [Z.Ticks+2]
			ld		c, a
			call	stdio_decimal24
			ld		a, '.'
			call	stdio_putc
			ld		a, [Z.preTick]		; @50Hz
			add		a					; as hundredths of a second
			call	stdio_decimalB2
			call	stdio_str
			db		" secs",0
			jp		good_end

;===============================================================================
; Y  the current thing being tested
;===============================================================================
cmd_y		ld		ix, 0					; default value
			ld		bc, 0
			call	gethex24				; in C:IX
			ld		hl, ix
			ld		de, bc

			ld		a, ' '
			call	stdio_putc
			ld		bc, de
			call	stdio_decimal32
			ld		a, ' '
			call	stdio_putc
			ld		bc, de
			call	stdio_32bit

			ld		a, ' '
			call	stdio_putc
			INC32

			ld		bc, de
			call	stdio_decimal32
			ld		a, ' '
			call	stdio_putc
			ld		bc, de
			call	stdio_32bit

			jp		good_end

;===============================================================================
; Z  another thing being tested
;===============================================================================
cmd_z		call	stdio_str
			db		"\r\nNMI test: ",0

			ld		hl, nmitest
			ld		[0x67], hl		; set the NMI vector to local handler
			ld		a, 0xff			; preload the 'reply'
			ld		[.saveB], a
			ld		b, 0			; item to count

.z1			ld		hl, .z2			; return address
			push	hl
			ld		hl, 0xabcd		; an example HL on stack
			push	hl
			ld		a, 0x99			; example AF on stack
			push	af

; this is a copy of what the debugger does:
			ld		a, 0x81			; enable the NMI card
			out		(MPGEN), a		; 12T
			pop		af				; 10T
			pop		hl				; 10T
			ret						; 10T

.z2			inc		b				; 4T
			inc		b
			inc		b
			inc		b				; 38 gave 3
			inc		b				; 32 gave 1
			inc		b				; 31 gave 1
			inc		b				; 30 gave 1  << run at this
			inc		b				; 29 gave 1
			inc		b				; 28 gave 0
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b
			inc		b			; that's 50 so 200T
			ld		a, [.saveB]	; recover the reply
			call	stdio_byte	; and display it
			jp		good_end

.saveB		db		0

; simple test NMI handler
nmitest		push	af
			ld		a, b				; copy the state of B
			ld		[cmd_z.saveB], a
			ld		a, 0x01				; disable the NMI card
			out		(MPGEN), a
			pop		af
			retn

;===============================================================================
; KILL  the kill command
;===============================================================================
cmd_kill	di
			halt				; just push the reset button kiddo
			jr		cmd_kill

;===============================================================================
; CLS  clear screen command
;===============================================================================
 if ALLOW_ANSI
cmd_cls		call	stdio_str
			db		"\e[H\e[2J", 0
			jp		good_end.j1
 endif
;===============================================================================
; LED command	eg:	LED 01 = LED1 off, LED2 on  LED x1 = leave LED1, LED2 on
;===============================================================================
 if LEDS_EXIST
cmd_led		ld		a, [Z.led_buffer]	; previous state
			ld		b, a				; hold in B
			call	skip				; skip blanks return next char
			jp		z, err_runout		; EOL so got nothing
			cp		'0'					; LED1 off?
			jr		nz, .cl1
			ld		a, b
			and		~0x08				; clear b3
			ld		b, a
			jr		.cl2
.cl1		cp		'1'					; LED1 on?
			jr		nz, .cl2
			ld		a, b
			or		0x08				; set b3
			ld		b, a
.cl2		call	skip				; get second character
			jr		z, .cl5				; clearly only doing LED1 today
			cp		'0'					; LED2 off?
			jr		nz, .cl3
			ld		a, b
			and		~0x01				; clear b0
			ld		b, a
			jr		.cl4
.cl3		cp		'1'					; LED2 on?
			jr		nz, .cl4
			ld		a, b
			or		0x01				; set b0
			ld		b, a
.cl4		call	skip
			jp		nz, err_toomuch		; more stuff on line is error
.cl5		ld		a, b
			ld		[Z.led_buffer], a
			call	rtc_init
			jp		good_end
 endif

;===============================================================================
; SAVE  read/write the rtc's ram		S address16 (not 20) R|W
;===============================================================================
cmd_save	ld		ix, [Z.def_address]		; default address
			call	gethexW					; in IX
			jp		nc, err_badaddress		; address syntax

			call	skip					; get the command letter
			jp		z, err_runout
			call	islower					; lower case
			jr		nc, .cp1				; no
			and		~0x20					; to uppercase
.cp1		ld		b, a					; save the 'R' or 'W'
			call	skip					; end of line
			jp		nz, err_toomuch			; oops, no
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
			jp		err_unknownaction

.cp2		call	rtc_rdram				; read ram	'R'
			jp		good_end
.cp3		call	rtc_wrram				; write ram	'W'
			jp		good_end
.cp4		call	rtc_rdclk				; read clock 'T'
			jp		good_end
.cp5		call	rtc_wrclk				; write clock 'S'
			jp		good_end

;===============================================================================
; ROM  program ROM N
;===============================================================================

cmd_rom		CALLFAR		ROMcommand
			jp			c, good_end
			jp			cmd_err

;===============================================================================
; FLAG  set diagnostic etc bit flags A-X (24 bits)
;===============================================================================
cmd_bits	db		0,0,0		; only writable in RAM mode

cmd_flag	call	skip		; first call only
			jp		z, .a6		; no commands, just display
			jr		.a2
.a1			call	skip		; subsequent calls
			jr		z, .a5		; save before display
.a2			call	isalpha
			jp		nc, err_outofrange
			and		~0x20		; force upper case
			cp		'Y'			; A=0, X=23
			jp		nc, err_outofrange
			push	hl, bc
			ld		hl, 1		; bit 0
			ld		c, 0		; work 24 bits
			sub		'A'			; convert to bit number
			jr		z, .a4		; zero so no slide
			ld		b, a
.a3			or		a			; clear carry
			rl		l			; hl << 1
			rl		h
			rl		c
			djnz	.a3
.a4			ld		a, [cmd_bits]
			xor		l
			ld		[cmd_bits], a
			ld		a, [cmd_bits+1]
			xor		h
			ld		[cmd_bits+1], a
			ld		a, [cmd_bits+2]
			xor		c
			ld		[cmd_bits+2], a
			pop		bc, hl
			jr		.a1

; save flags
.a5			ld		hl, Z.rtc_buffer
			call	rtc_rdram
			ld		a, [cmd_bits]
			ld		[Z.rtc_buffer], a
			ld		a, [cmd_bits+1]
			ld		[Z.rtc_buffer+1], a
			ld		a, [cmd_bits+2]
			ld		[Z.rtc_buffer+2], a
			ld		hl, Z.rtc_buffer
			call	rtc_wrram

; display flags
.a6			call	stdio_str
			db		"\r\n", 0
			ld		a, 24
			ld		b, a
			ld		c, 'A'
			ld		hl, [cmd_bits]
			ld		a, [cmd_bits+2]
			ld		e, a
.a7			ld		a, '.'
			rr		e
			rr		h
			rr		l
			jr		nc, .a8
			ld		a, c
.a8			call	stdio_putc		; write A
			inc		c
			djnz	.a7
			jp		good_end

;===============================================================================
; WAIT 	if SW7 is on idle with the interrupts on until it goes off
;===============================================================================

cmd_wait	CALLFAR		WAITcommand
			jp			c, good_end
			jp			bad_end

;===============================================================================
; functions we make available to other RAMs
;===============================================================================
bios_functions
			dw		f_abc
bios_count	equ		($-bios_functions)/2

f_abc		ret

;===============================================================================
; Error loaders so I can just jp cc, readable_name
;===============================================================================
err_badaddress
			ld		a, ERR_BAD_ADDRESS
cmd_err		ld		[Z.last_error], a
			jp		bad_end
err_toomuch
			ld		a, ERR_TOOMUCH
			jr		cmd_err
err_outofrange
			ld		a, ERR_OUTOFRANGE
			jr		cmd_err
err_badcount
			ld		a, ERR_BADCOUNT
			jr		cmd_err
err_runout
			ld		a, ERR_RUNOUT
			jr		cmd_err
err_badblock
			ld		a, ERR_BADBLOCK
			jr		cmd_err
err_baddatetime
			ld		a, ERR_BADDATETIME
			jr		cmd_err
err_unknownaction
			ld		a, ERR_UNKNOWNACTION
			jr		cmd_err
err_manana
			ld		a, ERR_MANANA
			jr		cmd_err
err_badrom
			ld		a, ERR_BADROM
			jr		cmd_err

 if SHOW_MODULE
	 	DISPLAY "bios0 size: ", /D, $-BIOS_START
 endif

