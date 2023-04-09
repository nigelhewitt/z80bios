;===============================================================================
;
;	files.asm		The code that understands FAT and disk systems
;
;===============================================================================
files_start		equ	$

; use local memory
; set up so local.thing is the absolute address of thing
				struct	local
				ds		PAGE2
ADRIVE			DRIVE			; DRIVEs for A, C and D
CDRIVE			DRIVE
DDRIVE			DRIVE
current			ds		1		; current drive letter
folder			DIRECTORY
file			FILE
fat_buffer		ds		512
text			ds		MAX_PATH+85
text2			ds		MAX_PATH+85
buffer			ds		512
a				db		0
b				db		0
				ends

;-------------------------------------------------------------------------------
; Set default Drive	Call with A as a drive letter
;					A drive is OK provided it is defined, no need to exist
;-------------------------------------------------------------------------------
f_setdrive	call	LocalON
			or		a					; zero to reset
			jr		z, .fs3
			cp		'0'					; keyboard reset
			jr		z, .fs3

; find a matching drive so we know it exists
			ld		b, nDrive
			call	islower
			jr		nc, .fs1
			and		~0x20				; force upper case
.fs1		ld		hl, local.ADRIVE
			ld		de, DRIVE
.fs2		ld		ix, hl
			cp		[ix+DRIVE.idDrive]
			jr		z, .fs6
			add		hl, de
			djnz	.fs2

; failed to find that drive so bad return but no change
			call	LocalOFF
			or		a					; clear carry
			ret

; de-initialise so clear the all the drive's mounted statii
.fs3		call	drive_init			; put in codes
			ld		b, nDrive
			ld		hl, local.ADRIVE
			ld		de, DRIVE
.fs4		ld		ix, hl
			ld		[ix+DRIVE.fat_type], 0	; 0 = not mounted
			add		hl, de
			djnz	.fs4

; save drive and exit
.fs5		xor		a
.fs6		ld		[local.current], a
			call	LocalOFF
			scf
			ret

;-------------------------------------------------------------------------------
; print the CWD for the default drive
;-------------------------------------------------------------------------------
f_printCWD	call	LocalON
			ld		a, [local.current]	; do we have a 'current drive'?
			or		a
			jr		z, .fp2				; no, so use ""

; We have a current drive but is it mounted yet?
			call	get_drive			; set IX to drive based on A
			jr		nc, .fp2			; aka current is trashed
			ld		a, [ix+DRIVE.fat_type]
			or		a
			jr		z, .fp1				; not mounted
			ld		hl, ix
			ld		bc, DRIVE.cwd
			add		hl, bc				; pointer to CWD
			ld		a, [hl]
			or		a
			jr		z, .fp1
			call	stdio_textW
			jr		.fp2

; fake it
.fp1		ld		a, [local.current]
			call	stdio_putc
			ld		a, ':'
			call	stdio_putc
			ld		a, '/'
			call	stdio_putc

; done
.fp2		call	LocalOFF
			scf
			ret

;-------------------------------------------------------------------------------
; CD command
;-------------------------------------------------------------------------------
f_cdcommand	call	LocalON
			ld		ix, local.text		; buffer
			ld		b, 100				; size of buffer in WCHARs
; test for legal, treat illegal as a terminator, translate \ to /
			ld		c, getW.B_badPath + getW.B_slash + getW.B_term
			call	getW				; get 16bit char string
			jr		nc, .fc1			; failed something

; do we have a drive to work on
			ld		a, [local.text+1]
			cp		':'
			jr		z, .fc0
			ld		a, [local.current]
			or		a
			jr		z, .fc3
.fc0
			ld		de, local.text		; target name in W16
			ld		iy, local.folder	; empty folder to work with
			call	OpenDirectory		; returns IY as DIRECTORY*
			jp		nc, .fc2			; failed

			ld		hl, [iy+DIRECTORY.drive]	; DRIVE*
			ld		bc, DRIVE.cwd
			add		hl, bc
			ld		de, hl				; destination

			ld		hl, iy
			ld		bc, DIRECTORY.longPath
			add		hl, bc				; source
			call	strcpy16			; WCHAR [HL]->[DE]

			call	LocalOFF
			jp		good_end

