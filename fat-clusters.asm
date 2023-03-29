;===============================================================================
;
;	fat-drive.asm		The code that understands FAT and disk systems
;
;===============================================================================

; Quick description of a FAT table entry

; A disk or other media  device is a block of 'sectors' of storage. These tend
; to be 512 bytes and are ordered sequentially. Hence at the most basic
; hardware level you can as the media for sector number 1234 and receive a 512
; byte block of data. Write is similar. if you want to break it down into to
; smaller packets or bundle sectors up to more that's your business.
;
; The data area of a partition of media is divided into groups of sectors
; called clusters. There is 1,2,4,8...128 sectors to a cluster set in the
; definition but being a binary fraction
; I crunch the multiplier into a slide with a mask to do remainders.
; Each cluster of sectors has a FAT entry that either tells you if the sector
; is free, damaged, reserved or gives you a link to the next cluster in the
; chain for that file or directory.
; Hence  the FAT table is a list of numbers, one for each cluster.
; Finding the value for a FAT16 or FAT32 file is easy as they are just fit in a
; sector and you can get the right value very simply however there is a huge
; game in doing FAT12 as one and a half bytes doesn't have friendly factors in
; a 2 dominated world. Also note that the clusters are numbered from 2 as 0 and
; 1 have special meanings.

; The top 4 bits of a FAT32 entry are reserved (FAT28?)
; 0  cluster is free
; ff6/fff6/ffffff6 cluster is reserved, do not use
; ff7/fff7/ffffff7 cluster is defective, do not use
; ff8-ffe/fff8/fffe/ffffff8-ffffffe reserved
; fff/ffff/ffffffff allocated and end of chain
; else is the number of next cluster in the chain

;-------------------------------------------------------------------------------
; Convert from a cluster number in a partition to the absolute sector number on
; the media of the first sector in that cluster
;
; call with IY as a pointer to the DRIVE structure for a mounted drive
; and cluster number in this partition in DE:HL
; returns the absolute sector number on the drive in DE:HL
; uses A
;-------------------------------------------------------------------------------

ClusterToSector
;	return drive->cluster_begin_sector + ((c - 2) << drive->sectors_to_cluster_right_slide);
			push	bc
			ld		a, l		; DE:HL -= 2
			sub		a, 2
			ld		l, a
			jr		nc, .cs1
			dec		h
			jr		nc, .cs1
			dec		e
			jr		nc, .cs1
			dec		d
.cs1							; now do the <<  (much faster than a multiply)
			ld		a,	[iy+DRIVE.sector_to_cluster_slide]
			or		a
			jr		z, .cs3		; aka divide by 1
			ld		b, a
.cs2		srl		d
			rr		e
			rr		h
			rr		l
			djnz	.cs2
.cs3							; add the begin sector
			ld		bc, [iy+DRIVE.cluster_begin_sector]
			add		hl, bc
			ld		bc, [iy+DRIVE.cluster_begin_sector+2]
			adc		de, bc
			pop		bc
			ret

;-------------------------------------------------------------------------------
; Convert from an absolute sector number on the media to the cluster number
; containing that sector in a partition
;
; call with IY as a pointer to the DRIVE structure for a mounted drive
; and an absolute sector number on the drive in DE:HL
; returns the cluster number in this partition containing the sector in DE:HL
; use A
;-------------------------------------------------------------------------------

SectorToCluster
;	return ((s - drive->cluster_begin_sector) >> drive->sectors_to_cluster_right_slide) + 2;
			push	bc
			ld		bc, [iy+DRIVE.cluster_begin_sector]
			sub		hl, bc
			ld		bc, [iy+DRIVE.cluster_begin_sector+2]
			sbc		de, bc

			ld		a,	[iy+DRIVE.sector_to_cluster_slide]
			or		a
			jr		z, .sc2			; aka multiply by 1
			ld		b, a
.sc1		srl		l
			rl		h
			rl		e
			rl		d
			djnz	.sc1
