;===============================================================================
;
; debug.asm		<sulk> <sulk> I want a single step debugger
;
;===============================================================================

	define	MAN_READABLE	1	; include lots of formatting for testing

; OK so here's the concept:
; The assembler has done most of the work putting all the links to attach core
; addresses to files and line numbers. This measns with a bit of shifty windows
; MDI work I get the pages of code insynch with the numbers.
; I also wrote a terminal program.
; Then I add tis module to do break points via an RST code and knock up some
; to issue NMIs to ger single stepping.

	include	"zeta2.inc"		; hardware definitions
	include	"vt.inc"		; page0 bad 0x069 bytes definitions

			org		0x100
			jp		setup
			db		" NIGSOFT Z80 DEBUGGER "

; select the RST to use 0x08, 0x10, 0x18... 0x38
useRST		equ		0x28

; messages sent to the PC
OK_CMD		equ		'@'				; instruction carried out
BAD_CMD		equ		'?'				; instruction failed

; convert the RST selection into the OP code
rstCODE		equ		useRST | 0xc7	; the RST instruction

; where we store our trap information
			struct	TRAP
pc			dw		0		; 16 bit address
page		db		0		; RAM number
code		db		0		; the byte we replaced
			ends

NTRAPS		equ		10
VERSION		equ		1		; mark breaking change
traps
	dup	NTRAPS
			TRAP
	edup

; used to restore the RSTxx/NMI jump instruction when we exit
oldRST		db		0,0,0
oldNMI		db		0,0,0

; man readable stuff that can be easily turned on and off
CRLF		macro
  if MAN_READABLE
			call	_CRLF
  endif
			endm
SPACE		macro
  if MAN_READABLE
			call	_SPACE
  endif
			endm

;===============================================================================
; setHook		take over RSTxx/NMI
; dropHook		restore RSTxx/NMI
;				return NC on error
;===============================================================================
setHook		ld		hl, useRST		; the code is the address
			ld		de, oldRST
			ld		bc, trapRST
			call	.hook
			ret		nc

			ld		hl, 0x66		; the code is the address
			ld		de, oldNMI
			ld		bc, trapNMI

.hook		ld		a, [de]
			or		a
			ret		nz				; return NC

			ld		a, [hl]
			ld		[de], a
			ld		[hl], 0xc3		; JP address16
			inc		hl
			inc		de
			ld		a, [hl]
			ld		[de], a
			ld		[hl], c
			inc		hl
			inc		de
			ld		a, [hl]
			ld		[de], a
			ld		[hl], b
			scf
			ret

dropHook	ld		de, useRST
			ld		hl, oldRST
			call	.drop
			ret		nc

			ld		de, 0x66
			ld		hl, oldNMI

.drop		ld		a, [hl]
			or		a
			ret		z					; return NC
			ld		b, 3
.dh1		ld		a, [hl]
			ld		[de], a
			ld		[hl], 0
			inc		hl
			inc		de
			djnz	.dh1
			scf
			ret

;===============================================================================
; getSlot	called with A = slot number, returns IX set to that slot
;			if the slot requested is too big returns NC
;===============================================================================
getSlot		cp		NTRAPS
			ret		nc					; >= NTRAPS
			push	hl, de
			ld		hl, traps			; first trap struct
			or		a
			jr		z, .gs2				; no adds
			ld		b, a
			ld		de, TRAP			; size of TRAP structure
.gs1		add		hl, de
			djnz	.gs1
.gs2		ld		ix, hl
			pop		de, hl
			scf
			ret

;===============================================================================
; getRAM		ensure the RAM we want to put a trap in is accessible
;				call with RAMn in C in reversed (RAM then ROM) order
;				returns HL as a pointer to the base of the ram in question.
;				if it needed mapping it will set up to do that
;				uses A
; restoreRAM	to restore the caller (or do nothing)
;				uses A
;===============================================================================
getRAM		push	bc, de
			ld		hl, Z.savePage		; where we save the page assignments
			ld		b, 4
			ld		a, c
			ld		d, 0
