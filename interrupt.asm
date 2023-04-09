;===============================================================================
;
;  Interrupt handlers
;
;===============================================================================

	if	BIOSROM != 0
rst00h	jp	reboot					; RST 0 is restart so send it to ROM0
	endif

; handlers for other RST N opcodes
rst08h	push	af
		ld		a, 1
		ld		[Z.snap_mode], a
		pop		af
		push	af
		call	_snap
		pop		af
		ret
rst10h
rst18h
rst20h
rst28h
rst30h
rst38h
			ret
nmih
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
;
; iTable has been moved to stepper.asm to make it fixed between BIOS options

; This assumes the ctc_int has already been run to set up the vectors

int_init
; first build the interrupt vector parts
			ld		a, high iTable		; top 8 bits of table address
			ld		i, a				; the special 'i' register
			im		2
			ret

;-------------------------------------------------------------------------------
; CTC0		should not trigger (CTC0)
;-------------------------------------------------------------------------------
int0		ei
			reti

;-------------------------------------------------------------------------------
; CTC1		50Hz = 20mS
;-------------------------------------------------------------------------------
		if	LIGHTS_EXIST
led_countdown	db	0
strobe_table	db	0x00, 0x80, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc, 0xfe, 0xff
				db	0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01, 0x00
				db	0x80, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc, 0xfe, 0xff
				db	0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01, 0x00
len_strobe		equ	$-strobe_table
		endif

int1		di
			push	af, hl
; 50 Hz ticks
			ld		a, [Z.preTick]		; uint8 counts 0-49
			inc		a
			ld		[Z.preTick], a
			cp		50
			jr		c, .q2
			xor		a
			ld		[Z.preTick], a
; 1Hz ticks
			ld		hl, Z.Ticks			; unit32 counts seconds
			inc		[hl]				; b0-7
			jr		nz, .q1				; beware, inc does not set carry
			inc		hl
			inc		[hl]				; b8-15
			jr		nz, .q1
			inc		hl
			inc		[hl]				; b16-23
			jr		nz, .q1
			inc		hl
			inc		[hl]				; b24-31	2^32 seconds is 136 years
.q1
; put things for 1Hz service here


.q2
; put things for 50Hz service here

; strobe leds
		if	LIGHTS_EXIST
			ld		a, [Z.preTick]		; drop to 25Hz
			and		1
			jr		nz, .lr2
			ld		a, [led_countdown]	; do we want a countdown?
			or		a
			jr		z, .lr2				; no
			cp		len_strobe			; beware the table length
			jr		c, .lr1
			ld		a, len_strobe
.lr1		dec		a
			ld		[led_countdown], a
			ld		hl, strobe_table
			add		a, l
			ld		l, a
			ld		a, h
			adc		0
			ld		h, a
			ld		a, [hl]
			out		(PIO+1), a
.lr2
; switches to lights option
  if BIOSROM == 0
  			ld		a, [cmd_bits]
			and		1					; bit 0 = 'A'
			jr		z, .q3
			in		a, (PIO_A)			; read switches
			out		(PIO_B), a			; write leds
.q3
	endif
		endif
; finished and exit
			pop		hl, af
			ei
			reti

;-------------------------------------------------------------------------------
; CTC2		Wired trigger from UART
;-------------------------------------------------------------------------------
int2		jp		serial_interrupt

;-------------------------------------------------------------------------------
; CTC3		Wired to PC3 which is an interrupt output in a smart mode
;-------------------------------------------------------------------------------
int3		ei
			reti

