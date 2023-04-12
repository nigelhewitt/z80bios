;===============================================================================
;
;	fat-drive.asm		The code that understands FAT and disk systems
;
; Important Contributions:
;		get_drive		call with drive letter in A and returns IX=DRIVE*
;		mount_drive		call with IX = DRIVE* to mount (if not already mounted)
;		unmount drive	call with IX = DRIVE* if the FD or SD mich be changed
;
;===============================================================================

fat_drive_start	equ	$

fat_report	equ	0			; chatty mode

; We call these routines
; I need to wrap them so we can do SD or FDD based on DRIVE.iDrive later

; call with DRIVE* in IX

media_init	push	ix, iy
			ld		iy, SD_CFGTBL
			call	SD_INIT
			pop		iy, ix
			ret

media_seek	push	ix, iy
			ld		iy, SD_CFGTBL
			call	SD_SEEK
			pop		iy, ix
			ret

media_read	push	ix, iy
			ld		iy, SD_CFGTBL
			call	SD_READ
			pop		iy, ix
			ret

media_write	push	ix, iy
			ld		iy, SD_CFGTBL
			call	SD_WRITE
			pop		iy, ix
			ret

;-------------------------------------------------------------------------------
; init_drive	Initialise the drives
;				set the drive_letter, hardware_type and partition_number
;				since these value never change this can be done repeatedly
;	uses nothing
;-------------------------------------------------------------------------------
drive_init	push	bc, de, hl, ix, af
			ld		ix, local.ADRIVE		; pointer to first DRIVE
			ld		hl, .init_data			; data to apply
			ld		b, nDrive				; number of drives
.di1		ld		a, [hl]
			inc		hl
			ld		[ix+DRIVE.idDrive], a	; set drive letter eg: 'C'
			ld		a, [hl]
			inc		hl
			ld		[ix+DRIVE.hwDrive], a	; set hardware type 0=SD, 1=FDD
			ld		a, [hl]
			inc		hl
			ld		[ix+DRIVE.iPartition], a	; set partition number 0-3
			ld		de, DRIVE
			add		ix, de
			djnz	.di1
			pop		af, ix, hl, de, bc
			ret

.init_data	db		'A', HW_FD, 0
			db		'C', HW_SD, 0
			db		'D', HW_SD, 1
nDrive		equ		($-.init_data)/3	; number of drives

;-------------------------------------------------------------------------------
; get_drive	convert Drive code letter in A currently 'A','C' or 'D'
;			returns IX set to DRIVE* and CY or IX=0 and NC
;-------------------------------------------------------------------------------
get_drive	push	bc, de, hl
			call	drive_init			; fill in letters, HW and partitions
			ld		b, nDrive			; number of drives
			ld		hl, local.ADRIVE	; pointer to first DRIVE
			ld		de, DRIVE			; size of a DRIVE
.gd1		ld		ix, hl
			cp		[ix+DRIVE.idDrive]	; test the id letter
			jr		z, .gd2				; match
			add		hl, de				; move to next DRIVE
			djnz	.gd1
			ld		ix, 0				; not found so fail
			xor		a
			jr		.gd3

.gd2		scf							; drive exists even if not mounted
.gd3		pop		hl, de, bc
			ret

;-------------------------------------------------------------------------------
; Read the boot sector from the drive and decide if it contains a partition
; table or if it is a one partition drive and this is a volume header.
; If it has a partition table use iPartion to load the required one and load
; its Volume header.
; 	call with IX as a blank DRIVE* to fill in with the idDrive, hwDrive and
; iPartion values set
;	returns NC is no such partition or no hardware
;	uses A
;-------------------------------------------------------------------------------

mount_drive
; is this DRIVE already initialised?
			ld		a, [ix+DRIVE.fat_type]
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
			push	bc, de, hl, iy
			call	media_init		; IX = DRIVE* with hwDrive set
			ERROR	nz, 1			; media_init failed in mount_drive

