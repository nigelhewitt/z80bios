;===============================================================================
;
; Serial.asm		Manage a 16550 UART
;
;===============================================================================
serial_start	equ		$

; UART registers
; <NC> indicates a pin that is not wired on the Zeta board

RBR		equ		UART+0		; Receive Buffer Register (read only)
THR		equ		UART+0		; Transmit Holding Register (write only)
IER		equ		UART+1		; Interrupt Enable Register
ERBFI	equ		0x01		;	Enable Received Data Available Interrupt
ETBEI	equ		0x02		;	Enable Transmit Holding Register Empty
ELSI	equ		0x04		;	Enable Receive Line Status Interrupt
EDSSI	equ		0x08		;	Enable Modem Status Interrupt
IIDR	equ		UART+2		; Interrupt Ident Register (read only)
NIP		equ		0x01		;	0 if interrupt pending
IMASK	equ		0x0e		;	3 bit interrupt ID
FFE		equ		0xc0		;	FIFO enables
FCR		equ		UART+2		; FIFO Control Register (write only)
FFEN	equ		0x01		;	FIFO enable
RFFR	equ		0x02		;	Receive FIFO Reset
TFFR	equ		0x04		;	Transmit FIFO reset
DMSEL	equ		0x08		;	DMA Mode Select
RCVR	equ		0xc0		;	Receiver Trigger
LCR		equ		UART+3		; Line Control Register (rw)
BITS5	equ		0x00		;	5 data bits
BITS6	equ		0x01		;	6 data bits
BITS7	equ		0x02		;	7 data bits
BITS8	equ		0x03		;	8 data bits
TSB		equ		0x04		;	two stop bits
PEN		equ		0x08		;	Parity enable
EPS		equ		0x10		;	Even Parity select
SPAR	equ		0x20		;	Stick Parity
SBRK	equ		0x40		;	Set Break
DLAB	equ		0x80		;	Divisor latch enable (convert UART+1,2 to divisor)
MCR		equ		UART+4		; Modem Control Register (rw)
DTR		equ		0x01		;	Data Terminal Ready  <NC>
RTS		equ		0x02		;	Request to Send
OUT1	equ		0x04		;	Out1 <NC>
OUT2	equ		0x08		;	Out2 <NC>
LOOPB	equ		0x10		;	Loopback
LSR		equ		UART+5		; Line Status Register (rw)
DAV		equ		0x01		;	Data Ready
OERR	equ		0x02		;	Overrun error
PERR	equ		0x04		;	Parity Error
FERR	equ		0x08		;	Framing Error
BI		equ		0x10		;	Break Interrupt
THRE	equ		0x20		;	Transmit Holding Register Empty
TEMT	equ		0x40		;	Transmitter Empty (fullY)
RXFFE	equ		0x80		;	Error in RCVR FIFO
MSR		equ		UART+6		; Modem Status Register (rw)
DCTS	equ		0x01		;	Delta CTS
DDSR	equ		0x02		;	Delta DSR <NC>
TERI	equ		0x04		; 	Trailing Edge RI <NC>
DDCD	equ		0x08		;	Delta DSR <NC>
CTS		equ		0x10		;	CTS
DSR		equ		0x20		;	DSR <NC 1>
RI		equ		0x40		;	RI  <NC 0>
DCD		equ		0x80		;	DCD <NC 1>

;===============================================================================
;	simplistic driver
;===============================================================================

serial_init							; set to 115200,8,1,N no handshaking
		ld		a, BITS8+TSB+DLAB
		out		(LCR), a
		ld		a, 1				; divider for 115200
		out		(UART+0), a
		xor		a
		out		(UART+1), a
		ld		a, BITS8+TSB		; 8,1,N
		out		(LCR), a
		ld		a, 0	; ERBFI		; only the rx data (at 8 bytes) interrupt
		out		(IER), a
		ld		a, FFEN  ; +0x80	; FIFOs enable + trigger IRAV at 8 bytes
		out		(FCR), a
		ld		a, RTS				; set both outputs
		out		(MCR), a
		ret

serial_dav							; check Data Available
		ld		a, RTS
		out		(MCR), a
		in		a, (LSR)
		and		DAV
		ret							; DAV sets NZ and returns true

serial_ndtr							; clear CTS so we don't get overrun
		xor		a
		out		(MCR), a
		ret

serial_read						; read data
		in		a, (LSR)
		and		DAV				; data available?
		jr		z, serial_read	; no
		in		a, (RBR)		; read data
		ret

serial_tbmt						; transmit buffer empty
		ret						; TBMT sets NZ and returns true

serial_sendW					; uses nothing
		push	af				; save the character to send
.ss1	in		a, (LSR)
		and		THRE
		jr		z, .ss1			; loop if !CTS || !THRE
		pop		af
		; then drop through
serial_send					; transmit a byte
		out		(THR), a
		ret

;===============================================================================
; Interrupt handler
;===============================================================================

; The only interrupt enabled atm is the Received data when the buffer
; reaches 8 characters which will just unset DTR
; Interrupt type table
si_table
		dw		si_ms			; 0 Modem Status
		dw		si_thre			; 2 Transmitter Holding Register Empty
		dw		si_rda			; 4 Received Data Available
		dw		si_rls			; 6 Receiver Line Status
		dw		si_dummy		; 8
		dw		si_dummy		; a
		dw		si_cto			; c Character Timeout
		dw		si_dummy		; e

serial_interrupt				; called from bios.asm
		di
		push	af
		push	hl
si1		in		a, (IIDR)		; interrupt ID
		bit		0, a			; test bit 0 in A
		jr		nz, .si2		; interrupt pending
		pop		hl
		pop		af
		ei
		reti

; Convert IID register value to vector
.si2	and		IMASK			; mask off any noise
		ld		hl, si_table
		add		a, l
		ld		l, a
		jr		nc, .si3
		inc		h
.si3	ld		a, [hl]
		inc		hl
		ld		h, [hl]
		ld		l, a
		jp		[hl]

; Modem Status Interrupt
; CTS, DSR, RI, DC change
si_ms	in		a, (MSR)		; reading MSR clears interrupt
		jr		si1

; Transmitter Holding Register Empty
si_thre:						; reading IIR cleared interrupt
		jr		si1

; Receive Data Available
si_rda:							; read data clears interrupt !!!!!!!!!!!!!!
		xor		a				; clear DTR+CTS
		out		(MCR), a
		jr		si1

; Receive line status
si_rls	in		a, (LSR)		; reading LSR clears interrupt
		jr		si1

; Character Timeout Indicator
si_cto							; reading
si_dummy
		jr		si1

 if SHOW_MODULE
	 	DISPLAY "serial size: ", /D, $-serial_start
 endif
