;===============================================================================
;
;	fat-drive.asm		The code that understands FAT and disk systems
;
; Important Contributions:
;		get_drive		call with drive letter in A and returns IY=DRIVE*
;		mount_drive		call with IY = DRIVE* to mount (if not already mounted)
;		unmount drive	call with IY = DRIVE* if the FD or SD mich be changed
;
;===============================================================================

fat_report	equ	1			; chatty mode

; This uses these routines
; I wrapped them so we can do SD or FDD based on DRIVE.iDrive

media_functions
; SD routines
			dw		SD_INIT
			dw		SD_SEEK
			dw		SD_READ
			dw		SD_WRITE
; FD routines
fd_media	dw		bad_media
			dw		bad_media
			dw		bad_media
			dw		bad_media

nMedia		equ		($-media_functions)/8

media_init	ld		a, 0				; no args
			jr		media_call
media_seek	ld		a, 1				; to DE:HL
			jr		media_call
media_read	ld		a, 2				; HL buffer, E sector count
			jr		media_call
media_write	ld		a, 3				; HL buffer, E sector count

media_call	push	ix, iy, bc, de, hl, hl	; two copies of HL
			ld		hl, media_functions

; add the function number *2
			sla		a						; convert A -> dw pointer
			add		l						; add to function pointer
			ld		l, a
			ld		a, h
			adc		0
			ld		h, a

; add the media type *8
			ld		a, [iy+DRIVE.hwDrive]	; get the HW type
			sla		a						; *8 for table size
			sla		a
			sla		a						; a byte until we get 16 media types
			add		l						; save the function number
			ld		l, a
			ld		a, h
			adc		0
			ld		h, a					; [HL] is the function
			ld		[.mc1], hl
			pop		hl						; recover the second copy of HL
			db		0xcd					; CALL
.mc1		dw		0

			pop		hl, de, bc, iy, ix
			ret

; place holder
bad_media	xor		a
			ERROR	z, 31
			ret
;-------------------------------------------------------------------------------
;	Drives as local variables
;-------------------------------------------------------------------------------

; set drive_letter, partition_number and hardware_type

ADRIVE			DRIVE	'A', 0, 1		; set drive letter and partition number
CDRIVE			DRIVE	'C', 0, 0		; the rest is zero
DDRIVE			DRIVE	'D', 1, 0
nDrive			equ		($-ADRIVE)/DRIVE	; number of drives

defaultDrive	db		'C'				; just a starting point

;-------------------------------------------------------------------------------
; get_drive	convert Drive code in A currently 'A','C' or 'D'
;			returns IY set to DRIVE and C or NC
;-------------------------------------------------------------------------------
get_drive	ld		b, nDrive
			ld		hl, ADRIVE
			ld		de, DRIVE
.gd1		ld		iy, hl
			cp		[iy+DRIVE.idDrive]
			jr		.gd1
			add		hl, de
			djnz	.gd1
			ld		iy, 0
			xor		a					; fail
			ret
.gd2		scf							; success
			ret

;-------------------------------------------------------------------------------
; Read the boot sector from the drive and decide if it contains a partition
; table or if it is a one partition drive and it is a volume header.
; The either process it as a Volume header of load one.
; 	call with IY* DRIVE to fill in with the iDrive and
; iPartion values set
;-------------------------------------------------------------------------------

testsig		db	"MSDOS5.0"			; used to id a value
	if	fat_report
fat0		db	"NOT FAT",0
fat12		db	"FAT12  ",0
fat16		db	"FAT16  ",0
fat32		db	"FAT32  ",0
	endif

mount_drive
; is this DRIVE already initialised?
			ld		a, [iy+DRIVE.fat_type]
			cp		FAT12
			jr		z, .rb0
			cp		FAT16
			jr		z, .rb0
			cp		FAT32
			jr		nz, .rb0a
.rb0		scf					; that was easy
			ret

; initialise things
.rb0a
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nmount_drive"
			WHITE
			db		0
	endif
			call	media_init
			ERROR	nz, 1
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\ninit OK"
			WHITE
			db		0
	endif

; seek to sector 0
			ld		de, 0
			ld		hl, 0
			call	media_seek			; DE:HL
			ERROR	nz, 2
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nseek 0 OK"
			WHITE
			db		0
	endif

; read the boot sector
			ld		hl, .fat_buffer
			ld		e, 1
			call	media_read
			ERROR	nz, 3
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nread 0 OK"
			WHITE
			db		0
	endif

; basic confidence test (works for both BOOT or VOLUME)
			ld		hl, .fat_buffer+BOOT.sig1
			ld		a, [hl]
			cp		a, 0x55
			ERROR	nz, 4
			inc		hl
			ld		a, [hl]
			cp		a, 0xaa
			ERROR	nz, 4

