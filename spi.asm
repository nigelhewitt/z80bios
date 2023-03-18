//==============================================================================
//
//		SPI.asm
//
//==============================================================================

; start with the definitions of the i/o bits

; flags
sd_debug			equ		0
sd_debug_cmd17		equ		0
sd_debug_cmd24		equ		0


; The PIO is set to PORT-C LOWER=INPUTS  UPPER=OUTPUTS
; ports
spi_out			equ		PIO_C
spi_in			equ		PIO_C

; bits
; Dout is b7 and Din is b0 so I can handle data with shifts
spi_mosi	equ		0x80	; C7
spi_clk		equ		0x40	; C6
spi_ssel	equ		0x20	; C5
;			equ		0x10	; C4  spare output

spi_miso	equ		0x01	; C0
;			equ		0x02	; C1  spare inputs
;			equ		0x04	; C2
;			equ		0x08	; C3

;===============================================================================
;
;	Based on 
;		SD Specifications Part 1 Physical Layer Simplified Specification
;		Version 9.00 August 22, 2022
;		Page 309 onwards
;
;===============================================================================
;############################################################################
; An SPI library suitable for talking to SD cards.
;
; This library implements SPI mode 0 (SD cards operate on SPI mode 0.)
; Data changes on falling CLK edge & sampled on rising CLK edge:
;        __                                             ___
; /SSEL    \______________________ ... ________________/      Host --> Device
;                 __    __    __   ... _    __    __
; CLK    ________/  \__/  \__/  \__     \__/  \__/  \______   Host --> Device
;        _____ _____ _____ _____ _     _ _____ _____ ______
; MOSI        \_____X_____X_____X_ ... _X_____X_____/         Host --> Device
;        _____ _____ _____ _____ _     _ _____ _____ ______
; MISO        \_____X_____X_____X_ ... _X_____X_____/         Host <-- Device
;
;############################################################################

;===============================================================================
; Write 8 bits in C to the SPI port
; It is assumed that SSEL is already low.
; This will leave: CLK=1, MOSI=(the LSB of the byte written)
; Uses: A
;===============================================================================

 assert spi_mosi==0x80, Bad SPI Dout bit		; so RR moves in from CY 

; Called with spi_ssel=0(active), spi_clk=0, spi_mosi=0
; Data is sampled on rising clock
; so should be changed (output) on the falling clock

spi_write8
		push	bc
		in		a, (spi_out)			; current bits

		; special case for the first bit as clock is low
		rr		a					; slide A right
		rl		c					; data b7 into CY
		rr		a					; into A b7 
		and		~spi_clk			; the clock should be low already
		out		(spi_out), a		; set data value & CLK clock low
		or		spi_clk				; set the clock
		out		(spi_out), a		; tell them to read data
		
		ld		b, 7
		; send the other 7 bits
.sw1	and		a, ~spi_clk			; a = spi_out value w/CLK & MOSI = 0
		rr		a					; slide A right
		rl		c					; data b7 into CY
		rl		a					; into A 
		out		(spi_out), a		; set data value & CLK falling edge
		or		spi_clk				; set the clock
		out		(spi_out), a
		djnz	.sw1
		pop		bc
		; leaves CLK high as next clock low is part of the next byte
		ret

;===============================================================================
; Read 8 bits from the SPI & return it in A.
; MOSI will be set to 1 during all bit transfers.
; This will leave: CLK=1, MOSI=1
; Returns the byte read in the A
; uses A
;===============================================================================

	assert	spi_miso==0x01, Bad SPI Din bit		; so RR moves it out too CY 

spi_read8
		push	bc, de
		ld		e, 0				; accumulate data in E
		in		a, (spi_out)		; current port outputs		
		and		~spi_clk			; CLK = 0
		or		spi_mosi			; MOSI = 1
		ld		d, a				; save in D for reuse

		; read the 8 bits
		ld		b, 0
.sr1	out		(spi_out), a		; set clock low (the read data moment)
		in		a, (spi_in)			; read data
		rr		a					; data into Carry
		rl		e					; data into E
		ld		a, d
		or		spi_clk				; set clock hi
		djnz	.sr1
		ld		a, e
		pop		de, bc
		; leaves CLK high as next clock low is part of the next byte
		ret

;===============================================================================
; Assert the select line
; This will leave: SSEL=0 (active), CLK=0, MOSI=1
; Uses A
;===============================================================================

spi_ssel_true
		; read and discard a byte to generate 8 clk cycles
		call	spi_read8

		; make sure the clock is low before we enable the card
		in		a, (spi_out)
		and		~spi_clk				; CLK = 0
		or		spi_mosi				; MOSI = 1
		out		(spi_out), a

		; enable the card
		and		~spi_ssel				; SSEL = 0
		out		(spi_out), a

		; generate another 8 clk cycles
		call	spi_read8
		ret

;===============================================================================
; de-assert the select line (set it high)
; This will leave: SSEL=1, CLK=0, MOSI=1
; Uses A
;===============================================================================
spi_ssel_false
		; read and discard a byte to generate 8 clk cycles
		call	spi_read8

		; make sure the clock is low before we disable the card
		in		a, (spi_out)
		and		~spi_clk				; CLK = 0
		out		(spi_out), a

		or		spi_ssel|spi_mosi		; SSEL=1, MOSI=1
		out		(spi_out), a

		; generate another 16 clk cycles
		call	spi_read8
		call	spi_read8
		ret

 if 0
;##############################################################
; Write the message from address in HL register for length in BC to the SPI port.
; Save the returned data into the address in the DE register
;##############################################################

spi_write
		call	spi_ssel_true

spi_write_loop
		ld		a, b
		or		c
		jp		z, spi_write_done
		push	bc
		ld		c, [hl]
		call	spi_write8
		inc		hl
		pop		bc
		dec		bc
		jp		spi_write_loop

spi_write_done
		call	spi_ssel_false
		ret
 endif

;===============================================================================
; HL = @ of bytes to write
; B = byte count
; clobbers: A, BC, D, HL
;===============================================================================

spi_write_str
		ld		c, [hl]			; get next byte to send
		call	spi_write8		; send it
		inc		hl				; point to the next byte
		djnz	spi_write_str	; count the byte & continue of not done
		ret
