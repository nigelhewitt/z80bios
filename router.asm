;===============================================================================
;
;	bios1		code to go in the ROM1 page that can be called
;
;===============================================================================

;-------------------------------------------------------------------------------
; function router
;-------------------------------------------------------------------------------

; We arrive on a temporary stack with 2 words one of which is our return address
; Fortunately we know the SP is now Z.cr_stack-2 so we can restore it
;
; words: Z.cr_sp, Z.cr_stack and byte: Z.cr_ret
; and our working values
; bytes: Z.cr_fn, Z.cr_a

bios		ld		sp, local_stack		; re-entrancy problem here
			push	hl, bc
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
			ld		l, a
			pop		bc					; restore BC
			ld		a, [Z.cr_a]
			ex		[sp], hl			; restore HL, put 'goto' address on SP
			ret							; aka POP PC
.bi1		pop		bc, hl
			ld		a, [Z.cr_a]
			jr		bad_end

; exit paths from handlers
good_end	scf
			jp		wedgeOut

bad_end		or		a					; clear carry
			jp		wedgeOut

; return from a wedged function

wedgeOut
; copy the interface wedge into PAGE0
			ld		[Z.cr_a], a
			push	af, bc, de, hl
			ld		de, Z.bios_wedge	; destination
			ld		hl, .returningWedge	; source
			ld		bc, size_wedgeR		; count
			ldir
			pop		hl, de, bc, af
			jp		Z.bios_wedge

; the returning wedge
.returningWedge
			ld		a, [Z.cr_ret]
			out		(MPGSEL3), a		; set which ROM in page3
			ld		a, [Z.cr_a]
			ld		sp, Z.cr_stack-2
			ret
size_wedgeR	equ		$-.returningWedge


; Local Stack
			ds		100
local_stack

