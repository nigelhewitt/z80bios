;===============================================================================
;
;	router.asm		code to manage calling functions is other ROMs
;
;===============================================================================

;-------------------------------------------------------------------------------
; wedgeROM	call a function in ROMn from ROM0
;			(Actually ROM1 is in RAM4 and ROM2 is in RAM5)
;			put the parameters on the registers as the function writeup
;			call this via the MACRO callBIOS
;
; 			The 'function' mak consider itself a task and exit via a jp to
;			good_end or bad_end or a function and return.
;			I pass all the registers and flags in and out intact.
;			If you want the callers stack use
;				LD IX, [Z.cr_sp] and IX pointes to the return address
;-------------------------------------------------------------------------------
;
; The actual page change is executed by the
; gotoRAM3/4/5 function in stepper.asm
;	these functions use A and then jump to the address 'bios'
;

	if BIOSROM == 0			// we only need this part in ROM0 (or RAM3)

; This function is called by the macro CALLBIOS
; The macro has saved A ->[Z.cr_a] ROM to [Z.cr_rom] and FN to [Z.cr_fn]

; I started pricing up the call to another ROM and it is
;	outbound
;		70T in the macro
;		113T in wedgeROM
;		28T in stepper
;		?? in remote bios
;	return
;		72T good_end
;		28T in stepper
;		96T in local bios
;-------------------------------------------------------------------------------
; transfer to the other ROM
;-------------------------------------------------------------------------------

; place data in PAGE0 slots for the transfer
wedgeROM	push	hl					; 11T
			di							; 4T
			ld		hl, 2				; 10T miss push hl so it points to ret
			add		hl, sp				; 11T
			ld		[Z.cr_sp], hl		; 20T
			pop		hl					; 10T
			ld		a, [Z.cr_rom]		; 13T
			cp		RAM4				; 7T
			jp		z, gotoRAM4			; 10T
			cp		RAM5				; 7T
			jp		z, gotoRAM5			; 10T

			ld		hl, ERR_BADFUNCTION
			ld		[Z.last_error], hl
			ei
			jp		bad_end

;-------------------------------------------------------------------------------
; handle the return from other ROM
;-------------------------------------------------------------------------------

bios		ld		sp, [Z.cr_sp]		; 20T
			push	hl					; 11T
			ld		hl, [Z.cr_a]		; 20T
			push	hl					; 11T
			pop		af					; 10T
			pop		hl					; 10T
			ei							; 4T
			ret							; 10T
	endif

;-------------------------------------------------------------------------------
; function router
;-------------------------------------------------------------------------------

	if BIOSROM != 0		; only in extra ROMs

; We arrive on a temporary stack with 2 words one of which is our return address
; Fortunately we know the SP is now Z.cr_stack-2 so we can restore it
;
; words: Z.cr_sp, Z.cr_stack and byte: Z.cr_ret
; and our working values
; bytes: Z.cr_fn, Z.cr_a

; NB: if you need stuff off the caller's stack remember we can
;		ld	ix, [Z.cr_sp] and [ix+0] is the return address etc.

bios		ld		sp, local_stack		; a stack that will work

			ld		[saveHL], hl		; put a return address on the stack
			ld		hl, return
			push	hl					; 11T
			ld		hl, [saveHL]

			push	hl, bc				; 11T + 11T
			ld		a, [Z.cr_fn]		; function number
			cp		bios_count			; number of functions
			jr		nc, .bi1
			ld		hl, bios_functions
			ld		b, 0				; function number in BC
			ld		c, a				; then double it to word pointer
			sla		c					; 0->b0, b7->cy
			rl		b					; through carry
			add		hl, bc
			ld		a, [hl]				; ld  hl, (hl)
			inc		hl
			ld		h, [hl]
			ld		l, a				; funtion address in HL
			pop		bc					; 10T restore BC
			ld		a, [Z.cr_a]
			ex		[sp], hl			; restore HL, put 'goto' address on SP
			ei
			ret							; 10T aka POP PC
			; this leaves us a return address to return on the stack
			; so a function can either jp to good/bad end to set/clear carry
			; or return to preserve its flags

.bi1		ld		hl, ERR_BADFUNCTION	; bad function number
			ld		[Z.last_error], hl
			pop		bc, hl
			ld		a, [Z.cr_a]
			jr		bad_end

; exit paths from handlers
; a little slight of hand to return the flags in case they are needed
; since we promise to return everything intact we cannot signal bad_end
; the function must do that itself.
good_end	scf							; set carry
			jr		return

bad_end		or		a					; clear carry

return		di							; 4T
			push	hl, af				; 11T + 11T
			pop		hl					; 10T actually AF
			ld		[Z.cr_a], hl		; 20T uses cr_rom as well
			pop		hl					; 10T
			jp		gotoRAM3			; 10T

; Local Stack
			ds		100
local_stack
saveHL		dw		0
	endif
