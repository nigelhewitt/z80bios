﻿;===============================================================================
;
; debug.asm		<sulk> <sulk> I want a single step debugger
;
;===============================================================================

	define	MAN_READABLE	1	; include lots of formatting for testing

; OK so here's the concept:
; The assembler has done most of the work putting all the links to attach core
; addresses to files and line numbers. This means that with a bit of shifty
; windows MDI work I get the pages of code in synch with the numbers.
; I also wrote a terminal program.
; Then I add this module to do break points via an RST code and knock up some
; hardware to issue NMIs to get single stepping.

;===============================================================================
;
; Problem number one: how to divert from my program under test to the debugger.
;
; I will have three ways in.
; 1) a callable function to set things up and test it with the DBG command
; 2) RST 0x28 executable code either compiled in or set as a 'trap'
;	 The trap version must save the code it replaces and reinsert it after the
;	 trap fires and back up the PC by one so 'continue' actually continues.
; 3) The NMI trap. See discussion of timing later but this allows single step
;	 execution.
;
;===============================================================================
;
; Problem number two: the RST/NMI code wants to break to the debug code.
;
; So firstly the redirection vectors in PAGE0 can point to fixed addresses so
; I need a fixed location handler to vector to PAGE3/RAM5 where the code lives.
; This can go in stepper.asm. See the macro MAKET below.
;
;===============================================================================

startDebug		equ		$
magic_port		equ		MPGEN
magic_set		equ		0x81
magic_clear		equ		0x01

; !! Currently I have the NMI card set to 30

;===============================================================================
;
; This file is compiled into all 'ROM's so they can all redirect the RST
; and the NMI vectors through to the works in RAM5
;
; code for a system that must switch PAGE3 to RAM5 to execute the debugger
;===============================================================================

; There are two versions of the macro MAKET and the go in the same place in the
; address16 map so the PAGE0 vectors always point to a handler. In RAM5 it goes
; straight to the code while in all others it does a page switch and then goes
; to the code passing on its return information. To make things compact I make
; both switch directions happen at the same point so the execution path in just
; runs through a point as if a routine was called.

; The macros are defined here to keep the code logical but used in switcher.asm

  if BIOSRAM != RAM5		; RAM5 is the server, all others are clients

;-------------------------------------------------------------------------------
; client macro to be used by switcher.asm
;
; There will be two of these, one for the RST and the other for the NMI
; They were initially intended to be two identical units on that did the
; mapping for the RST and the other for the NMI.

; The PAGE0 vector points to the start of the macro so we have the return
; address on the stack. Then we push HL, AF and BC.
; Then load B with the return RAMn value
; The macro then switches to RAM5 so they must be aligned exactly.
;
; RAM5 does the debugger functions and then switches back to the caller here.
; Rather than necessarily using the matching exit the RST exit just continues
; while the NMI one fires the 'single step' device.
; They both execute POP BC,AF,HL RET/RETN
;
; Because of all the alignment issues there is a lot of checking that flags up
; errors if something goes wrong.
;-------------------------------------------------------------------------------

; to return to the caller
;		jump to the start of the macro
;		with the target RAM hardware address in A

; the vector on RST and NMI point to start+5

 	macro	MAKET	isNMI
.p1			call	debugLoad
			out		(MPGSEL3), a

		if ($-.p1) != 5
		 	DISPLAY "MAKET access address: 5 expected but got: ", /D, $-.p1
			problem with 5
		endif
			pop		bc
		if isNMI
			ld		a, magic_set
			out		(magic_port), a
		endif
  			pop		af, hl
  			ret
		if !isNMI
			nop : nop: nop : nop
		endif

		if ($-.p1) != 13
		 	DISPLAY "MAKET size: 13 expected but got: ", /D, $-.p1
			problem with 13
		endif
  	endm