.st1		ld		a, c				; get RAMn
			xor		0x20				; toggle ROM/RAM to hardware style
			cp		[hl]				; what is in what page?
			jr		z, .st2				; we have a match
			inc		hl
			inc		d
			djnz	.st1

; if we get here the RAM we want is not mapped in so we put it in PAGE1
			ld		a, [Z.savePage+1]
			ld		[.saveRAM], a		; page we need to restore
			ld		a, c
			out		(MPGSEL+1), a		; map the required page
			ld		hl, PAGE1
			pop		de, bc
			ret

; RAM is accessible without re-mapping
.st2		ld		hl, 0
			rr		d					; convert 0-1-2-3 to 0-0x40-0x80-0xc0
			rr		h
			rr		d
			rr		h
			ld		a, 0				; zero for nothing to fix on exit
			ld		[.saveRAM], a
			pop		de, bc
			ret

.saveRAM	db		0

restoreRAM	ld		a, [getRAM.saveRAM]
			or		a
			ret		z
			out		(MPGSEL+1), a
			ret

;===============================================================================
;	SetTrap		call	IX pointer to trap structure
;						C RAMn to set the trap in (0-31)
;						HL address14 to trap (we will mask it)
;				returns CY if OK (NC = slot already used)
;===============================================================================

; first check if it is already used
setTrap		ld		a, [ix+TRAP.page]	; check used (aka PC set)
			or		[ix+TRAP.pc+1]
			ret		nz					; already used return NC

; first find if we have that page on the map...
			push	de, hl, hl
			call	getRAM
			pop		de					; was HL
			ld		l, e
			ld		a, d
			and		0x3f
			or		h
			ld		h, a				; gives us a mapped HL

			ld		a, [hl]
			ld		[ix+TRAP.code], a
			ld		[ix+TRAP.pc], l
			ld		[ix+TRAP.pc+1], h
			ld		[ix+TRAP.page], c
			ld		[hl], rstCODE		; RSTxx
			call	restoreRAM			; undo any mapping
			pop		hl, de
			scf
			ret

resetTrap	push	de, hl
			ld		c, [ix+TRAP.page]
			call	getRAM
			pop		de					; was HL
			ld		l, [ix+TRAP.pc]
			ld		a, [ix+TRAP.pc+1]
			and		0x3f
			or		d
			ld		h, a				; gives us a mapped HL
			ld		[hl], rstCODE
			call	restoreRAM
			pop		hl, de
			ret

freeTrap	push	de, hl
			ld		c, [ix+TRAP.page]
			call	getRAM
			pop		de					; was HL
			ld		l, [ix+TRAP.pc]
			ld		a, [ix+TRAP.pc+1]
			and		0x3f
			or		d
			ld		h, a				; gives us a mapped HL

			ld		a, [ix+TRAP.code]
			ld		[hl], a
			call	restoreRAM
			pop		hl, de
			ret

;===============================================================================
;	Trap	the hook has caught one
;			the PC is on the stack
; the RAM must be mapped for it to execute so the system is simpler
;===============================================================================

	struct REGS
sp		dw		0
iy		dw		0
ix		dw		0
hl		dw		0
de		dw		0
bc		dw		0
af		dw		0
pc		dw		0
	ends

trapRST		push	af, bc
			call	.trapW		; put regs et all on the stack and set IY

; now we need to reset the trap by putting the replaced character back
; so we can 'continue' or step

; get the page for the PC in C
			ld		a, [iy+REGS.pc+1]	; MSbyte of PC
			ld		l, Z.savePage>>2	; on dd boundary so nothing lost
			rl		a					; slide A into L  <<2
			rl		l
			rl		a
			rl		l					; gives the address of the savePage+n
			ld		h, 0
			ld		c, [hl]				; give the page for this address

; and the 14 bit version of the address in DE
			ld		e, [iy+REGS.pc]
			ld		a, [iy+REGS.pc+1]
			and		0x3f				; mask to 14 bit address in DE
			ld		d, a

