;===============================================================================
;
; STDIO.asm		redirectable text io
;
;===============================================================================
stdio_start		equ	$

; currently I have only two ways to input/output from these routines
; to serial or to strings. I wanted a data location that wasn't in RAM
; to select this but the only reasonable one to do this at speed is
; the io byte at (UART+7)
; zero means use serial_sendW/serial_read
; 1 means write to (IY++)
; I guess we might have more later...
;
;===============================================================================

; stdio redirect:  manana

; write the character in A, uses nothing
stdio_putc
		jp		serial_sendW	; uses nothing

; wait for and return a character in A, uses A only
stdio_getc
		jp		serial_read

;-------------------------------------------------------------------------------
; U8toWCHAR		get a 16 bit char in BC from usual input string
;				based on https://en.wikipedia.org/wiki/UTF-8
;				return Z on end of line
;				return CY on good end
;-------------------------------------------------------------------------------

U8toWCHAR	call	getc			; get a character in A
			jr		nc, .gu4		; good end of line

; %0wwwwwww are one byte characters
;	(7 bits)
			bit		7, a			; 0x80 set
			jr		nz, .gu1		; no, single byte in BC

; accumulate the result in BC
			ld		b, 0			; accumulate the character in BC
			ld		c, a
			jr		.gu3			; good end

; test for mal-formed code (continuation byte as first byte)
.gu1		bit		6, a
			jr		z, .gu5			; error, continuation byte format

; %110xxxxx are the first byte of a two byte char
; the whole char is %110xxxxx %10wwwwwwww giving char %xxxxxwwwwww
;	(11 bits)
			bit		5, a
			jr		nz, .gu2		; not two bytes

; unpack 2 byte code
			and		0x1f
			ld		b, a			; <<6 is quicker as top byte then >>2
			ld		c, 0
			srl		b
			rr		c
			srl		b
			rr		c
			call 	getc			; get second byte
			jr		z, .gu5			; error, run out of buffer
			bit		7, a
			jr		z, .gu5			; error
			bit		6, a
			jr		nz, .gu5		; error
			and		0x3f			; mask
			or		c
			ld		c, a
			jr		.gu3			; good end

; %1110yyyy are the first byte of a three byte char
; the whole char is %1110yyyy %10xxxxxx %10wwwwww giving %yyyyxxxxxxwwwwww
;	(16 bits)
.gu2		bit		4, a			;
			jr		nz, .gu5		; not three byte so I give up

; unpack 3 byte code
			and		0x0f
			ld		b, a			; stil needs shifting  <<4

			call 	getc			; get second byte
			jr		z, .gu5			; error, run out of input
			bit		7, a
			jr		z, .gu5			; error
			bit		6, a
			jr		nz, .gu5		; error
			and		0x3f			; mask
			sla		a				; slide to top of A
			sla		a
			sla		a				; now slide 4 places into B
			rl		b
			sla		a
			rl		b
			sla		a
			rl		b
			sla		a
			rl		b
			ld		c, a

			call	getc			; get second byte
			jr		z, .gu5			; error, run out of input
			bit		7, a
			jr		z, .gu5			; error
			bit		6, a
			jr		nz, .gu5		; error
			and		0x3f			; mask
			or		c
			ld		c, a

; good end  return NZ and C
.gu3		or		1				; set NZ
			scf						; and CY good end
			ret

; good EOL
.gu4		ld		bc, 0
			and		0				; set zero
			scf
			ret

; bad_end
.gu5		ld		bc, 0
			and		0				; set Z and NC
			ret

;-------------------------------------------------------------------------------
; WCHARtoU8		write the 16 bit char in BC to stdout_putc using UTF-8
;				based on https://en.wikipedia.org/wiki/UTF-8
;				uses AF
;				returns nothing
;-------------------------------------------------------------------------------

WCHARtoU8
; test for one char ie: <=0x7f (7 bits)
			ld		a, c
			and		0x80
			or		b
			jr		nz, .wc1 	; >0x7f

; single char output %0wwwwwww
			ld		a, c
			call	stdio_putc
			ret

; test for two chars (11 bits)
.wc1		ld		a, b
			and		0xf8		; > 0x7ff
			jr		nz, .wc2