.sc2
			pop		bc
			ld		a, l
			add		a, 2
			ld		l, a
			ret		nc
			inc		h
			ret		nc
			inc		e
			ret		nc
			inc		d
			ret

;-------------------------------------------------------------------------------
; Flush the FAT table buffer if it was written to
;	call with DRIVE in IY
;	DRIVE.last_fat_sector contains the sector number in the FAT of the cache
;	uses A
;-------------------------------------------------------------------------------

FlushFat	ld		a, [iy+DRIVE.fat_dirty]
			or		a
			ret		z
			ld		b, [iy+DRIVE.fat_count]				; almost invariably 2

; make the sector number in the first fat table
			push	bc, de, hl
			ld		hl, [iy+DRIVE.fat_begin_sector]		; first sector of FAT
			ld		de, [iy+DRIVE.fat_begin_sector+2]
			ld		bc, [iy+DRIVE.last_fat_sector]
			add		hl, bc
			ld		bc, [iy+DRIVE.last_fat_sector+2]
			adc		de, bc

			ld		b, [iy+DRIVE.fat_count]		; how many FATs?
			push	bc
			jr		.ff2
.ff1		push	bc
			ld		bc, [iy+DRIVE.fat_size]
			add		hl, bc
			ld		bc, [iy+DRIVE.fat_size+2]
			adc		de, bc
.ff2		call	fathw_seek			; seek to DE:HL
			ERROR	nz, 11
			ld		hl, iy
			ld		bc, DRIVE.fatTable
			add		hl, bc
			call	fathw_write
			ERROR	nz, 12
			pop		bc
			djnz	.ff1
			pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
;  Read and cache a FAT sector
;	call with DRIVE in IY and the FAT sector in DE:HL
;	uses A
;-------------------------------------------------------------------------------

GetFatSector
; if required_sector == last_fat_sector return
			push	bc, hl, de
			ld		bc, [iy+DRIVE.last_fat_sector]
			sub		hl, bc
			jr		nz, .gf1
			ld		bc, [iy+DRIVE.last_fat_sector+2]
			sub		de, bc
			jr		nz, .gf1
			pop		de, hl, bc		; we have a match
			ret
.gf1
			call	FlushFat		; it may need doing
			pop		de, hl
			push	hl, de
			ld		bc, [iy+DRIVE.fat_begin_sector]
			add		hl, bc
			ld		bc, [iy+DRIVE.fat_begin_sector+2]
			adc		de, bc
			call	fathw_seek		; seek to DE:HL
			ERROR	nz, 13
			ld		hl, iy
			ld		bc, DRIVE.fatTable
			add		hl, bc
			call	fathw_write
			ERROR	nz, 14
			pop		de, hl
			ld		[iy+DRIVE.last_fat_sector], hl
			ld		[iy+DRIVE.last_fat_sector+2], de
			pop		bc
			ret

;-------------------------------------------------------------------------------
; First an explanation about how I handle FAT12 because it is the messy one to
; do fast and reasonably compactly.
; This is my fifth method and is fine tuned for speed.
; Why worry isn't it history? well my 1.44Mb FDD is FAT12 so I need it.
; The version I have not seen is FAT16.
; So... 12 bit FAT entries close packed. That's one and a half bytes with
; the LSbits first
;
; byte0					  byte1						byte2
; A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 B0 B1 B2 B3	B4 B5 B5 B6 B7 B8 B9 B10 B11
;
; Well one and a half is not a factor of 512 so packing means we get overlap.
; I reason that three FAT sectors are 1536 bytes and that's exactly 1024 12 bit
; entries so I propose to consider a FAT table to be sequence of 3 sector
; blocks (actually as 12 bits can only address 4096 clusters there will never
; be more than 4 of these 3 sector blocks).
; There might not be 4 and the number of blocks might not be a multiple of
; three but there will be drive->fat_size sectors which will contain enough
; sectors to contain drive->count_of_clusters entries.
;
; Of those 1024 entries only two need special handling due to overhanging the
; sector boundaries so I want to pick them out for special treatment and not
; slow handling the other 1022 down.
;
; Similarly with the two 12 bit elements in three bytes it seems better handle
; them in 'pairs' totalling three bytes per pair. Consider them as 'even' and
; 'odd' as all 'even' elements decode one way and all 'odd' elements decode in
; the other way.
;
; So: A 'triad' of sectors contain 512 pairs
; It would be nice to just read three sectors into one big buffer but it's
; hardly needed as reducing the number of media reads is the main speed issue.
;
;	 sector 0 contains 170 pairs, then another 'even' entry and 4 spare bits
;			  of the overhanging 'odd' entry
;	 sector 1 contains 1 byte that is part of the overhanging 'odd' entry,
;			  170 more pairs, then another byte of overhanging 'even'
;	 sector 2 contains 4 bits of overhanging 'even', an 'odd' entry
;			  and finally 170 pairs. Total 1024
;-------------------------------------------------------------------------------