.fc1		call	stdio_str
			db		" -- Bad pathname",0
			call	LocalOFF
			jp		bad_end
.fc2		call	stdio_str
			db		" -- Folder not found",0
			call	LocalOFF
			jp		bad_end
.fc3		call	stdio_str
			db		" -- No current drive",0
			call	LocalOFF
			jp		bad_end

;-------------------------------------------------------------------------------
; DIR command
;-------------------------------------------------------------------------------
f_dircommand
			call	LocalON
			ld		a, [local.current]
			or		a
			jr		nz, .fd1

; no current drive so force C:
			ld		a, 'C'
			ld		[.test_path], a
			ld		de, .test_path
			jr		.fd3

; we have a current drive so is it legal? (should never fail)
.fd1		call	get_drive			; get DRIVE* in ix
			jr		nc, .fd6			; bad end

; is it initialised? ie: will there be a CWD entry
			ld		a, [ix+DRIVE.fat_type]
			or		a
			jr		nz, .fd2
			ld		a, [local.current]	; not initialise so open root
			ld		[.test_path], a
			ld		de, .test_path
			jr		.fd3

; we have a CWD
.fd2		ld		hl, DRIVE.cwd
			ld		de, ix
			add		hl, de
			ld		de, hl

; now open the directory in [DE]
.fd3		ld		iy, local.folder
			call	OpenDirectory
			jr		nc, .fd6

			ld		iy, local.folder
			ld		hl, [iy+DIRECTORY.drive]
			ld		ix, hl

.fd4		ld		ix, local.file
			call	NextDirectoryItem
			jr		nc, .fd5

			ld		hl, local.text
			ld		de, MAX_PATH+85
			call	WriteDirectoryItem
			call	stdio_str
			db		"\r\n", 0
			ld		hl, local.text
			call	stdio_text
			jr		.fd4

.fd5		call	LocalOFF
			scf
			ret
.fd6		call	LocalOFF
			xor		a		; NC
			ret

.test_path	db	'C',0, ':',0, '/',0, 0,0

;-------------------------------------------------------------------------------
; TYPE command
;-------------------------------------------------------------------------------
f_typecommand
			call	LocalON

; first get a filename
			ld		ix, local.text		; buffer
			ld		b, 100				; size of buffer in WCHARs
; test for legal, treat illegal as a terminator, translate \ to /
			ld		c, getW.B_badPath + getW.B_slash + getW.B_term
			call	getW				; get 16bit char string
			jp		nc, .ft1			; failed something

; then two numbers for screen length and width
			ld		ix, 24
			call	getdecimalB
			jr		nc, .ft1
			ld		a, ixl
			ld		[local.a], a

			ld		ix, 80
			call	getdecimalB
			jr		nc, .ft1
			ld		a, ixl
			ld		[local.b], a

			call	stdio_str
			db		"\r\nFile: ",0
			ld		hl, local.text
			call	stdio_textW

			call	stdio_str
			db		"  length: ",0
			ld		a, [local.a]
			call	stdio_decimalB

			call	stdio_str
			db		"  width: ",0
			ld		a, [local.b]
			call	stdio_decimalB

			jp		good_end

.ft1		jp		bad_end

;-------------------------------------------------------------------------------
; LOAD command
;-------------------------------------------------------------------------------
f_loadcommand
			call	LocalON
			call	stdio_str
			db		"\r\nLOAD command",0
			call	LocalOFF
			scf
			ret

;===============================================================================
; diagnostic tools
;===============================================================================