; two char output	%110xxxxx %10wwwwww
			push	de
			ld		de, bc		; save the char
			sla		c			; BC << 2
			rl		b
			sla		c
			rl		b
			ld		a, b
			or		0xc0
			call	stdio_putc

			ld		a, e		; LSBy
			and		0x3F
			or		0x80
			call	stdio_putc
			ld		bc, de
			pop		de
			ret

; no need to test a 16bit register for 16 chars
; output 3 chars %1110yyyy %10xxxxxx %10wwwwww
.wc2		push	de
			ld		de, bc
			srl		b			; BC >> 4
			rr		c
			srl		b
			rr		c
			srl		b
			rr		c
			srl		b
			rr		c
			ld		a, c
			or		0xe0
			call	stdio_putc

			ld		bc, de
			sla		c			; BC <<2
			rl		b
			sla		c
			rl		b
			ld		a, b
			or		0x80
			call	stdio_putc

			ld		a, e
			and		0x3f
			or		0x80
			call	stdio_putc
			ld		bc, de
			pop		de
			ret

;-------------------------------------------------------------------------------
; stdio_text	output null terminated string starting at HL
;				uses nothing
; stdio_textU8	translate chars in the 0x80-0xff to UTF-8 and output
; stdio_textW	translate 16 bit char string at HL to UTF-8 and output
;-------------------------------------------------------------------------------
stdio_text
		push	af, hl
.st1	ld		a, [hl]				; test the next character
		or		a					; trailing null?
		jr		z, .st2				; not
		call	stdio_putc			; send the character
		inc		hl					; move to the next character
		jr		.st1
.st2	pop		hl, af
		ret

stdio_textU8
		push	af, hl
.su1	ld		a, [hl]
		or		a
		jr		z, .su3				; delimiter
		bit		7, a
		jr		nz, .su2			; 0x80-0xff

; output one char
		call	stdio_putc
		inc		hl
		jr		.su1

; output two chars
.su2	rlca						; rotate A direct so b7,6 end up as b1,0
		rlca
		and		0x03
		or		0xc0
		call	stdio_putc

		ld		a, [hl]
		and		0x3f
		call	stdio_putc
		inc		hl
		jr		.su1

; end
.su3	pop	hl, af
		ret

stdio_textW
		push	af, bc, hl
.sw1	ld		c, [hl]
		inc		hl
		ld		b, [hl]
		inc		hl
		ld		a, b
		or		c
		jr		z, .sw2		; null terminator
		call	WCHARtoU8
		jr		.sw1
.sw2	pop		hl, bc, af
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
		jr		z, .g7
		cp		0x0d				; ^M enter
		jr		z, .g7

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
		jr		z, .g7				; end of line regardless
		call	isalpha				; set CY if [A-Za-z]
		jr		nc, .g3				; loop
		cp		'A'					; up arrow?
		jr		nz, .g1

; we have and up arrow so adopt previous buffer
; first wind back over any current typing
.g3a	ld		a, d
		or		a
		jr		z, .g3c
		ld		a, 0x08
		call	stdio_putc
		dec		d
		jr		.g3a

; now echo the buffer to a null
.g3c	push	hl
.g3b	ld		a, [hl]
		or		a
		jr		z, .g3d				; rejoin text loop
		call	stdio_putc
		inc		d
		inc		hl
		jr		.g3b
.g3d	pop	hl
		jr	.g1

; if we get to here it is an 'ordinary' character
.g4		ld		e, a				; save it in E

; do we have room left in the buffer?
		ld		a, d				; get index
		inc		a					; index+1 (if we are full b==d)
		cp		b
		jr		nz, .g5
;;		call	beep
		jr		.g1

; place in at hl[d++]
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

; good exit adding terminating 0
.g7		push	hl
		ld		a, l
		add		d
		ld		l, a
		jr		nc, .g8
		inc		h
.g8		xor		a
		ld		[hl], a
		pop		hl
		ret

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
			or		l
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
			or		l
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
					; if C=0xff use local [HL] not [C:HL]
			push	af, bc, ix
			ld		ix, hl					; move pointer to C:IX
; do a line
.sd1		ld		a, 0x0d					; '\r'
			call	stdio_putc
			ld		a, 0x0a					; '\n'
			call	stdio_putc
			ld		hl, ix
			ld		a, c
			cp		0xff
			jr		z, .sd1a
			call	stdio_20bit				; write C:HL as address
			jr		.sd1b
.sd1a		call	stdio_word
.sd1b		ld		a, ' '					; ' '
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

