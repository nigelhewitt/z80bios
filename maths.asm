;===============================================================================
;
; Maths.asm		Provide simple sums
;
;===============================================================================
maths_start		equ	$

; !! all unsigned value functions

;===============================================================================
;	multiply H by E, 16 bit result in HL
;		I copied the shifting the result into the bottom of HL
;		as you shift the input out of the top from Rodnay Zak's book.
;===============================================================================
mul8x8
			ld		l, 0		; H input, also HL gets the results
			ld		d, 0		; extend E into DE
			ld		b, 8		; number of slides
.m1			add		hl, hl		; slide left the L, and slide b7 out of H
			jr		nc, .m2		; if we got a bit...
			add		hl, de		; add the other multiplicand
.m2			djnz	.m1			; 8 times
			ret

;===============================================================================
;	multiply BC by DE, 16 bit result in HL
;		return CY on overflow
;===============================================================================
mul16x16r16
			ld		a, c		; move low into A
			ld		c, b		; high byte
			ld		b, 16		; 16 steps
			ld		hl, 0		; result
.m3			srl		c			; high into CY (was BC at call)
			rra					; CY into A
			jr		nc, .m4		; if we get a bit out of b0
			add		hl, de		; if a bit comes our of b0 do the add
			ret		c			; overflow
.m4			ex		de, hl		; add de, de = sla de
			add		hl, hl
			ret		c			; overflow
			ex		de, hl
			djnz	.m3			; 16 times
			cp		a			; clear carry
			ret

;===============================================================================
; OK this on is NOT heavily optimised but it works
; a full 16 x 16 = 32 multiply so it needs more registers than we have
;===============================================================================
mul16x16r32			; multiply HL by DE, return 32 bit result in HL,DE
			AUTO	8

; we are going to make (IY)...(IY+3) the result call it xRES
; (IY+4)...(IY+7) the value based on HL call it xHL
; loop of 16 and DE!=0:
;   slide DE right into CY
; 	if CY add 'xHL' to 'xRES'
;	slide xHL left (aka *2)
; return rxRES

; set up the storage
			xor		a
			ld		[iy+0], a		; xRES = 0
			ld		[iy+1], a
			ld		[iy+2], a
			ld		[iy+3], a
			ld		[iy+4], l		; xHL = HL
			ld		[iy+5], h
			ld		[iy+6], a
			ld		[iy+7], a
; loop of 16 and
			ld		b, 16
			jr		.m6
; this is the slide xHL left but by doing it here after the DJNZ
; I save doing it then exiting on the last pass
.m5			xor		a				; clear carry
			rl		[iy+4]
			rl		[iy+5]
			rl		[iy+6]
			rl		[iy+7]

.m6			xor		c				; clear carry
			rr		b
			rr		c
; if CY add xHL to xRES
			jr		nc, .m7			; no add required
			ld		a, [iy+4]		; xRES + xHL
			add		a, [iy+0]
			ld		[iy+0], a
			ld		a, [iy+5]
			adc		a, [iy+1]
			ld		[iy+1], a
			ld		a, [iy+6]
			adc		a, [iy+2]
			ld		[iy+2], a
			ld		a, [iy+7]
			adc		a, [iy+3]
			ld		[iy+3], a
.m7			ld		a, d			; if DE==0 there is no point in continuing
			or		e
			jr		z, .m8
			djnz	.m5
; return in DE,HL
.m8			ld		l, [iy+0]
			ld		h, [iy+1]
			ld		e, [iy+2]
			ld		d, [iy+3]
			RELEASE	8
			ret

;===============================================================================
;	div16x16		BC = quotient, DE = divisor, BC = result, HL = remainder
;		return CY on divide by zero
;		from http://z80-heaven.wikidot.com/advanced-math#toc29
;===============================================================================
div16x16
			xor		a
			ld		h, a
			ld		l, a
			sub		e
			ld		e, a
			sbc		a, a
			sub		d
			ld		d, a

			ld		a, b
			ld		b, 16

