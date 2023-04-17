;===============================================================================
;
;	router.asm		code to manage calling functions is other ROMs
;
;===============================================================================
router_start	equ	$

;-------------------------------------------------------------------------------
; wedgeROM	call a function in ROMn from ROM0
;			(Actually ROM1 is in RAM4 and ROM2 is in RAM5)
;			put the parameters on the registers as the function writeup
;			call this via the MACRO callBIOS
;
; 			The 'function' may consider itself a task and exit via a jp to
;			good_end or bad_end or a function and return.
;			I pass all the registers and flags in and out intact.
;			If you want the callers stack use
;				LD IX, [Z.cr_sp] and IX pointes to the return address
;-------------------------------------------------------------------------------
;
; The actual page change is executed by the
; gotoRAM3/4/5 function in stepper.asm
;	these functions use A and then jump to the address 'bios'

; This function is called by the macro CALLFAR
; The macro has saved ROM to [Z.cr_rom] and FN to [Z.cr_fn]

; I started pricing up the call to another ROM and it is
;	outbound
;		68T in the macro
;		113T in wedgeROM
;		28T in stepper
;		?? in remote bios
;	return
;		72T good_end
;		28T in stepper
;		96T in local bios
;-------------------------------------------------------------------------------
; transfer to the other ROM/RAM
;-------------------------------------------------------------------------------

; CALLFAR has placed data in PAGE0 slots for the transfer
; the macro has put:
;	ROM	-> Z.cr_rom
;	FN	-> Z.cr_fn

wedgeROM	di							; 4T
			push	hl					; 11T

; save AF to pass on
			push	af					; 11T
			pop		hl					; 10T
			ld		[Z.cr_af], hl		; 13T save AF

; save SP for return
			ld		hl, 2				; 10T miss push hl so it points to ret
			add		hl, sp				; 11T
			ld		[Z.cr_sp], hl		; 20T
			pop		hl					; 10T

; set up return RAM
			ld		a, BIOSRAM			; 7T  RAM to return too
			ld		[Z.cr_ret], a		; 13T

; jump to the requested RAM
			ld		a, [Z.cr_ram]		; 13T target
			cp		RAM3				; 7T
			jp		z, gotoRAM3			; 10T
			cp		RAM4				; 7T
			jp		z, gotoRAM4			; 10T
			cp		RAM5				; 7T
			jp		z, gotoRAM5			; 10T

; if we get here it failed on RAM selection
			ld		hl, ERR_BADFUNCTION
			ld		[Z.last_error], hl
			ei
			jp		bad_end

;-------------------------------------------------------------------------------
; handle the return from other ROM
;-------------------------------------------------------------------------------

transfer	ld		a, [Z.cr_ret]		; 0xff for a return
			cp		0xff
			jr		nz, doCall			; a call

; manage a return
			ld		sp, [Z.cr_sp]		; 20T	as we saved above
			push	hl					; 11T
			ld		hl, [Z.cr_af]		; 20T	AF saved by target
			push	hl					; 11T
			ld		a, BIOSROM
			ld		[Z.savePage+3], a
			pop		af					; 10T
			pop		hl					; 10T
			ei							; 4T
			ret							; 10T

;-------------------------------------------------------------------------------
; function router
;-------------------------------------------------------------------------------

; receives data in Z.cr_fn, Z.cr_af, Z.cr_sp and Z.cr_ret
; return to RAM cr_ret conserving cr_sp,

doCall		ld		sp, local_stack		; a stack that will work
			ld		a, BIOSRAM
			ld		[Z.savePage+3], a

; build a return handler
			ld		[.saveHL], hl		; save HL while we put stuff on stack
			ld		hl, [Z.cr_sp]		; save the return SP
			push	hl
 			ld		hl, [Z.cr_ret]		; return RAM in LSbyte
			push	hl

; at this point SP = local_stack-4
			ld		hl, return			; return address
			push	hl					; 11T doing a ret now jumps to return
			ld		hl, [.saveHL]		; restore callers HL

; now process the FN
			push	hl, bc				; 11T + 11T
			ld		a, [Z.cr_fn]		; function number
			cp		bios_count			; number of functions
			jr		nc, .bi1			; bad function
			ld		hl, bios_functions
			ld		b, 0				; function number in BC
			ld		c, a				; then double it to word pointer
			sla		c					; 0->b0, b7->cy
			rl		b					; through carry
			add		hl, bc
			ld		a, [hl]				; ld  hl, (hl)
			inc		hl
			ld		h, [hl]
			ld		l, a				; function address in HL
			ld		bc, [Z.cr_af]		; restore the callers A
			push	bc
			pop		af
			pop		bc					; 10T restore BC
			ex		[sp], hl			; restore HL, put 'goto' address on SP
			ei
			ret							; 10T aka POP PC
.saveHL		dw		0

			; this leaves us a return address to return on the stack
			; so a function can either jp to good/bad end to set/clear carry
			; or return to preserve its flags

; bad function number
.bi1		ld		hl, ERR_BADFUNCTION	; bad function number
			ld		[Z.last_error], hl
			pop		bc, hl
			ld		a, [Z.cr_af]
			jp		bad_end

; exit paths from handlers
; a little slight of hand to return the flags in case they are needed
; since we promise to return everything intact we cannot signal bad_end
; the function must do that itself.

  if BIOSRAM != RAM3
good_end	scf							; set carry
			jr		return
bad_end		or		a					; clear carry
  endif

return		di							; 4T
			ld		sp, local_stack-4	; brutalise the stack
			push	hl, af				; 11T + 11T
			pop		hl					; 10T actually AF
			ld		[Z.cr_af], hl		; 20T
			pop		hl					; 10T
			ld		[.saveHL], hl		; save HL while we get stuff off the stack
; restore the stuff we saved
			pop		hl
			ld		a, 0xff				; flag this as a return
			ld		[Z.cr_ret], a
			ld		a, l				; return ROM
			pop		hl					; the caller's stack
			ld		sp, hl
			ld		hl, [.saveHL]
			cp		RAM3				; 7T
			jp		z, gotoRAM3			; 10T
			cp		RAM4				; 7T
			jp		z, gotoRAM4			; 10T
			cp		RAM5				; 7T
			jp		z, gotoRAM5			; 10T
; crash and burn
			halt		; improved handler later

.saveHL		dw		0

; Local Stack
local_stack_bottom
			ds		200
local_stack

 if SHOW_MODULE
	 	DISPLAY "router size: ", /D, $-router_start
 endif