; Start with the workers to put/get entries in a simple byte array

;-------------------------------------------------------------------------------
; split into 3 byte pairs:	a worker that is common to both get and set

; call with HL = array, BC=index returns HL=pointer E=even/odd
; uses A,BC,D
;-------------------------------------------------------------------------------
get12bitW
		ld		e, 0
		srl		b			; divide BC/2 -> BC (0-171)
		rr		c
		rl		e			; remainder	(0-1)
		ld		d, c		; save the pair number
		sla		c			; BC = 2* pairs
		rl		b
		ld		a, c		; add D to make BC=3*pairs
		add		a, d
		ld		c, a
		jr		nc, .gb1
		inc		b
.gb1	add		hl, bc		; HL is now a pointer to the pair
		ret

;-------------------------------------------------------------------------------
; get 12 bits from an array of bytes
;	call with HL -> start of the array
;			  BC = required index (0-342)
;	returns result in DE
;	uses A
;-------------------------------------------------------------------------------
get12bitsA
		push	hl, bc
; split into 3 byte pairs
		call	get12bitW	; point HL to the pair
		rr		e			; remainder into CY
		jr		c, .gb2		; do the odd pair

; even pair
		ld		de, [hl]
		ld		a, d
		and		0x0f
		ld		d, a
		jr		.gb4

; odd pair
.gb2	inc		hl
		ld		e, [hl]		; get 4 lsbs (in msbs)
		inc		hl
		ld		d, [hl]		; get 8 msbs
		ld		b, 4
.gb3	srl		d
		rr		e
		djnz	.gb3
.gb4	pop		bc, hl
		ret

;-------------------------------------------------------------------------------
; as above but set the bits
;	call with HL -> start of the array
;			  BC = required index (0-342)
;			  DE = bits required
; uses A
;-------------------------------------------------------------------------------

set12bitsA
		push	hl, bc, de
; split into 3 byte pairs
		call	get12bitW	; point HL to pair
		rr		e			; remainder into CY
		jr		c, .sb2		; do the odd pair

; even pair
		ld		[hl], e		; 8 lsbs
		inc		hl
		ld		a, d		; cowardice
		and		0x0f
		ld		d, a
		ld		a, [hl]		; get the current bits
		and		0xf0		; mask the 4 lsbs of the odd entry
		or		d
		ld		[hl], a
		jr		.sb3

; odd pair
.sb1	inc		hl
		ld		c, 0		; zero c
		ld		b, 4
.sb2	sla		d			; slide DEC left 4 places
		rl		e
		rl		c
		djnz	.sb2
		ld		a, [hl]
		and		0x0f		; retain the even bits
		or		c			; out in our bits
		ld		[hl], a
		inc		hl
		ld		[hl], e
.sb3	pop		de, bc, hl
		ret

;-------------------------------------------------------------------------------
; Now wrap that with cluster selection
;-------------------------------------------------------------------------------
; get12bitsFAT
;		call with IY = DRIVE and HL=cluster index (12 bit)
;		returns HL = cluster value (12 bit)
;		uses A
;-------------------------------------------------------------------------------
get12bitsFAT
		push	bc, de