printDIRECTORY			; IY = DIRECTORY*
			push	af, bc, de, hl
			call	stdio_str
			GREEN
			db		"\r\nDIRECTORY: ", 0
			ld		hl, DIRECTORY.longPath
			ld		bc, iy
			add		hl, bc
			call	stdio_textW						; wide chars output

			call	stdio_str
			db		"  at: 0x",0
			ld		hl, iy
			call	stdio_word

			call	stdio_str
			db		"\r\nstartCluster: 0x",0
			GET32i	iy, DIRECTORY.startCluster		; DE:HL
			ld		bc, de
			call	stdio_32bit						; BC:HL

			call	stdio_str
			db		"  sector: 0x",0
			GET32i	iy, DIRECTORY.sector			; DE:HL
			ld		bc, de
			call	stdio_32bit						; BC:HL

			call	stdio_str
			db		"  sectorinbuffer: 0x",0
			GET32i	iy, DIRECTORY.sectorinbuffer	; DE:HL
			ld		bc, de
			call	stdio_32bit					; BC:HL

			call	stdio_str
			db		"  slot: ",0
			ld		a, [iy+DIRECTORY.slot]			; A
			call	stdio_decimalB					; A

prExit		call	stdio_str
			WHITE
			db		0
			pop		hl, de, bc, af
			ret

printDRIVE				; IX = DRIVE*
			push	af, bc, de, hl
			call	stdio_str
			GREEN
			db		"\r\nDRIVE: ",0
			ld		a, [ix+DRIVE.idDrive]
			call	stdio_putc

			call	stdio_str
			db		"  hardware: ",0
			ld		a, [ix+DRIVE.hwDrive]
			call	stdio_decimalB						; A

			call	stdio_str
			db		"  partition: ", 0
			ld		a, [ix+DRIVE.iPartition]
			inc		a
			call	stdio_decimalB

			call	stdio_str
			db		"  type: 0x", 0
			ld		a, [ix+DRIVE.fat_type]
			call	stdio_byte

			call	stdio_str
			db		"  at: 0x",0
			ld		hl, ix
			call	stdio_word

			call	stdio_str
			db		"\r\ncwd: ", 0
			ld		hl, DRIVE.cwd
			ld		bc, ix
			add		hl, bc
			call	stdio_textW

			call	stdio_str
			db		"\r\nfat_size: ", 0
			GET32i	ix, DRIVE.fat_size
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  nFATs: ", 0
			ld		a, [ix+DRIVE.fat_count]
			call	stdio_decimalB

			call	stdio_str
			db		"  partition_begin_sector: ",0
			GET32i	ix, DRIVE.partition_begin_sector	; DE:HL
			ld		bc, de
			call	stdio_decimal32						; BC:HL

			call	stdio_str
			db		"\r\nsector_to_cluster_slide: ", 0
			ld		a, [ix+DRIVE.sector_to_cluster_slide]
			call	stdio_decimalB

			call	stdio_str
			db		"  sectors_in_cluster_mask: 0x", 0
			ld		a, [ix+DRIVE.sectors_in_cluster_mask]
			call	stdio_byte

			call	stdio_str
			db		"  fat_begin_sector: ", 0
			GET32i	ix, DRIVE.fat_begin_sector
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"\r\nfat_dirty: 0x", 0
			ld		a, [ix+DRIVE.fat_dirty]
			call	stdio_byte

			call	stdio_str
			db		"  root_dir_first_sector: ", 0
			GET32i	ix, DRIVE.root_dir_first_sector
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  root_dir_entries: ", 0
			GET32i	ix, DRIVE.root_dir_entries
			ld		bc, de
			call	stdio_decimalW

			call	stdio_str
			db		"\r\ncluster_begin_sector: ", 0
			GET32i	ix, DRIVE.cluster_begin_sector
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  count_of_clusters: ", 0
			GET32i	ix, DRIVE.count_of_clusters
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"\r\nlast_fat_sector: ", 0
			GET32i	ix, DRIVE.last_fat_sector
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  fat_free_speedup: ", 0
			GET32i	ix, DRIVE.fat_free_speedup
			ld		bc, de
			call	stdio_decimal32

			jp		prExit