; is it a VOLUME?
			ld		hl, 0		; if it's a volume set it as the beginning
			ld		[iy+DRIVE.partition_begin_sector], hl
			ld		[iy+DRIVE.partition_begin_sector+2], hl

; it's hardly definitive but if it has "MSDOS5.0" in BootTest it is a VOLUME
			ld		b, 8
			ld		hl, .fat_buffer + BOOT.BootTest
			ld		de, testsig
.rb1		ld		a, [de]
			cp		[hl]
			jr		nz, .rb2
			inc		hl
			inc		de
			djnz	.rb1
			jp		.rb7				; do this sector as a volume
.rb2

; so we assume it's a BOOT and report on the partition tables
	if fat_report
			ld		b, 4
			ld		c, 1			; mark partitions 1-4
			ld		ix, .fat_buffer + BOOT.Partition1
.rb3		push	bc
			ld		hl, 0
			ld		a, [ix+PARTITION.TypeCode]
			or		a
			jp		z, .rb5
			ld		hl, fat12		; FAT12
			cp		a, FAT12
			jr		z, .rb4
			ld		hl, fat16		; FAT16
			cp		a, FAT16
			jr		z, .rb4
			ld		hl, fat32		; FAT32
			cp		a, FAT32
			jr		nz, .rb5		; display nothing
.rb4		call	stdio_str
			BLUE
			db		"\r\nPARTITION: ",0
			ld		a, c
			call	stdio_decimalB
			call	stdio_str
			db		" FAT type: ", 0
			call	stdio_text		; print fat type
			call	stdio_str
			db		"  LBA begin: ",0
			ld		hl, [ix+PARTITION.LBA_Begin]
			ld		bc, [ix+PARTITION.LBA_Begin+2]
			call	stdio_decimal32		; BC:HL
			call	stdio_str
			db		" Sectors: ",0
			ld		hl, [ix+PARTITION.nSectors]
			ld		bc, [ix+PARTITION.nSectors+2]
			call	stdio_decimal32
.rb5		pop		bc
			ld		de, PARTITION
			add		ix, de
			inc		c
			djnzF	.rb3
	endif

; right time to extract the partition's important bits
; point IX to the PARTITION
			ld		a, [iy+DRIVE.iPartition]
			cp		4
			ERROR	nc, 5
			ld		ix, .fat_buffer + BOOT.Partition1
			sla		a		; *= 16 aka sizeof PARTITION
			sla		a
			sla		a
			sla		a
			ld		e, a
			ld		d, 0
			add		ix, de				; point ix to partition
	if fat_report
			call	stdio_str
			BLUE
			db		"\r\nSelecting partition: ",0
			ld		a, [iy+DRIVE.iPartition]
			inc		a
			call	stdio_decimalB
	endif

; get the type or error out
; (we will redo this on cluster count later, this is just to kick out errors)
			ld		a, [ix+PARTITION.TypeCode]
			cp		FAT12
			jr		z, .rb6
			cp		FAT16
			jr		z, .rb6
			cp		FAT32
			ERROR	nz, 6
.rb6		ld		[iy+DRIVE.fat_type], a

; get the starting cluster
			ld		hl, [ix+PARTITION.LBA_Begin]
			ld		[iy+DRIVE.partition_begin_sector], hl
			ld		hl, [ix+PARTITION.LBA_Begin+2]
			ld		[iy+DRIVE.partition_begin_sector+2], hl
			ld		a, [ix+PARTITION.TypeCode]

; time to read the VOLUME
			ld		de, [iy+DRIVE.partition_begin_sector+2]
			ld		hl, [iy+DRIVE.partition_begin_sector]
			call	media_seek			; DE:HL
			ERROR	nz, 7

	if fat_report
			call	stdio_str
			db		"\r\nRead VOLUME"
			WHITE
			db		0
	endif
			ld		hl, .fat_buffer
			ld		e, 1
			call	media_read
			ERROR	nz, 8

; checks on a volume
			ld		hl, .fat_buffer+BOOT.sig1
			ld		a, [hl]
			cp		a, 0x55
			ERROR	nz, 9
			inc		hl
			ld		a, [hl]
			cp		a, 0xaa
			ERROR	nz, 9

; process the data out of the volume
; NB: we jump to here is the BOOT isn't a boot
.rb7		ld		ix, .fat_buffer
; first ensure we are 512bytes/sector
			ld		a, [ix+VOLUME32.BPB_BytsPerSec]
			or		a
			ERROR	nz, 10
			ld		a, [ix+VOLUME32.BPB_BytsPerSec+1]
			cp		2
			ERROR	nz, 10
	if fat_report
			call	stdio_str
			BLUE
			db		"\r\nBytes per sector: 512", 0
	endif

