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
; Macros would be too big so return via JP (IY)
; Then we write wrappers to do the required jobs

;-------------------------------------------------------------------------------
; _setPage	a stack free convert from address20 in C:IX to PAGEn n is in A
;			returns IX as a 16 bit address into Z80 address space (in PAGEn)
;			** Not callable: returns via a JP (IY) **
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
									; H= 00rxxxxx  r=ROM xxxxx 0-32 ROM/RAM page
			ld		a, l			; get the PAGE number again
			add		a, MPGSEL0		; add the base page select register
			ld		c, a			; we can use C as an output pointer
			out		(c), h			; swap the page in
			
			ld		a, ixh			; get address bits b15-8
			sla		a
			sla		a				; slide up two places (discarding top bits)
			cp		a				; clear carry
			rr		l				; slide b0 of L (page number) into carry
			rr		a				; and into A b7
			rr		l
			rr		a				; gives the page number b1-0 in bits b7-6 of A
									; A = ppaaaaaa p=page, xxxxx address b13-8
			ld		ixh, a			; put IX back together
			jp		(iy)

;-------------------------------------------------------------------------------
; _resPage	stack free restore RAMn to PAGEn where A = page no 0 to 3
;			uses A BC and returns JP (IY)
;-------------------------------------------------------------------------------
_resPage	and		0x03			; mask
			ld		b, a			; save page number
			add		a, MPGSEL0
			ld		c, a			; gives port address
			ld		a, b			
			add		a, RAM0			; page RAMn
			out		(c), a			; back into PAGEn
			jp		(iy)

;-------------------------------------------------------------------------------
; setPage	here is a wrapper that assumes the stack is somewhere safe
;			call with required address in C:IX and page in A
;			sets the page and returns an address16 in IX
;			uses A and IX
;-------------------------------------------------------------------------------
setPage		push	iy, hl, bc
			ld		iy, .sp1		; return address
			jr		_setPage
.sp1		pop		bc, hl, iy
			ret
			
;-------------------------------------------------------------------------------
; resPage	wrapper to restore RAMn to PAGEn, passed in n in A
;			uses AF
;-------------------------------------------------------------------------------
resPage		push	bc, iy
			ld		iy, .rp2
			jr		_resPage
.rp2		pop		iy, bc
			ret

;-------------------------------------------------------------------------------
; getPageByte	get a byte from C:IX in A leaving everything unchanged
;				works the stack free trick so it can get from anywhere
;-------------------------------------------------------------------------------
getPageByte	push	hl, bc, iy, ix
;	SNAP "getPageByte start"
			ld		a, 1			; via PAGE1
			ld		iy, .gb1
			jp		_setPage
.gb1		ld		h, (IX)			; get the byte
			ld		a, 1			; PAGE1
			ld		iy, .gb2
			jr		_resPage
.gb2		ld		a, h			; result in A
;	SNAP "getPageByte end"
			pop		ix, iy, bc, hl
			ret

;-------------------------------------------------------------------------------
; putPageByte	set a byte in C:IX from A
;				again works the stack free trick
;-------------------------------------------------------------------------------
putPageByte	push	de, hl, bc, iy, ix
;	SNAP "putPageByte start"
			ld		d, a			; save the byte
			ld		a, 1			; via PAGE1
			ld		iy, .pb1
			jp		_setPage		; does not use DE
.pb1		ld		(IX), d			; get the byte
			ld		a, 1			; PAGE1
			ld		iy, .pb2
			jp		_resPage
.pb2		ld		a, d
;	SNAP "putPageByte end"
			pop		ix, iy, bc, hl, de
			ret

;-------------------------------------------------------------------------------
; incCIX	increment C:IX safely if there is a danger of crossing a page
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

	if 0
;===============================================================================
; banked memory LDIR	copy from C:HL to B:DE for IX counts
;						destination must be RAM, IX==0 results in 64K copy
;						works the 'stack free' trick
;						return CY = good
; you are free to read from and write to any memory address. If you overwrite
; yourself that's your problem. I only protect you from the stack getting
; switched in and out.
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

putRP		macro	rr			; save a register pair on the extended set
			ld		iy, rp
			exx
			ld		rp, iy
			exx
			endm
getRP		macro	rr			; retrieve a register pair from the extended set
			exx
			ld		iy, rr
			exx
			ld		rr, iy
			endm
add20		macro	dd, ss		; add ss to A:dd
			add		dd, ss
			adc		0
			endm
bank_ldir
; get some working space
			di
			push	ix, iy
			exx
			push	bc, de, hl
			exx
; save C:HL as source		3 bytes
; save B:DE as dest			3 bytes
			putRP	bc		; save C:HL and B:DE
			putRP	de
			putRP	hl
; save IX as count			2 bytes
			
; if source + count overflows 1024K return error (beyond actual memory)
			getRP	bc
			getRP	hl
			ld		a, c		; source C:HL -> A:HL
			add20	hl, ix		; A:HL += IX
			and		0xf0		; NZ >=1024K
			jr		nz, .bl1	; bad end
; if dest + count overflows 512K return error (beyond RAM)
			getRP	de			; B should be untouched
			ld		a, b		; dest B:DE -> A:DE
			add20	de, ix		; A:DE += IX
			and		0xf8		; NZ >= 512K
			jr		z, .bl3		; OK, go run the loop
; do error exit
.bl1		or		a			; clear carry = bad end
.bl2		exx					; bad end
			pop		hl, de, bc
			exx
			pop		iy, ix
			ret
; start of loop
.bl3
; map source in PAGE1 to C:HL
			save	ix as counter
			save	ix as n
			ld		a, 1		; A=page, map C:IX
			getRP	bc
			getRP	hl
			ld		ix, hl		; gives address in C:IX
			ld		iy, .bl4
			jr		_setPage	; uses A HL BC IX IY
.bl4		save	ix as source local address
; map destination as PAGE2
			ld		a, 2		; A=page, map C:IX
			getRP	bc
			getRP	de
			ld		ix, de		; gives address in C:IX
			ld		c, b
			ld		iy, .bl5
			jr		_setPage	; uses A HL BC IX IY
.bl5		save	ix as dest local address
; nS = 0x4000 - (source & 0x3fff)  aka number of bytes left in its page
			usave	count as ix
			; if IX>=0x4000 IX=0x4000
			usave	source local address to HL
			ld		a, h
			and		0x3f
			ld		hl, a
			ld		de, 0x4000
			sub		de, hl		; gives nS
			; if de<IX IX=de
			
			
; nD = 0x4000 - (dest & 0x3fff)

; n = least of count, nS and nD

; copy PAGE1 to PAGE2 for n
			usave	local source pointer as hl
			usave	local dest pointer as de
			usave	n as BC
			ldir
; count -= n
			usave	n as de
			usave count as hl
			sub		hl, de
			save	hl as count
; if count==0 {
			ld		a, h
			or		l
			jr		nz, .blP
; unmap PAGE1
			ld		a, 1
			ld		iy, .blX
			jp		_resPage
.blX
; unmap PAGE2
			ld		a, 2
			ld		iy, .blY
			jp		_resPage
.blY
; return good
			scf
			jp		.bl2
; }
; source += n
.blP		getRP	bc
			getRP	de
			getRP	hl
			usave counter as ix
			ld		a, c		; source A:HL
			add20	hl, ix		; add IX to A:HL
			ld		c, a
; dest += n;
			ld		a, d
			add20	de, ix
			ld		d, a
			putRP	bc
			putRP	de
			putRP	hl
; jump to start of loop
			jp		.bl3

	endif