; seek to sector 0
			ld		de, 0
			ld		hl, 0
			call	media_seek			; IX*=drive, DE:HL=sector number
			jp		nz, .rb20			; fail soft

; read the boot sector (read into fatTable as we aren't using it yet)
			ld		hl, ix				; DRIVE*
			ld		bc, DRIVE.fatTable	; pointer to fatTable
			add		hl, bc
			ld		e, 1
			call	media_read			; IX=DRIVE*, HL=address, E=sectors
			jp		nz, .rb20			; fail soft

; basic confidence test (works for both BOOT or VOLUME)
			ld		hl, ix
			ld		bc, DRIVE.fatTable + BOOT.sig1
			add		hl, bc				; pointer to sig1
			ld		a, [hl]
			cp		0x55
			ERROR	nz, 4				; bad sig in BOOT0 in mount_drive
			inc		hl
			ld		a, [hl]
			cp		0xaa
			ERROR	nz, 4				; bad sig in BOOT0 in mount_drive

; is it a VOLUME?
			ld		hl, 0		; if it's a volume set it as the beginning
			ld		[ix+DRIVE.partition_begin_sector], hl
			ld		[ix+DRIVE.partition_begin_sector+2], hl

; it's hardly definitive but if it has "MSDOS5.0" in BootTest it is a VOLUME
			ld		hl, ix
			ld		bc, DRIVE.fatTable + BOOT.BootTest
			add		hl, bc
			ld		b, 8
			ld		de, .testsig
.rb1		ld		a, [de]
			cp		[hl]
			jr		nz, .rb2			; fail
			inc		hl
			inc		de
			djnz	.rb1
			jp		.rb7				; do this sector as a volume
.rb2
; right time to extract the partition's important bits
; point IY to the PARTITION
			ld		a, [ix+DRIVE.iPartition]	; requested partition 0-3
			cp		4
			ERROR	nc, 5		; bad partition requested in mount_drive

			ld		hl, ix
			ld		de, DRIVE.fatTable + BOOT.Partition1
			add		hl, de
			ld		iy, hl

			sla		a		; *= 16 aka sizeof PARTITION (3*16=48 so byte)
			sla		a
			sla		a
			sla		a
			ld		e, a
			ld		d, 0
			add		iy, de				; point IY to partition

; get the type or error out
; (we will redo this later based on cluster count, this is to kick out non-FAT)
			ld		a, [iy+PARTITION.TypeCode]
			or		a
			jp		z, .rb20		; no such partition
			cp		FAT12
			jr		z, .rb6
			cp		FAT16
			jr		z, .rb6
			cp		FAT32
			ERROR	nz, 6				; FAT type byte not recognised in mount_drive
.rb6		ld		[ix+DRIVE.fat_type], a

; get the starting cluster
			ld		hl, [iy+PARTITION.LBA_Begin]
			ld		[ix+DRIVE.partition_begin_sector], hl
			ld		de, [iy+PARTITION.LBA_Begin+2]
			ld		[ix+DRIVE.partition_begin_sector+2], de

; time to read the VOLUME into DRIVE.fatTable
			call	media_seek		; IX=DRIVE*, DE:HL=sector address
			ERROR	nz, 7			; media_seek failed in mount_drive

			ld		hl, ix			; DRIVE*
			ld		de, DRIVE.fatTable
			add		hl, de
			ld		e, 1
			call	media_read		; IX*=DRIVE, HL=buffer, E=sector count
			ERROR	nz, 8			; media_read failed in mount_drive

; checks on a VOLUME
			ld		hl, ix
			ld		de, DRIVE.fatTable + VOLUME32.sig1
			add		hl, de
			ld		a, [hl]
			cp		0x55
			ERROR	nz, 9			; bad sig in VOLUME in mount_drive
			inc		hl
			ld		a, [hl]
			cp		0xaa
			ERROR	nz, 9			; bad sig in VOLUME in mount_drive

; process the data out of the volume
; NB: we jump to here is the BOOT isn't a boot
.rb7		ld		hl, ix
			ld		de, DRIVE.fatTable
			add		hl, de
			ld		iy, hl

; first ensure we are 512bytes/sector
			ld		a, [iy+VOLUME32.BPB_BytsPerSec]
			or		a
			ERROR	nz, 10		; 512 bytes/sector check failed in mount_drive
			ld		a, [iy+VOLUME32.BPB_BytsPerSec+1]
			cp		2			; aka 512>>8
			ERROR	nz, 10		; 512 bytes/sector check failed  in mount_drive

; Process the BPB_SecPerClus into a slide and a mask
; this number is a power of 2 so 1,2,4...128
; since I need to multiply and divide by it a lot and take remainders that
; is done with a slide and a mask
			ld		a, [iy+VOLUME32.BPB_SecPerClus]		; 1...128
			ld		de, 0								; D=slide, E=mask
.rb8		srl		a				; slide into CY
			jr		c, .rb9			; we have the bit
			inc		d
			scf
			sll		e
			jr		.rb8

.rb9		or		a				; a check, they promise a multiple of two
			ERROR	nz, 25			; sectors/cluster bad number
			ld		[ix+DRIVE.sector_to_cluster_slide], d
			ld		[ix+DRIVE.sectors_in_cluster_mask], e

; determine FAT size (if FAT12/16 is set use it)
			ld		de, 0
			ld		hl, [iy+VOLUME12.BPB_FATSz16]
			ld		a, h
			or		l
			jr		nz, .rb10
			ld		de, [iy+VOLUME32.BPB_FATSz32+2]
			ld		hl, [iy+VOLUME32.BPB_FATSz32]
.rb10		ld		[ix+DRIVE.fat_size], hl
			ld		[ix+DRIVE.fat_size+2], de

; we now need to generate the count_of_clusters value
; but that involves some transient numbers so they go in .local_temp
; total sectors (local)

; if BPB_TotSec16 is set use it else use BPB_TotSec32
			ld		de, 0
			ld		hl, [iy+VOLUME12.BPB_TotSec16]
			ld		a, h
			or		l
			jr		nz, .rb11
			ld		de, [iy+VOLUME32.BPB_TotSec32+2]
			ld		hl, [iy+VOLUME32.BPB_TotSec32]
.rb11		ld		[.local_total_sectors], hl		; TotSec -> local_total_sectors
			ld		[.local_total_sectors+2], de

; local RootDirSectors = ((volID->BPB_RootEntCnt * 32) + (volID->BPB_BytsPerSec - 1)) / volID->BPB_BytsPerSec;
			ld		de, 0
			ld		hl, [iy+VOLUME12.BPB_RootEntCnt]
			ld		b, 5
.rb12		or		a				; clear carry
			rl		l
			rl		h
			rl		e
			rl		d
			djnz	.rb12
			ld		bc, 511
			add		hl, bc
			ld		b, 9			; divide by 512
.rb13		or		a				; clear carry
			srl		h
			rr		l
			djnz	.rb13
			ld		[.local_root_dir_sectors], hl	; b16*32/512 can't be more than 4096

; local DataSec = TotSec - (volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size) + RootDirSectors);
			ld		b, [iy+VOLUME32.BPB_NumFATs]	; actually 1 or 2
			ld		hl, 0
			ld		de, 0
