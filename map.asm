;===============================================================================
;
;	Memory addressing
;
;===============================================================================
;
; The Zeta2 arrangement with 1Mb total over the RAM and ROM means that the
; tools need to reflect this. Normally BIOS software just uses 16 bits and that
; covers it all but I want to be able to address everything.
; I decided that bios addressing is usually 20 bits so 0xffffff
; The top bit 0x80000 is the ROM select. This is actually the opposite way
; round to the board design but it makes far more sense as you think in terms
; of normally working in the base RAM from zero up and accessing the ROM or the
; 'switched out' RAM pages is an infrequent event.
; So if you type in an address the bottom 14 bits ie 0x3fff are just simple
; addressing. The next 5 bits select the pages and the final 20th bit selects
; ROM.
; Hence for most things you are accessing the 'standard fit' of RAM0/1/2 in
; 0-0xbfff but you can go anywhere.
; I will do this by making the BIOS memory R/W functions swap the required
; block into PAGE1 just while they need access the they restore RAM1. I really
; wish I could read the MPGSEL1 registers and restore them to what they were
; but I suspect that for 99%+ of the time this will work.
;
;===============================================================================

;===============================================================================
; Memory page addressing
;===============================================================================
; Called with a 20 bit address in C:IX and the required page number in A (0-3)
; b0-13 are just address bus stuff
; b14-18 are the 0-31 page
; bit 19 is ROM select (actually reversed from PCB design but mentally better)
; bits 20-23 are an error
; uses AF, returns 16 bit address in IX
; fixes IX to point to the correct CPU address16 to access the memory

; all nice and straightforward until you ask
;		"WHERE ARE WE EXECUTING AND WHERE IS THE STACK?"
; OK so this code is compiled to go in PAGE3 but that might be ROM or RAM

; What I need are routines that are stack free that I can build from.
; Macros would be too big so return via JP [IY]
; Then we write wrappers to do the required jobs

;-------------------------------------------------------------------------------
; _setPage	a stack free convert from address20 in C:IX to PAGEn n is in A
;			returns IX as a 16 bit address into Z80 address space (in PAGEn)
;			** Not callable: returns via a JP [IY] **
;			uses A HL BC IX IY
;-------------------------------------------------------------------------------
_setPage	and		0x03			; PAGE number 0-3 aka b1-0, mask to be safe
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
			ld		c, a			; we can use C as an output pointer
			ld		b, 0
			ld		a, h
			ld		[bc], a
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
			jp		[iy]

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
			ld		b, 0
			ld		[bc], a
			out		(c), a			; back into PAGEn
			jp		[iy]

;-------------------------------------------------------------------------------
; setPage	here is a wrapper that assumes the stack is somewhere safe
;			call with required address in C:IX and page in A
;			sets the page and returns an address16 in IX
;			uses A and IX
;-------------------------------------------------------------------------------
setPage		push	iy, hl, de, bc
			ld		iy, .sp1		; return address
			jr		_setPage
.sp1		pop		bc, de, hl, iy
			ret

;-------------------------------------------------------------------------------
; resPage	wrapper to restore RAMn to PAGEn, passed in n in A
;			uses AF
;-------------------------------------------------------------------------------
resPage		push	bc, de, iy
			ld		iy, .rp2
			jr		_resPage
.rp2		pop		iy, de, bc
			ret

;-------------------------------------------------------------------------------
; getPageByte	get a byte from C:IX in A leaving everything unchanged.
;				It works the stack free trick so it can get from anywhere
;
;				If C==0xff use [IX] local memory
;-------------------------------------------------------------------------------
getPageByte	ld		a, c
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
; putPageByte	set a byte in C:IX from A.
;				Again it works the stack free trick
;				if C==0xff use [IX] local memory
;-------------------------------------------------------------------------------
putPageByte	push	de
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
; incCIX	increment C:IX safely if there is a danger of crossing a page so
;			just incrementing IX isn't safe
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