debugLoad	ex		(sp), hl		; put HL on stack and return address in HL
			push	af, bc			; gives HL,AF,BC on stack
			ld		a, RAM5			; target PAGE3 RAM in HW format
			ld		b, BIOSRAM		; client PAGE3 RAM
			jp		(hl)			; 'return'

;===============================================================================
; code for a system that is in RAM5 already
;===============================================================================
 else

; server macro to be used by stepper.asm

; funcLocal		is the local version of the handler with no page switching
; funcRemote	is the handler for a page switched call
; funcExit		is a way to return to a different address (execute from...)

 	macro	MAKET	funcLocal, funcRemote, funcExit
.p1			jp		funcLocal
funcExit	out		(MPGSEL3), a
		if ($-.p1) != 5
		 	DISPLAY "MAKET access address: 5 expected but got: ", /D, $-.p1
			error message
		endif
  			jp		funcRemote
  			nop : nop :nop :nop : nop
		if ($-.p1) != 13
		 	DISPLAY "MAKET size: 13 expected but got: ", /D, $-.p1
			error message
		endif
			endm

;===============================================================================
; input handlers
;		handle the initial link from the RST/NMI/direct setup call
;		manage the context and pass it to the debugger
;===============================================================================

; We face two 'register on stack' situations
;
; Local: where the SP can be trusted because we didn't change any pages but
; all that is on the stack is the return address for the RST/NMI
;
; Remote: where it can't be used as it probably will be in RAM3 and it
; contains the return address of the RST/NMI, HL, AF and BC

nmiLocal	push	hl, af, bc			; match the stack of the remote

; unset NMI trap hardware
			ld		a, 0x01
			out		(MPGEN), a

; record the return details
			ld		b, BIOSRAM			; not mapped
			ld		c, 1				; NMI style

; unset the NMI internal states and jp debugger
			ld		hl, debugger
			push	hl
			retn

rstLocal	push	hl, af, bc
			ld		b, BIOSRAM			; not mapped
			ld		c, 2				; RST style
			jr		debugger

; these are via the mapper and already have PC, HL, AF and BC on the stack
nmiRemote

; unset NMI trap hardware
			ld		a, 1
			out		(MPGEN), a

; record the return details
			ld		c, 1				; NMI style

; unwind the NMI internal states and jp debugger
			ld		hl, debugger
			push	hl
			retn

rstRemote	ld		c, 2				; RST style
			jr		debugger

; this is the direct call from the DBG command
debugSetup	push	hl, af, bc
			ld		b, BIOSRAM
			ld		c, 0
			jr		debugger

;===============================================================================
; debugger:	the service
; The big problem here is the stack. This could well be in PAGE3 and have been
; swapped out so we need to use our local stack before we call anything but we
; need to save the SP.
; NOTICE: at this point I have not updated the savePage[] array so it still
; points to the old PAGE3 although this is passed in B
;===============================================================================

	struct REGSAVE
HL			dw		0	; the first 4 are in the same order as the client stack
BC			dw		0	;
AF			dw		0	;
PC16		dw		0	;
SP16		dw		0
DE			dw		0
AFd			dw		0
BCd			dw		0
DEd			dw		0
HLd			dw		0
IX			dw		0
IY			dw		0
PAGES		dd		0
RET			db		0
MODE		db		0
PC20		d24		0
SP20		d24		0
	ends
regs		REGSAVE

; the system pushed PC, HL, AF, BC before remapping
; so start by saving the context

debugger	ld		a, b					; return RAM page
			ld		[regs.RET], a			; RET (RAMn)
			ld		a, c					; 0=setup, 1=NMI, 2=RST
			ld		[regs.MODE], a			; MODE (setup, 1=NMI, 2=RST)
			ld		[regs.SP16], sp			; SP (save addr16)

; localise the stack
			ld		sp, DebuggerStack		; get a safe stack

; we need the savePages array to interpret the addr16 values
			ld		hl, [Z.savePage]
			ld		[regs.PAGES], hl		; PAGES
			ld		hl, [Z.savePage+2]
			ld		[regs.PAGES+2], hl

