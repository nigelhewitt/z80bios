;===============================================================================
;
;	fat-folder.asm		The code that understands FAT and disk systems
;
; Important contributions:
;	OpenDirectory	call with DE=WCHAR* path, returns IY=DIRECTORY* CY on OK
;	ResetDirectory	IY=DIRECTORY* resets so starts from beginning again
;	NextDirectoryItem IY=DIRECTORY*, IX=FILE* to fill in, NC on finished
;	WriteDirectoryItem IX=FILE*, HL=chars, DE=maxChars
;
;===============================================================================

;-------------------------------------------------------------------------------
; zero a block of memory
;			call with HL = pointer, BC = count
;-------------------------------------------------------------------------------
zeroBlock	push	bc, de, hl
			xor		a					; the zero
			ld		[hl], 0				; to HL, source pointer
			ld		de, hl				; DE is destination
			inc		de					; one up
			dec		bc					; one down
			ldir						; [HL++]->[DE++], BC-- until BC==0
			pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
; Unpack a long filename from a DIRL record
; NB: the parts are given in reverse order
; call with	IX = FILE*	where we build the filename
;			IY = DIRN* (DIRL) the directory entry
;-------------------------------------------------------------------------------

; copy a block of B WCHARs from [HL]->[DE] return Z on a 0
; uses A, B, DE, HL
unpackWorker
			ld		a, [hl]
			ld		[de], a
			inc		hl
			inc		de
			or		[hl]		; is this a zero WCHAR?
			ld		[de], a		; save a zero if it is, overwritten if it isn't
			ret		z
			ld		a, [hl]
			ld		[de], a
			inc		hl
			inc		de
			djnz	unpackWorker
			or		1			; set NZ
			ret

UnpackLong
; check the 'first' flag in the order byte
			ld		a, [iy+DIRL.LDIR_Ord]
			and		0x40
			jr		nz, .ul1			; not first

; first so clear the long name in the FILE
			ld		hl, ix				; file
			ld		bc, FILE.longName
			add		hl, bc				; pointer to longName
			ld		bc, MAX_PATH
			call	zeroBlock

; save the checksum
			ld		a, [iy+DIRL.LDIR_ChkSum]
			ld		[ix+FILE.shortnamechecksum], a
			jr		.ul2

; not the first entry so check the checksum matches
.ul1		ld		a, [iy+DIRL.LDIR_ChkSum]
			cp		[ix+FILE.shortnamechecksum]
			ERROR	nz, 24						; error, no recovery, just die

; make a pointer to where the text goes in WCHAR longName[]
.ul2		ld		a, [iy+DIRL.LDIR_Ord]		; get the sequence number
			and		0x3f
			dec		a							; slot number
			ld		c, a						; copy to BC
			ld		b, 0						; multiply * 13  aka 1+4+8
			ld		hl, bc						; HL = slot*1
			sla		c
			rl		b							; BC = slot*2
			sla		c
			rl		b							; BC = slot*4
			add		hl, bc						; HL = slot*5
			sla		c
			rl		b							; BC = slot*8
			add		hl, bc						; HL = slot*13 = index in longName[]
			add		hl, hl						; HL = (slot*13)*2
			ld		bc, FILE.longName			; byte offset in longName
			add		hl, bc
			ld		bc, ix						; FILE*
			add		hl, bc						; pointer to text
			ld		de, hl

; do the blocks of text
			ld		hl, iy						; DIRN*
			ld		bc, DIRL.LDIR_Name1
			add		hl, bc
			ld		b, 5						; first 5 characters
			call	unpackWorker
			ret		z							; finished

			ld		hl, iy
			ld		bc, DIRL.LDIR_Name2
			add		hl, bc
			ld		b, 6						; next 6 characters
			call	unpackWorker
			ret		z							; finished

			ld		hl, iy
			ld		bc, DIRL.LDIR_Name3
			add		hl, bc
			ld		b, 2						; last 2 characters
			call	unpackWorker
			ret									; finished

