;===============================================================================
;
; RTC.asm		Manage the Real Time Clock and the SPI bus
;
;===============================================================================
rtc_start		equ	$
; SPI register bits
; We don't have a hardware SPI implementation so it has to be hand cranked

; The port is RTC
; output bits (6 bit register not b1,b2)
; the RTCIN data line goes through a tristate gate enabled by RTCWE LOW
RTCCE		equ		0x10	; Chip Enable to the DS1302 pin5 (b4) active high
RTCWEN		equ		0x20	; Tristate Enable for RTCIN		 (b5) active low
RTCCLK		equ		0x40	; Clock to DS1302 pin7			 (b6) active high
RTCIN		equ		0x80	; Data to DS1302 pin6 tristate	 (b7)
; input bits
RTCOUT		equ		0x01	; Data Output from the DS1302 p6 (b0) active high
JP1			equ		0x40	; Jumper JP1	 (b6) high if no jumper in place
FDCHANGE	equ		0x80	; FDC disk in sw (b7) fdc plug p34

; Spare pins
P10			equ		0x08	; LED1 active low
P7			equ		0x01	; LED2 active low

;===============================================================================
;	SPI driver
;	Timings are taken from the DS1302 data sheet for 5V operation
;===============================================================================

; Timing: Z80 instructions are measured in T states which is one clock count
; I can assume that is 100nS as my 10MHz Z80 is pretty good spec for a Z80.
; However as an OUT instruction is 11 T-states two consecutive OUTs are 1100ns
; apart and none of the minimum timings are that tight so all I need to worry
; about is the sequence of outputs.

		db	"<RTC Driver>"

;===============================================================================
;
; RTC datablock
;
;===============================================================================

; the RTC defines 9 bytes
			struct	rtcdata
seconds		ds		1
; [0]		b0-3		decimal second units (0-59)
;			b4-6		decimal seconds tens
;			b7			CH (Clock Halt = totally lowest power shutdown)
minutes		ds		1
; [1]		b0-3		decimal minutes units (0-59)
;			b4-6		decimal minutes tens
;			b7			undefined
hours		ds		1
; [2]	two forms
;			b0-3		decimal hour units (1-31)
;			b4-5		decimal hour tens (1-12
;			b6-7		0,0
;		or
;			b4			decimal hours
days		ds		1
; [3]		b0-3		decimal day units (1-31)
;			b4-5		decimal day tens
;			b6-7		0,0
months		ds		1
; [4]		b0-3		decimal month units (1-12)
;			b4			decimal month tens
;			b5-7		0,0,0
dayofweek	ds		1
; [5]		b0-2		decimal day units (1-7)
;			b3-7		0,0,0,0,0
years		ds		1
; [6]		b0-3		decimal year units (0-99)
;			b4-7		decimal year tens
mode		ds		1
; [7]		b7			WP write protect
stat		ds		1	; NOT AVAILABLE IN BURST MODE
; [8]		b0-1		RS charging switches 0 for off
;			b2-3		DS
;			b4-7		TS
			ends

;===============================================================================
;
;	Code based on RomWBW  by Wayne Warthen <wwarthen@gmail.com>
;		published on github
;
;===============================================================================

; I found his example delays - they seem OTT against the datasheet
; then I find in his comment references to 50MHz so divide by 5
dly2		call	dly1	; double dly1 so 5.4uS @ 10MHz
dly1		ret				; call + return = 17+10 T states so 2.7uS

;===============================================================================
; Initialise or complete a command sequence
;	sets A to the current port value
;	set all lines to quiescent state
;===============================================================================
rtc_init
		ld		a, [Z.led_buffer]	; led driver bits b3 and b0
		and		0x09				; mask out any noise
		or		RTCWEN				; set A with WE (active low) quiescent
		out		(RTC), a			; write to port
		ret							; return port state in A

;===============================================================================
; Send command in E to RTC
;	All RTC sequences must call this first to send the RTC command.
;	The command is then sent via a put. CE and CLK are left asserted. This
;	is intentional because when the clock is lowered, the first bit
;	will be presented to read (in the case of a read cmd).
;
;	N.B. Register A contains working value of latch port and must not
;	be modified between calls to rtc_cmd, rtc_put, and rtc_get.
;
;	0) assume all lines are undefined at entry
;	1) de-assert all lines (CE, RD, CLOCK & DATA)
;	2) wait 1us
;	3) set CE high
;	4) wait 1us
;	5) put command
;===============================================================================
rtc_cmd
		call	rtc_init		; initialise A with the quiescent state values
		call	dly2			; delay 2 * 27 t-states
		or		RTCCE			; assert CE (active high)
		out		(RTC), a		; write to RTC port
		call	dly2			; delay 2 * 27 t-states
		; fall through to rtc_put