; As discussed we work in 'triads of sectors containing 3*512/1.5 = 1024 values
; rather than read all three sectors we decide which sector to read and for the
; two entries that overhang there is a bit of messing about but for the other
; 1022 it's pretty routine.
; To handle the oddities I have a byte fatPrefix extending the fatTable buffer
; by one before and fatSuffix extending it behind.

; uint8_t triad = index/1024;				// which triad of sectors?
		ld		d, h				; cluster/256
		srl		d					; /512
		srl		d					; /1024	= triad number (0-3)
		ld		a, d
		sla		a					; *2
		add		a, d				; triad*3 = FAT sector at start of triad
		ld		d, a

;	index %=  1024;					// index within that triad
		ld		b, h
		ld		a, h
		and		0xfc
		ld		c, a				; gives index in BC (in 1.5 byte units)

; now we work in groups
		CPHL	341
		jr		c, .gf1				; 0-340
		jr		z, .gf3				; 341
		CPHL	682
		jr		c, .gf4				; 342-681
		jr		z, .gf5				; 682
		jp		.gf6				; 683-1023

; 0-340 that's 170 pairs and the whole of 340 (even)
; uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);
.gf1	ld		l, d				; fat sector we want
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable
		ld		de, iy
		add		hl, de				; pointer to array

; return get12bitsA(array, index);
.gf2	call	get12bitsA			; HL=array, BC=index, return DE
		ld		hl, de				; return in HL
		pop		de, bc
		ret

; 341		the last 4 bits of sector0 and the first 8 bits of sector1
.gf3	ld		l, d				; fat sector we want
		ld		h, 0				; first sector of the triad
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable + 511
		ld		de, iy
		add		hl, de				; pointer to last byte of the array

; drive->fatPrefix = array[511];	// save the overlap byte in front of the buffer
		ld		a, [hl]
		inc		iyh							; shameful frig to get over the
		ld		[iy+DRIVE.fatPrefix-256], a	; +127/-128 byte limit on offsets
		dec		iyh							; as the offset is signed!!

; array = (uint8_t*)GetFatSector(drive, triad*3+1) - 2;
		ld		l, d				; fat sector we want
		inc		l					; second sector of the triad
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-2
		ld		de, iy
		add		hl, de				; pointer to two bytes before the array

; we are pointing to the pair 340/341
; return get12bitsA(array, 1);
		ld		bc, 1				; index
		jr		.gf2				; use the duplicate code in previous

; 342-681 inclusive completely within the second sector
; uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1) + 1;
.gf4	ld		l, d				; fat sector we want
		inc		l					; second sector of the triad
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable+1
		ld		de, iy
		add		hl, de				; pointer to after the overlapped byte

; index is in BC, array in HL
; return get12bitsA(array, index-342);
		ld		de, hl				; I really want sub bc, 342
		ld		hl, -342
		add		hl, bc
		ld		bc, hl
		ld		hl, de
		jr		.gf2

; 682		this time our overlap is a whole byte and an even item
.gf5	ld		l, d				; fat sector we want (triad+1)
		inc		l
		ld		h, 0				; second sector of the triad
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable + 511
		ld		de, iy
		add		hl, de				; pointer to last byte of the array

; drive->fatPrefix = array[511];	// save the overlap byte in front of the buffer
		ld		a, [hl]
		inc		iyh							; shameful frig to get over the
		ld		[iy+DRIVE.fatPrefix-256], a	; +127/-128 byte limit on offsets
		dec		iyh							; as the offset is signed!!

; array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;
		ld		l, d				; fat sector we want
		inc		l					; third sector of the triad
		inc		l
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-1
		ld		de, iy
		add		hl, de				; pointer to one byte before the array

; we are pointing to the pair 682/683
; return get12bitsA(array, 0);
		ld		bc, 0				; index
		jp		.gf2				; use the duplicate code in previous

; 683-1023 inclusive an odd byte and 170 pairs all completely within sector three
;		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;
.gf6	ld		l, d				; fat sector we want
		inc		l					; third sector of the triad
		inc		l
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-1
		ld		de, iy
		add		hl, de				; pointer to the overlapped byte

