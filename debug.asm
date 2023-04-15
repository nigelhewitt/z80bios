;===============================================================================
;
; debug.asm		<sulk> <sulk> I want a single step debugger
;
;===============================================================================

; OK so here's the concept:
; We read the assemblers output and display a cut down version of that on
; the PC and to trap/single step the code we copy the next instruction out
; and put in an RTS ??. The RST throws to a wait and report system and when
; it is told to continue we replace the command and jump to it. Single step
; just implies adding another trap on the next opcode.

			org		0x100
			jp		setup

; select the RST to use 0x08, 0x10, 0x18... 0x38
useRST		equ		0x28

; messages sent to the debugger
HAVE_TRAP	equ		'!'				; trap fired
BAD_TRAP	equ		'~'				; bad trap fired
OK_TRAP		equ		'@'				; instruction carried out

; convert the RST selection into the OP code
rstCODE		equ		useRST | 0xc7	; the RST instruction

; where we store our trap information
			struct	trap
PC			dw		0
CODE		db		0
			ends

NTRAPS		equ		10
traps
	dup	NTRAPS
			trap
	edup

; used to restore the RSTxx jump instruction when we exit
oldHook		db		0,0,0

;===============================================================================
; setHook		take over RST28
; dropHook		restore RST28
;===============================================================================
setHook		ld		hl, useRST
			ld		de, oldHook
			ld		a, [hl]
			ld		[de], a
			ld		[hl], 0xc3		; JP address16
			inc		hl
			inc		de
			ld		a, [hl]
			ld		[de], a
			ld		[hl], Trap & 0xff
			inc		hl
			inc		de
			ld		a, [hl]
			ld		[de], a
			ld		[hl], Trap >> 8
			ret

dropHook	ld		hl, useRST
			ld		de, oldHook
			ld		b, 3
.dh1		ld		a, [de]
			ld		[hl], a
			inc		hl
			inc		de
			djnz	.dh1
			ret

;===============================================================================
; getSlot	called with A = slot number, returns IX set to that slot
;			if the slot requested is too big returns NC
;===============================================================================
getSlot		cp		NTRAPS
			ret		nc

			push	hl, de
			ld		hl, traps
			or		a
			jr		z, .gs2
			ld		b, a
			ld		de, trap			; size of trap structure
.gs1		add		hl, de
			djnz	.gs1
.gs2		ld		ix, hl
			pop		de, hl
			scf
			ret

;===============================================================================
;	SetTrap		call	IX pointer to trap structure
;						HL address to trap
;				returns CY if OK (NC = slot already used)
;===============================================================================

setTrap		ld		a, [ix+trap.PC]		; chech used (aka PC set)
			or		[ix+trap.PC+1]
			jr		nz, .st1			; already used
			ld		a, [hl]
			ld		[ix+trap.CODE], a
			ld		[ix+trap.PC], l
			ld		[ix+trap.PC+1], h
			ld		[hl], rstCODE		; RSTxx
			scf
			ret
.st1		or		a					; clear carry
			ret

resetTrap	ld		l, [ix+trap.PC]
			ld		h, [ix+trap.PC+1]
			ld		a, [ix+trap.CODE]
			ld		[hl], a
			ret

freeTrap	ld		l, [ix+trap.PC]
			ld		h, [ix+trap.PC+1]
			ld		a, h
			or		l
			ret		z
			ld		a, [ix+trap.CODE]
			ld		[hl], a
			xor		a
			ld		[ix+trap.CODE], a
			ld		[ix+trap.PC], a
			ld		[ix+trap.PC+1], a
			ret

;===============================================================================
;	Trap	the hook has caught one
;			the PC is on the stack
;===============================================================================

Trap		push	af, bc, de, hl, ix, iy	; six on stack (12 bytes)
			ld		hl, 0
			add		hl, sp				; points to the HL on the stack
			ld		bc, 14
			sub		hl, bc				; point to the return address
			ld		e, [hl]
			inc		hl
			ld		d, [hl]				; get the return address

			ld		b, NTRAPS
			ld		ix, traps			; first trap structure
.tr1		cp		l, [ix+trap.PC]
			jr		nz, .tr2
			cp		h, [ix+trap.PC+1]
			jr		z, .tr3 			; match
.tr2		ld		de, trap			; size of trap structure
			add		ix, de
			djnz	.tr1

; unexpected trap
			ld		a, BAD_TRAP			; crash and burn
			call	serial_putc
			call	packW				; send the address

			ld		a, 2				; bad trap mode
			call	debugger
			jr		.tr4				; bad trap so nothing to repaint

; good trap
.tr3		call	CRLF
			ld		a, HAVE_TRAP
			call	serial_putc
			call	packW				; send address

			ld		a, 1				; good trap mode
			call	debugger

; exit good trap
; restore the code value we overwrote
			ld		l, [ix+trap.PC]
			ld		h, [ix+trap.PC+1]
			ld		a, [ix+trap.CODE]
			ld		[hl], a

; decrement the return address so we execute that code
			ld		hl, 0
			add		hl, sp
			ld		bc, 14
			add		hl, bc				; points to return address

			ld		e, [hl]
			inc		hl
			ld		d, [hl]
			dec		de
			ld		[hl], d
			dec		hl
			ld		[hl], e

; return to code
.tr4		pop		iy, ix, hl, de, bc, af
			ret

;===============================================================================
; debugger	wait for and execute debugger commands
;			this runs in three modes:
;			0 startup 	when it has no context to display
;			1 trap		with a context
;			2 badTrap 	unexpected call
;===============================================================================