;===============================================================================
; Write byte in E to the RTC
;	Write byte in E to the RTC.  CE is implicitly asserted at
;	the start.  CE and CLK are left asserted at the end in case
;	next action is a read.
;
;	0) assume entry with CE high, others undefined
;	1) set CLK low
;	2) wait 250ns
;	3) set data according to bit value
;	4) set CLK high (at least 50nS after data so no worries)
;	5) wait 250ns (clock reads data bit from bus) (50nS on my datasheet)
;	6) loop for 8 data bits
;	7) exit with CE and CLK high
;	uses E, A carries the port state through
;===============================================================================
rtc_put
		push	bc
		ld		b, 8			; loop for 8 bits
		and		~RTCWEN			; set write mode (active low)
.rp1	and		~RTCCLK			; set clock low (active high)
		out		(RTC), a		; do it
		call	dly1			; delay 27 t-states
		rla						; prep A to get data bit into b7 via carry
		rr		e				; next bit to send into carry
		rra						; CY into b7 and other bits back to correct pos
		out		(RTC), a		; assert data bit on bus
		or		RTCCLK			; set clock high (active high) chip reads on re
		out		(RTC), a
		call	dly1			; delay 27 t-states
		djnz	.rp1			; loop
		pop		bc
		ret

;===============================================================================
; Read byte from RTC, return value in E
;	Read the next byte from the RTC into E.  CE is implicitly
;	asserted at the start.  CE and CLK are left asserted at
;	the end.  clock *must* be left asserted from rtc_cmd
;
;	0) assume entry with CE high, others undefined
;	1) set RD high and clock low (data sets within 200nS)
;	3) wait 250ns (chip puts data bit on bus)
;	4) read data bit
;	5) set clock high
;	6) wait 250ns
;	7) loop for 8 data bits
;	8) exit with CE, CLK, RD high
; uses E, A carries the port state on through
;===============================================================================
rtc_get
		push	bc
		ld		e, 0			; initialize received value to 0
		ld		b, 8			; loop for 8 bits
		or		RTCWEN			; set read mode (write is active low)
.rg1	and		~RTCCLK			; set CLK low (data ready in 200nS)
		out		(RTC), a		; write to RTC port (clock must be low for >250nS)
		call	dly1			; delay 2 * 27 t-states
		push	af				; save port value
		in		a, (RTC)		; read the RTC port
		rra						; data bit to carry b0
		rr		e				; shift into working value
		pop		af				; restore port value
		or		RTCCLK			; clock back to high (data tristates in 70nS)
		out		(RTC), a		; write to RTC port
		call	dly1			; delay 27 t-states
		djnz	.rg1			; loop
		pop		bc
		ret

;===============================================================================
; Burst read clock data into buffer at HL
;	uses A
;===============================================================================
rtc_rdclk
		push	bc, de, hl
		ld		e, 0xbf			; command = 0xbf to burst read clock
		call	rtc_cmd			; send command to RTC
		ld		b, 7			; b is loop counter
.rr1	call	rtc_get			; get next byte
		ld		[hl], e			; save in buffer
		inc		hl				; inc buf pointer
		djnz	.rr1			; loop if not done
		pop		hl, de, bc
		jp		rtc_init	; SET BACK TO JR

;===============================================================================
; Burst write clock data from buffer at HL
;	uses A
;===============================================================================
rtc_wrclk
		push	bc, de, hl
		; set the write protect bit to zero
		ld		e, 0x8e			; command = 0x8e to write control register
		call	rtc_cmd			; send command
		ld		e, 0x00			; 0x00 = unprotect
		call	rtc_put			; send value to control register
		call	rtc_init		; finish it

		; send the 'clock burst' command
		ld		e, 0xbe			; command = 0xbe to burst write clock
		call	rtc_cmd			; send command to rtc
		ld		b, 7			; b is loop counter