; index is in BC, array in HL
; return get12bitsA(array, index-682);		// 683->index 1 so we never needed array[0]
		ld		de, hl				; I really want sub bc, 682
		ld		hl, -682
		add		hl, bc
		ld		bc, hl
		ld		hl, de
		jp		.gf2

;-------------------------------------------------------------------------------
; set12bitsFAT
;		call with IY = DRIVE and HL=cluster index (12 bit)
;				  DE = required cluster value
;		uses A
;-------------------------------------------------------------------------------
set12bitsFAT
		push	bc, hl, de
; The structure is pretty much a cut and stick from above
; although the actual works differ especially on the overlaps

; uint8_t triad = index/1024;		// which triad of sectors?
		ld		d, h				; cluster/256
		srl		d					; /512
		srl		d					; /1024	= triad number (0-3)
		ld		a, d
		sla		a					; *2
		add		a, d				; triad*3 = FAT sector at start of triad
		ld		d, a

;	index %=  1024;					// index within that triad
		ld		b, h
		ld		a, h
		and		0xfc
		ld		c, a				; gives index in BC (in 1.5 byte units)

; now we work in groups
		CPHL	341
		jr		c, .sf1				; 0-340
		jr		z, .sf3				; 341
		CPHL	682
		jr		c, .sf4				; 342-681
		jr		z, .sf5				; 682
		jp		.sf6				; 683-1023

; 0-340 that's 170 pairs and the whole of 340 (even)
; uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);
.sf1	ld		l, d				; fat sector we want
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable
		ld		de, iy
		add		hl, de				; pointer to the array

; set12bitsA(array, index, value);
.sf2	pop		de					; recover the data
		call	set12bitsA			; HL=array, BC=index, DE=value
		ld		a, 1
		ld		[iy+DRIVE.fat_dirty], a
		pop		hl, bc
		ret

; 341		the last 4 bits of sector0 and the first 8 bits of sector1
.sf3	ld		b, d				; save triad address as we need DE
		ld		l, d				; first sector of the triad
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable
		ld		de, iy
		add		hl, de				; pointer to array

; set12bitsA(array, 341, value);	// spills over into DRIVE.fatSuffix
		pop		de					; get and resave the data
		push	de
		push	bc					; save the triad sector
		ld		bc, 341
		call	set12bitsA			; HL=array, BC=index, DE=value
		ld		a, 1
		ld		[iy+DRIVE.fat_dirty], a
		pop		bc

; array = (uint8_t*)GetFatSector(drive, triad*3+1) - 2;
		ld		l, b				; triad sector
		inc		l					; sector1
		ld		h, 0				; second sector of the triad
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-2
		ld		de, iy
		add		hl, de				; pointer to array-2

; set12bitsA(array, 1, value);
;	we are pointing to the pair 340/341
		ld		bc, 1				; index
		jr		.sf2				; HL = array, BC = index, DATA on stack

; 342-681 inclusive completely within the second sector
; uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1) + 1;
.sf4	ld		l, d				; fat sector we want
		inc		l					; second sector of the triad
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable+1
		ld		de, iy
		add		hl, de				; pointer to after the overlapped byte

; index is in BC, array in HL
; return set12bitsA(array, index-342, value);
		ld		de, hl				; I really want sub bc, 342
		ld		hl, -342
		add		hl, bc
		ld		bc, hl
		ld		hl, de
		jr		.sf2				; HL = array, BC = index, DATA on stack

; 682		this time our overlap is a whole byte and an even item
; uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1);
.sf5	ld		l, d				; fat sector we want (triad+1)
		ld		b, d				; save as we need DE
		inc		l
		ld		h, 0				; second sector of the triad
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable + 511
		ld		de, iy
		add		hl, de				; pointer to last byte of the array

