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

; write the character in A, uses nothing
stdio_putc
		push	af				; do the most common first and fastest
		in		a, (REDIRECT)
		cp		1
		jr		z, .sp1
		pop		af
		jp		serial_sendW	; uses nothing
.sp1	pop		af
		ld		[iy], a
		inc		iy
		ret

; wait for and return a character in A, uses A only
stdio_getc
		in		a, (REDIRECT)
		cp		1
		jp		nz, serial_read
		ld		a, [iy]
		or		a
		ret		z				; stick at a null
		inc		iy
		ret

; output null terminated string starting at HL, uses nothing
stdio_text
		push	af
.st1	ld		a, [hl]				; test the next character
		or		a					; trailing null?
		jr		z, .st2				; not
		call	stdio_putc			; send the character
		inc		hl					; move to the next character
		jr		.st1
.st2	pop		af
		ret
;===============================================================================
;
; stdio_str		a simple all inline text writer
;				call	 stdio_str
;				db		"null terminated string", 0
;				... more code
;				uses nothing so good for debugging
;===============================================================================
stdio_str	ex		[sp], hl		; old return address in HL, HL on stack
			push	af
.str1		ld		a, [hl]			; character from string
			inc		hl
			or		a
			jr		z, .str2
			call	stdio_putc
			jr		.str1
.str2		pop		af
			ex		[sp], hl		; recover HL, set new return address
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
; Will trash escape sequences aka \e.*[A-Za-z]
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
		ld		[hl], a				; save the char
		call	stdio_putc			; echo character to screen (FULL DUPLEX)
		pop		hl
		inc		d
		jr		.g1

;===============================================================================
; stdio formatted outputs
;===============================================================================

;-------------------------------------------------------------------------------
; hex outputs:	all use nothing
; since hex automatically zero fills we have various size variants as we
; use 20 bit addresses et al.
;-------------------------------------------------------------------------------

stdio_32bit	push	af				; BC:HL in hex
			push	hl
			ld		hl, bc
			call	stdio_word
			pop		hl
			jr		stdio_word.sw1

stdio_24bit	push	af				; C:HL in hex
			ld		a, c
			call	stdio_byte
			jr		stdio_word.sw1

stdio_20bit	push	af				; C:HL in hex
			ld		a, c
			call	stdio_nibble
			jr		stdio_word.sw1

stdio_word	push	af				; HL in hex
.sw1		ld		a, h
			call	stdio_byte
			ld		a, l
			call	stdio_byte
			pop		af
			ret

stdio_byte	push	af				; A in hex
			srl		a				; a>>=4
			srl		a
			srl		a
			srl		a
			call	stdio_nibble
			pop		af
			; fall through
stdio_nibble						; A b3-0 in hex
			push	af
			and		0x0f
			add		0x90			; kool trick
			daa						; if a nibble is >0x9 add 6
			adc		0x40
			daa
			call	stdio_putc		; uses nothing
			pop		af
			ret

;-------------------------------------------------------------------------------
;  decimal outputs : all use nothing
;-------------------------------------------------------------------------------

; div10	input HL, output HL/10 with remainder in A use nothing else
;		uses the 16/16 routine as it's good and fast
div10		push	bc, de
			ld		bc, hl			; BC = quotient
			ld		de, 10			; DE = divisor
			call	div16x16		; BC = result, HL = remainder
			ld		a, l			; cannot be >=10
			ld		hl, bc
			pop		de, bc
			ret

; div10b32  divide BC:HL by 10, result in BC:HL, remainder in A
div10b32	push	de
			ld		de, hl
			ld		hl, 10
			call	divide32by16	; call BC:DE = numerator, HL = denominator
									; returns BC:DE = result, HL = remainder
			ld		a, l			; remainder
			ld		hl, de			; LSW of result
			pop		de
			ret

; The ...B2 and ...W4 versions zero fill to give minimum lengths
; mainly used for dates and times
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

; compare HL to N : return Z for HL==N, NC for HL>=N CY for HL<N uses A
; (same results as with A in CP N)
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
			push	af
			CPHL	10
			ld		a, '0'
			jr		c, .sd1	; HL<10 so prefix with 000
			CPHL	100
			ld		a, '0'
			jr		c, .sd2	; 00
			CPHL	1000
			ld		a, '0'
			jr		c, .sd3	; 0
			jr		stdio_decimalW.sd1

.sd1		call	stdio_putc
.sd2		call	stdio_putc
.sd3		call	stdio_putc
			jr		stdio_decimalW.sd1

stdio_decimalW				; HL in decimal
			push	af
.sd1		push	hl				; save the value
			call	div10			; HL=HL/10, A=HL%10  (aka remainder)
			push	af				; save remainder for this digit
			ld		a, h			; test zero
			or		a, l
			call	nz, stdio_decimalW	; recursive
			pop		af
			add		'0'
			call	stdio_putc
			pop		hl, af
			ret