.rb14		push	bc
			ld		bc, [ix+DRIVE.fat_size]
			add		hl, bc
			ld		bc, [ix+DRIVE.fat_size+2]
			adc		de, bc
			pop		bc
			djnz	.rb14
			ld		bc, [.local_root_dir_sectors]	; + RootDirSectors
			add		hl, bc
			ld		bc, 0
			sbc		de, bc

			ld		bc, [iy+VOLUME32.BPB_RsvdSecCnt]
			add		hl, bc
			ld		bc, 0
			ex		hl, de
			adc		hl, bc
			ex		hl, de
			ld		[.local_temp3], hl				; save the item to subtract
			ld		[.local_temp3+2], de

			ld		hl, [.local_total_sectors]		; TotSec
			ld		de,	[.local_total_sectors+2]
			ld		bc, [.local_temp3]				; get DataSec
			sub		hl, bc
			ld		bc, [.local_root_dir_sectors+2]
			sbc		de, bc

; drive->count_of_clusters = DataSec / volID->BPB_SecPerClus;
			ld		b, [ix+DRIVE.sector_to_cluster_slide]
			ld		a, b
			or		a
			jr		z, .rb16
.rb15		srl		d
			rr		e
			rr		h
			rr		l
			djnz	.rb15
.rb16		ld		[ix+DRIVE.count_of_clusters], hl
			ld		[ix+DRIVE.count_of_clusters+2], de