; set12bitsA(array, 341, value);
		pop		de					; get and resave the data
		push	de
		push	bc					; save the triad sector
		ld		bc, 341
		call	set12bitsA			; HL=array, BC=index, DE=value
		ld		a, 1
		ld		[iy+DRIVE.fat_dirty], a
		pop		bc

; array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;
		ld		l, b				; fat sector we want
		inc		l					; third sector of the triad
		inc		l
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-1
		ld		de, iy
		add		hl, de				; pointer to one byte before the array

; we are pointing to the pair 682/683
; return get12bitsA(array, 0);
		ld		bc, 0				; index
		jp		.sf2				; HL = array, BC = index, DATA on stack

; 683-1023 inclusive. An odd byte and 170 pairs all completely within sector three
;		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;
.sf6	ld		l, d				; fat sector we want
		inc		l					; third sector of the triad
		inc		l
		ld		h, 0
		ld		de, 0
		call	GetFatSector
		ld		hl, DRIVE.fatTable-1
		ld		de, iy
		add		hl, de				; pointer to the overlapped byte

; index is in BC, array in HL
; return get12bitsA(array, index-682);		// 683->index 1 so we never needed array[0]
		ld		de, hl				; I really want sub bc, 682
		ld		hl, -682
		add		hl, bc
		ld		bc, hl
		ld		hl, de
		jp		.sf2				; HL = array, BC = index, DATA on stack

;-------------------------------------------------------------------------------
; now we have the messy bits done we can write the cluster entry handlers
;-------------------------------------------------------------------------------
;  GetClusterEntry
;		call with IY = DRIVE
;				  DE:HL = cluster number
;		returns	  DE:HL = FAT entry 12/16/32 bits
;		uses A
;-------------------------------------------------------------------------------

GetClusterEntry
		ld		a, [iy+DRIVE.fat_type]
		cp		FAT12
		jr		z, .gc3
		cp		FAT16
		jr		z, .gc2
		cp		FAT32
		jr		z, .gc1
		ld		hl, 0xffff
		ld		de, hl
		ret

; do the FAT32 entry
;	return ((uint32_t*)GetFatSector(drive, cluster/128))[cluster%128] & 0xfffffff;	// not the top 4 bits

.gc1	push	bc, hl
		; divide by 128 taking advantage of the fact that the cluster number is actually 28 bits
		sla		l				; slide DEHL << 1
		rl		h
		rl		e
		rl		d
		ld		l, h			; now DE:HL >>8
		ld		h, e
		ld		e, d
		ld		d, 0			; gives the FAT sector
		call	GetFatSector
		pop		hl				; lsw of cluster
		ld		a, l			; cluster % 128
		and		0x7f
		ld		l, a
		ld		h, 0			; give index into fat sector
		sra		l				; *=4 for dword pointer
		rr		h
		sra		l
		rr		h
		ld		bc, DRIVE.fatTable
		add		hl, bc
		ld		bc, [hl]
		inc		hl
		inc		hl
		ld		de, [hl]
		ld		hl, bc
		pop		bc
		ret

; do the FAT16 entry
;	return ((uint32_t*)GetFatSector(drive, cluster/256))[cluster%256];
.gc2	push	bc, hl
		ld		l, h			; DE:HL >>8
		ld		h, e
		ld		e, d
		ld		d, 0			; gives the FAT sector
		call	GetFatSector
		pop		hl				; lsw of cluster
		ld		h, 0			; give index into fat sector
		sra		l				; *=2 for word pointer
		rr		h
		ld		bc, DRIVE.fatTable
		add		hl, bc
		ld		bc, [hl]
		ld		hl, bc

; sign extend: if(hl==0xffff) de=0ffff
		CPHL	0xffff
		jr		nz, .gc2a
		ld		de, hl
.gc2a	pop		bc
		ret

; do the FAT12 entry
;	return get12bitsFAT(drive, cluster);
.gc3	call	get12bitsFAT	; HL=cluster (12 bit)
		ld		de, 0

; sign extend: if(hl==0x0fff) de=0ffff
		CPHL	0x0fff
		jr		nz, .gc3a
		ld		hl, 0xffff
		ld		de, hl
