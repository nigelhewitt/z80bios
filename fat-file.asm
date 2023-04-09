;===============================================================================
;
;	fat-file.asm		The code that understands FAT and disk systems
;	Important contributions
;
;===============================================================================
fat_file_start	equ	$

;-------------------------------------------------------------------------------
; isDir		test a FILE* in IX and return CY if it is a folder
;			ie
;-------------------------------------------------------------------------------
isDir		ld		a, [ix+FILE.dirn + DIRN.DIR_Attr]
			bit		attrVOL, a	; Volume bit
			ret		nz
			bit		attrDIR, a	; Directory bit
			ret		z			; and never sets CY
			scf
			ret

;-------------------------------------------------------------------------------
; isFile	test a FILE* in IX and return CY if it is a folder
;-------------------------------------------------------------------------------
isFile		ld		a, [ix+FILE.dirn + DIRN.DIR_Attr]
			bit		attrVOL, a	; Volume bit
			ret		nz
			bit		attrDIR, a	; directory bit
			ret		nz			; and never sets CY
			scf
			ret

;-------------------------------------------------------------------------------
; fileSize	return file size in DE:HL
;-------------------------------------------------------------------------------
fileSize	ld		hl, [ix+FILE.dirn+DIRN.DIR_FileSize]
			ld		de,	[ix+FILE.dirn+DIRN.DIR_FileSize+2];
			ret

;-------------------------------------------------------------------------------
; matchName		test the FILE* in IX with wanted item WCHAR* DE
;				return CY on match
;-------------------------------------------------------------------------------
matchName	push	hl, bc
			ld		hl, ix
			ld		bc,	FILE.longName
			add		hl, bc
			call	strcmp16		; returns CY on match
			pop		bc, hl
			ret

;-------------------------------------------------------------------------------
; OpenFile		call with empty FILE* in IX and WCHAR* path in DE
;				loads the FILE and returns CY
;				else NC
;-------------------------------------------------------------------------------
OpenFile
; First we need to split the pathname and the filename
			push	iy, hl, de
			ld		hl, de			; take the name
			ld		de, '/'			; reverse search for a '/'
			call	strrchr16		; reverse search
			jr		nc, .of1		; no '/' so just a filename

; we have a pathname/filename so break them with a null on the '/'
			push	de				; push second copy of full paath
			ld		[hl], 0			; '/' is low byte only so this is a null
			ex		[sp], hl		; HL=pathname, [SP]=char before filename
			ld		ix, local.folder
			ld		de, hl			; pathname in DE
			call	OpenDirectory	; get the named DIRECTORY
			jr		nc,	.of3		; failed
			pop		hl				; char before filename
			ld		[hl], '/'		; put the full path back together
			inc		hl				; advance to the filename
			inc		hl
			jr		.of2

; just a filename, get the default DIRECTORY on the default DRIVE
.of1		push	de				; save filename pointer
			ld		de, .null		; point to a "" pathname
			call	OpenDirectory
			jr		nc,	.of3		; fail
			pop		de
123
; now select the file in the folder
.of2		call	NextDirectoryItem	; fill in FILE
			jr		nc, .of4				; run out so fail
			call	isFile
			jr		nc, .of2			; folder or stuff
			call	matchName			; test on DE
			jr		nc, .of2			; not us

; we have the FILE so prep it
; NextDirectoryItem has done quite a bit. ie:
; drive, dirn, startCluster, longName, pathName, filePointer=0

			ld		a, 0x03				; open for read
			ld		[ix+FILE.open_mode], a
			ld		hl, 0xffff
			ld		[ix+FILE.sector_file], hl
			ld		[ix+FILE.sector_file+2], hl
			ld		[ix+FILE.cluster_file], hl
			ld		[ix+FILE.cluster_file+2], hl
			ld		[ix+FILE.cluster_abs], hl
			ld		[ix+FILE.cluster_abs+2], hl
			ld		[ix+FILE.first_sector_in_cluster], hl
			ld		[ix+FILE.first_sector_in_cluster+2], hl

			pop		de, hl, iy
			scf
			ret

; error exits
.of3		pop		de					; pop an extra item and discard
.of4		pop		de, hl, iy
			or		a
			ret

