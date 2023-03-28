//==============================================================================
//
//		SPI.asm
//
//==============================================================================

; start with the definitions of the i/o bits

; The PIO is set to PORT-C LOWER=INPUTS  UPPER=OUTPUTS
; ports
spi_out			equ		PIO_C
spi_in			equ		PIO_C

; bits
; Dout is b7 and Din is b0 so I can handle data with shifts
spi_mosi	equ		0x80	; C7
spi_clk		equ		0x40	; C6
spi_sd_sel	equ		0x20	; C5
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
;	Good SPI text
;		https://www.analog.com/en/analog-dialogue/articles/introduction-to-spi-interface.html
;
;===============================================================================
; This library is for SPI mode 0 (SD cards operate on SPI mode 0)
; "Data is sampled on rising CLK edge and changes on falling CLK edge"
; So set your data out, do CLK=1,   read your data in, do CLK=0
; To assert mode 0 the clock should always be low when CS transitions
; Data is sent MSB first
; It appears that all commands have a zero MSB so if the MOSI line is
; left high you are just receiving.
;        __                                             ___
; /CS      \_____________________ ... ________________/      Host --> Device
;                __    __    __   ... _    __    __
; CLK    _______/  \__/  \__/  \__     \__/  \__/  \______   Host --> Device
;        _____ _____ _____ _____ _     _ _____ _____ ______
; MOSI   _____X_____X_____X_____X_ ... _X_____X_____/         Host --> Device
;        _____ _____ _____ _____ _     _ _____ _____ ______
; MISO   _____X_____X_____X_____X_ ... _X_____X_____/         Host <-- Device
;
;===============================================================================
; Write 8 bits in C to the SPI port MSB first
; Call with SSEL=0 and CLK=0
; This will leave: CLK=0, MOSI=(the LSB of the byte written)
; Uses: A
;===============================================================================

 assert spi_mosi==0x80, Bad SPI Dout bit		; so RR moves in from CY

spi_write8
		push	bc
		ld		c, a
		in		a, (spi_out)		; current bits

		ld		b, 8
; set up data bit
.sw1	rla							; slide A left so MOSI spills out
		rl		c					; data b7 into CY
		rra							; data into A b7=MOSI getting A straight
		out		(spi_out), a		; set data value on MOSI
; CLK hi
		or		spi_clk				; clock high with data
		out		(spi_out), a		; CLK=1
; CLK lo
		and		~spi_clk			; clock low to trigger sample
		out		(spi_out), a		; tell them to read data
; loop
		djnz	.sw1
		pop		bc
		ret

;===============================================================================
; Read 8 bits from the SPI & return it in A. MSB first
; MOSI will be set to 1 during all bit transfers.
; should be called with: CLK=0 and MOSI=1
; This will leave:		 CLK=0 and MOSI=1
; Returns the byte read in the A
; uses A
;===============================================================================

	assert	spi_miso==0x01, Bad SPI Din bit		; so RR moves it out too CY

spi_read8
		push	bc, de
		in		a, (spi_out)		; current port outputs
		or		spi_mosi			; MOSI set to 1 ('send' a 0xFF)
;		out		(spi_out), a

		; read the 8 bits
		ld		b, 8
; clk hi
.sr1	ld		d, a				; save clock low output bits while we use A
		or		a, spi_clk			; set clock hi
		out		(spi_out), a
; read a bit						; if we were uber fast we would delay here
		in		a, (spi_in)			; read data
		rra							; data into Carry
		rl		e					; data into E b0
; clock lo
		ld		a, d				; get the clock low bits back
		out		(spi_out), a
		djnz	.sr1
		ld		a, e
		pop		de, bc
		ret

;===============================================================================
; Assert the SD select line
; This will leave: SSEL=0 (active), CLK=0, MOSI=1
; Uses A
;===============================================================================

spi_sd_sel_true
		; read and discard a byte to generate 8 clk cycles
		call	spi_read8

		; make sure the clock is low before we enable the card
		in		a, (spi_out)
		and		~spi_clk				; CLK = 0
		or		spi_mosi				; MOSI = 1
		out		(spi_out), a

		; enable the card
		and		~spi_sd_sel				; SD_SEL = 0
		out		(spi_out), a

		; generate another 8 clk cycles
		call	spi_read8
		ret

;===============================================================================
; de-assert the select line (set it high)
; This will leave: SD_SEL=1, CLK=0, MOSI=1
; Uses A
;===============================================================================
spi_sd_sel_false
		; read and discard a byte to generate 8 clk cycles
		call	spi_read8

		; make sure the clock is low before we disable the card
		in		a, (spi_out)
		and		~spi_clk				; CLK = 0
		out		(spi_out), a

		or		spi_sd_sel|spi_mosi		; SD_SEL=1, MOSI=1
		out		(spi_out), a

		; generate another 16 clk cycles
		call	spi_read8
		jp		spi_read8

 if 0
;##############################################################
; Write the message from address in HL register for length in BC to the SPI port.
; Save the returned data into the address in the DE register
;##############################################################

spi_write
		call	spi_sd_sel_true

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
		call	spi_sd_sel_false
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