;-------------------------------------------------------------------------------
; Make the flag letters for the folder display
;		call with HL pointer text* to where you want the six sequential characters
;		C	flag bits
;		uses A, HL
;-------------------------------------------------------------------------------

makeFlags	ld		a, 'R'
			bit		0, d
			jr		z, .mf1
			ld		a, '.'
.mf1		ld		[hl], a

			ld		a, 'H'
			bit		1, d
			jr		z, .mf2
			ld		a, '.'
.mf2		ld		[hl], a

			ld		a, 'S'
			bit		2, d
			jr		z, .mf3
			ld		a, '.'
.mf3		ld		[hl], a

			ld		a, 'V'
			bit		3, d
			jr		z, .mf4
			ld		a, '.'
.mf4		ld		[hl], a

			ld		a, 'D'
			bit		4, d
			jr		z, .mf5
			ld		a, '.'
.mf5		ld		[hl], a

			ld		a, 'A'
			bit		5, d
			jr		z, .mf1
			ld		a, '.'
.mf6		ld		[hl], a
			ret

decimal2digits			; call with 0-99 in A, writes to HL, uses B
			push	hl
			ld		l, a
			ld		h, 0
			call	div10			; HL -> HL->10 remainder in A
			ld		b, a			; save remainder
			ld		a, l			; get tens
			pop		hl
			call	decimalDigit
			ld		a, b			; and fall through...

decimalDigit			; call	 with 0-9 in A, write to HL++
			and		0x0f
			or		0x30
			ld		[hl], a
			inc		hl
			ret

ndigitworker
			call	div10b32		; divide BC:HL by 10, remainder in A
			push	af				; save remainder
			ld		a, d
			or		e
			or		b
			or		c				; if BC:HL!=0 recursive call
			call	nz, ndigitworker
			jr		decimalDigit

decimalNdigits		; write DE:BC to HL, in A characters
					; right justified and space filled
			push	de, bc, af, hl

; first do it left justified (the easy one)
			call	ndigitworker
			pop		de, af				; was HL = start pointer
			push	af, de				; A = width

; the aim is to do an LDDR to move the characters
; so we want HL = source      = current_pointer - 1
;			 DE = destination = initial_pointer+width-1
;			 BC = count		  = width - (current_pointer - initial_pointer)
;			 A  = mumber of spaces = width - count
; currently
;			 DE = initial_pointer
;			 HL = current_pointer
;			 A = width
;			 BC free

			dec		hl
			push	hl					; source on the stack
			inc		hl

			ld		bc, hl				; save current pointer
			sub		hl, de				; current_pointer - initial pointer
			ld		h, a				; save width
			sub		l					; gives count (small number)
			jr		z, .dn2				; no move
			jr		c, .dn2				; negative move, needed more space
			ld		c, a
			ld		b, 0
			push	bc					; count on the stack
			ld		a, h				; width
			ld		b, a				; save width again
			dec		a					; width -1
			ld		l, a
			ld		h, 0				; HL = width-1
			add		hl, de				; HL = initial_pointer + width -1
			ld		a, b				; recover width again

			ld		de, hl				; destination
			pop		bc					; count
			sub		c					; A = width - count
			pop		hl					; source
			lddr						; the decrementing copy

; space fill
			ld 		b, a				; width-count = number of spaces
			ld		a, ' '
.dn1		ld		[de], a
			dec		de
			djnz	.dn1
.dn2		pop		hl, af, bc, de
			ret

;-------------------------------------------------------------------------------
;  MakeTime
;  MakeDate
;		call with HL -> pointer to where you want the six sequential characters
;		DE = time or date value
;-------------------------------------------------------------------------------