; and now we get the FAT type based on the Microsoft rules
			CP32n	4085
			ld		a, FAT12
			jr		c,	.rb17		; FAT12
			CP32n	65525
			ld		a, FAT16
			jr		c, .rb17		; FAT16
			ld		a, FAT32
.rb17		ld		[ix+DRIVE.fat_type], a

; drive->root_dir_entries = volID->BPB_RootEntCnt;
			ld		hl, [iy+VOLUME32.BPB_RootEntCnt]
			ld		[ix+DRIVE.root_dir_entries], hl

; drive->fat_begin_sector = drive->partition_begin_sector + volID->BPB_RsvdSecCnt;
			ld		hl, [ix+DRIVE.partition_begin_sector]
			ld		de, [ix+DRIVE.partition_begin_sector+2]
			ld		bc, [iy+VOLUME32.BPB_RsvdSecCnt]
			add		hl, bc
			ld		bc, 0
			adc		de, bc
			ld		[ix+DRIVE.fat_begin_sector], hl
			ld		[ix+DRIVE.fat_begin_sector+2], de

; drive->root_dir_first_sector = drive->partition_begin_sector
;				+ volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size);
; well we have the first part in DE:HL already
			ld		b, [iy+VOLUME32.BPB_NumFATs]	; sometimes 1 normally 2
			ld		[ix+DRIVE.fat_count], b
.rb19		push	bc
			ld		bc, [ix+DRIVE.fat_size]
			add		hl, bc
			ld		bc, [ix+DRIVE.fat_size+2]
			adc		de, bc
			pop		bc
			djnz	.rb19
			ld		[ix+DRIVE.root_dir_first_sector], hl
			ld		[ix+DRIVE.root_dir_first_sector+2], de

; drive->cluster_begin_sector = drive->partition_begin_sector
;		+ volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size)
;		+ RootDirSectors;
;	so just add .local_root_dir_sectors ro our current DE:HL
			ld		bc, [.local_root_dir_sectors]
			add		hl, bc
			ld		bc, 0
			adc		de, bc
			ld		[ix+DRIVE.cluster_begin_sector], hl
			ld		[ix+DRIVE.cluster_begin_sector+2], de

; drive->cwd[0] = drive->idDrive;	drive->cwd[1] = L':';	drive->cwd[2] = L'/';	drive->cwd[3] = 0;
			ld		l, [ix+DRIVE.idDrive]		; need this in WCHAR
			ld		h, 0
			ld		[ix+DRIVE.cwd], hl
			ld		l, ':'
			ld		[ix+DRIVE.cwd+2], hl
			ld		l, '/'
			ld		[ix+DRIVE.cwd+4], hl
			ld		l, 0
			ld		[ix+DRIVE.cwd+6], hl

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
			pop		iy, hl, de, bc
			scf
			ret

; soft fail (no drive or partition)
.rb20		pop		iy, hl, de, bc
			or		a
			ret

; local constants
.testsig	db	"MSDOS5.0"			; used to id a value

; local variables
.local_total_sectors	dd	0
.local_root_dir_sectors	dd	0
.local_temp3			dd	0

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

.dead		di
;			halt
;			jr		.dead
			jp		bad_end

 if SHOW_MODULE
	 	DISPLAY "fat_drive size: ", /D, $-fat_drive_start
 endif