; now correct the page we are in so the banked copy will work
			ld		a, BIOSRAM
			ld		[Z.savePage+3], a

; now do the simple registers
			ld		[regs.DE], de			; DE
			ld		[regs.IX], ix			; IX
			ld		[regs.IY], iy			; IY
			exx
			ld		[regs.BCd], bc			; BCd
			ld		[regs.DEd], de			; DEd
			ld		[regs.HLd], hl			; HLd
			exx
			ex		af, af'
			push	af
			ex		af, af'
			pop		hl
			ld		[regs.AFd], hl			; AFd

; PC16, AF, BC and HL are on the old stack which may be mapped out
; use the bank_ldir routine in map.asm
			ld		hl, regs.HL & 0x3fff	; destination for copy
			ld		c, BIOSRAM ^ 0x20		; addr24 in C:HL
			call	c24to20
			push	hl
			ld		b, c					; into B:(pushed)

			ld		hl, [regs.SP16]			; addr16
			ld		de, regs.PAGES
			call	c16to20					; to addr20 in C:HL
			put24	regs.SP20, c, hl		; save in regs

			pop		de						; gives destination in B:DE
			ld		ix, 8					; count is 4 words
			call	bank_ldir				; copy addr21 C:HL to addr21 B:DE
											; for IX counts

; update the addr20 values for PC
			ld		hl, [regs.PC16]
			ld		de, regs.PAGES
			call	c16to20
			put24	regs.PC20, c, hl

			jp		debuggerUI				; now go and run the UI

;===============================================================================
; When the debugger is sent back to the code we need to restore the registers
; which were open to editing then either jump or exit via the page switch
;===============================================================================

ssFlag		db		0

singleStepExit
			ld		a, 1
			jr		debuggerExit.de1
debuggerExit
			xor		a
.de1		ld		[ssFlag], a

; convert PC and SP back to addr16 in case they were edited
; return on not in map
 if 0
			get24	regs.SP20, c, hl
			call	c20to24
			push	iy
			CALLF	_c24to16
			pop		iy
			ret		nc
			ld		[regs.SP16], hl

			get24	regs.PC20, c, hl
			call	c20to24
			push	iy
			CALLF	_c24to16
			pop		iy
			ret		nc
			ld		[regs.PC16], hl
 endif

; that leaves HL, BC, AF, PC and SP
; copy HL,BC,AF, PC to the old stack
			ld		hl, regs.HL & 0x3fff	; source for copy
			ld		c, BIOSRAM ^ 0x20
			call	c24to20

			get24	regs.SP20, b, de		; destination is B:DE
			ld		ix, 8					; count is ix
			call	bank_ldir				; copy addr21 C:HL to addr21 B:DE
											; for IX counts

; restore the straight forward items
			ld		de, [regs.DE]			; DE
			ld		ix, [regs.IX]			; IX
			ld		iy, [regs.IY]			; IY
			exx
			ld		bc, [regs.BCd]			; BCd
			ld		de, [regs.DEd]			; DEd
			ld		hl, [regs.HLd]			; HLd
			exx
			ld		hl, [regs.AFd]			; AFd
			push	hl
			ex		af, af'
			pop		af
			ex		af, af'
			ld		sp, [regs.SP16]

; now restore the savePage values (must be after the call to bank_ldir)
			ld		hl, [regs.PAGES]
			ld		[Z.savePage], hl
			ld		hl, [regs.PAGES+2]
			ld		[Z.savePage+2], hl

; there are 4 ways out, local/remote normal/single-step
			ld		a, [ssFlag]
			or		a
			jr		nz, .de3			; single step

; Normal
			ld		a, [regs.RET]
			cp		BIOSRAM
			jr		nz, .de2

; Normal Local return
			pop		bc, af, hl
			ret

; Normal Remote return
.de2		ld		a, [regs.RET]
			jp		rstExit			; switch, POP BC AF HL RET