; set up for a loop of the TRAPS
			ld		ix, traps
			ld		b, NTRAPS

; get the page for the PC
.tr1		ld		a, [ix+TRAP.page]	; test the page
			cp		c
			jr		nz, .tr2			; nope
			ld		a, [ix+TRAP.pc]		; test LSbyte of PC
			cp		e
			jr		nz, .tr2
			ld		a, [ix+TRAP.pc+1]	; MS byte of PC
			and		0x3f				; but that's a 14 bit address
			cp		d
			jr		z, .tr3				; we have a match
.tr2		ld		hl, TRAP			; size of a TRAP structure
			ex		hl, de
			add		ix, de
			ex		hl, de
			djnz	.tr1
			ld		ix, 0				; signals we have no context
			jr		.tr4				; compiled in RST so no reset needed

; we have found a call so patch the code hack to how it was
			dec		[iy+REGS.pc]		; back up over the RST
.tr3		ld		hl, [iy+REGS.pc]	; this is the code
			ld		a, [ix+TRAP.code]
			ld		[hl], a
.tr4
			call	debugger

; return to code
.tr5		pop		hl					; discard the copy of the SP
			pop		iy, ix, hl, de, bc, af
			ret

; worker to put the registers et al on the stack
.trapW		pop		bc					; return address
			push	de, hl, ix, iy		; now six on stack (12 bytes)
			; the alt registers can be directly accessed as they won't change
			ld		iy, 14
			add		iy, sp				; gives SP when the RST was executed
			push	iy

			ld		iy, 0
			add		iy, sp				; points to REGS on the stack
										; so [iy+REGS.de] is the DE value etc.
			ld		hl, bc				; now 'return'
			jp		[hl]

;===============================================================================
; trapNMI	hopefully an expected Single Step return
;===============================================================================

trapNMI		push	af, bc
			call	trapRST.trapW		; use the worker in trapRST

			ld		ix, 0
			jr		singleStep.ss1

;===============================================================================
; setup		called by the installer
;===============================================================================
setup		push	af, bc
			call	trapRST.trapW		; use the worker in trapRST

			ld		ix, 0
			call	debugger			; no reset to worry about

; return to code
			jr		trapRST.tr5			; same code so why not?

;===============================================================================
; singleStep	step on to the next instruction
;				This might be used to do a 'proper' debugging step or
;				it might just be used to get the current instruction done so we
;				can replace the trap
; WARNING: must only be called from the debugger with NOTHING pushed
;===============================================================================

magic_port		equ		MPGEN
magic_set		equ		0x81
magic_clear		equ		0x01