; Process the BPB_SecPerClus into a slide and a mask
; this number is a power of 2 so 1,2,4...128
; since I need to multiply and divide by it and take remainders that is done
; with a slide and a mask
			ld		a, [ix+VOLUME32.BPB_SecPerClus]		; 1...128
			ld		de, 0								; D=slide, E=mask
.rb8		srl		a									; 1 becomes z
			jr		z, .rb9
			inc		d
			scf
			sll		e
			jr		.rb8
.rb9		ld		[iy+DRIVE.sector_to_cluster_slide], d
			ld		[iy+DRIVE.sectors_in_cluster_mask], e
	if fat_report
			call	stdio_str
			db		"\r\nSectors per cluster: ",0
			ld		a, [ix+VOLUME32.BPB_SecPerClus]
			call	stdio_decimalB
			call	stdio_str
			db		"  slide: ",0
			ld		a, [iy+DRIVE.sector_to_cluster_slide]
			call	stdio_decimalB
			call	stdio_str
			db		" mask: 0x",0
			ld		a, [iy+DRIVE.sectors_in_cluster_mask]
			call	stdio_byte
	endif

; determine FAT size (if FAT12/16 is set use it)
			ld		de, 0
			ld		hl, [ix+VOLUME12.BPB_FATSz16]
			ld		a, h
			or		l
			jr		nz, .rb10
			ld		de, [ix+VOLUME32.BPB_FATSz32+2]
			ld		hl, [ix+VOLUME32.BPB_FATSz32]
.rb10		ld		[iy+DRIVE.fat_size], hl
			ld		[iy+DRIVE.fat_size+2], de
	if fat_report
			call	stdio_str
			db		"\r\nFAT size: ",0
			ld		bc, de
			call	stdio_decimal32
	endif

; we now need to generate the count_of_clusters value
; but that involves some transient numbers so they go in .local_temp
; total sectors (local)
			ld		de, 0
			ld		hl, [ix+VOLUME12.BPB_TotSec16]
			ld		a, h
			or		l
			jr		nz, .rb11
			ld		de, [ix+VOLUME32.BPB_TotSec32+2]
			ld		hl, [ix+VOLUME32.BPB_TotSec32]
.rb11		ld		[.local_temp1], hl				; TotSec -> local_temp1
			ld		[.local_temp1+2], de

; local RootDirSectors = ((volID->BPB_RootEntCnt * 32) + (volID->BPB_BytsPerSec - 1)) / volID->BPB_BytsPerSec;
			ld		de, 0
			ld		hl, [ix+VOLUME12.BPB_RootEntCnt]
			ld		b, 5
.rb12		or		a				; clear carry
			rl		l
			rl		h
			rl		e
			rl		d
			djnz	.rb12
			ld		bc, 511
			add		hl, bc
			ld		b, 9		; divide by 512
.rb13		or		a			; clear carry
			srl		h
			rr		l
			djnz	.rb13
			ld		[.local_temp2], hl	; b16*32/512 can't be more than 4096
	if fat_report
			call	stdio_str
			db		"\r\nRoot Directory Sectors: ",0
			call	stdio_decimalW
	endif

; local DataSec = TotSec - (volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size) + RootDirSectors);

			ld		b, [ix+VOLUME32.BPB_NumFATs]	; actually 1 or 2
			ld		hl, 0
			ld		de, 0
.rb14		push	bc
			ld		bc, [iy+DRIVE.fat_size]
			add		hl, bc
			ld		bc, [iy+DRIVE.fat_size+2]
			adc		de, bc							; compiles as ex de,hl : sbc hl,bc : ex de,hl
			pop		bc
			djnz	.rb14

			ld		bc, [.local_temp2]				; + RootDirSectors
			add		hl, bc
			ld		bc, 0
			sbc		de, bc

			ld		bc, [ix+VOLUME32.BPB_RsvdSecCnt]
			add		hl, bc
			ld		bc, 0
			ex		hl, de	: adc hl, bc : ex hl, de
			ld		[.local_temp3], hl				; save the item to subtract
			ld		[.local_temp3+2], de

			ld		hl, [.local_temp1]				; TotSec
			ld		de,	[.local_temp1+2]
			ld		bc, [.local_temp3]				; get DataSec
			sub		hl, bc
			ld		bc, [.local_temp2+2]
			sbc		de, bc

; drive->count_of_clusters = DataSec / volID->BPB_SecPerClus;
			ld		b, [iy+DRIVE.sector_to_cluster_slide]
			ld		a, b
			or		a
			jr		z, .rb16
.rb15		srl		d
			rr		e
			rr		h
			rr		l
			djnz	.rb15
.rb16		ld		[iy+DRIVE.count_of_clusters], hl
			ld		[iy+DRIVE.count_of_clusters+2], de
	if fat_report
			call	stdio_str
			db		"\r\nCount of clusters: ",0
			ld		bc, de
			call	stdio_decimal32
	endif