; shift the bits from BC into HL
.d1			rl		c
			rla
			adc		hl, hl
			add		hl, de
			jr		c, .d2
			sbc		hl, de
.d2			djnz	.d1
			rl		c
			rla
			ld		b, a
			ret

;===============================================================================
; divide32by16
; another non optimised register busting divide
;===============================================================================
divide32by16			; call with BC,DE = numerator, HL = denominator
						; return BC,DE = result, HL = remainder
			AUTO		9
.result		equ			0
.remainder	equ			4
.counter	equ			8

; clear RESULT and REMAINDER
; loop for 32
; {
;   shift RESULT left one bit
;   shift BC,DE left into CY
;   shift CY into REMAINDER
;   if (REMAINDER >= HL)
;   {
;	   REMAINDER -= HL
;      RESULT += 1
;   }
;   return RESULT AND REMAINDER
;
; ok BC:DE and HL will stay as they are
; (IY+0) is RESULT and (IY+4) is REMAINDER

; clear RESULT and REMAINDER
			xor		a
			ld		[iy+.result+0], a		; RESULT = 0
			ld		[iy+.result+1], a
			ld		[iy+.result+2], a
			ld		[iy+.result+3], a
			ld		[iy+.remainder+0], a	; REMAINDER = 0
			ld		[iy+.remainder+1], a
			ld		[iy+.remainder+2], a
			ld		[iy+.remainder+3], a

; loop for 32
			ld		[iy+.counter], 32		; use as a loop counter

; shift RESULT left one bit
.d3			xor		a				; clear carry
			rl		[iy+.result+0]			; through carry
			rl		[iy+.result+1]
			rl		[iy+.result+2]
			rl		[iy+.result+3]

;   shift BC,DE left into CY
			xor		a				; should be clear already
			rl		e
			rl		d
			rl		c
			rl		b

;   shift CY into REMAINDER
			rl		[iy+.remainder+0]
			rl		[iy+.remainder+1]
			rl		[iy+.remainder+2]
			rl		[iy+.remainder+3]

;   if (REMAINDER >= HL)
;		remember cp n returns CY if n>A so NC for A>=N
;		we test for NC
			ld		a, [iy+.remainder+3] ; actually I don't think this is possible
			or		[iy+.remainder+2]
			jr		nz, .d4			; REMAINDER is way bigger than HL
			ld		a, [iy+.remainder+1]
			cp		h
			jr		c, .d5			; H >
			jr		nz, .d4			; H <
			ld		a, [iy+.remainder+0]
			cp		l
			jr		c, .d5			; L>
.d4

;   {
;	   REMAINDER -= HL
			ld		a, [iy+.remainder+0]
			sub		l
			ld		[iy+.remainder+0], a
			ld		a, [iy+.remainder+1]
			sbc		h
			ld		[iy+.remainder+1], a
			ld		a, [iy+.remainder+2]
			sbc		0
			ld		[iy+.remainder+2], a
			ld		a, [iy+.remainder+3]
			sbc		0
			ld		[iy+.remainder+3], a

;      RESULT += 1
			ld		a, [iy+.result+0]
			inc		a
			ld		[iy+.result+0], a
			ld		a, [iy+.result+1]
			adc		0
			ld		[iy+.result+1], a
			ld		a, [iy+.result+2]
			adc		0
			ld		[iy+.result+2], a
			ld		a, [iy+.result+3]
			adc		0
			ld		[iy+.result+3], a

;   }
.d5			dec		[iy+.counter]	; loop counter
			jp		nz, .d3			; dec does Z but not CY

; return BC|:DE = result, HL = remainder
			ld		e, [iy+.result+0]
			ld		d, [iy+.result+1]
			ld		c, [iy+.result+2]
			ld		b, [iy+.result+3]
			ld		l, [iy+.remainder+0]
			ld		h, [iy+.remainder+1]
			RELEASE	9
			ret
 if SHOW_MODULE
	 	DISPLAY "maths size: ", /D, $-maths_start
 endif