; gethex24	gets a 24 bit address in C:IX
gethex24	call	gethex32
			ld		a, b
			or		a
			jr		z, gh8			; good end
			jr		gh10			; bad end

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

;-------------------------------------------------------------------------------
; Get a WCHAR string from the input allowing UTF-8
;	delimit on spaces but accept quotes (with "" for a quote)
;	and while I'm at it map \ to /
;		call with usual HL pointer to line, D buffer count, use E as index
;		assume the string is in PAGE0 so accessible
;		IX = WCHAR receiving buffer
;		B = buffer size
;		if C b0 is set apply path character rules
;		if C b1 is set apply filename rules
;		if C b2 is set do the anti-annoyance fix of '\' to '/'
;		if C b3 treat illegal characters as terminators
;		returns Carry on string returned (length!=0 and legal)
; uses A
;-------------------------------------------------------------------------------
getW
; define the bit flags used as local labels
.B_badPath	equ		0		; make test for illegal pathname characters
.B_badName	equ		1		; make test for illegal filename characters
.B_slash	equ		2		; swap \ to /
.B_term		equ		3		; treat illegal as terminator
.B_quote	equ		4		; we are in a quoted portion
.B_last		equ 	5		; the last char was a " ending a quoted section

			push	iy
			ld		a, c			; clear the bits I use for internal flags
			and		0x0f
			ld		c, a
			ld		iy, bc			; working space

			call	skip			; skip spaces and return the first char
			jp		z, .gw12		; end of input with no string
			dec		e				; back up the index so HL[E] is the char

			call	U8toWCHAR		; get first 16 bit char in BC
			jp		z, .gw12		; end of line is bad here
			jp		nc, .gw12		; so is a bad character
			jr		.gw2			; step into the loop

; loop
.gw1		call	U8toWCHAR		; not first char in BC
			jp		z, .gw11		; end if line is OK here
			jp		nc, .gw12		; but not a bad character
.gw2
; test for double quote
			ld		a, b
			or		a
			jr		nz, .gw5		; not "
			ld		a, c
			cp		0x22			; double quote
			jr		nz, .gw5		; not "

; sort out a double quote
; using iyl.B_quote as 'we are in double quotes so spaces are legal'
; and	iyl.B_last as 'the last char was a double quote ending double quotes'
			ld		a, iyl
			bit		.B_last, a		; was the last char an end of quote?
			jr		z, .gw3			; no

; last char was a close of quotes so rescind the end of quoted string
; and insert a "
			set		.B_quote, a
			res		.B_last, a
			ld		iyl, a
			jp		.gw10			; save the char

; is this a start/end of double quotes?
.gw3		ld		a, iyl
			bit		.B_quote, a		; are we in a quoted string?
			jr		nz, .gw4		; yes
			set		.B_quote, a		; no, so set the quoted string bit
			ld		iyl, a
			jr		.gw1			; loop
.gw4		res		.B_quote, a		; end a quote
			set		.B_last, a		; set last char was EOQ flag
			ld		iyl, a
			jr		.gw1			; loop

; we have a non-quote char
.gw5		ld		a, iyl			; so it is not an end of quote
			res		.B_last, a
			ld		iyl, a

; test for a a space but not in double quotes
			bit		.B_quote, a		; but are we quoted?
			jr		nz, .gw6		; can't be a terminator then
			ld		a, b
			or		a
			jr		nz, .gw6		; not a space
			ld		a, c
			cp		' '
			jp		z, .gw11		; delimiting space
.gw6		ld		a, iyl

; are we testing for filename/pathname illegal chars?
			bit		.B_badName, a	; name takes precedence
			jr		nz, .gw6a		; testing to the filename list
			bit		.B_badPath, a
			jr		z, .gw9			; not testing
			push	hl				; testing to the pathname list
			ld		hl, .badPath
			jr		.gw6b
.gw6a		push	hl
			ld		hl, .badName	; including /\:
.gw6b

; do the 'legal' tests
			ld		a, b
			or		b
			jr		nz, .gw8		; all the chars blocked are in 0-0x7f
			ld		a, c			; LSbyte
.gw7		ld		a, [hl]
			inc		hl
			or		a
			jr		z, .gw8			; end of list so good
			cp		c
			jr		nz, .gw7		; good char so loop
			pop		hl				; bad char
			ld		a, ixl			; get the flags
			bit		.B_term, a		; treat illegal as terminator?
			jp		nz, .gw11
			jp		.gw12