;===============================================================================
; banked memory LDIR	copy from C:HL to B:DE for IX counts
;						destination must be RAM, IX==0 results in 64K copy
;						works the 'stack free' trick
;						return CY = good
;						uses  A, BC, DE, HL, IX, IY
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

put24		macro	name, r, rr		; save a 24 bit item
			ld		[name], rr
			ld		a, r
			ld		[name+2], a
			endm
get24		macro	name, r, rr		; retrieve a 24 bit item
			ld		rr, [name]
			ld		a, [name+2]
			ld		r, a
			endm

bank_ldir	di						; no interrupts while the stack is volatile

; save C:HL as .source
; save B:DE as .dest
; save ix as .count
			put24	.source, c, hl
			put24	.dest,   b, de
			ld		[.count], ix

; if source + count overflows 1024K return error (beyond actual memory)
			ld		a, c				; source in A:HL
			ld		bc, ix				; count into something we can add
			add		hl, bc				; A:HL += count
			adc		0
			and		0xf0				; NZ >=1024K
			jr		nz, .bl1			; bad end

; if dest + count overflows 512K return error (beyond RAM)
			get24	.dest, a, hl		; dest in A:HL
			add		hl, bc				; += count
			adc		0
			and		0xf8				; NZ >= 512K
			jr		z, .bl3				; OK, go run the loop

; do a bad exit
.bl1		or		a					; clear carry = bad end
			ret

; start of loop
.bl3

; map source in PAGE1 as source
			get24	.source, c, ix
			ld		iy, .bl4
			ld		a, 1				; A=page, map C:IX
			jp		_setPage			; uses A HL BC IX IY
.bl4		ld		[.localsource], ix

; nS = 0x4000 - (localsource & 0x3fff); aka number of bytes left in source page
			ld		e, ixl				; ix = localsource
			ld		a, ixh
			and		0x3f
			ld		d, a				; DE = localsource & 0x3fff
			ld		hl, 0x4000
			sub		hl, de
			ld		bc, hl				; nS in BC

; map destination as PAGE2
			get24	.dest, c, ix
			ld		iy, .bl5
			ld		a, 2				; A=page, map C:IX
			jp		_setPage			; uses A HL BC IX IY
.bl5		ld		[.localdest], ix

; nD = 0x4000 - (dest & 0x3fff)
			ld		e, ixl
			ld		a, ixh
			and		0x3f
			ld		d, a				; DE = localdest & 0x3fff
			ld		hl, 0x4000
			sub		hl, de
			ld		de, hl				; copy nD into DE

; n = min(nS and nD)
			sub		hl, bc				; nD - nS
			jr		nc, .bl6			; jump if HL<=BC aka nS<nD
			ld		bc, de				; nS>nD so use nD
.bl6									; BC is min value

; n = min(n and count)
			ld		hl, [.count]		; HL and DE are count
			ld		de, hl
			sub		hl, bc
			jr		nc, .bl7				; jump if HL>BC aka count>n
			ld		bc, de				; count<n so use count
.bl7		ld		[.n], bc

; copy PAGE1 to PAGE2 for n
			ld		hl, [.localsource]
			ld		de, [.localdest]
			ldir

; count -= n
			ld		bc, [.n]
			ld		hl, [.count]
			sub		hl, bc
			ld		[.count], hl

; if count==0 finish
			ld		a, h
			or		l
			jr		z, .bl8				; done, so clean up

; source += n
			get24	.source, a, hl
			ld		de, [.count]
			add		hl, de				; A:HL += DE
			adc		0
			put24	.source, a, hl

; dest += n;
			get24	.dest, a, hl
			add		hl, de
			adc		0
			put24	.dest, a, hl

; jump to start of loop
			jp		.bl3

; unmap PAGE1
.bl8		ld		a, 1
			ld		iy, .bl9
			jp		_resPage
.bl9

; unmap PAGE2
			ld		a, 2
			ld		iy, .bl10
			jp		_resPage
.bl10

; return good
			scf
			ret

; local variables
.source			d24		0
.dest			d24		0
.count			dw		0
.localsource	dw		0
.localdest		dw		0
.n				dw		0