printFILE		; call with IX = FILE*
			push	af, bc, de, hl
			call	stdio_str
			GREEN
			db		"\r\nFILE: ",0
			ld		hl, FILE.pathName
			ld		bc, ix
			add		hl, bc
			call	stdio_textW
			call	stdio_str
			db		" ==> ", 0
			ld		hl, FILE.longName
			ld		bc, ix
			add		hl, bc
			call	stdio_textW

			call	stdio_str
			db		"  at: 0x",0
			ld		hl, ix
			call	stdio_word

			call	stdio_str
			db		"\r\ndrive*: 0x", 0
			ld		hl, [ix+FILE.drive]
			call	stdio_word

			call	stdio_str
			db		"  startCluster: ", 0
			GET32i	ix, FILE.startCluster
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  shortnamechecksum: 0x", 0
			ld		a, [ix+FILE.shortnamechecksum]
			call	stdio_byte

			call	stdio_str
			db		"\r\nfile_dirty: 0x", 0
			ld		a, [ix+FILE.file_dirty]
			call	stdio_byte

			call	stdio_str
			db		"  open_mode: 0x", 0
			ld		a, [ix+FILE.open_mode]
			call	stdio_byte

			call	stdio_str
			db		"\n\rsector_file: ", 0
			GET32i	ix, FILE.sector_file
			ld		bc, de
			call	stdio_decimal32

			call	stdio_str
			db		"  cluster_file: ", 0
			GET32i	ix, FILE.cluster_file
			ld		bc, de
			call	stdio_decimal32
						
			call	stdio_str
			db		"  cluster_abs: ", 0
			GET32i	ix, FILE.cluster_abs
			ld		bc, de
			call	stdio_decimal32
						
			call	stdio_str
			db		"\r\nfilePointer: ", 0
			GET32i	ix, FILE.filePointer
			ld		bc, de
			call	stdio_decimal32
						
			call	stdio_str
			db		"  first_sector_in_cluster: ", 0
			GET32i	ix, FILE.first_sector_in_cluster
			ld		bc, de
			call	stdio_decimal32
						
			push	iy
			ld		hl, FILE.dirn
			ld		bc, ix
			add		hl, bc
			ld		iy, hl
			call	printDIRN
			pop		iy

			jp		prExit

printDATE				; call with date in BC
						; b0-4 = day,  b5-8 = month, b9-15 = year
			ld		a, b
			and		0x1f
			call	stdio_decimalB2
			ld		a, '/'
			call	stdio_putc
			srl		b			; years to 8-14 (0-6) so 0 to 127
			rr		c			; months to 4-7
			srl		c
			srl		c
			srl		c
			srl		c			; months to 0-3
			ld		a, c
			call	stdio_decimalB2
			ld		a, '/'
			call	stdio_putc
			ld		a, b
			sub		20			; years count from 1980
			jp		stdio_decimalB2

printTIME				; call with time in BC, if e7!=0 then tenths in E0-6
						; b0-4 = seconds/2, b5-10 = minutes, b11-15=hours
			ld		a, b
			srl		a			; hours from 3-7 to 0-4
			srl		a
			srl		a
			call	stdio_decimalB2
			ld		a, ':'
			call	stdio_putc
			sla		c			; half seconds to 1-5
			rl		b			; minutes to 6-11 in BC
			ld		d, c		; save half seconds
			sla		c
			rl		b			; 7-12
			sla		c
			rl		b			; to 8-13 which is 0-5 in B
			ld		a, b
			and		0x1f
			call	stdio_decimalB2
			ld		a, ':'
			call	stdio_putc
			ld		a, d
			and		0x1e
			ld		d, a
			ld		a, e		; do we have 10ths? (0-19)
			bit		7, e
			jr		z, .pt2		; no
			cp		0x8a		; are the tenths >10
			jr		nc, .pt1	; no
			set		0, d		; add the missing second to D
.pt1		sub		0x8a		; gives the remaining 10th in A
			ld		e, a		; save 10ths
			ld		a, d
			call	stdio_decimalB2
			ld		a, '.'
			call	stdio_putc
			ld		a, e
			and		0x0f
			or		0x30
			jp		stdio_putc
