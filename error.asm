;===============================================================================
;
;	error.asm	Convert Z:last_error to text message
;				Since I'm bursting into multi-rom bios I can stop
;				being frugal with my bytes
;
;===============================================================================

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
			jp		f_good			; exit
.se2		ld		hl, err_X		; unknown error
			jr		.se1

;===============================================================================
;
; show_help
;
;===============================================================================

cmd_help	db	"\r\n"
			db	"A  [A-P] set/clear diagnostic flags\r\n"
			db	"B  read a block of data to an address\r\n"
 if ALLOW_ANSI
 			db	"C  clear screen\r\n"
 endif
			db	"D  dump from an address\r\n"
			db	"E  last error text\r\n"
			db	"F  fill memory\r\n"
			db	"H  hex test\r\n"
			db	"I  input from a port\r\n"
			db	"K  kill\r\n"
 if LEDS_EXIST
			db	"L  set the LEDs\r\n"
 endif
			db	"N  program ROM options I|E|P|W\r\n"
			db	"O  output to a port\r\n"
			db	"R  read memory\r\n"
			db	"S  save command\r\n"
			db	"T  time set/get\r\n"
			db	"W  write memory\r\n"
			db	"X  execute from an address\r\n"
			db	"Z  anything test\r\n"
			db	"?  list commands"
			db	0

f_help		ld		hl, cmd_help
			call	stdio_text
			jp		f_good