debugger	ld		[.dbMode], a

; commands (no command can be hex or we could get in a mess)
.db1		call	CRLF
			ld		a, '>'
			call	serial_putc
			call	serial_putc

			call	serial_getc
			cp		'H'				; set hook
			jr		z, .db4
			cp		'U'				; unhook
			jr		z, .db6
			cp		'+'				; set a trap
			jr		z, .db7
			cp		'-'				; clear a trap
			jr		z, .db8
			cp		'R'				; send registers
			jr		z, .db9
			cp		'G'				; get memory
			jr		z, .db11
			cp		'P'				; put memory
			jr		z, .db20
			cp		'X'				; continue
			jr		z, .db30
			cp		'S'				; step
			jr		z, .db40
			cp		'Z'				; crash out
			jr		z, .db50

; ignore hex
			cp		'0'
			jr		c, .db2			; <'0' so bad
			cp		'9'+1
			jr		nc, .db1		; <='9' so ignore
			cp		'A'
			jr		c, .db2			; <'A' so bad
			cp		'F'+1
			jr		nc, .db1		; <='F' so ignore

; command error
.db2		ld		a, '?'			; command not recognised
.db3		call	serial_putc
			jr		.db1			; loop

; H COMMAND: set Hook
.db4		call	setHook
.db5		ld		a, OK_TRAP
			jr		.db3

; U COMMAND: release hook
.db6		call	dropHook
			jr		.db5

; +ssaaaa COMMAND: set a trap
.db7		call	unpackB			; slot in A
			jr		nc, .db2		; not hex
			call	getSlot			; point IX to the slot
			jr		nc, .db2		; no such slot
			call	unpackW			; address in HL
			jr		nc, .db2
			call	setTrap
			jr		nc, .db2		; trap already in use
			jr		.db5

; -ss COMMAND: remove a trap
.db8		call	unpackB
			jr		nc, .db2
			call	getSlot
			jr		nc, .db2
			call	freeTrap
			jr		.db5

; R COMMAND: send registers
; the stack is ret SP AF BC DE HL IX IY ret_from_debugger
.db9		ld		hl, 0
			add		hl, sp				; points to the HL on the stack
			ld		bc, 16
			sub		hl, bc				; point to the return address

			ld		e, [hl]
			inc		hl
			ld		d, [hl]
			inc		hl
			dec		de					; omit the RST
			ex		hl, de
			call	packW
			ex		hl, de
			ld		b, 6
.db10		ld		e, [hl]
			inc		hl
			ld		d, [hl]
			inc		hl
			ex		de, hl
			call	packW
			ex		de, hl
			djnz	.db10
			jr		.db5

; Gaaaannnn COMMAND: get memory
.db11

; Paaaannnndddd... COMMAND: put memory
.db20

; C COMMAND: continue
.db30
; S COMMAND: step
.db40
; Z COMMAND: crash out
.db50
			jr		.db2

.dbMode		db		0		;

CRLF		push	af
			ld		a, 0x0d
			call	serial_putc
			ld		a, 0x0d
			call	serial_putc
			pop		af
			ret
;===============================================================================
; setup called to initialise
;===============================================================================

setup		xor		a				; setup mode
			jp		debugger

;===============================================================================
; hex managers
;===============================================================================

; unpack nibble return CY on OK (upper case only)
unpackN		call	serial_getc
; try A-F
			cp		'F'+1
			ret		nc			; >'F'+1 so bad
			cp		'A'
			jr		c, .un2		; <'A'
			sub		'A'-10		; hence A-F
.un1		scf
			ret
; try 0-9
.un2		sub		'0'
			jr		c, .un3		; fail <'0'
			cp		10
			jr		nc, .un1	; good <=9
.un3		or		a
			ret

; unpack byte into A, uses B
unpackB		call	unpackN
			ret		nc
			sla		a
			sla		a
			sla		a
			sla		a
			ld		b, a
			call	unpackN
			ret		nc
			or		b
			ret

; unpack word into HL, uses A and B
unpackW		call	unpackB
			ret		nc
			ld		h, a
			call	unpackB
			ld		l, a
			ret

; pack a word
packW		ld		a, h
			call	packB
			ld		a, l
			call	packB
			ret

; pack a byte (MSnibble first = man readable)
packB		push	af				; A in hex
			srl		a				; a>>=4
			srl		a
			srl		a
			srl		a
			call	packN
			pop		af
			; fall through

; pack a nibble
packN		push	af
			and		0x0f
			add		0x90			; kool trick
			daa						; if a nibble is >0x9 add 6
			adc		0x40
			daa
			call	serial_putc
			pop		af
			ret

;===============================================================================
; code lifted from serial.asm
;===============================================================================

UART	equ		68H			; UART (16550)
RBR		equ		UART+0		; Receive Buffer Register (read only)
THR		equ		UART+0		; Transmit Holding Register (write only)
LSR		equ		UART+5		; Line Status Register (rw)
DAV		equ		0x01		;	Data Ready
THRE	equ		0x20		;	Transmit Holding Register Empty

serial_getc						; read data
		in		a, (LSR)
		and		DAV				; data available?
		jr		z, serial_getc	; no
		in		a, (RBR)		; read data
		ret

serial_putc						; uses nothing
		push	af				; save the character to send
.ss1	in		a, (LSR)
		and		THRE
		jr		z, .ss1			; loop if !CTS || !THRE
		pop		af
		out		(THR), a
		ret