; I'm not messing about with zero fill on 32 bit
stdio_decimal32				; BC:HL in decimal
			push	af, hl, bc, de
			call	div10b32		; BC:HL=BC:HL/10, A=BC:HL%10  (aka remainder)
			pop		de
			push	af				; save remainder for this digit
			ld		a, h			; test zero
			or		a, l
			call	nz, stdio_decimal32	; recursive
			pop		af, bc, hl
			add		'0'
			call	stdio_putc
			pop		af
			ret

stdio_decimal24				; C:HL in decimal
			push	af
			ld		a, b
			ld		b, 0
			call	stdio_decimal32
			ld		b, a
			pop		af
			ret

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

; Return hex value from a pretested hex digit (so only [0-9A-F] is supplied)
tohex		cp		'A'
			jr		c, .tx1				; a < 'A' so 0-9
			sub		'A'-10
			ret
.tx1		sub		'0'
			ret

;===============================================================================
;  stdio_dump		format a dump of memory
;===============================================================================
stdio_dump			; C:HL = pointer, DE = count, uses HL and DE
			push	af, bc, ix
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
			pop		ix, bc, af
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
.getc1		ld		a, [hl]			; get the next char
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
; 			Return a 32 bit value in BC:IX with CY for OK, NC for syntax error
;			or overflow
; 			If the line is blank that returns BC:IX unchanged as a default with
;			CY set
;===============================================================================
; As a user convenience if gethex is called but the number starts with a '.'
; we discard the '.' and divert to get a decimal number similarly a '$' forces
; hex. Hence .$.$.$5 has it bouncing about but it still gives 5
; 'A give you the ascii value of A
; # just accepts the default and moves on to the next argument

gethex32	call	skip			; get the first character
			jr		nz, .gh3		; jump if not EOL
			inc		e				; cheaper than jumping over the unget
.gh1		dec		e				; unget
.gh2		scf						; return good
			ret
.gh3		cp		'.'
			jp		z, getdecimal
			cp		0x27			; '
			jr		z, .gh6
			cp		'$'
			jr		z, gethex32
			cp		'#'
			jr		z, .gh2
			ld		ix, 0			; remove the default
			ld		bc, 0

; Now process the characters
.gh4		call	ishex			; test for hex and make upper case
			jr		nc, .gh1		; failed hex test so unget and return
			call	tohex			; returns 0x00 to 0x0f in A

; BC:IX <<= 4
			push	de, hl
			ld		de, bc
			ld		hl, ix
			ld		b, 4
.gh5		sla		l
			rl		h
			rl		e
			rl		d
			ccf
			jp		nc, .gh7		; overflow
			djnz	.gh5
			ld		bc, de

; C:IX |= a
			add		l				; we made 4 spaces and de is 0-f so no CY
			ld		l, a
			ld		ix, hl
			pop		hl, de

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
			
; stack unwind for overflow return
.gh7		pop		hl, de
			or		a				; clear carry
			ret

; Restricted versions of gethex32 that preserve the registers we don't use and
; overflow as appropriate			

; gethex20	gets a 20 bit address in C:IX
gethex20	call	gethex32
			ld		a, c
			and		0xf0
			or		b
			jr		z, gh8			; good end
			jr		gh10			; bad end

; gethexW	as above but preserves BC and returns NC on overflow into BC
gethexW		push	bc
			ld		bc, 0			; default
			call	gethex32
			jr		nc, gh9			; failed
			ld		a, c
			or		b
			jr		nz, gh9			; overflow
gh7			pop		bc				; good end with pop
gh8			scf
			ret

; gethexB	as above but preserves BC and returns NC on overflow into BC or IXH
gethexB		push	bc
			ld		bc, 0			; default
			call	gethex32
			jr		nc, gh9			; bad end
			ld		a, ixh
			or		c
			or		b
			jr		z, gh7			; no overflow so good end
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
			jp		z, gethex32
			cp		'#'				; accept default
			jr		z, .gd2
			cp		0x27			; '
			jr		z, gethex32.gh6
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
			ld		a, [Z.snap_mode]
			or		a
			ld		hl, 12			; stack depth since call (14)
			jr		z, .sn1
			ld		hl, 14
.sn1		add		hl, sp
			call	stdio_word
			call	stdio_str
			db		" PC:", 0
			ld		a, [Z.snap_mode]
			or		a
			ld		hl, 8			; return address (12)
			jr		z, .sn2
			ld		hl, 12
.sn2		add		hl, sp
			ld		a, [hl]
			inc		hl
			ld		h, [hl]
			ld		l, a			; return address of _snap
			ld		a, [Z.snap_mode]
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