.cw1	ld		e, [hl]			; get next byte to write
		call	rtc_put			; put next byte
		inc		hl				; increment buffer pointer
		djnz	.cw1			; loop if not done

		; sent the eighth byte to re-write protect it
		ld		e, 0x80			; add control reg byte, 0x80 = protect on
		call	rtc_put			; write required 8th byte
		and		~RTCCE			; CE low before CLK low (NVH add)
		out		(RTC), a
		pop		hl, de, bc
		jp		rtc_init

;===============================================================================
; Burst read ram data into buffer at HL
;	uses A
;===============================================================================
rtc_rdram
		push	bc, de, hl
		ld		e, 0xff			; command = 0xff to burst read ram
		call	rtc_cmd			; send command to rtc
		ld		b, 31			; b is loop counter
.cr1
		call	rtc_get			; get next byte
		ld		[hl], e			; save in buffer
		inc		hl				; inc buf pointer
		djnz	.cr1			; loop if not done
		pop		hl, de, bc
		jp		rtc_init

;===============================================================================
; Burst write ram data from buffer at HL
;	uses A
;===============================================================================
rtc_wrram
		push	bc, de, hl

		; clear the write protect bit to zero
		ld		e, 0x8e			; command = 0x8e to write control register
		call	rtc_cmd			; send command
		ld		e, 0x00			; 0x00 = unprotect
		call	rtc_put			; send value to control register
		call	rtc_init		; finish it

		ld		e, 0xfe			; command = 0xfe to burst write ram
		call	rtc_cmd			; send command to rtc
		ld		b, 31			; b is loop counter
.rw1	ld		e, [hl]			; get next byte to write
		call	rtc_put			; put next byte
		inc		hl				; increment buffer pointer
		djnz	.rw1			; loop if not done
		and		~RTCCE			; CE low before CLK low (NVH add)
		out		(RTC), a

		; set the write protect bit to one
		ld		e, 0x8e			; command = 0x8e to write control register
		call	rtc_cmd			; send command
		ld		e, 0x80			; 0x80 = protect
		call	rtc_put			; send value to control register
		call	rtc_init		; finish it

		pop		hl, de, bc
		jp		rtc_init

;===============================================================================
;  set/clear LEDS
;	LED1 (left hand)  = b3 active low
;	LED2 (right hand) = b0 active low
;===============================================================================
 if LEDS_EXIST
set_led	and		0x09
		ld		[Z.led_buffer], a
		jp		rtc_init
 endif

;===============================================================================
; Routines to manage converting a date time string to and from RTC format
;===============================================================================

d1			db		"Sunday", 0		; day of the week stings
d2			db		"Monday", 0
d3			db		"Tuesday", 0
d4			db		"Wednesday", 0
d5			db		"Thursday", 0
d6			db		"Friday", 0
d7			db		"Saturday"
dx			db		0				; catch a zero return

DOW			dw		dx, d1, d2, d3, d4, d5, d6, d7

;-------------------------------------------------------------------------------
; Unpack masked BCD to a proper decimal number A->A
; uses nothing
;-------------------------------------------------------------------------------
unpackBCD	push	bc
			ld		b, a
			and		0xf0			; so A = tens digit as N*16
			srl		a				; to N*8
			ld		c, a			; save it
			srl		a				; to N*4
			srl		a				; to N*2
			add		c				; +N*8 = N*10
			ld		c, a
			ld		a, b
			and		0x0f			; mask bottom digit
			add		c				; add the 10*
			pop		bc
			ret

;-------------------------------------------------------------------------------
; Pack decimal into BCD A->A
; works for A<=99  It might be best to mask the output
; uses nothing
;-------------------------------------------------------------------------------
packBCD		push	bc
			ld		c, 0			; tens
			jr		.pb2
.pb1		sub		10				; <10 loops beats a divide any day
			inc		c
.pb2		cp		10
			jr		nc, .pb1
			sla		c				; C<<=4
			sla		c
			sla		c
			sla		c
			add		c
			pop		bc
			ret