; Single Step
.de3		ld		a, [regs.RET]
			cp		BIOSRAM
			jr		nz, .de4

; Single Step Local return
			pop		bc
			ld		a, magic_set
			out		(magic_port), a
			pop		af, hl
			ret

; Single Step Remote return
.de4		ld		a, [regs.RET]
			jp		nmiExit			; switch, POP BC, trigger SS, POP AF HL RET

;===============================================================================
; debugger tools and utilities
;===============================================================================

; select the RST to use 0x08, 0x10, 0x18... 0x38
useRST		equ		0x28

; prefixes for messages sent to the PC
SIGNON_CMD	equ		'*'				; first char of a break
OK_CMD		equ		'@'				; instruction carried out
BAD_CMD		equ		'?'				; instruction failed

; convert the RST selection into the appropriate  OP code
rstCODE		equ		useRST | 0xc7	; the RST instruction

; where we store our trap information
			struct	TRAP
pc			dw		0		; 16 bit address
page		db		0		; RAM number
code		db		0		; the byte we replaced
			ends

NTRAPS		equ		10
VERSION		equ		1		; mark breaking changes
traps
	dup	NTRAPS
			TRAP
	edup

; used to restore the RSTxx/NMI jump vectors when we exit
oldRST		db		0,0,0
oldNMI		db		0,0,0

; man readable stuff that can be easily turned on and off
CRLF		macro
  if MAN_READABLE
			call	sCRLF
  endif
			endm
SPACE		macro
  if MAN_READABLE
			call	sSPACE
  endif
			endm

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
			ld		b, 4				; test 4 slots
			ld		d, 0				; count if found
			ld		a, c				; get requested RAMn
			xor		0x20				; toggle ROM/RAM to hardware style
.st1		cp		[hl]				; what is in what page?
			jr		z, .st2				; we have a match
			inc		hl
			inc		d
			djnz	.st1

; if we get here the RAM we want is not mapped in so we put it in PAGE1
			ld		a, [Z.savePage+1]
			ld		[.saveRAM], a		; page we need to restore (hardware mode)
			ld		a, c
			xor		0x20				; to hardware mode
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
;
;  unsetTrap	put back the user code soi we can continue
;  resetTrap	reset an existing trap
;  freeTrap		clear the trap so the slot is free
;				call with IX to trap structure
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

unsetTrap	push	de, hl
			ld		c, [ix+TRAP.page]
			call	getRAM				; returns HL as pointer to base of page
			ld		l, [ix+TRAP.pc]		; HL only has top two bits set
			ld		a, [ix+TRAP.pc+1]
			and		0x3f
			or		h
			ld		h, a				; gives us a mapped HL
			ld		a, [ix+TRAP.code]	; get users code
			ld		[hl], a				; replace so we can continue
			call	restoreRAM
			pop		hl, de
			ret

resetTrap	push	de, hl
			ld		c, [ix+TRAP.page]
			call	getRAM
			ld		l, [ix+TRAP.pc]
			ld		a, [ix+TRAP.pc+1]
			and		0x3f
			or		h
			ld		h, a				; gives us a mapped HL
			ld		[hl], rstCODE
			call	restoreRAM
			pop		hl, de
			ret

freeTrap	call	unsetTrap
			xor		a
			ld		[ix+TRAP.page], a	; mark the slot as free
			ld		[ix+TRAP.pc+1], a
			ret

;===============================================================================
; debugger	wait for and execute debugger commands
; NB: I have put a lot of 'man readable' stuff in for testing both ways so
; whitespace should just be ignored
;===============================================================================

commandList	db		'i'				; get information
			dw		cmd_info
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
			dw		db_bad_end
			db		0				; end of list

debuggerUI
			ld		a, [regs.MODE]
			or		a				; 0 = setup
			jr		z, .db3			; so skip the trap check
			cp		1
			jr		z, .db3			; 1 = NMI