makeTime		; b0-4 = seconds/2, b5-10 = minutes, b11-15=hours
			push	bc
			ld		a, d			; hours
			srl		a
			srl		a
			srl		a
			call	decimal2digits
			ld		a, ':'
			ld		[hl], a
			inc		hl
			ld		bc, de			; minutes
			rl		c
			rl		b
			rl		c
			rl		b
			rl		c
			rl		b
			ld		a, b
			and		0x3f
			call	decimal2digits
			ld		a, e			; seconds
			and		0x1f
			sla		a				; double it
			pop		bc
			jp		decimal2digits

makeDate		; b0-4 = day,  b5-8 = month, b9-15 = year
			push	bc
			ld		a, e			; days
			and		0x1f
			call	decimal2digits
			ld		a, '/'
			ld		[hl], a
			inc		hl
			ld		bc, de			; months
			rl		c
			rl		b
			rl		c
			rl		b
			rl		c
			rl		b
			ld		a, b
			and		0x0f
			call	decimal2digits
			ld		a, d			; years
			srl		a
			pop		bc
			jp		decimal2digits

;-------------------------------------------------------------------------------
; WriteDirectoryItem
;			call with IX = FILE*
;			HL = text buffer
;			DE = max character count
;-------------------------------------------------------------------------------

MakeSmallCharacter		; call with text pointer in HL, max_count in DE
						; and the char in BC
; THIS ROUTINE IS JUST A PLACEHOLDER FOR A PROPER WCHAR handler
			ld		a, d
			or		e
			ret		z			; prevent the overrun
			ld		[hl], c
			inc		hl
			dec		de
			ret

WriteDirectoryItem	; "%8s %8s %6s %8u %10u  %s"
					; date, time, flags, filesize, startcluster, longname
			push	de, bc, iy, ix
; check DE>=59 so the fixed text fits and an 8.3 and a trailing null
			CPDE	59
			ERROR	nc, 23

; get a pointer to the DIRN
			ld		bc, hl
			ld		hl, FILE.dirn
			ld		de, ix
			add		hl, de
			ld		iy, hl				; IY pointer to FILE.dirn
			ld		hl, bc				; recover the output pointer

; date
			ld		de, [iy+DIRN.DIR_WrtDate]
			call	makeDate
			ld		a, ' '
			ld		[hl], a
			inc		hl
; time
			ld		de, [iy+DIRN.DIR_WrtTime]
			call	makeTime
			ld		a, ' '
			ld		[hl], a
			inc		hl

; attributes
			ld		c, [iy+DIRN.DIR_Attr]
			call	makeFlags
			ld		a, ' '
			ld		[hl], a
			inc		hl

; file size
			GET32i	iy, DIRN.DIR_FileSize
			ld		a, 8					; 8 digits
			call	decimalNdigits
			ld		a, ' '
			ld		[hl], a
			inc		hl

; start cluster
			GET32i	ix, FILE.startCluster
			ld		a, 10					; 10 digits
			call	decimalNdigits
			ld		a, ' '
			ld		[hl], a
			inc		hl
			SUBDE	45

; long name
			push	hl
			ld		hl, ix					; FILE*
			ld		bc, FILE.longName
			add		hl, bc					; pointer to long name
			ld		iy, hl					; in ix
			pop		hl
.wd1		ld		a, [iy]
			ld		c, a
			inc		iy
			ld		a, [iy]
			ld		b, a
			or		c
			jr		z, .wd2					; finished
			call	MakeSmallCharacter
			jr		.wd1

.wd2		pop		ix, iy, bc, de
			ret

;-------------------------------------------------------------------------------
; MakeLongFromShort	When there isn't a long file name make one from the
;						short name.
;						Also use the DIR_NTRes flag bits:
;							0x08 make the name lower case
;							0x10 make the extension lower case
;	call with IX = FILE with DIRN copied in
;		uses A
;-------------------------------------------------------------------------------

MakeLongFromShort
			push	bc, de, hl
; pointer to long name
			ld		hl, ix				; file
			ld		bc, FILE.longName
			add		hl, bc				; pointer to longName
			ld		de, hl

