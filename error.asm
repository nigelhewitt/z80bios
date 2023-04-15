;===============================================================================
;
;	error.asm	Convert Z:last_error to text message
;				Since I'm bursting into multi-rom bios I can stop
;				being frugal with my bytes
;
;===============================================================================

error_start		equ	$
error_list
	dw	err_0
	dw	err_1
	dw	err_2
	dw	err_3
	dw	err_4
	dw	err_5
	dw	err_6
	dw	err_7
	dw	err_8
	dw	err_9
	dw	err_10
	dw	err_11
	dw	err_12
	dw	err_13
	dw	err_14
	dw	err_15

max_error	equ	($-error_list)/2

err_0		db	"No error", 0						; ERR_NO_ERROR
err_1		db	"Unknown command", 0				; ERR_UNKNOWN_COMMAND
err_2		db	"Syntax error in Address", 0		; ERR_BAD_ADDRESS
err_3		db	"More stuff on line", 0				; ERR_TOOMUCH
err_4		db	"Bad byte data", 0					; ERR_BADBYTE
err_5		db	"Out of range", 0					; ERR_OUTOFRANGE
err_6		db	"Syntax error in count", 0			; ERR_BADCOUNT
err_7		db	"Syntax error in Port", 0			; ERR_BADPORT
err_8		db	"Run out of data", 0				; ERR_RUNOUT
err_9		db	"Bad block", 0						; ERR_BADBLOCK
err_10		db	"Syntax error in date or time", 0	; ERR_BADDATETIME
err_11		db	"Unknown qualifier", 0				; ERR_UNKNOWNACTION
err_12		db	"Sorry, not coded yet", 0			; ERR_MANANA
err_13		db	"Bad rom selection", 0				; ERR_BADROM
err_14		db	"This code must run in RAM",0		; ERR_NOTINRAM
err_15		db	"Bad far function call",0			; ERR_BADFUNCTION

err_X		db	"Unknown error", 0

f_error		push	af, hl, de
			ld		hl, error_list
			ld		de, [Z.last_error]
			ld		a, d
			or		a
			jr		nz, .se2
			ld		a, e
			cp		max_error
			jr		nc, .se2
; convert number to message
			sla		e
			rl		d
			ld		hl, error_list
			add		hl, de
			ld		a, [hl]			; ld hl, (hl)
			inc		hl
			ld		h, [hl]
			ld		l, a
.se1		call	stdio_text
; clear last_error
			or		a
			ld		[Z.last_error], a
			pop		de, hl, af
			jp		good_end		; exit
.se2		ld		hl, err_X		; unknown error
			jr		.se1

;===============================================================================
;
; show_help
;
;===============================================================================

cmd_help	db	"\r\n"
			db	"BOOT  Hard reset.\r\n"
 if ALLOW_ANSI
 			db	"CLS   Clear screen.\r\n"
 endif
 			db	"x:    Select a drive currently A,C or D. 0: resets disk system.\r\n"
 			db	"CD    Change the current folder.\r\n"
 			db	"      The current drive:folder is prefixed to the prompt.\r\n"
			db	"CORE  Zero all of user RAM and refresh the reset vectors et al.\r\n"
			db	"DEBG  Call the debugger\r\n"
 			db	"DIR   Lists the files in the current folder.\r\n"
			db	"DUMP  Dump from an address in hex/chars mode. DUMP address24 [count16]\r\n"
			db	"ERR   Get the text description of the last error code recorded.\r\n"
			db	"EXEC  Execute from an address16=0x100\r\n"
			db	"FILL  Fill memory   FILL start24 count16 value8\r\n"
			db	"FLAG  [A-Y] set/clear and show diagnostic flags.\r\n"
			db	"HEX   Hex test, echo numbers and values.\r\n"
			db	"IN    Input from a port. IN address8\r\n"
			db	"KILL  Interrupt off, halt.\r\n"
 if LEDS_EXIST
			db	"LED   Set the LEDs   LED 1=on,0=off,all else skip to next.\r\n"
 endif
			db	"LOAD  Load a file into memory  LOAD filename [address24=0x100]\r\n"
			db	"ROM   Program ROM options I|E|P|W - incomplete\r\n"
			db	"OUT   Output to a port. OUT address8 value8\r\n"
			db	"READ  Read memory. READ address24\r\n"
			db	"SAVE  Save to RTC RAM.  SAVE address R=read|W=write|T=read clock|S=write clock\r\n"
			db	"TIME  Time set/get   t [21:55[:45]] [26/03/[20]23]\r\n"
			db	"TYPE  type a file.  TYPE filename .screenlines8{24] .screenwidth8[80]\r\n"
			db	"W     Write memory   w address20 value8 value8 value8...\r\n"
;			db	"Y     Whatever I am currently testing\r\n"
;			db	"Z     Something to test\r\n"
			db	"WAIT  Switch to ROM2 and wait while SW7 is down with interrupts on\r\n"
			db	"?     List commands\r\n"
			db	"\n"
			db	"Where and example is given [optional argument are in brackets]\r\n"
			db	"  and the default value is marked with =.\n\r"
			db	"address16  16 bit address in the currently mapped memory\r\n"
			db	"address24  Full 1Mb address range in 0-0x7ffff for RAM and\r\n"
			db	"           0x80000-0xfffff for ROM and 0xffxxxx for an address\r\n"
			db	"           in the mapped memory as addressed by the Z80.\r\n"
			db 	"address8/value8 are 8 bit values\n\r"
			db	"Most items just take hex by default other then the clock settings.\r\n"
			db  "Prefix with $123 to force hex, .123 to force decimal\r\n"
			db	"use 'X to make an 8 bit ascii value.\r\n"
			db	0

f_help		ld		hl, cmd_help
			call	stdio_text
			jp		good_end

 if SHOW_MODULE
	 	DISPLAY "error size: ", /D, $-error_start
 endif
