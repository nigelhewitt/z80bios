;===============================================================================
;
; STDIO.asm		redirectable text io
;
;===============================================================================

; currently  have only two ways to input/output from these routines
; to serial or to strings. I wanted a data location that wasn't in RAM
; to select this but the only reasonable one to do this at speed is
; the io byte at (UART+7)
; zero means use serial_sendW/serial_read
; 1 means write to (IY++)
;
;===============================================================================

; stdio redirect: 0=serial (official), 1=IY++ else got to serial (debug)

; write the character in A
stdio_putc
		push	af				; do the most common first and fastest
		in		a, (REDIRECT)
		cp		1
		jr		z, .sp1
		pop		af
		jp		serial_sendW
.sp1	pop		af
		ld		(iy), a
		inc		iy
		ret

; wait for and return a character in A
stdio_getc
		in		a, (UART+6)
		cp		1
		jp		nz, serial_read
		ld		a, (iy)
		or		a
		ret		z				; stick at a null
		inc		iy
		ret

; output null terminated string starting at HL
; uses AF
stdio_text
		ld		a, (hl)				; test the next character
		or		a					; trailing null?
		ret		z					; finished
		call	stdio_putc			; send the character
		inc		hl					; move to the next character
		jr		stdio_text

;===============================================================================
;
; stdio_str		a simple all inline text writer
;				call	 stdio_str
;				db		"null terminated string", 0
;				... more code
;				uses nothing so good for debugging
;===============================================================================

; uses nothing
stdio_str	ex		(sp), hl		; old return address in HL, HL on stack
			push	af
.str1		ld		a, (hl)			; character from string
			inc		hl
			or		a
			jr		z, .str2
			call	stdio_putc
			jr		.str1
.str2		pop		af
			ex		(sp), hl		; recover HL, set new return address
			ret

;===============================================================================
;
; getline()		call with	HL = pointer to buffer
;							B  = sizeof buffer
;				returns		D  = number of characters in buffer
;							buffer may overrun and contain trash
;
; This is a very simple routine that runs full duplex so it echoes the
; characters typed and only the only editing it accepts is a destructive
; backspace. It does not do tabs and it terminates on \r or \n.
; Added: trash escape sequences aka \e.*[A-Za-z]
;
;===============================================================================

getline								; HL = pointer to buffer, B=sizeof buffer
		ld		d, 0				; index into line

.g1		call	stdio_getc			; get a keystroke

; if enter just return
		cp		0x0a				; ^J line feed
		ret		z
		cp		0x0d				; ^M enter
		ret		z

; if backspace decrement count and send "\b \b"
		cp		0x08				; ^H destructive backspace
		jr		nz, .g2
		ld		a, d				; test for index == 0
		or		a
		jr		z, .g1				; ignore
		dec		d
		ld		a, 0x08				; <BS>
		call	stdio_putc
		ld		a, 0x20				; ' '
		call	stdio_putc
		ld		a, 0x08				; <BS>
		call	stdio_putc
		jr		.g1

; if ESC start rejecting characters until we get a letter
.g2		cp		0x1b				; <ESC>
		jr		nz, .g4
.g3		call	stdio_getc			; next character
		cp		0x0d				; get out on <ENTER>
		ret		z					; end of line regardless
		call	isalpha				; set CY if [A-Za-z]
		jr		nc, .g3				; loop
		jr		.g1					; end loop, get next char

; if we get to here it is an 'ordinary' character
.g4		ld		e, a				; save it in E
; do we have room left in the buffer?
		ld		a, d				; get index
		inc		a					; index+1 (if we are full b==d)
		cp		b
		jr		nz, .g5
;;		call	beep
		jr		.g1
; place in at buffer[index++]
.g5		push	hl					; pointer to base of buffer
		ld		a, l				; HL = HL + D (index)
		add		d					; set CY on overflow
		ld		l, a
		jr		nc, .g6
		inc		h