.gw8		pop		hl
.gw9

; are we changing \ to /
			ld		a, iyl			; flags
			bit		.B_slash, a
			jr		z, .gw10		; no
			ld		a, c
			cp		'\'
			jr		nz, .gw10
			ld		c, '/'

; save the character
.gw10		ld		[ix], c
			inc		ix
			ld		[ix], b
			inc		ix
			dec		iyh
			jp		nz, .gw1
			jr		.gw12			; run out of buffer

; good exit
.gw11		ld		[ix], 0			; add trailing null
			ld		[ix+1], 0
			pop		iy
			scf
			ret

; bad exit
.gw12		ld		[ix], 0			; add trailing null so the string is 'safe'
			ld		[ix+1], 0
			or		a				; clear CY	= bad end
			pop		ix
			ret

; illegal chars
.badName	db	':', '/', '\'
.badPath	db	'<', '>', '"', '|', '?', '*', 0

;-------------------------------------------------------------------------------
; strcpy16	copy a 16bit string from HL to DE
;			uses A and advances HL and DE
;-------------------------------------------------------------------------------
strcpy16	push	bc
.sc1		ld		c, [hl]
			inc		hl
			ld		a, c
			ld		[de], a
			inc		de
			ld		a, [hl]
			inc		hl
			ld		[de], a
			inc		de
			or		c
			jr		nz, .sc1
			pop		bc
			dec		de
			dec		de
			ret

;-------------------------------------------------------------------------------
; strcmp16	WCHAR* HL, WCHAR* DE
;			uses A
;			return CY on match
;-------------------------------------------------------------------------------

strcmp16	push	bc, de, hl
;load BC
.sc1		ld		c, [hl]		; LD BC, [HL++]
			inc		hl
			ld		b, [hl]
			inc		hl

; test for match
			ld		a, [de]		; CP [DE++]
			inc		de
			cp		c
			jr		nz, .sc2
			ld		a, [de]
			inc		de
			cp		b
			jr		nz, .sc2

; match so if that was a 0 we have a winner
			ld		a, b
			or		c
			jr		nz, .sc1
			pop		hl, de, bc
			scf
			ret

; no match so fail
.sc2		pop		hl, de, bc
			or		a
			ret

;-------------------------------------------------------------------------------
;  strend16		advance HL to the end of a 16bit string
;				uses A
;-------------------------------------------------------------------------------
strend16	ld		a, [hl]
			inc		hl
			or		[hl]
			jr		z, .se1
			inc		hl
			jr		strend16
.se1		dec		hl
			ret

;-------------------------------------------------------------------------------
; strchr16		search for char DE in [HL]
; strrchr16		search for char DE in [HL] from the end backwards
;				uses A updates HL
;				return CY on success
;-------------------------------------------------------------------------------

strchr16	push	bc
.st1		ld		c, [hl]			; ld BC, [HL++]
			inc		hl
			ld		b, [hl]
			inc		hl
			ld		a, b			; BC==0?
			or		c
			jr		z, .st2			; failed EOS
			ld		a, b
			cp		d
			jr		nz, .st1		; no match
			ld		a, c
			cp		e
			jr		nz, .st1		; no match
			dec		hl
			dec		hl
			pop		bc
			scf
			ret
.st2		pop		bc
			or		a				; clear carry
			ret

strrchr16	push	bc, ix
			ld		ix, hl			; save the start position
			dec		ix				; back one char
			dec		ix
			call	strend16		; advance HL to EOS
.st3		ld		a, ixh
			cp		h
			jr		nz, .st4
			ld		a, ixl
			cp		l
			jr		z, .st5		; back at the start so fail
.st4		dec		hl
			ld		b, [hl]			; ld BC, [HL--]
			dec		hl
			ld		a, [hl]
			cp		d
			jr		nz, .st3		; no match
			ld		a, c
			cp		e
			jr		nz, .st3		; no match
			pop		ix, bc
			scf
			ret

.st5		pop		ix, bc
			or		a				; clear carry
			ret

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

;===============================================================================
; 1 mSecond delay
; uses nothing
;===============================================================================

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
;===============================================================================
; delay BC mSecs
;===============================================================================

delay		call	delay1ms
			dec		bc
			ld		a, b
			or		c
			ret		z
			jr		delay
 if SHOW_MODULE
	 	DISPLAY "stdio size: ", /D, $-stdio_start
 endif