; pointer to shortName in DIR
			ld		hl, ix
			ld		bc, FILE.dirn + DIRN.DIR_Name
			add		hl, bc

; copy in the filename
			ld		a, [ix+FILE.dirn+DIRN.DIR_NTRes]
			ld		c, a
			ld		b, 8
.ml1		ld		a, [hl]
			bit		3, c			; make name lowercase?
			jr		z, .ml2
			call	isupper
			jr		nc, .ml2
			or		0x20			; uppercase to lowercase
.ml2		ld		[de], a
			inc		de
			xor		a
			ld		[de], a			; that's a WCHAR
			inc		de
			inc		hl
			djnz	.ml1

; now remove trailing spaces (just backspace DE)
; (only trailing as "A B C.TXT" is legal but "abc  .txt" needs a longName)
			ld		b, 8
.ml3		dec		de
			dec		de
			ld		a, [de]
			cp		' '
			jr		nz, .ml4		; until [DE] points to a non space
			djnz	.ml3			; stop at 8 for no-name eg: ".abc"

; add a '.'
.ml4		inc		de
			inc		de
			ld		a, '.'
			ld		[de], a
			inc		de
			inc		de

; copy in the extension
			ld		a, [ix+FILE.dirn+DIRN.DIR_NTRes]
			ld		c, a
			ld		b, 3
.ml5		ld		a, [hl]
			bit		4, c			; make name lower case?
			jr		z, .ml6
			call	isupper
			jr		nc, .ml6
			or		0x20			; make uppercase into lowercase
.ml6		ld		[de], a
			inc		de
			xor		a
			ld		[de], a			; that's a WCHAR
			inc		de
			inc		hl
			djnz	.ml5

; now remove trailing spaces (just backspace DE)
			ld		b, 8
.ml7		dec		de
			dec		de
			ld		a, [de]
			cp		' '
			jr		nz, .ml8		; until [DE] points to a non space
			djnz	.ml7			; stop at 8 for no-name eg: ".abc"

; add the trailing null
.ml8		inc		de
			inc		de
			xor		a
			ld		[de], a
			inc		de
			ld		[de], a
			pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
; AddPath	append more path but understand "." and ".."
;			!! only one path element at a time and hence no ./\ !!
;			I also assume the path ends in a '/'
;			call with HL = (WCHAR*)path		(assumed size = MAX_PATH)
;					  DE = (WCHAR*)more path to append
;	uses A
;-------------------------------------------------------------------------------

AddPath		push	bc, hl, de

; first deal with the special cases of "." and ".."
; WARNING: if the first char is '.' then the second either is null, so "."
; or I assume it is ".."
			ld		b, 0				; use B as the 'special case ".."' flag
			ld		a, [de]				; lower of [0]
			cp		'.'
			jr		nz, .ap3			; not special case
			inc		de
			ld		a, [de]				; upper of [0]
			or		a
			jr		nz, .ap3			; not special case
			inc		de
			inc		de
			ld		a, [de]				; upper of [1]
			or		a
			jr		nz, .ap3			; not special case
			dec		de
			ld		a, [de]				; lower of [1]
			or		a
			jr		nz, .ap2			; not "."

; process as "."
.ap1		pop		de, hl, bc			; is "."
			ret							; the easy one

; ".x" process as ".."
.ap2		ld		b, 1				; special case ".." marker

; advance to the end of HL counting the '/' (should always be 1 for "C:/")
.ap3		ld		e, 0				; slash counter

.ap4		ld		c, [hl]				; lsbyte
			inc		hl
			ld		a, [hl]				; usbyte is zero for '/' or NULL
			inc		hl					; HL points to next char
			or		a
			jr		nz, .ap4			; neither a null nor a '/' so loop
			or		c					; a is zero so recover char + set flags
			jr		z, .ap5				; end of string
			cp		'/'
			jr		nz, .ap4
			inc		e					; count a '/'
			jr		.ap4

