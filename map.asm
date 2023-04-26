;===============================================================================
;
;	Memory addressing
;
;===============================================================================
map_start		equ	$

; see the discussion of address16, address20 and address24 in bios.asm:76

;===============================================================================

;===============================================================================
; Memory page addressing translations
;===============================================================================

; Do the easy ones first

; c20to24		convert a address20 into an address24
;				(page8 and address14)
;				call with addr20 in C:HL and get the results in C:HL
;				uses nothing
c20to24		rl		h
			rl		c
			rl		h
			rl		c
			srl		h
			srl		h
			ret

; c24to20		convert a page8:address14 into an address20
;				in/out via C:HL
;				uses nothing
c24to20		rl		h
			rl		h
			srl		c
			rr		h
			srl		c
			rr		h
			ret

; c16to24		convert an address16 into an address20 using a mapping table
;				call with address16 in HL and DE as address16 pointing to
;				mapping table (normally DE = Z.savePage)
;				results in C:HL
;				uses A
c16to24		push	de
			xor		a			; get b14-15 of HL in A b0-1
			rl		h
			rla
			rl		h
			rla
			srl		h			; put HL back straight clearing b14-15
			srl		h
			add		e			; add A to DE
			ld		e, a
			ld		a, d
			adc		0
			ld		d, a
			ld		a, [de]		; get page
			xor		0x20		; toggle the RAM/ROM bit
			ld		c, a
			pop		de
			ret

; composites using the previous code

; convert c21toc20 (resolve bit 20)
;			needs DE as map table
c21to20		bit		4,c
			ret		z			; easy
			; from this point we ignore C so it devolves to c16to20
			; fall through

; if you want c16to20 on C:HL
;			needs DE as map table
c16to20		call	c16to24
			jr		c24to20

;===============================================================================
; Now the hard one. Convert an address24 to an address16 that will work in [HL]
;
; It's all nice and straightforward until you ask
;		"WHERE ARE WE EXECUTING AND WHERE IS THE STACK?"
; OK so this code is compiled to go in PAGE3
;
;					******  HUGE WARNING  ******
; If you want N bytes and you convert the first address to 24 you get
; a 14 bit HL back. Add N to HL and if it overflows 14 bits you need to do your
; transfer in two parts before and after the page switch
; consider using the extended LDIR below
;-------------------------------------------------------------------------------

; 'stackfree' call and return
; I use _ as a prefix for stackfree calls just to remind me they are different
; and then I use macros to make them feel normal

CALLF		macro		target
			ld			iy, .ret
			jp			target
.ret
			endm
RETF		macro
			jp			(iy)
			endm

;-------------------------------------------------------------------------------
; First a worker: Try to map an address24 to the current pages
; It needs to be stack free as _c24to16 calls can be nested (eg: bank_ldir)
; call with requested addr24 in C:HL, pagemap[] in DE
; returns CY on success with HL as addr16
; uses A, B and DE
;-------------------------------------------------------------------------------

_c24to16W	ld		a, c				; requested page
			xor		0x20				; swap ROM/RAM bit to hardware mode
			ex		de, hl				; table in HL, addr in DE

			ld		b, 4				; test all 4 slots
.c1			cp		a, [hl]
			jr		z, .c2
			inc		hl
			djnz	.c1

; not found
			ex		de, hl				; retore addr in DL
			or		a					; clear carry
			RETF

; found it so no need to map anything
; it is in PAGE(4-B)
.c2			ld		a, 4
			sub		b					; page
			ex		de, hl				; get addr14 back
			rl		h
			rl		h
			rr		a
			rr		h
			rr		a
			rr		h
			ld		bc, 0				; nothing to do to fix
			scf
			RETF

