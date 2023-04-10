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
fat_folder_start	equ	$

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

; copy a block of B WCHARs from [HL]->[DE] return Z on 0
; uses A, BC, DE, HL
unpackWorker
			ld		a, [hl]
			ld		[de], a
			ld		c, a		; save low byte
			inc		hl
			inc		de
			ld		a, [hl]
			ld		[de], a		; save a zero if it is, overwritten if it isn't
			inc		de
			inc		hl
			or		c			; was that a 0,0 WCHAR?
			ret		z
			djnz	unpackWorker
			or		1			; set NZ
			ret

UnpackLong
; check the 'first' flag in the order byte
			ld		a, [iy+DIRL.LDIR_Ord]
			and		0x40
			jr		z, .ul1			; not first

; if first clear the long name in the FILE
			ld		hl, ix				; file
			ld		bc, FILE.longName
			add		hl, bc				; pointer to longName
			ld		bc, MAX_PATH
			call	zeroBlock

; save the checksum
			ld		a, [iy+DIRL.LDIR_ChkSum]
			ld		[ix+FILE.shortnamechecksum], a
			jr		.ul2

; not the first entry so check the checksum matches previous one
.ul1		ld		a, [iy+DIRL.LDIR_ChkSum]
			cp		[ix+FILE.shortnamechecksum]
			ERROR	nz, 15		; shortnamechecksum fails in UnpackLong