; end of string
.ap5		ld		a, b				; was that a special case or ".."?
			jr		z, .ap7				; no

; special case ".."
			ld		a, e				; count of '/'
			cp		2
			jr		c, .ap1				; less than so fail soft

; count HL back to the previous '/'
; since we have a count of 2 or more we need not worry about length tests
			dec		hl					; step HL back to point at null
			dec		hl
.ap6		dec		hl					; step to the MBbyte of char
			ld		b, [hl]
			dec		hl					; step to the start of the char
			ld		a, [hl]
			cp		a, '/'				;
			jr		nz, .ap6			; nope
			ld		a, b
			or		a
			jr		nz, .ap6			; nope
			inc		hl
			inc		hl
			xor		a
			ld		[hl], a
			inc		hl
			ld		[hl], a
			jr		.ap1					; pop and exit

; finally do the append
.ap7		pop		de					; recover the string pointer
			push	de
.ap8		ld		a, [de]
			inc		de
			ld		c, a
			ld		a, [de]
			inc		de
			ld		b, a
			or		c					; test for EOS
			jr		z, .ap9				; end of string
			ld		[hl], c
			inc		hl
			ld		[hl], b
			inc		hl
			jr		.ap8				; add loop

; end of string so add a / and a null
.ap9		ld		a, '/'
			ld		[hl], a
			xor		a
			ld		[hl], 0				; ms byte of the char
			inc		hl
			ld		[hl], 0
			inc		hl
			ld		[hl], a
			pop		de, hl, bc
			ret

;-------------------------------------------------------------------------------
; NormalisePath
; I am using C:/abc/path/name/file.ext style directory separators here
; but with years of DOS/Windows I don't need telling off when I type a '\'
;		call with HL = WCHAR pathname
; uses A
;-------------------------------------------------------------------------------

NormalisePath
			push	de, hl
.np1		ld		e, [hl]
			inc		hl
			ld		d, [hl]			; but don't inc hl
			ld		a, e
			or		d
			jr		z, .np3			; end of string
			ld		a, d			; MSbyte
			or		a
			jr		nz, .np2		; not \
			ld		a, e
			cp		'\'
			jr		nz, .np2		; not \
			ld		a, '/'
			dec		hl				; back to first byte of char
			ld		[hl], a
			inc		hl				; to second byte
.np2		inc		hl				; to next char
			jr		.np1
.np3		pop		hl, de
			ret

;===============================================================================
; Now the workers for DIRECTORY
;===============================================================================

;-------------------------------------------------------------------------------
; ResetDirectory			called with IY=DIRECTORY
;	basically rewind it so NextDirectoryItem can start over
;-------------------------------------------------------------------------------
ResetDirectory
			push	de, hl, ix
			ld		hl, [iy+DIRECTORY.drive]	; point IY to drive
			ld		ix, hl

; do we have a start cluster? (ie use the root)
			ld		hl, [iy+DIRECTORY.startCluster]
			CP32	0
			jr		nz, .rd1

; no, so FAT12/16 use the root directory
			GET32i	ix, DRIVE.root_dir_first_sector
			jr		.rd2						; save as dir->sector

; FAT32, use the startCluster as sector
.rd1		GET32i	iy, DIRECTORY.startCluster	; start Cluster from DIRECTORY
			call	ClusterToSector				; needs DRIVE in iy
.rd2		SET32i	iy, DIRECTORY.sector		; save as sector

; set the slot to zero
			xor		a
			ld		[iy+DIRECTORY.slot], a
			ret

;-------------------------------------------------------------------------------
;  NextDirectoryItem
;	pass in		IY = DIRECTORY
;				IX = FILE
;		returns C on OK or NC is there are none left
;-------------------------------------------------------------------------------

NextDirectoryItem
			push bc, de, hl