;-------------------------------------------------------------------------------
; _c24to16	C:HL is address24, DE = current mappings
;			A as page to map to if we map (0-3 but we're executing in 3 so 0-2)
;			returns HL as address16
;					BC data to reset this mapping (see _c24to16fix)
;			uses A and IY for the return
;-------------------------------------------------------------------------------
_c24to16	; first look up the page in map [DE] to see if we already have it

			and		3					; mask page request to be safe
			ld		[.page], a			; suggested page
			ld		[.map], de

			ld		[.IY], iy
			CALLF	_c24to16W			; try for a local page, uses A, B and DE
			ld		iy, [.IY]
			jr		nc, .c1				; not found
			RETF

; not found so we have to map it
; get the previous value for the restore
.c1			ld		de, [.map]
			ld		a, [.page]
			add		e
			ld		e, a
			ld		a, d
			adc		0
			ld		d, a
			ld		a, [de]				; get previous page in hardware mode
			ld		b, a				; save for the restore

			ld		a, c				; required page
			xor		0x20				; make hardware mode
			ld		d, a				; save page

			ld		a, [.page]
			add		a, MPGSEL			; gives page select port
			ld		c, a

			ld		a, d				; page to switch too
			out		(c), a				; C = mapping port

			rl		h
			rl		h
			ld		a, [.page]
			rra
			rr		h
			rra
			rr		h
			ld		de, [.map]
			RETF

.page		db		0
.map		dw		0
.IY			dw		0

; unmap the change made by c24to16
;			call with BC the data returned by c24to16
_c24to16fix	ld		a, c				; port is zero for nothing to do
			or		a
			jr		z, .c3
			ld		a, b
			out		(c), a
.c3			RETF

;-------------------------------------------------------------------------------
; getPageByte	get the byte from address21 C:HL in A
;				It works the stack free trick so it can get from anywhere
;-------------------------------------------------------------------------------
getPageByte	push	bc, de, hl, iy
			ld		de, Z.savePage
			call	c21to20				; resolve addr21 to addr20
			call	c20to24				; break out the page number
			CALLF	_c24to16
			ld		a, [hl]
			ld		[.save], a
			CALLF	_c24to16fix
			ld		a, [.save]
			pop		iy, hl, de, bc
			ret
.save		db		0

;-------------------------------------------------------------------------------
; putPageByte	set a byte in address21 C:HL with A.
;				Again it works the stack free trick
;-------------------------------------------------------------------------------
putPageByte	push	bc, de, hl, iy
			ld		[.save], a
			ld		de, Z.savePage
			call	c21to20				; resolve addr21 to addr20
			call	c20to24				; break out the page number
			CALLF	_c24to16
			ld		a, [.save]
			ld		[hl], a
			CALLF	_c24to16fix
			ld		a, [.save]
			pop		iy, hl, de, bc
			ret
.save		db		0

;-------------------------------------------------------------------------------
; incCHL20	increment address20 in C:HL
;			uses nothing
;-------------------------------------------------------------------------------

incCHL20	inc		l			; does not set CY
			ret		nz			; INC HL sets nothing!
			inc		h
			ret		nz
			inc		c
			ret

;-------------------------------------------------------------------------------
; addCHLDE	add DE to C:HL
;			uses A
;-------------------------------------------------------------------------------
addCHLDE	add		hl, de
			ld		a, c
			adc		0
			ld		c, a
			ret

;===============================================================================
;
;	Local memory	To allow things like the SD and FAT systems plenty of room
;					to play in I use RAM6 in PAGE2 as it's internal memory.
;					The routines to handle this are virtually trivial but do
;					need to 'play nicely' interface with the normal 'return
;					to base' code
;
;  NB: The absolute address20 for items in Local memory is
;		(RAM6^0x20)<<14 + (offset & 0x3fff)
;===============================================================================

; here is the pre-'play nicely' code
LocalON		push	af
			ld		a, RAM6
			out		(MPGSEL2), a
			ld		[Z.savePage+2], a
			pop		af
			ret
LocalOFF	push	af
			ld		a, RAM2
			out		(MPGSEL2), a
			ld		[Z.savePage+2], a
			pop		af
			ret

;===============================================================================
; banked memory LDIR	copy from addr21 C:HL to addr21 B:DE for IX counts
;						destination must be RAM, IX==0 results in 64K copy
;						works the 'stack free' trick
;						return CY = good
;						uses  A, BC, DE, HL
;
; You are free to read from and write to any memory address although if you
; overwrite your own executable code that's your problem. Here I only protect
; you from the stack getting switched in and out.
; You end up with memory restored to PAGE1=RAM1 and PAGE2=RAM2
; I will Disable Interrupts, if you want to EI after it returns BMG
;===============================================================================

; In theory a 16bit counter allows a 64K copy (IX==0) so there can be multiple
; discontinuities in both source and destination 16K pages. However it has to
; be done with sequential LDIR commands or it will take a week if we page map
; for each byte.
; Hence I write a piece of code to do 'the next contiguous slice' and then
; restarts itself to do the next slice until the count runs out
; As we use PAGE1 for the source and PAGE2 for the destination and we may be
; running in ROM1 there is a problem for variables so this ought to run in
; CPU registers


bank_ldir	di						; no interrupts while the stack is volatile
			push	iy

; convert C:HL addr21 to addr20 and save as .source20
			push	de
			ld		de, Z.savePage
			call	c21to20
			put24	.source20, c, hl
			pop		de

; convert B:DE addr21 to addr20 and save as .dest20
			ld		c, b
			ld		hl, de
			ld		de, Z.savePage
			call	c21to20
			put24	.dest20, c, hl

; save ix as .count16
			ld		[.count16], ix

; if source + count overflows 1024K return error (beyond actual memory)
			get24	.source20, c, hl
			ld		de, ix				; count
			call	addCHLDE			; C:HL += DE
			ld		a, c
			and		0xf0				; >=1024K top of memory
			jr		nz, .bl1			; bad end

; if dest + count overflows 512K return error (beyond RAM)
			get24	.dest20, c, hl		; dest in C:HL
			call	addCHLDE			; C:HL += DE
			ld		a, c
			and		0xf8				; >=512K top of RAM
			jr		z, .bl2

; do a bad exit
.bl1		pop		iy
			or		a					; clear carry = bad end
			ret

; start of loop
.bl2

; convert source20 to address24
			get24	.source20, c, hl	; source
			call	c20to24				; separate out the page in C
			put24	.source24, c, hl

; nS = 0x4000 - (source & 0x3fff); aka number of bytes left in source page
			ld		a, h				; mask to 14 bits
			and		0x3f
			ld		d, a				; into DE
			ld		e, l
			ld		hl, 0x4000
			sub		hl, de
			push	hl					; save nS

; convert dest to adress24
			get24	.dest20, c, hl		; dest
			call	c20to24				; separate out the page in C
			put24	.dest24, c, hl

; nD = 0x4000 - (dest & 0x3fff)
			ld		a, h				; mask to 14 bits
			and		0x3f
			ld		d, a				; into DE
			ld		e, l
			ld		hl, 0x4000
			sub		hl, de				; nD in HL
			ld		de, hl				; and DE

; n = min(nS and nD)
			pop		bc					; recover nS
			sub		hl, bc				; nD - nS
			jr		nc, .bl3			; jump if HL<=BC aka nS<nD
			ld		bc, de				; nS>nD so use nD in BC
.bl3
; n = min(n and count)
			ld		hl, [.count16]		; HL and DE are both count
			ld		de, hl
			sub		hl, bc
			jr		nc, .bl4			; jump if HL>BC aka count>n
			ld		bc, de				; count<n so use count
.bl4		ld		[.n], bc

; map destination as PAGE2
			get24	.dest24, c, hl		; get .dest24
			ld		a, 2				; page 2
			ld		de, Z.savePage
			CALLF	_c24to16			;
			ld		[.sBC], bc			; map recovery data
			ld		[.dest16], hl		; addr16 for the copy

; map source to PAGE1
			get24	.source24, c, hl	; get .source24
			ld		a, 1				; page 1
			ld		de, Z.savePage
			CALLF	_c24to16
			ld		[.dBC], bc			; map recovery data

; copy PAGE1 to PAGE2 for n
			ld		de, [.dest16]
			ld		bc, [.n]
			ldir

; unmap PAGE1 and PAGE2
			ld		bc, [.dBC]
			CALLF	_c24to16fix
			ld		bc, [.sBC]
			CALLF	_c24to16fix

; count -= n
			ld		bc, [.n]
			ld		hl, [.count16]
			sub		hl, bc
			ld		[.count16], hl

; if count==0 finish
			ld		a, h
			or		l
			jr		z, .bl5				; done, so clean up

; source += n
			get24	.source20, c, hl
			ld		de, [.n]
			call	addCHLDE			; C:HL += DE
			put24	.source20, c, hl

; dest += n;
			get24	.dest20, c, hl
			call	addCHLDE			; C:HL += DE
			put24	.dest20, c, hl

; jump to start of loop
			jp		.bl2

; return good
.bl5		pop		iy
			scf
			ret

; local variables
.source20		d24		0
.dest20			d24		0
.source24		d24		0
.dest24			d24		0
.sBC			dw		0
.dBC			dw		0
.dest16			dw		0
.count16		dw		0
.n				dw		0


;======================================================================================
;======================================================================================
;======================================================================================
;					OLD STUFF BEING PHASED OUT
;======================================================================================
;======================================================================================
;======================================================================================


;-------------------------------------------------------------------------------
; _setPage	a stack free convert from address20 in C:IX
;			to PAGEn n is in A(bits 0-1)
;			returns IX as a 16 bit address into Z80 address space (in PAGEn)
;			** Not callable: returns via a JP [IY] **
;			uses A HL BC IX IY
;-------------------------------------------------------------------------------
_setPage	bit		4, c			; bit 20
			jr		nz, .sp1		; don't map
			and		0x03			; PAGE number 0-3 aka b1-0, mask to be safe
			ld		l, a			; save PAGE number in L
			ld		a, c			; bits b23-16 of C:IX
			and		0x0f			; mask to b19-16 just to be safe
			ld		h, a			; save in H b3-0
			ld		a, ixh			; get the address bits b15-8
			rl		a				; slide address b15-14 into H b1-0
			rl		h				; via carry
			rl		a
			rl		h				; giving address bits b19-14 in H b5-0
			ld		a, h
			xor		0x20			; swap the ROM and RAM bit
			ld		h, a			; H = the value to write to MPGSELn
									; H = 00rxxxxx  r=ROM xxxxx 0-32 ROM/RAM
			ld		a, l			; get the PAGE number again
			add		a, MPGSEL0		; add the base page select register
			ld		c, a			; output port address
			out		(c), h			; swap the page in

			ld		a, ixh			; get address bits b15-8
			sla		a
			sla		a				; slide up two places (discarding top bits)
			cp		a				; clear carry
			rr		l				; slide b0 of L (page number) into carry
			rr		a				; and into A b7
			rr		l
			rr		a				; gives page number b1-0 in bits b7-6 of A
									; A = ppaaaaaa p=page, xxxxx address b13-8
			ld		ixh, a			; put IX back together
.sp1		jp		[iy]

;-------------------------------------------------------------------------------
; _resPage	stack free restore RAMn to PAGEn where A = page no 0 to 3
;			uses A BC and returns JP [IY]
;-------------------------------------------------------------------------------
_resPage	and		0x03			; mask
			ld		b, a			; save page number
			add		a, MPGSEL0
			ld		c, a			; gives port address
			ld		a, b
			add		a, RAM0			; page RAMn
			out		(c), a			; back into PAGEn
			jp		[iy]

;;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

;-------------------------------------------------------------------------------
; XgetPageByte	get a byte from address20 C:IX in A leaving everything unchanged.
;				It works the stack free trick so it can get from anywhere
;
;				If C==0xff use [IX] local memory
;-------------------------------------------------------------------------------
XgetPageByte	ld		a, c
			cp		0xff
			jr		nz, .gb1
			ld		a, [ix]
			ret

.gb1		push	hl, bc, iy, ix
			ld		a, 1			; via PAGE1
			ld		iy, .gb2		; return address
			jp		_setPage		; does not ret due to stack, jp [iy]
.gb2		ld		h, [IX]			; get the byte
			ld		a, 1			; PAGE1
			ld		iy, .gb3
			jr		_resPage
.gb3		ld		a, h			; result in A
			pop		ix, iy, bc, hl
			ret
;-------------------------------------------------------------------------------
; XputPageByte	set a byte in C:IX from A.
;				Again it works the stack free trick
;				if C==0xff use [IX] local memory
;-------------------------------------------------------------------------------
XputPageByte	push	de
			ld		d, a			; save the byte
			ld		a, c			; local page?
			cp		0xff
			jr		nz, .pb1		; no
			ld		a, d
			ld		[ix], a
			jr		.pb4

.pb1		push	hl, bc, iy, ix
			ld		a, 1			; via PAGE1
			ld		iy, .pb2
			jp		_setPage		; does not use DE
.pb2		ld		[IX], d			; get the byte
			ld		a, 1			; PAGE1
			ld		iy, .pb3
			jp		_resPage
.pb3		ld		a, d
			pop		ix, iy, bc, hl
.pb4		pop		de
			ret

;-------------------------------------------------------------------------------
; incCIX	increment address20 in C:IX safely if there is a danger of crossing
;			a page so just incrementing IX isn't safe
;			uses nothing
;-------------------------------------------------------------------------------
incCIX		push	de
			ld		de, 1
			add		ix, de		; sadly inc IX does not carry
			ld		d, a		; preserve A
			ld		a, c
			adc		0
			ld		c, a
			ld		a, d
			pop		de
			ret

 if SHOW_MODULE
	 	DISPLAY "map size: ", /D, $-map_start
 endif