;-------------------------------------------------------------------------------
; Convert dd/mm/yy to day-of-the-week
; Basically work out the day number in modulus 7
; !!!! In fact it dawns on me I can do all the maths in modulus7 !!!!
;-------------------------------------------------------------------------------
getDOW			; call with D=day(1-31), B=month(1-12), C=two digit year(0-99)
				; returns DOW(1-7) with Sunday=1
				; uses A
;
; int DOW(int year, int month, int day){
;    if (month < 3) {
;        month += 12;
;        year--;
;    }
;    int k = year % 100;
;    int j = year / 100;	// 20
;    int q = day;
;    int m = month;
;	// this expression hits a maximum of about 405
;    return (q + 13*(m+1)/5 + k + k/4 + j/4 + 5*j + 6) % 7;
;}
;
			SNAPT	"DOW"
			push	hl
			ld		a, b		; month
			cp		3			; CY = month < 3
			jr		nc, .d1		; jr if !(month < 3)
			add		12			; month += 12
			ld		b, a		; save month
			dec		c			; year--
.d1
;	calculate 13*(month+1)/5
			ld		a, b		; month
			inc		a			; (m+1) <=13
			ld		l, a		; *1
			sla		l
			sla		l			; *4
			add		l			; *5
			sla		l			; *8
			add		l			; *13 (13*13)<=169

			ld		h, 0
.d2			cp		5			; /5
			jr		c, .d3		; CY if a<5
			sub		5
			inc		h
			jr		.d2
.d3			ld		a, h		; <= 33

			add		d			; +q <= 64
			add		c			; +k <= 163
			srl		c
			srl		c
			add		c			; +k/4 <=188
			add		6			; +j/4+5*j+6=505 then mod 7 = 6
.d4			cp		7
			jr		c, .d6		; 0-6
			sub		7
			jr		.d4

.d6			inc		a			; 1-7
			pop		hl
			ret

;-------------------------------------------------------------------------------
; unpack RTC block into text stdio so it can be redirected
;-------------------------------------------------------------------------------
unpackRTC		; call with buffer pointer in IX
			push	hl
			push	bc
			push	de
			ld		a, [ix+rtcdata.hours]	; hours in BCD (0-23)
			and		0x3f					; 24hr flag
			call	unpackBCD
			call	stdio_decimalB2
			ld		a, ':'
			call	stdio_putc
			ld		a, [ix+rtcdata.minutes]	; minutes (0-59)
			and		0x7f					; should be zero
			call	unpackBCD
			call	stdio_decimalB2
			ld		a, ':'
			call	stdio_putc
			ld		a, [ix+rtcdata.seconds]	; seconds (0-59)
			and		0x7f					; charging flag
			call	unpackBCD
			call	stdio_decimalB2
			ld		a, ' '
			call	stdio_putc
			ld		a, [ix+rtcdata.days]	; dom (1-31)
			and		0x3f
			call	unpackBCD
			call	stdio_decimalB2
			ld		a, '/'
			call	stdio_putc
			ld		a, [ix+rtcdata.months]	; month (1-12)
			and		0x1f
			call	unpackBCD
			call	stdio_decimalB2
			ld		a, '/'
			call	stdio_putc
			ld		a, [ix+rtcdata.years]	; year (0-99)
			call	unpackBCD
			ld		hl, 2000
			add		a, l
			ld		l, a
			ld		a, 0
			adc		a, h
			ld		h, a
			call	stdio_decimalW4
			ld		a, ' '
			call	stdio_putc
			; the chip doesn't set what DOW is 1 so I will
			; go with the classical definition
			ld		a, [ix+rtcdata.dayofweek] ; day of the week 1-7
			and		0x7
			add		a					; double it to be a word index
			ld		c, a
			ld		b, 0
			ld		hl, DOW				; word table of string pointers
			add		hl, bc
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			ld		hl, bc
			call	stdio_text
			pop		de
			pop		bc
			pop		hl
			ret

;-------------------------------------------------------------------------------
; packRTC	read the command style buffer into the RTC data
; buffer can consist of DD/MM/YY or DD/MM/YYYY and HH:MM:SS or HH:MM or both
; the buffer must not contain anything after it
; returns CY on success
;-------------------------------------------------------------------------------
packRTC			; call with HL=buffer, D=maxcount, E=index, IY=RTC buffer