singleStep	pop		hl					; our return address
			ld		[.ssReturn], hl
			pop		hl					; the debuggers return address
			ld		[.ssReturn+2], hl
			ld		[.ssIX], ix
			pop		hl					; discard the SP copy
			pop		iy, ix, hl, de, bc
			ld		a, magic_set
			out		(magic_port), a		; part of 11T
			pop		af					; 10T
			ret							; 10T and 27T (? later the NMI sets

; and the NMI handler puts everything back on the stack and jumps to here
.ss1		ld		a, magic_clear		; turn off the NMI
			out		(magic_port), a
			ld		ix, [.ssIX]
			ld		hl, [.ssReturn+2]
			push	hl
			ld		hl, [.ssReturn]		; return address so we are 'normal'
			push	hl
			retn						; unwind the FF registers

.ssReturn	dw		0
.ssIX		dw		0

;===============================================================================
; debugger	wait for and execute debugger commands
; NB: I have put a lot of 'man readable' stuff in for testing both ways so
; whitespace should just be ignored
;===============================================================================

commandList	db		'i'				; get information
			dw		cmd_info
			db		'h'				; set hooks
			dw		cmd_hook
			db		'u'				; clear hooks
			dw		cmd_unhook
			db		'+'				; set a trap
			dw		cmd_trap
			db		'-'				; clear a trap
			dw		cmd_untrap
			db		'r'				; send registers
			dw		cmd_getregs
			db		't'				; set registers
			dw		cmd_setregs
			db		'g'				; send memory
			dw		cmd_get
			db		'p'				; put memory
			dw		cmd_put
			db		'k'				; continue
			dw		cmd_continue
			db		'x'				; execute from an address
			dw		cmd_exec
			db		's'				; step
			dw		cms_step
			db		'z'				; close down
			dw		cmd_close
			db		'q'				; used as a dummy
			dw		bad_end
			db		0				; end of list

debugger
			call	sendSignOn

; commands (no command can be hex or we could get in a total mess)
.db1		CRLF
			ld		a, OK_CMD
			call	putc

.db1a		call	getc			; getc ignores white space but does do echo
			call	ishex			; ignore hex if data is streaming
			jr		c, .db1a

			ld		c, a			; hold the command in C
			ld		hl, commandList
.db2		ld		a, c
			cp		[hl]			; test against the list
			jr		z, .db3			; we have a match
			inc		hl
			inc		hl
			inc		hl
			ld		a, [hl]
			or		a
			jr		nz, .db2
			jr		bad_end

; found
.db3		inc		hl				; step over the command char
			ld		a, [hl]			; load the address
			inc		hl
			ld		h, [hl]
			ld		l, a
			jp		[hl]

; and the two usual returns
good_end	ld		a, OK_CMD
.ge1		call	putc
			jr		debugger.db1

some_end	jr		c, good_end
bad_end		ld		a, BAD_CMD
			jr		good_end.ge1

;===============================================================================
;	command handlers
;	either end by jumping to good_end or bad_end
;	or if they are CY/NC for bad/good some_end
;===============================================================================

;-------------------------------------------------------------------------------
; 'i' COMMAND: get info
cmd_info
			ld		a, VERSION
			call	packB
			ld		a, NTRAPS
			call	packB
			jr		good_end

;-------------------------------------------------------------------------------
; 'h' COMMAND: set Hook
cmd_hook
			call	setHook			; adopt RST and NMI
			jr		some_end		; report errors

;-------------------------------------------------------------------------------
; 'u' COMMAND: release hook
cmd_unhook
			call	dropHook		; restore RST and NMI
			jr		some_end		; report errors

;-------------------------------------------------------------------------------
; '+s slot page address' COMMAND: set a trap
cmd_trap
			call	unpackB			; slot in A
			jr		nc, bad_end		; not hex
			call	getSlot			; point IX to the slot
			jr		nc, bad_end		; no such slot

			call	unpackB			; get the page in A
			jr		nc, bad_end
			ld		c, a
			call	unpackW			; address in HL
			jr		nc, bad_end

			call	setTrap			; needs IX=slot, C=page, HL=address
			jr		some_end		; report errors

;-------------------------------------------------------------------------------
; '-s slot' COMMAND: remove a trap and free the slot
cmd_untrap
			call	unpackB
			jr		nc, bad_end
			call	getSlot
			jr		nc, bad_end

			call	freeTrap		; requires IX
			jr		good_end		; does not report

;-------------------------------------------------------------------------------
; 'r' COMMAND: send registers
; the stack is ret SP AF BC DE HL IX IY ret_from_debugger
cmd_getregs
; ret sp, iy, ix, hl, de, bc, af, pc
			ld		hl, iy				; point to regs on stack
			ld		b, 8
.cr1		ld		e, [hl]
			inc		hl
			ld		d, [hl]
			inc		hl
			ex		de, hl
			SPACE
			call	packW
			ex		de, hl
			djnz	.cr1

; af' bc' de' hl'
			exx
			push	hl, de, bc
			exx
			ex		af, af'
			push	af
			ex		af, af'
			ld		b, 4
.cr2		pop		hl
			SPACE
			call	packW
			djnz	.cr2
			jp		good_end

;-------------------------------------------------------------------------------
; 't' COMMAND set registers
cmd_setregs
			jp		bad_end

;-------------------------------------------------------------------------------
; g address16 count8 COMMAND: get memory
cmd_get
			call	unpackW			; address in HL
			jp		nc, bad_end
			call	unpackB			; count is A
			jp		nc, bad_end
			ld		b, a			; count
.cg1		ld		a, [hl]
			call	packB
			inc		hl
			djnz	.cg1
			jp		good_end

;-------------------------------------------------------------------------------
; p address count dddd.. COMMAND: put memory
cmd_put
			jp		bad_end

;-------------------------------------------------------------------------------
; k COMMAND continue
cmd_continue
			ld		a, OK_CMD
			call	putc
			call	sendSignOff
			ret

;-------------------------------------------------------------------------------
; 'x address' execute from an address
cmd_exec
			call	unpackW
			jp		nc, bad_end
			ld		[iy+REGS.pc], hl
			jr		cmd_continue

;-------------------------------------------------------------------------------
; 's' single step command
cms_step
			call	singleStep
			jp		good_end

;-------------------------------------------------------------------------------
; 'z' close down command
cmd_close
;			call	sendSignOff
			jp		bad_end

;===============================================================================
; utilities
;===============================================================================

_CRLF		push	af
			ld		a, 0x0d
			call	serial_putc
			ld		a, 0x0a
			call	serial_putc
			pop		af
			ret

_SPACE		push	af
			ld		a, 0x20
			call	serial_putc
			pop		af
			ret

text		ld		a, [hl]
			or		a
			ret		z
			call	putc
			inc		hl
			jr		text


sendSignOn	ld		hl, .signon
			jr		text
.signon		db		0x1b, "[1?",0

sendSignOff	ld		hl, .signoff
			jr		text
.signoff	db		0x1b, "[0?\r\n", 0

ishex		cp		'0'
			jr		c, .ih1			; jr LT so bad
			cp		'9'+1
			ret		c				; LT so 0-9
			cp		'A'
			jr		c, .ih1
			cp		'F'+1
			ret		c
			cp		'a'
			jr		c, .ih1
			cp		'f'+1
			ret
.ih1		or		a				; clear carry
			ret

; getc with skip white
getc		call	serial_getc
			cp		' '
			jr		z, getc
			cp		0x0d
			jr		z, getc
			cp		0x0a
			jr		z, getc
			ret

; putc as an alias to serial_putc
putc		jr		serial_putc

; HEX HANDLERS : Man readable so MS first !!!!!!!!!!!!!!!!!!!!!!

; unpack nibble return CY on OK
unpackN		call	getc
; try a-f
			cp		'f'+1
			ret		nc			; >='f'+1 so bad
			cp		'a'
			jr		c, .un2		; < 'a' so try lower
			sub		'a'-10
.un1		scf
			ret
; try A-F
.un2		cp		'F'+1
			ret		nc			; >='F'+1 so bad
			cp		'A'
			jr		c, .un3		; <'A'
			sub		'A'-10		; hence A-F
			jr		.un1
; try 0-9
.un3		sub		'0'
			jr		c, .un4		; fail <'0'
			cp		10
			jr		c, .un1	; good <=9
.un4		or		a
			ret

; unpack byte into A
unpackB		call	unpackN
			ret		nc
			sla		a
			sla		a
			sla		a
			sla		a
			ld		[.upA], a
			call	unpackN
			ret		nc
			db		0xf6		; OR A, n
.upA		db		0			; n
			scf
			ret

; unpack word into HL
unpackW		ld		[.upW], a
			call	unpackB
			ret		nc
			ld		h, a
			call	unpackB
			ld		l, a
			db		0x3e		; LD A,n
.upW		db		0			; n
			ret

; pack a word in HL, uses A
packW		ld		a, h
			call	packB
			ld		a, l
			; fall through

; pack a byte in A
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
			call	putc
			pop		af
			ret

;===============================================================================
; code lifted from serial.asm
;===============================================================================

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