.null		dw	0			; aka ""

;-------------------------------------------------------------------------------
; SeekFile	set filePointer to DE:HL (for read must be less than fileSize)
;-------------------------------------------------------------------------------
; Time for a discussion on how to 'do' files
;	The FAT system provideds me with startCluster
;	fat-clusters.asm provides GetClusterEntry which is the next cluster
;	we have FILE.buffer[512]
;
;	Distinguish between sector/cluster values '_file' which are just counting
;	up from zero at the beginning as if everything was nice and flat
;	and sector/cluster values '_abs' where all the FAT and partition stuff are
;	taken care of.
;
;	So to get to a specific point in a file aka filePointer
;
;	Work out the sector_file
;		address_in_sector	= filePointer %= 512	ie: the n in buffer[n]
;		sector_file			= file_pointer / 512
;		if(sector_file == old_sector_file)
;			finished
;
;	Now work out the cluster_file
;		sector_in_cluster	= sector_file % drive->sectors_in_cluster
;		cluster_file		= sector_file / drive->sectors_in_cluster
;		if(cluster_file == old_cluster_file)
;			goto XX
;
;	find the new cluster (with a shortcut if we are going forwards)
;	we count up cluster_file and absolute cluster_abs in parallel
;		search_cluster_file = 0;
;		search_cluster_abs  = startingCluster
;		if(old_cluster_file < cluster_file){		// FATs only go forwards
;			search_cluster_file = old_cluster_file;
;			search_cluster_abs  = old_cluster_abs
;		}
;		while(search_cluster_file < cluster_file){
;			++search_cluster_file;
;			search_cluster_abs = GetClusterEntry(search_cluster_abs)
;			if(search_cluster_abs == 0xffffffff) ERROR
;		}
;		old_cluster_file = cluster_file
;		old_cluster_abs  =  search_cluster_abs;
;		old_first_sector_in_cluster = drive->ClusterToSector(cluster_abs);
; XX:	old_sector_file = sector_file
;		READ: old_first_sector_in_cluster + sector_in_cluster
;		finished
;
; Now I will use line from this to comment the assembler code below
; Just watch out as the values saved in the FILE are all the old_ ones as they
; define what is in the buffer.
;
;	Obvious isn't it?
;-------------------------------------------------------------------------------
_seekFile	GET32i	ix, FILE.filePointer	; entry without SET
			jr		seekFile.sf1

seekFile	PUT32i	ix, FILE.filePointer
.sf1		push	de, hl

; Work out the sector_file
; sector_file = file_pointer / 512
			ld		l, h		; >>8
			ld		h, e
			ld		e, d
			ld		d, 0
			srl		e			; make that >>9 ie /512
			rr		h
			rr		l			; gives sector in file

; if(sector_file == old_sector_file)
;	finished
			PUT32i	ix, FILE.sector_file
			jr		nz, .nf1
			pop		hl, de
			ret

.nf1		PUT32	.nf_sector_file			; save proposed sector_file

; Get the sector in the cluster
; sector_in_cluster	= sector_file % drive->sectors_in_cluster
; NB: as sectors_in_cluster are all powers of two we do this with a simple AND
			push	bc, iy
			ld		bc, [ix+FILE.drive]
			ld		iy, bc

			ld		a, [iy+DRIVE.sectors_in_cluster_mask]
			or		a
								; if A==0 sector_in_cluster is zero (happy trick)
			ld		[.nf_sector_in_cluster], a
			jr		z, .nf3		; 1 sector per cluster = always a new cluster
								; FAT12 is always one for one
			and		l			; mask the bottom 8 bits of sector_file
			ld		[.nf_sector_in_cluster], a

; cluster_file = sector_file / drive->sectors_in_cluster
; again since sectors_in_cluster is a power of two this is a shift
			ld		b, [iy+DRIVE.sector_to_cluster_slide]
.nf2		srl		e			; no need to do D as it went when I /=512
			rr		h
			rr		l
			djnz	.nf2

.nf3		PUT32	.nf_cluster_file		; save proposed cluster_file