; mode==2
; firstly inspect the PC to see if it was a trap
; The debugger passed us the addr16 and the PAGEn
; so get the PAGEn from the PC20 and mask address16 to address14
			get24	regs.PC20, c, hl
			call	c20to24			; gives us RAMn in C
			ld		hl, [regs.PC16]	; and addr16 in HL
			dec		hl				; back to trap address
			ld		a, h
			and		0x3f			; 14 bit address
			ld		h, a
			ld		ix, traps
			ld		b, NTRAPS
			ld		de, TRAP
.db1		ld		a, [ix+TRAP.page]
			cp		c
			jr		nz, .db2
			ld		a, [ix+TRAP.pc]
			cp		l
			jr		nz, .db2
			ld		a, [ix+TRAP.pc+1]
			and		0x3f			; 14 bit address
			cp		h
			jr		z, .db4
.db2		add		ix, de
			djnz	.db1

; no match so it isn't a trap just an RST
			ld		a, 2			; compiled in RST
.db3		push	af
			jr		.db5

; found  a trap
.db4		ld		a, NTRAPS+3
			sub		b				; gives trap number + 3
			push	af				; save slot number

; remove the trap and back up the PC for the continue
			call	unsetTrap
			ld		hl, [regs.PC16]
			dec		hl
			ld		[regs.PC16], hl
			ld		de, regs.PAGES	; update PC20
			call	c16to20
			put24	regs.PC20, c, hl


.db5		call	sendSignOn		; switch terminal to debugger mode
			ld		a, SIGNON_CMD
			call	db_putc
			pop		af
			call	packB			; 0 for set up, 1=NMI, 2=compiled in RST
									; 3-(NTRAPS+2) a trap

; Start of command loop:
; commands (no command can be hex or we could get in a total mess)
.db6		CRLF
			ld		a, OK_CMD
			call	db_putc

.db7		call	db_getc			; db_getc ignores white space but does do echo
			call	ishex			; ignore hex if data is streaming
			jr		c, .db7

			ld		c, a			; hold the command in C
			ld		hl, commandList
.db8		ld		a, c
			cp		[hl]			; test against the list
			jr		z, .db9			; we have a match
			inc		hl
			inc		hl
			inc		hl
			ld		a, [hl]
			or		a
			jr		nz, .db8
			jr		db_bad_end

; found
.db9		inc		hl				; step over the command char
			ld		a, [hl]			; load the address
			inc		hl
			ld		h, [hl]
			ld		l, a
			jp		[hl]

; and the two usual returns
db_good_end	ld		a, OK_CMD
.ge1		call	db_putc
			jr		debuggerUI.db6

db_some_end	jr		c, db_good_end
db_bad_end	ld		a, BAD_CMD
			jr		db_good_end.ge1

;===============================================================================
;	command handlers
;	either end by jumping to db_good_end or db_bad_end
;	or if they are CY/NC for bad/good db_some_end
;===============================================================================

;-------------------------------------------------------------------------------
; 'i' COMMAND: get info
cmd_info
			ld		a, VERSION
			call	packB
			ld		a, NTRAPS
			call	packB
			jr		db_good_end

;-------------------------------------------------------------------------------
; '+s slot page address' COMMAND: set a trap
cmd_trap
			call	unpackB			; slot in A
			jr		nc, db_bad_end	; not hex
			call	getSlot			; point IX to the slot
			jr		nc, db_bad_end	; no such slot

			call	unpackB			; get the page in A
			jr		nc, db_bad_end
			ld		c, a
			call	unpackW			; address in HL
			jr		nc, db_bad_end

			call	setTrap			; needs IX=slot, C=page, HL=address
			jr		db_some_end		; report errors

;-------------------------------------------------------------------------------
; '-s slot' COMMAND: remove a trap and free the slot
cmd_untrap
			call	unpackB
			jr		nc, db_bad_end
			call	getSlot
			jr		nc, db_bad_end

			call	freeTrap		; requires IX
			jr		db_good_end