.gc3a	pop		bc
		ret
;-------------------------------------------------------------------------------
;  GetClusterEntry
;		call with IY = DRIVE
;				  DE:HL = cluster number
;				  DE':HL' = FAT entry 12/16/32 bits (ALT REGISTERS!)
;		uses A
;-------------------------------------------------------------------------------
; again the structure is taken from the routine above
SetClusterEntry
		ld		a, [iy+DRIVE.fat_type]
		cp		FAT12
		jr		z, .sc3
		cp		FAT16
		jr		z, .sc2
		cp		FAT32
		jr		z, .sc1
		ret

; do the FAT32 entry
.sc1	push	bc, hl
		; divide by 128 taking advantage of the fact that the cluster number is actually 28 bits
		sla		l				; slide DEHL << 1
		rl		h
		rl		e
		rl		d
		ld		l, h			; now DE:HL >>8
		ld		h, e
		ld		e, d
		ld		d, 0			; gives the FAT sector
		call	GetFatSector
		pop		hl				; lsw of cluster
		ld		a, l			; cluster % 128
		and		0x7f
		ld		l, a
		ld		h, 0			; give index into fat sector
		sra		l				; *=4 for dword pointer
		rr		h
		sra		l
		rr		h
		ld		bc, DRIVE.fatTable
		add		hl, bc
		exx
		push	hl
		exx
		pop	bc
		ld		[hl], bc
		inc		hl
		inc		hl
		exx
		push	de
		exx
		pop		bc
		ld		[hl], bc
		pop		bc
		ret

; do the FAT16 entry
.sc2	push	bc, hl
		ld		l, h			; DE:HL >>8
		ld		h, e
		ld		e, d
		ld		d, 0			; gives the FAT sector
		call	GetFatSector
		pop		hl				; lsw of cluster
		ld		h, 0			; give index into fat sector
		sra		l				; *=2 for word pointer
		rr		h
		ld		bc, DRIVE.fatTable
		add		hl, bc
		exx
		push	hl
		exx
		pop		bc
		ld		[hl], bc
		pop		bc
		ret

; do the FAT12 entry
;	return get12bitsFAT(drive, cluster);
.sc3	push	de, hl
		ld		a, h
		and		0x0f			; 12 bits
		ld		h, a
		exx
		push	hl
		exx
		pop		de
		ld		a, d
		and 	0x0f
		ld		d, a
		call	set12bitsFAT	; HL=cluster (12 bit), DE=value
		pop		hl, de
		ret

;-------------------------------------------------------------------------------
;
; GetNextSector		the classic FAT table question
;					call current sector in DE:HL
;					returns next sector in DE:HL
;					or 0 if EOF
;-------------------------------------------------------------------------------

GetNextSector
;	beware the FAT12/16 root directory
;	if(current_sector < drive->cluster_begin_sector)
;		return ++current_sector >= drive->cluster_begin_sector ? 0 : current_sector;

		CPDEHLIY	DRIVE.cluster_begin_sector
		jr			z, .gn2				; =
		jr			nc, .gn2			; >

		INCDEHL
		CPDEHLIY	DRIVE.cluster_begin_sector
		jr			z, .gn1				; =
		jr			nc, .gn1			; >
		ret								; not >=
.gn1	ld			hl, 0				; bad end
		ld			de, hl
		ret

;	uint32_t x = (current_sector+1) & drive->sectors_in_cluster_mask;
;	if(x) return current_sector+1;

.gn2	ld		a, l
		inc		a
		and		[iy+DRIVE.sectors_in_cluster_mask]
		jr		z, .gn3
		INCDEHL
		ret

;	uint32_t n = GetClusterEntry(drive, SectorToCluster(drive, current_sector));
;	if(n==0xfffffff) return 0;
;	return YY_ClusterToSector(drive, n);

.gn3	call	SectorToCluster
		call	GetClusterEntry
		CPDEHL	0xffffffff
		jr		z, .gn1
		call	ClusterToSector
		ret