.g6		ld		a, e				; recover the character
		ld		(hl), a				; save the char
		call	stdio_putc			; echo character to screen (FULL DUPLEX)
		pop		hl
		inc		d
		jr		.g1

;===============================================================================
; stdio formatted outputs
;===============================================================================

; all use A
stdio_24bit	ld		a, c			; C:HL in hex
			call	stdio_byte
			jr		stdio_word
stdio_20bit	ld		a, c
			call	stdio_nibble
			; fall through
stdio_word							; HL in hex
			ld		a, h
			call	stdio_byte
			ld		a, l
			; fall through
stdio_byte							; A in hex
			push	af
			srl		a				; a>>=4
			srl		a
			srl		a
			srl		a
			call	stdio_nibble
			pop		af
			and		0x0f
			; fall through
stdio_nibble
			add		0x90			; kool trick
			daa						; if a nibble is >0x9 add 6
			adc		0x40
			daa
			jp		stdio_putc

			; input HL, output HL/10 with remainder in A use nothing else
			; uses the 16/16 routine it's good
div10		push	bc
			push	de
			ld		bc, hl			; BC = quotient
			ld		de, 10			; DE = divisor
			call	div16x16		; BC = result, HL = remainder
			ld		a, l			; cannot be >=10
			ld		hl, bc
			pop		de
			pop		bc
			ret

div10b24			; divide C:HL by 10, result in C:HL, remainder in A
					; uses B
			push	de
			ld		de, hl
			ld		b, 0
			ld		hl, 10
			call	divide32by16	; call BC:DE = numerator, HL = denominator
									; returns BC:DE = result, HL = remainder
			ld		a, l
			ld		hl, de
			pop		de
			ret

; The ...B2 and ...W4 versions zero fill to give minimum lengths
; mainly added for dates and times
; you always get one digit so 0 is 0

stdio_decimalB3				; A in decimal with at least three digits
			push	af
			cp		10			; CY if <10
			jr		c, .sd1		; needs "00"
			cp		100			; CY if a<100
			jr		c, .sd2		; needs "0"
			jr		.sd3
.sd1		ld		a, '0'
			call	stdio_putc
.sd2		ld		a, '0'
			call	stdio_putc
.sd3		pop		af
			jr		stdio_decimalB

stdio_decimalB2				; A in decimal with at least two digits
			cp		10		; CY if a<10
			jr		nc, stdio_decimalB
			push	af
			ld		a, '0'
			call	stdio_putc
			pop		af
			; fall through
stdio_decimalB				; A in decimal
			push	hl
			ld		h, 0
			ld		l, a
			call	stdio_decimalW
			pop		hl
			ret

; compare HL to N : return Z for HL==N, NC for HL>=N CY for HL<N
CPHL		macro	n
			ld		a, h
			cp		high n
			jr		c, .cphl1	; n>HL so return CY and NZ
			jr		nz, .cphl1	; n<HL so return NC and NZ
			ld		a, l		; we get here on h == high n
			cp		low n		; setCY and Z flags on L
.cphl1
			endm

stdio_decimalW4				; HL in decimal with at least 4 digits
			CPHL	10
			ld		a, '0'
			jr		c, .sd1	; HL<10 so prefix with 000
			CPHL	100
			ld		a, '0'
			jr		c, .sd2	; 00
			CPHL	1000
			ld		a, '0'
			jr		c, .sd3	; 0
			jr		stdio_decimalW

.sd1		call	stdio_putc
.sd2		call	stdio_putc
.sd3		call	stdio_putc
			; fall through
stdio_decimalW				; HL in decimal
			push	hl				; save the value
			call	div10			; HL=HL/10, A=HL%10  (aka remainder)
			push	af				; save remainder for this digit
			ld		a, h			; test zero
			or		a, l
			call	nz, stdio_decimalW	; recursive
			pop		af
			pop		hl
			add		'0'
			jp		stdio_putc