.pr1		ld		ix, 0
			call	getdecimalB			; might be HH, might be DD
			ret		nc					; a bad end
			call	skip				; get the delimiter / or :
			jr		z, .pr2				; unexpected EOL
			cp		':'					; we are doing a time
			jp		z, .pr5				; do time
			cp		'/'
			jr		z, .pr3				; ok
.pr2		or		a					; clear CY
			ret							; bad end
; read DD/MM/YY
.pr3		ld		a, ixl				; get DD
			or		a
			jr		z, .pr2				; 0 is bad
			cp		32
			jr		nc, .pr2			; >=32 is bad
			ld		b, a				; save DD -> B

			ld		ix, 0
			call	getdecimalB			; get MM
			ret		nc					; bad end
			ld		a, ixl
			or		a
			jr		z, .pr2				; 0 is bad
			cp		13
			jr		nc, .pr2			; >=13 is bad
			ld		c, a				; save MM -> C

			call	skip
			jp		z, .pr2				; unexpected EOL
			cp		'/'
			jp		nz, .pr2			; delimiter expected

			ld		ix, 0				; get year
			call	getdecimalW			; YYYY or YY
			ret		nc					; another bad end

			; ideally I would do ix %= 100 here but I can shortcut that
			; based on the fact that anything that isn't 20xx is an error
			; so if it is > 256 I subtract 2000 and then test for 0-99
			ld		a, ixh
			or		a
			jr		z, .pr4				; jr if <256
			push	de					; sub ix, 2000
			ld		de, -2000			; or even add ix, -2000
			add		ix, de
			pop		de
			ld		a, ixh
			or		a
			jp		nz, .pr2			; bad, probably negative
.pr4		ld		a, ixl
			cp		100
			jp		nc, .pr2			; >= 99
; we have B=DD, C=MM, A=YY
			push	af						; keep the unpacked value for DOW
			call	packBCD					; pack A
			ld		[iy+rtcdata.years], a	; years
			pop		af
			push	bc
			push	de
			ld		d, b
			ld		b, c
			ld		c, a
			call	getDOW					; call with D=day(1-31)
											; B=month(1-12)
											; C=two digit year(0-99)
											; returns DOW(1-7) with Sunday=1
			ld		[iy+rtcdata.dayofweek], a	; DOW
			pop		de
			pop		bc
			ld		a, c
			call	packBCD
			ld		[iy+rtcdata.months], a	; months
			ld		a, b
			call	packBCD
			ld		[iy+rtcdata.days], a	; days
; end of date so if there is more it is a time but I'll take anything
.pr4a
			call	skip
			jr	z, .pr4b			; EOL so done OK
			dec		e					; unget
			jp		.pr1				; go again
.pr4b		scf							; good end
			ret
; read HH:MM:SS or HH:MM
.pr5		ld		a, ixl				; get HH
			cp		24
			jp		nc, .pr2			; >=24 is bad
			ld		b, a				; save HH -> B

			ld		ix, 0
			call	getdecimalB			; get MM
			ret		nc					; bad end
			ld		a, ixl
			cp		60
			jp		nc, .pr2			; >=60 is bad
			ld		c, a				; save MM -> C

			call	skip
			jr		z, .pr6				; EOL so no seconds
			cp		':'
			jr		nz, .pr5a			; not correct delimiter
			ld		ix, 0
			call	getdecimalB			; get SS
			ret		nc					; bad end
			ld		a, ixl
			cp		60
			jp		nc, .pr2			; >=60 is bad
			jr		.pr7
.pr5a		dec		e					; unget
.pr6		xor		a
.pr7
; we have B=HH, C=MM, A=SS so pack it
			call	packBCD					; pack A
			and		0x7f
			ld		[iy+rtcdata.seconds], a	; seconds
			ld		a, c
			call	packBCD
			ld		[iy+rtcdata.minutes], a	; minutes
			ld		a, b
			and		0x3f					; ensure the 12/24 is at 24
			call	packBCD
			ld		[iy+rtcdata.hours], a	; hours (with 24hr set)
			jp		.pr4a
;
 if SHOW_MODULE
	 	DISPLAY "rtc size: ", /D, $-rtc_start
 endif