; make a pointer to where the text goes in WCHAR longName[]
.ul2		ld		a, [iy+DIRL.LDIR_Ord]	; get the sequence number
			and		0x3f
			dec		a						; slot number (0-0x3f/63.)
			ld		c, a					; copy to BC
			ld		b, 0					; multiply * 13  aka 1+4+8
			ld		hl, bc					; HL = slot*1
			sla		c						; (0-0x7e)
			sla		c						; (0-0xfc)
			add		hl, bc					; HL = slot*5
			sla		c						; (0-0x1f8)
			rl		b						; BC = slot*8 (first time C involved
			add		hl, bc					; HL = slot*13 = index in longName[]
			add		hl, hl					; HL = (slot*13)*2
			ld		bc, FILE.longName		; byte offset to WCHAR[] longName
			add		hl, bc
			ld		bc, ix					; FILE*
			add		hl, bc					; pointer to text for this slot
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
			jp		unpackWorker

;-------------------------------------------------------------------------------
; Make the flag letters for the folder display
;		call with HL pointer text* to where you want six sequential characters
;		call with C	flag bits
;		uses A, HL
;-------------------------------------------------------------------------------

makeFlags	ld		a, 'R'			; read only
			bit		attrRO, c
			call	.makeFlagsWorker

			ld		a, 'H'			; hidden
			bit		attrHIDE, c
			call	.makeFlagsWorker

			ld		a, 'S'			; system
			bit		attrSYS, c
			call	.makeFlagsWorker

			ld		a, 'V'			; volume
			bit		attrVOL, c
			call	.makeFlagsWorker

			ld		a, 'D'			; directory
			bit		attrDIR, c
			call	.makeFlagsWorker

			ld		a, 'A'			; archive
			bit		attrARCH, c
			; fallthrough

.makeFlagsWorker
			jr		nz, .mf1
			ld		a, '.'
.mf1		ld		[hl], a
			inc		hl
			ret
;-------------------------------------------------------------------------------
; decimal2digits	call with 0-99 in A, writes to HL, uses B
;-------------------------------------------------------------------------------
decimal2digits
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
;-------------------------------------------------------------------------------
; decimalNdigits	Write BC:DE to [HL], in A characters
;					right justified and space filled
;-------------------------------------------------------------------------------
decimalNdigits
			push	de, bc, af, hl

; first do it left justified (the easy one)
			call	.ndigitworker		; use BC, DE, AF and advances HL
			pop		de, af				; DE = start pointer (was HL)

; Currently:
;	DE = initial_pointer (in HL when called)
;	HL = current_pointer (one beyond the last digit added)
;	A = width
;	BC free
;	stack is callers DE BC

; The aim is to do an LDDR to move the characters forwards, then space fill
; so I want:
;	HL = source      = current_pointer - 1 (on last digit)
;	DE = destination = initial_pointer+width-1 (where I want the last digit)
;	BC = count		  = current_pointer - initial_pointer
;	A  = number of spaces to add = width - count
;	if width >= count no move - return HL=current_pointer
;	else LDDR then space fill [DE--] for A, return HL=destination+1

			push	hl					; current pointer (return HL if no move)
										; also source+1 for the copy
			ld		bc, hl				; save current pointer
			sub		hl, de				; current_pointer - initial pointer
			push	hl					; put count on stack

			ld		h, a				; save width
			sub		l					; width - count
			jr		c, .dn2 			; count>width ie: overflow no move
			jr		z, .dn2				; count==width ie: no move
			ld		l, a				; save as spaces in L

			ld		a, h				; recover width
			add		e					; initial_pointer + width
			ld		e, a
			ld		a, d
			adc		0
			ld		d, a				; destination in DE
			pop		bc					; count from stack in BE
			ld		a, l				; recover spaces number into A
			pop		hl					; source+1 from stack
			dec		hl					; gives source
			push	de					; initial+width as return HL value
			dec		de					; destination for copy
			lddr						; the decrementing copy

; space fill
; now DE is the space before the first character
			ld 		b, a				; width-count = number of spaces
			ld		a, ' '
.dn1		ld		[de], a
			dec		de
			djnz	.dn1

; unwind the return values
			pop		hl					; next_address
			jr		.dn3
			ret

; overflow case return final counter DE in HL
.dn2		pop		bc					; discard the counter
			pop		hl					; current pointer
.dn3		pop		bc, de
			ret

.ndigitworker		; BC:DE/10->BC:DE
			ex		de, hl
			call	div10b32		; divide BC:HL by 10, remainder in A
			ex		de, hl
			push	af				; save the remainder
			ld		a, d
			or		e
			or		b
			or		c				; if BC:HL!=0 recursive call
			call	nz, .ndigitworker
			pop		af
			jp		decimalDigit	; A + '0' -> [HL++]

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
			ld		a, ':'
			ld		[hl], a
			inc		hl
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
			sla		c
			rl		b
			sla		c
			rl		b
			sla		c
			rl		b
			ld		a, b
			and		0x0f
			call	decimal2digits
			ld		a, '/'
			ld		[hl], a
			inc		hl
			ld		a, d			; years
			srl		a
			sub		20				; dates based on 1980
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

WriteDirectoryItem	; "%8s %8s %6s %11u %11u  %s"
					; date, time, flags, filesize, startcluster, longname
			push	ix, iy, bc, hl, de
; check DE>=59 so the fixed text fits and an 8.3 and a trailing null
			CPDE	59
			ERROR	c, 16		; not enough buffer for WriteDirectoryItem

; get a pointer to the DIRN
			ld		bc, hl				; save the output pointer
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
			push	hl
			GET32i	iy, DIRN.DIR_FileSize	; loads DE:HL
			ld		bc, de
			ld		de, hl
			pop		hl
			ld		a, 11					; 11 digits
			call	decimalNdigits			; BC:DE to [HL++]
			ld		a, ' '
			ld		[hl], a
			inc		hl
; start cluster
			push	hl
			GET32i	ix, FILE.startCluster	; load DE:HL
			ld		bc, de
			ld		de, hl
			pop		hl
			ld		a, 11					; 11 digits
			call	decimalNdigits			; BC:DE to [HL++]
			ld		a, ' '
			ld		[hl], a
			inc		hl

; long name
			pop		de						; get the max count back
			push	de
			push	hl
			ex		de, hl
			ld		bc, 46					; characters so far
			sub		hl, bc
			ex		de, hl
			ld		hl, ix					; FILE*
			ld		bc, FILE.longName
			add		hl, bc					; pointer to long name
			ld		iy, hl					; in IY
			pop		hl
.wd1		ld		c, [iy]
			inc		iy
			ld		b, [iy]
			inc		iy
			ld		a, b
			or		c
			jr		z, .wd2					; finished
			call	MakeSmallCharacter
			jr		.wd1

.wd2		xor		a
			ld		[hl], a					; terminating null
			pop		de, hl, bc, iy, ix
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

; pointer to shortName in DIRN
			ld		hl, ix
			ld		bc, FILE.dirn + DIRN.DIR_Name
			add		hl, bc

; copy in the filename part
			ld		a, [ix+FILE.dirn+DIRN.DIR_NTRes]
			ld		c, a			; save the 'make lower case flags'
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
; (only trailing as "A B C.TXT" might be legal but "abc  .txt" needs a longName)
			ld		b, 8
.ml3		dec		de				; back up from 'ready for next char'
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
			ld		b, 3
.ml5		ld		a, [hl]
			bit		4, c			; make ext lower case?
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
			djnz	.ml5			; leave [DE] pointing to after the EXT

; now remove trailing spaces (just backspace DE)
			ld		b, 4			; need an extra pass to move before the ext
.ml7		dec		de				; back to the character
			dec		de
			ld		a, [de]
			cp		' '
			jr		nz, .ml8		; until [DE] points to a non space
			djnz	.ml7

; remove a trailing dot or it goes on directories et al
.ml8		ld		a, [de]
			cp		'.'
			jr		z, .ml9

; add the trailing null
			inc		de
			inc		de
.ml9		xor		a
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
AddPath
			push	bc, de, hl

; first deal with the special cases of "." and ".."
			ld		hl, .dotdot
			call	strcmp16
			jr		c, .ap2
			ld		hl, .dot
			call	strcmp16
			jr		nc, .ap6			; neither

; dot
.ap1		pop		hl, de, bc			; the easy one is "."
			ret

; dotdot 	so move HL to the end of the string
.ap2		pop		hl					; recover the path pointer
			push	hl
			call	strend16			; HL points to terminating null

; then move back to the /
			dec		hl					; character before
			dec		hl
.ap3		dec		hl
			ld		a, [hl]				; msb of char
			dec		hl
			or		a
			jr		nz, .ap3			; not a delimiter
			ld		a, [hl]				; lsb of the character
			cp		':'
			ERROR	z, 22				; : found trying to do cd ..
			cp		'/'
			jr		nz, .ap3			; not a delimiter

			inc		hl					; move to char after the delimiter
			inc		hl
			ld		[hl], 0				; put in a null
			inc		hl
			ld		[hl], 0
			jr		.ap1

; do the append version
; advance HL to the EOL
.ap6		pop		hl					; recover the pointer
			push	hl
			call	strend16			; advance HL to the null

; copy on the addition
			ex		de, hl				; HL = source, DE = dest
			call	strcpy16			; advances HL and DE
			ld		hl, .slash
			call	strcpy16
			jp		.ap1

.dotdot		dw		'.'
.dot		dw		'.',0
.slash		dw		'/',0

;===============================================================================
; Now the workers for DIRECTORY
;===============================================================================

;-------------------------------------------------------------------------------
; ResetDirectory			called with IY=DIRECTORY*
;	basically rewind it so NextDirectoryItem can start over
;-------------------------------------------------------------------------------
ResetDirectory
			push	de, hl, ix
			ld		hl, [iy+DIRECTORY.drive]	; point IX to DRIVE
			ld		ix, hl

; start cluster is zero for root directory
			GET32i	iy, DIRECTORY.startCluster
			CP32	0
			jr		nz, .rd1

; zero so use the root_dir_first_sector from DRIVE
			GET32i	ix, DRIVE.root_dir_first_sector
			jr		.rd2						; save as dir->sector

; not zero so use it to generate a sector number
.rd1		GET32i	iy, DIRECTORY.startCluster	; start Cluster from DIRECTORY
			call	ClusterToSector				; needs DRIVE* in IX
.rd2		PUT32i	iy, DIRECTORY.sector		; save as sector

; set the slot to zero
			xor		a
			ld		[iy+DIRECTORY.slot], a
			pop		ix, hl, de
			ret

;-------------------------------------------------------------------------------
;  NextDirectoryItem
;	pass in		IY = DIRECTORY*
;				IX = FILE*
;		returns C on OK or NC is there are none left
;-------------------------------------------------------------------------------
NextDirectoryItem
			push	bc, de, hl
; clear all the file variables
			ld		hl, ix
			ld		bc, FILE
			call	zeroBlock

; load the buffer for NextDirectoryItem
			GET32i	iy, DIRECTORY.sector		; to DE:HL
			CP32i	iy, DIRECTORY.sectorinbuffer
			jp		z, .nd1					; OK

; read sector
			PUT32i	iy, DIRECTORY.sectorinbuffer	; save as new SIB
 			call	media_seek				; to DE:HL
			ERROR	nz, 17		; media_seek fails in NextDirectoryItem
			ld		hl, iy
			ld		bc, DIRECTORY.buffer
			add		hl, bc
			ld		e, 1					; one block only
			call	media_read
			ERROR	nz, 18		; media_read fails in NextDirectoryItem

; loop
.nd1		ld		a, [iy+DIRECTORY.slot]
			cp		16						; 16 slots to a block
			jp		c, .nd2					; still in range (0-15)

; get a new sector
	;	DirFlush()					<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

; GetNextSector
			push	ix						; put the FILE on hold
			ld		hl, [iy+DIRECTORY.drive]
			ld		ix, hl
			GET32i	iy, DIRECTORY.sector	; update the sector (DE:HL)
			call	GetNextSector			; needs DRIVE* in IX, value in DE:HL
			PUT32i	iy, DIRECTORY.sector
			pop		ix

			ld		a, d					; end of chain?
			or		e
			or		h
			or		l
			jp		z, .nd9					; ought to be signalled by a zero

; read sector
			PUT32i	iy, DIRECTORY.sectorinbuffer	; save as new SIB
			call	media_seek						; to DE:HL
			ld		hl, iy
			ld		bc, DIRECTORY.buffer
			add		hl, bc
			ld		e, 1					; one block only
			call	media_read
			ERROR	nz, 19				; media_read fails in NextDirectoryItem
			xor		a
			ld		[iy+DIRECTORY.slot], a

; locate next entry
.nd2		ld		l, a					; A contains slot (0-15)
			ld		h, 0
			sla		l						; multiply by 32
			sla		l
			sla		l
			sla		l
			sla		l						; first one that might carry out
			rl		h
			ld		bc, iy					; DIRECTORY*
			add		hl, bc
			ld		bc, DIRECTORY.buffer
			add		hl, bc					; pointer to DIRN

; get the first byte of the name
			ld		a, [hl]
			cp		0xe5					; unused entry
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
			add		hl, bc					; destination
			ld		de, hl
			ld		hl, iy					; source = DIRN
			ld		bc, DIRN				; size of a DIRN
			ldir

; get the start cluster
			ld		hl, [iy+DIRN.DIR_FstClusLO]
			ld		de,	[iy+DIRN.DIR_FstClusHI]
			PUT32i	ix, FILE.startCluster

; test for a long file name and if none make one
			ld		a, [ix+FILE.longName]
			or		[ix+FILE.longName+1]
			jr		nz, .nd5
			call	MakeLongFromShort			; needs IY=FILE
			jr		.nd7

; test the supplied shortname's checksum
; 	csum = ((csum & 1) ? 0x80 : 0) + (csum >> 1) + d->DIR_Name[i];
.nd5		ld		b, 11
			ld		hl, iy					; DIRN (DIRN.DIR_Name==0)
			xor		a
.nd6		rrca							; direct b0->b7
			add		a, [hl]
			inc		hl
			djnz	.nd6
			cp		[ix+FILE.shortnamechecksum]
			ERROR	nz, 20			; shortnamecheckum fails in NextDirctoryItem

; last details
.nd7		pop		iy						; restore DIRECTORY*
			inc		[iy+DIRECTORY.slot]		; slot++ for next time
			ld		hl, 0
			ld		de, hl
			PUT32i	ix, FILE.filePointer	; start at 0
			ld		hl, [iy+DIRECTORY.drive]
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
.nd9		or		a				; clear carry (do not increment slot)
			pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
; getToken		Read through a WCHAR* path "stuff-abc/def/gei/" starting from
;				the pointer, say 6 and copy abc into the buffer moving the
;				index to past the delimiter ie 10
;  call with HL = (WCHAR*)text, DE=(WCHAR*)buffer, BC = index
;  return CY if there is a token and NC if not
; uses A and updates BC
;-------------------------------------------------------------------------------
getToken	push		hl, de
			add			hl, bc			; pointer to indexed item
			add			hl, bc			; in WCHARs

; check for no token ie end of input (input starting / dealt with elsewhere)
			inc			hl
			ld			a, [hl]
			dec			hl
			or			[hl]
			jr			nz, .gt1
			pop			de, hl
			or			a				; NC for no token
			ret

; loop copying input to output until end of input or /
.gt1		push		bc
			ld			c, [hl]			; LD BC, [HL++]
			inc			hl
			ld			b, [hl]
			inc			hl
			ld			a, c			; CP BC, 0
			or			b
			jr			z, .gt3			; end of input
			ld			a, c			; CP BC, '/'
			cp			'/'
			jr			nz, .gt2		; not delimiter
			ld			a, b
			or			a
			jr			z, .gt4			; delimiter

; not delimiter or end of string so copy it over
.gt2		ld			a, c
			ld			[de], a
			inc			de
			ld			a, b
			ld			[de], a
			inc			de
			pop			bc
			inc			bc
			jr			.gt1

; end of input
.gt3		pop			bc
			jr			.gt5

; delimiter so terminate the buffer
.gt4		pop			bc
			inc			bc				; step over the delimiter
.gt5		xor			a
			ld			[de], a
			inc			de
			ld			[de], a
			pop			de, hl
			scf
			ret

;-------------------------------------------------------------------------------
; ChangeDirectory	call with IY = DIRECTORY* and  DE=WCHAR path*
;					returns CY if it happens
; use A
;-------------------------------------------------------------------------------

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
			inc		de
			ld		a, [de]
			or		a
			jr		nz, .cd1
			inc		de
			ld		a, [de]
			or		a
			jr		nz, .cd1
			pop		de
			scf
			ret

; we need a FILE to work in
.cd1		pop		de
			push	de, bc, hl, ix
			ld		ix, local.tempfile2		; get a working FILE*

.cd2		call	NextDirectoryItem		; IY=DIRECTORY*, IX=FILE*
			jp		nc, .cd3				; finished so failed

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
			PUT32i	iy, DIRECTORY.startCluster
			ld		hl,	0
			ld		de, 0
			PUT32i	iy, DIRECTORY.sector
			xor		a
			ld		[iy+DIRECTORY.slot], a
			call	ResetDirectory
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
; If you ask for "" you get the default directory of the default drive
;	call with		IY = DIRECTORY*  empty structure to be filled in
;					DE = WCHAR* path
;	returns C if OK or NC if it fail
;-------------------------------------------------------------------------------

OpenDirectory
;=========================== SELECT THE DRIVE ==================================

			push	ix, bc, hl, de, de
			ld		a, [de]					; save a prospective drive letter
			ld		b, a
			inc		de
			ld		a, [de]					; get high byte
			inc		de
			or		a
			jr		nz,	.od2				; not A-? so give up now

			ld		a, [de]					; drive indicator
			inc		de
			cp		':'						; was that C: ?
			jr		nz, .od2				; no
			ld		a, [de]					; high byte
			inc		de
			or		a
			jr		nz, .od2

			ld		a, b					; get back the drive letter
			call	islower
			jr		nc, .od1
			and		~0x20
.od1		call	isupper					; a letter A-Z
			ERROR	nc, 23			; not a drive letter in OpenDirectory

; we have a C: style start so use that as the drive and advance DE to the path
			ld		c, a					; save the drive letter in C
			inc		sp						; discard the pushed DE
			inc		sp
			jr		.od3

; we have no C: to start so use the default drive and restore DE
.od2		ld		a, [local.current]		; letter code 'A'=FDC, 'C'/'D'=SD
			ld		c, a					; drive letter in C
			pop		de
.od3

;========================== INITIALISE TO ROOT =================================

; so get a DRIVE in IX
			push	de, bc
			call	get_drive				; 'C' letter in A returns IX
			ERROR	nc, 21					; get_drive fails in OpenDirectory
			call	mount_drive				; if not mounted mount it
			ERROR	nc, 22					; mount_drive fails in OpenDirectory
			pop		bc, de

; set up some basic values from the DRIVE
; if the request is for "" or "A:/" this is all we need
			xor		a
			ld		hl, ix
			ld		[iy+DIRECTORY.drive], hl			; dw DRIVE*
			ld		hl, 0
			ld		[iy+DIRECTORY.startCluster], hl		; dd start from root
			ld		[iy+DIRECTORY.startCluster+2], hl
			ld		[iy+DIRECTORY.sector], hl			; dd nothing yet
			ld		[iy+DIRECTORY.sector+2], hl
			dec		hl									; 0xffff
			ld		[iy+DIRECTORY.sectorinbuffer], hl	; dd nothing loaded
			ld		[iy+DIRECTORY.sectorinbuffer+2], hl
			ld		[iy+DIRECTORY.slot], a				; db as reset

; Put something sensible in the longpath like "C:/"
			push	de
			ld		a, c								; get the drive letter
			ld		hl, DIRECTORY.longPath				; point to the buffer
			ld		bc, iy
			add		hl, bc
			ld		de, hl								; target
			push	de
			ld		hl, .init							; source "X:/"
			ld		bc, .size_init
			ldir
			pop		de									; target
			ld		[de], a								; drive letter
			pop		de

;=============================  PROCESS CWD ====================================

; if the path does not start with a / use the CWD for that drive
			ld		a, [de]
			cp		'/'
			jr		nz, .od4			; not from root
			inc		de					; check msb is zero
			ld		a, [de]
			dec		de
			or		a
			jr		z, .od7				; start from root

; loop through the elements of the drive's CWD
.od4		push	de					; save our path pointer
			ld		hl, ix				; DRIVE*
			ld		bc, DRIVE.cwd
			add		hl, bc				; pointer to CWD
			ld		bc, 3				; the CWD is at least "A:\"
.od5		ld		de, local.temptext1	; text buffer
			call	getToken			; HL = text, DE=buffer, BC = index
			jr		nc, .od6			; run out of tokens so OK to move on

			push	hl, bc				; save the token stuff
			ld		de, local.temptext1	; token
			call	ChangeDirectory		; IY = DIRECTORY* and  DE=WCHAR path*
			pop		bc, hl
			ERROR	nc, 24		; failed one element of a CWD in OpenDirectory
			jr		.od5				; done OK so try again

; End of CWD
.od6		pop		de
			jr		.od8

; Not CWD so move over the /
.od7		inc		de
			inc		de
.od8

;=========================== PROCESS THE PATH ==================================

; now do the path's tokens
; DE should point to the first token
			ld		hl, de				; path in HL
			ld		bc, 0				; zero the index
			ld		de, local.temptext1	; text buffer
.od9		call	getToken			; HL = text, DE=buffer, BC = index
			jr		nc, .od10			; run out of tokens

			push	hl, bc				; save token pointers
			ld		de, local.temptext1	; text buffer
			call	ChangeDirectory		; IY = DIRECTORY* and  DE=WCHAR path*
			pop		bc, hl
			jr		c, .od9				; done OK
			pop		de, hl, bc, ix
			xor		a
			ret

.od10		call	ResetDirectory		; IY=DIRECTORY*
			pop		de, hl, bc, ix
			scf
			ret

.init		dw		'X', ':','/', 0
.size_init	equ	$-.init

 if SHOW_MODULE
	 	DISPLAY "fat_folder size: ", /D, $-fat_folder_start
 endif