stdio_decimal24				; C:HL in decimal
			push	hl				; save the value
			push	bc
			push	de
			call	div10b24		; C:HL=C:HL/10, A=C:HL%10  (aka remainder)
			pop		de
			push	af				; save remainder for this digit
			ld		a, h			; test zero
			or		a, l
			call	nz, stdio_decimal24	; recursive
			pop		af
			pop		bc
			pop		hl
			add		'0'
			jp		stdio_putc

;===============================================================================
; basic text handling
;===============================================================================

; Test for uppercase, return CY if true
isupper		cp		'A'				; set CY if A < 'a'
			ccf						; make that unset
			ret		nc				; fail
			cp		'Z'+1			; set CY of A < 'Z'+1
			ret

; test for alpha, return CY if true
isalpha		call	isupper			; as above
			ret		c				; it's alpha
			; fall through

; Test for lowercase, return CY if true
islower		cp		'a'				; set CY id a < 'a'
			ccf						; complement carry
			ret		nc				; NC if a<'a'
			cp		'z'+1			; set CY if a< 'z'+1
			ret

; Test char in a in range 0-9 return CY if true, return A intact
isdigit		cp		'0'				; set CY if <= '0'
			ccf						; complement CY
			ret		nc				; return false as less than '0'
			cp		'9'+1			; set CY if <= '9'
			ret

; Test char for in A in range [0-9A-Fa-f] and return CY if true
; if true return A as uppercase
ishex		call	isdigit				; return C if [0-9]
			ret		c
			push	bc
			ld		b, a				; save the char
			call	islower				; is it lower case? [a-z]
			jr		nc, .ix1			; no
			and		~0x20				; convert to uppercase
.ix1		cp		'A'					; set CY if a<'A'
			jr		nc, .ix3			; jr if >= 'A'
.ix2		ld		a, b				; fail exit: recover the raw char
			pop		bc
			cp		a					; aka clear CY
			ret
.ix3		cp		'F'+1				; set CY if a<'F'+1
			jr		nc, .ix2			; jr if a >= 'F'+1 so false - recover
			pop		bc					; discard saved char and ret uppercase
			ret

; Return hex from a pretested hex digit (so only [0-9A-F] is supplied)
tohex		cp		'A'
			jr		c, .tx1				; a < 'A' so 0-9
			sub		'A'-10
			ret
.tx1		sub		'0'
			ret

;===============================================================================
;  stdio_dump		format a dump of memory
;===============================================================================
stdio_dump			; C:HL = pointer, DE = count, uses A
			push	bc
			push	ix
			ld		ix, hl					; move pointer to C:IX
; do a line
.sd1		ld		a, 0x0d					; '\r'
			call	stdio_putc
			ld		a, 0x0a					; '\n'
			call	stdio_putc
			ld		hl, ix
			call	stdio_20bit				; write C:HL as address
			ld		a, ' '					; ' '
			call	stdio_putc
; how many bytes to do this row at a max of 16?
			ld		a, d					; count msbyte
			or		a						; >256 so do 16
			jr		nz, .sd2				; use 16
			ld		a, e
			cp		16						; CY if A < 16
			jr		c, .sd3					; a<16 so use it
.sd2:		ld		a, 16
.sd3:		ld		b, a					; counter in b
			ld		h, 16					; number of slots left for blanking
; save details for the character pass
			push	de						; save count
			push	bc						; save for count and C for address
			push	ix						; save pointer
; do the hex version
.sd4		call	getPageByte				; get the byte from C:IX
			call	stdio_byte
			ld		a, h					; blank counter
			cp		9
			ld		a, ' '
			jr		nz, .sd5
			ld		a, '-'
.sd5		call	stdio_putc
			call	incCIX					; increment C:IX
			dec		h						; max--
			djnz	.sd4					; actual count--
			ld		a, h					; do we have any blanks to do?
			or		a
			jr		z, .sd7					; no
			add		a						; *2
			add		h						; *3
			ld		b, a