; clear the file's longName
			ld		hl, ix
			ld		bc, FILE.longName
			add		hl, bc
			ld		bc, MAX_PATH
			call	zeroBlock

; load the buffer for NextDirectoryItem
			GET32i	iy, DIRECTORY.sector
			CP32i	iy, DIRECTORY.sectorinbuffer
			jr		z, .nd1					; OK
; read sector
			SET32i	iy, DIRECTORY.sectorinbuffer
			call	media_seek				; to DE:HL
			ld		hl, iy
			ld		bc, DIRECTORY.buffer
			add		hl, bc
			ld		e, 1					; one block only
			call	media_read
			ERROR	nz, 20

; loop
.nd1		ld		a, [iy+DIRECTORY.slot]
			cp		16						; 16 slots to a block
			jr		c, .nd2					; still in range

; get a new sector
	;	DirFlush()					<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
; GetNextSector
			push	ix						; put the FILE on hold
			ld		hl, [iy+DIRECTORY.drive]
			ld		iy, hl
			GET32i	iy, DIRECTORY.sector	; update the sector
			call	GetNextSector
			SET32i	iy, DIRECTORY.sector
			pop		ix

; read sector
			SET32i	iy, DIRECTORY.sectorinbuffer
			call	media_seek				; to DE:HL
			ld		hl, iy
			ld		bc, DIRECTORY.buffer
			add		hl, bc
			ld		e, 1					; one block only
			call	media_read
			ERROR	nz, 21
			xor		a
			ld		[iy+DIRECTORY.slot], a
.nd2

; locate next entry
			ld		l, a					; A contains slot
			ld		h, 0
			ld		b, 5					; multiply by 32
.nd3		sla		l
			rr		h
			djnz	.nd3
			ld		bc, iy					; DIRECTORY
			add		hl, bc
			ld		bc, DIRECTORY.buffer
			add		hl, bc					; pointer to DIRN

; get the first byte of the name
			ld		a, [hl]
			cp		a, 0xe5					; unused entry
			jp		z, .nd8					; goto next slot
			or		a						; zero is end of directory
			jp		z, .nd9					; return End of Directory

; we have and entry but is it a long filename part?
			push	iy						; save the DIRECTORY
			ld		iy, hl					; pointer to DIRN
			ld		a, [iy+DIRN.DIR_Attr]
			and		0x0f
			cp		0x0f
			jr		nz, .nd4				; not a long name
			call	UnpackLong				; IX=FILE, IY=DIRN
			pop		iy						; restore the DIRECTORY
			jp		.nd8					; next slot

; we have a file or directory entry
; currently DIRECTORY is on stack, IX=DIRN, IY=FILE
; copy the DIRN	into the FILE
.nd4		ld		hl, ix					; FILE
			ld		bc, FILE.dirn
			add		hl, bc
			ld		de, iy
			ld		bc, DIRN				; size of a DIRN
			ldir

; get the start cluster
			ld		hl, [iy+DIRN.DIR_FstClusLO]
			ld		de,	[iy+DIRN.DIR_FstClusHI]

; test for a long file name and if none make one
			ld		a, [ix+FILE.longName]
			or		[ix+FILE.longName+1]
			jr		nz, .nd5
			call	MakeLongFromShort			; needs IY=FILE
			jr		.nd7

; test the supplied longname's checksum
; 	csum = ((csum & 1) ? 0x80 : 0) + (csum >> 1) + d->DIR_Name[i];
.nd5		ld		b, 11
			ld		hl, iy					; DIRN (DIRN.DIR_Name==0)
			xor		a
.nd6		rrca							; direct b0->b7
			add		a, [hl]
			djnz	.nd6
			cp		[ix+FILE.shortnamechecksum]
			ERROR	nz, 21