;-------------------------------------------------------------------------------
; 'r' COMMAND: send registers
cmd_getregs
			ld		hl, regs		; point to REGSAVE regs
			ld		b, REGSAVE/2	; size in WORDS
.cr1		SPACE
			ld		e, [hl]
			inc		hl
			ld		d, [hl]
			inc		hl
			ex		de, hl
			call	packW
			ex		de, hl
			djnz	.cr1
			jp		db_good_end

;-------------------------------------------------------------------------------
; 't' COMMAND set registers
cmd_setregs
			ld		hl, regs		; point to REGSAVE regs
			ld		b, REGSAVE/2	; size in WORDS
.sr1		ex		de, hl
			call	unpackW			; unpack into A
			ex		de, hl
			ld		[hl], e
			inc		hl
			ld		[hl], d
			inc		hl
			djnz	.sr1
			jp		db_good_end

;-------------------------------------------------------------------------------
; g address20 count8 COMMAND: get memory
cmd_get
			call	unpackN			; 4 bits
			jp		nc, db_bad_end
			ld		c, a
			call	unpackW			; address in HL
			jp		nc, db_bad_end
			call	unpackB			; count is A
			jp		nc, db_bad_end
			ld		b, a			; count
			SPACE

; now get the RAM page
			push	hl
			rl		h				; get the page in C
			rl		c
			rl		h
			rl		c				; C is page (not hardware mode)
			call	getRAM			; RAMn in C, returns HL base of the ram
			pop		de				; pop the old address16
			ld		a, d			; convert to address14
			and		0x3f
			ld		d, a
			add		hl, de			; add offset to page
.cg1		ld		a, [hl]
			call	packB
			inc		hl
			djnz	.cg1

			call	restoreRAM		; put the memory back as was
			jp		db_good_end

;-------------------------------------------------------------------------------
; p address20 count8 dddd.. COMMAND: put memory
cmd_put
			jp		db_bad_end

;-------------------------------------------------------------------------------
; k COMMAND continue
cmd_continue
			ld		a, OK_CMD
			call	db_putc
			call	sendSignOff
			jp		debuggerExit

;-------------------------------------------------------------------------------
; 'x address' execute from an address
cmd_exec
			call	unpackW
			jp		nc, db_bad_end
;			ld		[iy+REGS.PC], hl
			jr		cmd_continue

;-------------------------------------------------------------------------------
; 's' single step command
cms_step
			ld		a, OK_CMD
			call	db_putc
			call	sendSignOff
			jp		singleStepExit

;-------------------------------------------------------------------------------
; 'z' close down command
cmd_close
			ld		a, OK_CMD
			call	db_putc
			call	sendSignOff
			jp		good_end

;===============================================================================
; utilities
;===============================================================================

sCRLF		push	af
			ld		a, 0x0d
			call	db_putc
			ld		a, 0x0a
			call	db_putc
			pop		af
			ret

sSPACE		push	af
			ld		a, 0x20
			call	db_putc
			pop		af
			ret

text		ld		a, [hl]
			or		a
			ret		z
			call	db_putc
			inc		hl
			jr		text


sendSignOn	ld		hl, .signon
			jr		text
.signon		db		0x1b, "[1?",0

sendSignOff	ld		hl, .signoff
			jr		text
.signoff	db		0x1b, "[0?", 0

; db_getc with skip white
db_getc		call	serial_read
			cp		' '
			jr		z, db_getc
			cp		0x0d
			jr		z, db_getc
			cp		0x0a
			jr		z, db_getc
			ret
db_putc		jp		serial_sendW	; send with wait on full

; HEX HANDLERS : Man readable so MS first !!!!!!!!!!!!!!!!!!!!!!

; unpack nibble return CY on OK
unpackN		call	db_getc
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
			call	db_putc
			pop		af
			ret
; the local stack in PAGE3
			ds		200
DebuggerStack

 endif
 if SHOW_MODULE
	 	DISPLAY "debug size: ", /D, $-startDebug
 endif