.sd6		ld		a, ' '					; "   "		; padding
			call	stdio_putc
			djnz	.sd6
; do the character version
.sd7		pop		ix						; address
			pop		bc						; line count and C of address
			pop		de						; counter
			ld		l, b					; save actual count for this line
.sd8		call	getPageByte				; get the byte
			cp		0x20					; blank out 0-0x1f
			jr		c, .sd9					; CY if a<0x20
			cp		0x7f					; CY if a<0x7f
			jr		c, .sd10
.sd9		ld		a, ' ' 					; '·'
.sd10		call	stdio_putc
			call	incCIX					; increment address
			dec		de						; decrement counter
			djnz	.sd8
; set up for next line
			ld		a, e					; check DE==0
			or		d
			ld		e, a
			ld		a, d
			jr		nz, .sd1				; do the next line
			pop		ix
			pop		bc
			ret

;===============================================================================
; Unpack the buffer for commands
; buffer HL, max count D, current index E
;===============================================================================

; Get char at (HL+E) in A, E++,  return zero, Z and NC if EOL and do not E++
getc		ld		a, e			; current index
			cp		d				; subtract length of line (must cy)
			jr		nc, .getc2		; bad
			push	hl
			ld		a, l			; HL += A
			add		e
			ld		l, a
			jr		nc, .getc1
			inc		h
.getc1		ld		a, (hl)			; get the next char
			pop		hl
			inc		e				; sets NZ
			scf						; return NZ, CY and data
			ret
.getc2		sub		a				; Z, NC and zero
			ret
; ungetc would just be 'dec e' so I'm not wrapping that in a subroutine

;-------------------------------------------------------------------------------
; Skip spaces returning next character (and NZ) or zero for EOL (and Z)
;-------------------------------------------------------------------------------
skip		call	getc			; returns Z and NC on EOL
			ret		z				; EOL NC and Z
			cp		0x20			; space
			jr		z, skip
			cp		0x08			; tab
			jr		z, skip
			scf
			ret						; return NZ on not EOL

; NB: to test if the rest of the line is clear call skip and NZ is error state

;===============================================================================
; gethex	Unpack a hex string in buffer HL, max count D, current index E
; 			Return a 24 bit value in C:IX with CY for OK, NC for syntax error
;			or overflow
; 			If the line is blank that returns C:IX unchanged as a default with
;			CY set
; 			uses BC
;===============================================================================
; As a user convenience if gethex is called but the number starts with a '.'
; we discard the '.' and divert to get a decimal number similarly a '$' forces
; hex. Hence .$.$.$5 has it bouncing about but it still gives 5
; 'A give you the ascii value of A
; # just accepts the default and moves on to the next argument

gethex		call	skip			; get the first character
			jr		nz, .gh3		; jump if not EOL
			inc		e				; cheaper than jumping over the unget
.gh1		dec		e				; unget
.gh2		scf						; return good
			ret
.gh3		cp		'.'
			jr		z, getdecimal
			cp		0x27			; '
			jr		z, .gh6
			cp		'$'
			jr		z, gethex
			cp		'#'
			jr		z, .gh2
			ld		ix, 0			; remove default
			ld		c, 0
; Now process the characters
.gh4		call	ishex			; test for hex and make upper case
			jr		nc, .gh1		; failed hex test so unget and return
			call	tohex			; returns 0x00 to 0x0f in A
; C:IX <<= 4
			ld		b, 4
.gh5		add		ix, ix			; aka ix<<1 into CY (yes it does set CY)
			rl		c				; rotate left through carry
			ccf						; complement carry
			ret		nc				; overflow so bad ending
			djnz	.gh5
; C:IX |= a
			push	de
			ld		d, 0
			ld		e, a
			add		ix, de			; we made 4 spaces and de is 0-f so no CY
			pop		de