; last details
.nd7		pop		iy						; restore DIRECTORY*
			inc		[iy+DIRECTORY.slot]		; slot++ for next time
			ld		hl, 0
			ld		de, hl
			SET32i	ix, FILE.filePointer	; start at 0
			ld		hl, [iy+DIRECTORY.drive]
			ld		[ix+FILE.drive], hl
			ld		hl, iy					; directory
			ld		[ix+FILE.drive], hl

; copy the dir->longPath to file->pathName
			ld		hl, ix					; FILE
			ld		bc, FILE.pathName
			add		hl, bc
			ld		de, hl					; destination
			ld		hl, iy					; DIRECTORY
			ld		bc, DIRECTORY.longPath
			add		hl, bc					; source
			ld		bc, MAX_PATH
			ldir

; return OK with a file, return CY set
			scf
			pop		hl, de, bc
			ret

; increment slot and loop
.nd8		inc		[iy+DIRECTORY.slot]
			jp		.nd1

; this is the 'we have run out of entries' ending, return NC set
.nd9		or		a
			pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
; getToken		Read through a path "stuff-abc/def/gei/" starting from the
;				pointer, say 6 and copy abc into the buffer moving the index
;				to past the delimiter ie 10
;  call with HL = text, DE=buffer, BC = index
;  return CY if there is a token and NC if not
; uses A and updates BC
;-------------------------------------------------------------------------------
getToken	push		hl, de
			add			hl, bc			; pointer to indexed item
.gt1		ld			a, [hl]
			or			a
			jr			z, .gt3			; end of input
			cp			'/'
			jr			z, .gt2			; delimiter
			ld			[de], a
			inc			hl
			inc			de
			jr			.gt1

; delimiter so step over it
.gt2		inc			hl
; end of input so leave HL on end
.gt3		xor			a
			ld			[de], a
			pop			hl				; original DE
			push		de
			sub			hl, de			; if they differ we got a token
			ld			a, h
			or			l				; or clears carry
			jr			z, .gt4
			scf
.gt4		pop			de, hl
			ret

;-------------------------------------------------------------------------------
; ChangeDirectory	call with IY = DIRECTORY* and  DE=WCHAR path*
;					returns CY if it happens
; use A
;-------------------------------------------------------------------------------

tempFile	FILE

ChangeDirectory
			call	ResetDirectory		; IX = DIRECTORY*

; handle "." with a shortcut
			push	de
			ld		a, [de]
			cp		'.'
			jr		nz, .cd1
			inc		de
			ld		a, [de]
			or		a
			jr		nz, .cd1
			ld		a, [de]
			or		a
			jr		nz, .cd1
			ld		a, [de]
			or		a
			jr		nz, .cd1
			pop		de
			scf
			ret

; we need a FILE to work in
.cd1		push	bc, hl, ix				; DE already pushed
			ld		ix, tempFile			; get a working FILE*

.cd2		call	NextDirectoryItem		; IY=DIRECTORY*, IX=FILE*
			jr		nc, .cd3				; finished so failed

			call	isDir					; FILE* in IX
			jr		nc, .cd2				; nope

			call	matchName				; FILE* in IX, WCHAR* DE
			jr		nc, .cd2				; nope

; we have a match
			ld		hl, ix					; FILE*
			ld		de, FILE.longName
			add		hl, de
			ld		de, hl					; more path
			ld		hl, iy					; DIRECTORY*
			ld		bc, DIRECTORY.longPath
			add		hl, bc					; path
			call	AddPath					; HL=path, DE=more path

			GET32i	ix, FILE.startCluster	; move the start cluster over
			SET32i	iy, DIRECTORY.startCluster
			ld		hl,	0
			ld		de, 0
			SET32i	iy, DIRECTORY.sector
			xor		a
			ld		[iy+DIRECTORY.slot], a
			scf
			jr		.cd4

; finished
.cd3		or		a			; clear carry = fail
.cd4		pop		ix, hl, bc, de
			ret