; if(cluster_file == old_cluster_file)
;	goto XX
			CP32i	ix, FILE.cluster_file
			jp		z, .nf6

; set up for the loop to find the cluster
			PUT32	.nf_target_cluster_file

; if(old_cluster_file < cluster_file){		// FATs only go forwards
			jr		nc,.nf4 		; jr if old_cluster_file >= cluster_file

; search_cluster_file = 0;
			ld		hl, 0
			ld		[.nf_search_cluster_file], hl
			ld		[.nf_search_cluster_file+2], hl

; search_cluster_abs  = startingCluster
			GET32i	ix, FILE.startCluster
			PUT32	.nf_search_cluster_abs
			jr		.nf5

; search_cluster_file = old_cluster_file;
.nf4		GET32i	ix, FILE.cluster_file
			PUT32	.nf_search_cluster_file
; search_cluster_abs  = old_cluster_abs
			GET32i	ix, FILE.cluster_abs
			PUT32	.nf_search_cluster_abs

; while(search_cluster_file < target_cluster_file){
.nf5		GET32	.nf_search_cluster_file
			CP32	.nf_target_cluster_file
			jr		c, .nf6				; end of loop
;			++search_cluster_file;
			INC32
			PUT32	.nf_search_cluster_file
;			search_cluster_abs = GetClusterEntry(search_cluster_abs)
			GET32	.nf_search_cluster_abs
			call	GetClusterEntry
			PUT32	.nf_search_cluster_abs
;			if(search_cluster_abs == 0xffffffff) ERROR
			CP32	0xffffffff
			ERROR	z, 25		; search beyond end of chain in seekFile
			jr		.nf4

; old_cluster_file = cluster_file
			GET32	.nf_search_cluster_abs
			PUT32i	ix, FILE.cluster_abs

; old_cluster_abs  =  search_cluster_abs;
			GET32	.nf_search_cluster_abs
			PUT32i	ix, FILE.cluster_abs

; old_first_sector_in_cluster = drive->ClusterToSector(cluster_abs);
			call	ClusterToSector
			PUT32i	ix, FILE.first_sector_in_cluster

; old_sector_file = sector_file
.nf6		GET32	.nf_sector_file
			PUT32i	ix, FILE.sector_file

; READ: old_first_sector_in_cluster + sector_in_cluster
			GET32i	ix, FILE.first_sector_in_cluster
			ld		a, [.nf_sector_in_cluster]
			add		l, a

			call	media_seek
			ERROR	nz, 25		; failed media_seek in seekFile
			ld		hl, ix
			ld		bc, FILE.buffer
			add		hl, bc
			ld		e, 1
			call	media_read
			ERROR	nz, 26		; failed media_read in seekFile

; finished
			pop		iy, bc, hl, de
			scf
			ret

; local variables
.nf_sector_file				dd		0
.nf_sector_in_cluster		db		0
.nf_cluster_file			dd		0
.nf_search_cluster_file		dd		0
.nf_search_cluster_abs		dd		0
.nf_target_cluster_file		dd		0

;-------------------------------------------------------------------------------
; ReadFileBuffer	loads the buffer with the sector containing filePointer
;-------------------------------------------------------------------------------
ReadFileBuffer
			ret

;-------------------------------------------------------------------------------
; fetch the next DE from the file to C:HL address
;-------------------------------------------------------------------------------
ReadFileBlock
			ret

;-------------------------------------------------------------------------------
; return a byte in A
;-------------------------------------------------------------------------------
ReadFileByte
			ret

;-------------------------------------------------------------------------------
; ReadFileString to C:HL max, for DE
;-------------------------------------------------------------------------------
ReadFileString
			ret

;-------------------------------------------------------------------------------
; TellFile		return the filePointer in DE:HL
;-------------------------------------------------------------------------------
TellFile	ld		hl, [ix+FILE.filePointer]
			ld		de, [ix+FILE.filePointer+2]
			ret

;-------------------------------------------------------------------------------
; CloseFile		Mostly a place holder until I add write
;-------------------------------------------------------------------------------
CloseFile
			ret

 if SHOW_MODULE
	 	DISPLAY "fat_file size: ", /D, $-fat_file_start
 endif