; and now we get the FAT type based on the Microsoft rules
			ld		a, FAT12
			CP32	4085
			jr		nc,	.rb17		; FAT12
			ld		a, FAT16
			CP32	65525
			jr		nc, .rb17		; FAT16
			ld		a, FAT32
.rb17		ld		[iy+DRIVE.fat_type], a
	if fat_report
			call	stdio_str
			db		"\r\nFAT type: ",0
			ld		hl, fat12
			cp		a, FAT12
			jr		z, .rb18
			ld		hl, fat16
			cp		a, FAT16
			jr		z, .rb18
			ld		hl, fat32
.rb18		call	stdio_text
	endif

; drive->root_dir_entries = volID->BPB_RootEntCnt;
			ld		hl, [ix+VOLUME32.BPB_RootEntCnt]
			ld		[ix+DRIVE.root_dir_entries], hl

; drive->fat_begin_sector = drive->partition_begin_sector + volID->BPB_RsvdSecCnt;
			ld		hl, [iy+DRIVE.partition_begin_sector]
			ld		de, [iy+DRIVE.partition_begin_sector+2]
			ld		bc, [ix+VOLUME32.BPB_RsvdSecCnt]
			add		hl, bc
			ld		bc, 0
			adc		de, bc
			ld		[ix+DRIVE.fat_begin_sector], hl
			ld		[ix+DRIVE.fat_begin_sector+2], de

; drive->root_dir_first_sector = drive->partition_begin_sector
;				+ volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size);
; well we have the first part in DE:HL already
			ld		b, [ix+VOLUME32.BPB_NumFATs]	; sometimes 1 normally 2
			ld		[iy+DRIVE.fat_count], b
.rb19		push	bc
			ld		bc, [iy+DRIVE.fat_size]
			add		hl, bc
			ld		bc, [iy+DRIVE.fat_size+2]
			adc		de, bc
			pop		bc
			djnz	.rb19
			ld		[ix+DRIVE.root_dir_first_sector], hl
			ld		[ix+DRIVE.root_dir_first_sector+2], de

; drive->cluster_begin_sector = drive->partition_begin_sector
;		+ volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size)
;		+ RootDirSectors;
;	so just add .local_temp2 ro our current DE:HL
			ld		bc, [.local_temp2]
			add		hl, bc
			ld		bc, 0
			adc		de, bc
			ld		[ix+DRIVE.cluster_begin_sector], hl
			ld		[ix+DRIVE.cluster_begin_sector+2], de

; drive->cwd[0] = drive->idDrive;	drive->cwd[1] = L':';	drive->cwd[2] = L'/';	drive->cwd[3] = 0;
			ld		l, [iy+DRIVE.idDrive]		; need this in WCHAR
			ld		h, 0
			ld		[iy+DRIVE.cwd], hl
			ld		l, ':'
			ld		[iy+DRIVE.cwd+2], hl
			ld		l, '/'
			ld		[iy+DRIVE.cwd+4], hl
			ld		l, 0
			ld		[iy+DRIVE.cwd+6], hl

;	drive->last_fat_sector	 = 0xfffffff;		// we have nothing in the fatTable buffer
;	drive->fat_dirty		 = false;			// so it doesn't need writing
;	drive->fat_free_speedup	 = 0;				// and we have no idea yet where the spaces are
			ld		hl, 0xffff
			ld		[ix+DRIVE.last_fat_sector], hl
			ld		[ix+DRIVE.last_fat_sector+2], hl
			xor		a
			ld		[ix+DRIVE.fat_dirty], a
			ld		hl, 0
			ld		[ix+DRIVE.fat_free_speedup], hl
			ld		[ix+DRIVE.fat_free_speedup+2], hl

			call	stdio_str
			BLUE
			db		"\r\nEnd of mount_drive"
			WHITE
			db		0
			ret

; local variables
.fat_buffer		ds	512
.local_temp1		dd	0
.local_temp2		dd	0
.local_temp3		dd	0
.local_temp4		dd	0

;-------------------------------------------------------------------------------
;	unmount_drive	called when a FD or an SD is removed so it will be totally
;					reloaded on next use as it might be changed
;		call with IX = DRIVE*
;-------------------------------------------------------------------------------
unmount_drive
			xor		a
			ld		[ix+DRIVE.fat_type], a
			ret

;-------------------------------------------------------------------------------
; error handler to use with the ERROR macro
;-------------------------------------------------------------------------------
error_handler
			call	stdio_str
			db		"\r\n\n"
			RED
			db		"Error number: ",0
			call	stdio_decimalB
			call	stdio_str
			WHITE
			db		"\n", 0
			jp		bad_end