.pt2		ld		a, d
			jp		stdio_decimalB2

printDIRN			; call with IY = DIRN*
			push	af, bc, de, hl
			call	stdio_str
			GREEN
			db		"\r\nDIRN: ",0
			ld		b, 8
			ld		hl, iy
.pd1		ld		a, [hl]
			inc		hl
			call	stdio_putc
			djnz	.pd1
			ld		a, '.'
			call	stdio_putc
			ld		b, 3
.pd2		ld		a, [hl]
			inc		hl
			call	stdio_putc
			djnz	.pd2

			call	stdio_str
			db		"  Attr: 0x",0
			ld		a, [hl]
			inc		hl
			call	stdio_byte

			call	stdio_str
			db		"  NT_res: 0x",0
			ld		a, [hl]
			call	stdio_byte

			call	stdio_str
			db		"\r\nCreate time: ",0
			ld		e, [hl]				; save tenths
			set		7, e				; tenths present
			inc		hl
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			inc		hl
			call	printTIME

			call	stdio_str
			db		" Create date: ", 0
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			inc		hl
			call	printDATE

			call	stdio_str
			db		" Last access: ",0
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			inc		hl
			call	printDATE

			ld		c, [hl]			; first cluster high word
			inc		hl
			ld		b, [hl]
			inc		hl
			push	bc

			call	stdio_str
			db		"\r\nWrite time: ",0
			ld		de, 0			; no tenths
			inc		hl
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			inc		hl
			call	printTIME

			call	stdio_str
			db		" Write date: ", 0
			ld		c, [hl]
			inc		hl
			ld		b, [hl]
			inc		hl
			call	printDATE

			call	stdio_str
			db		" First cluster: ", 0
			ld		e, [hl]			; first cluster low word
			inc		hl
			ld		d, [hl]
			inc		hl
			ex		de, hl
			pop		bc				; BC:HL
			call	stdio_decimal32
			ex		de, hl

			call	stdio_str
			db		" File size: ", 0
			ld		e, [hl]			; first cluster low word
			inc		hl
			ld		d, [hl]
			inc		hl
			ld		c, [hl]			; first cluster low word
			inc		hl
			ld		b, [hl]
			ex		de, hl
			call	stdio_decimal32

			DUMPrr	0xff, iy, DIRN
			jp		prExit

;===============================================================================
;
;	define EOF	0xffff
;
; These are the functions I wish to emulate
;
;	FILE*		fopen(uint8_t* pathname, uint8_t *mode);
;	FILE*		fopenD(FILE* file, uint8_t *mode);
;	void		fclose(FILE* fp);
;	uint32_t	fread(void* buffer, uint16_t count, FILE* fp);
;	uint32_t	fwrite(void* buffer, uint16_t count, FILE* fp);
;	uint16_t	fgetc(FILE* fp);
;	uint8_t*	fgets(uint8_t* buffer, uint16_t count, FILE* fp);
;	int			fputc(uint8_t c, FILE* fp);
;	int			fputs(uint8_t* str, FILE* fp);
;	uint8_t		fseek(FILE* fp, int32_t offset, uint8_t origin);
;	uint32_t	ftell(FILE*fp);
;	bool		isDIR(FILE* file);
;	bool		isFILE(FILE* file);
;	uint8_t		isOpen(FILE* file);
;	uint8_t*	longpath(FILE* fp);
;	uint8_t*	longname(FILE* fp);
;	uint32_t	filesize(FILE* fp);
;
;	FOLDER*		openfolder(uint8_t* pathname);
;	bool		changefolder(FOLDER* folder, uint8_t* path);
;	FILE*		findnextfile(FOLDER* folder);
;	void		resetfolder(FOLDER* folder);
;	uint8_t*	folderpathname(FOLDER* fol);
;	void		closefolder(FOLDER* folder);
;
;	char*		writefiledesc(FILE* fp);
;
;===============================================================================

 if SHOW_MODULE
	 	DISPLAY "files size: ", /D, $-files_start
 endif