;-------------------------------------------------------------------------------
; OpenDirectory			open with a path
;
; If the path starts with A: or C: you have selected a drive, if not you get
;		the default
; If it has / next you have selected the root directory, if not the CWD of that
; device then you get folder/folder or /folder/folder/
;	call with		IY = DIRECTORY*  to empty structure
;					DE = WCHAR* path
;	returns C if oK or NC if it fail
;-------------------------------------------------------------------------------

OpenDirectory
			ld		a, [defaultDrive]		; letter code 'A'=FDC, 'C'=SD
			ld		c, a
			ld		a, [de]					; save a prospective drive letter
			ld		b, a
			inc		de						; skip the high byte fix later
			inc		de
			ld		a, [de]					; driver indicator
			cp		a, ':'					; was that C:
			jr		nz, .od2				; no
			ld		a, b
			call	islower
			jr		nc, .od1
			and		~0x20
.od1		ld		c, a
.od2		ld		a, c					; leave it in C

; so get a DRIVE in IX
			call	get_drive				; 'C' letter in A returns IX
			ret		nc						; the short way with Dissenters

; set up some basic values as if it is "" or "A:\" this is what they get
			xor		a
			ld		hl, ix
			ld		[iy+DIRECTORY.drive], hl			; dw DRIVE
			ld		hl, 0
			ld		[iy+DIRECTORY.startCluster], hl		; dd start from root
			ld		[iy+DIRECTORY.startCluster+2], hl
			ld		[iy+DIRECTORY.sector], hl			; dd not yet
			ld		[iy+DIRECTORY.sector+2], hl
			dec		hl									; 0xffff
			ld		[iy+DIRECTORY.sectorinbuffer], hl	; dd					// none yet
			ld		[iy+DIRECTORY.sectorinbuffer+2], hl
			ld		[iy+DIRECTORY.slot], a				; db as reset

; put something sensible in the longpath	"C:/"
			ld		a, c								; get the drive letter
			ld		hl, DIRECTORY.longPath				; point to the buffer
			ld		bc, ix
			add		hl, bc
			ld		[hl], a								; drive letter
			inc		hl
			xor		a
			ld		[hl], a
			inc		hl
			ld		a, ':'								; :
			ld		[hl], a
			inc		hl
			xor		a
			ld		[hl], a
			ld		a, '/'								; /
			ld		[hl], a
			inc		hl
			xor		a
			ld		[hl], a
			inc		hl
			ld		[hl], a								; trailing null
			inc		hl
			ld		[hl], a

; if the path does not start with a / use the CWD for that drive
			ld		a, [de]
			cp		'/'
			jr		z, .od4				; not CWD

; loop through the elements of the drive's CWD
			push	de					; save out path pointer
			ld		hl, ix				; DRIVE*
			ld		bc, DRIVE.cwd
			add		hl, bc				; pointer to CWD
			ld		bc, 3				; the CWD is at least "A:\"
			ld		de, .temp1			; text buffer
.od3		call	getToken			; HL = text, DE=buffer, BC = index
			jr		nc, .od5			; run out of tokens
			call	ChangeDirectory		; IY = DIRECTORY* and  DE=WCHAR path*
			jr		c, .od3				; done OK
			pop		de					; fail
			xor		a
			ret

.od4		inc		de					; if it was a / move over it
			inc		de
			jr		.od6
.od5		pop		de					; recover main path
.od6

; now do the path's tokens
			ld		hl, de				; path in HL
			ld		bc, 0				; zero the index
			ld		de, .temp1			; text buffer
.od7		call	getToken			; HL = text, DE=buffer, BC = index
			jr		nc, .od8			; run out of tokens
			call	ChangeDirectory		; IY = DIRECTORY* and  DE=WCHAR path*
			jr		c, .od7				; done OK
			pop		de					; fail
			xor		a
			ret
.od8
			call	ResetDirectory		; IY=DIRECTORY*
			scf
			ret

; local variable
.temp1		ds		MAX_PATH*2