; Next character
			call	getc
			jr		z, .gh2			; EOL so return OK
			jr		.gh4			; more text must be more hex so go do it
; process a single ascii character as 'C			
.gh6		call	getc			; get the next character
			jr		z, gh10			; EOL is a bust
			ld		ix, 0
			ld		ixl, a
			ld		c, 0
			jr		.gh2			; return good

; gethex20	gets a 20 bit address in C:IC
gethex20	call	gethex
			ld		a, c
			and		0xf0
			jr		z, gh8			; good end
			jr		gh10			; bad end
			
; gethexW	as above but preserves BC and returns NC on overflow into C
gethexW		push	bc
			ld		c, 0			; default
			call	gethex
			jr		nc, gh9			; failed
			ld		a, c
			or		a
			jr		nz, gh9			; overflow
gh7			pop		bc				; good end with pop
gh8			scf
			ret

; gethexB	as above but preserves BC and returns NC on overflow into C or IXH
gethexB		push	bc
			ld		c, 0			; default
			call	gethex
			jr		nc, gh9			; bad end
			ld		a, ixh
			or		c
			jr		z, gh7			; no overflow
gh9			pop		bc				; bad end with pop
gh10		xor		a				; clear carry
			ret						; bad end

;===============================================================================
; getdecimal	as above but in decimal
;				string in buffer HL, max count D, current index E
;				return value in C:IX with CY for OK, NC for syntax error or
;				overflow
;				If the line is blank that returns C:IX unchanged as default and
;				CY set
;===============================================================================
getdecimal	call	skip			; get first char
			jr		nz, .gd3		; jump if not EOL
			inc		e				; prevent the unget if EOL
.gd1		dec		e				; unget
.gd2		scf						; return good
			ret
.gd3		cp		'.'				; skip '.'
			jr		z, getdecimal
			cp		'$'				; is hex
			jp		z, gethex
			cp		'#'				; accept default
			jr		z, .gd2
			cp		0x27			; '
			jr		z, gethex.gh6
			ld		ix, 0			; remove default
			ld		c, 0
; Now process the characters
.gd4		call	isdigit			; test for decimal
			jr		nc, .gd1		; failed decimal test so unget and return
			sub		'0'				; convert to a number
; C:IX *= 10
			push	de
			push	af
			add		ix, ix			; *2, sets CY f overflow
			rl		c
			jr		c, .gd5			; C overflows
			ld		de, ix			; save *2 value in A:DE
			ld		a, c
			add		ix, ix			; *4
			rl		c
			jr		c, .gd5			; overflow
			add		ix, ix			; *8
			rl		c
			jr		c, .gd5			; overflow
			add		ix, de			; *10
			adc		a, c			; really adc c, a
			ld		c, a
			jr		c, .gd5			; overflow
			pop		af				; recover the value
			ld		d, 0
			ld		e, a
			add		ix, de			; +A
			ld		a, c			; inc c would not set CY on over
			adc		0
			ld		c, a
.gd5		pop		de				; come here with CY set for bad end
			ccf						; complement carry
			ret		nc				; bad ending
; Next character
			call	getc
			jr		z, .gd2			; EOL so return OK
			jr		.gd4			; should be more digits so go do it

; getdecimalW	as above but preserves BC and returns NC on overflow into C
getdecimalW	push	bc
			ld		c, 0				; default
			call	getdecimal
			jr		nc, getdecimalB.gd7	; bad end
			ld		a, c
			or		a
			jr		nz, getdecimalB.gd7	; overflow
.gd6		scf							; good end
			pop		bc
			ret

; getdecimalB	as above but preserves BC and returns NC on overflow into C or IXH
getdecimalB	push	bc
			ld		c, 0				; default
			call	getdecimal
			jr		nc, .gd7			; bad end
			ld		a, ixh
			or		c
			jr		z, getdecimalW.gd6	; no overflow
.gd7		xor		a					; clear carry
			pop		bc
			ret							; bad end

