;===============================================================================
;
;	fat.asm		The code that understands FAT and disk systems
;
;===============================================================================

fat_report	equ	1			; chatty mode

; This uses the routines
; later I shall wrap them so we can do SD or FDD based on DRIVE.iDrive

fathw_init	push	iy
			call	SD_INIT
			pop		iy
			ret
fathw_seek	push	iy
			ld		iy, SD_CFGTBL
			call	SD_SEEK		; to DE:HL
			pop		iy
			ret
fathw_read	push	iy
			ld		iy, SD_CFGTBL
			call	SD_READ		; HL = buffer, E=block count
			pop		iy
			ret
fathw_write	push	iy
			ld		iy, SD_CFGTBL
			call	SD_WRITE
			pop		iy
			ret

; "M"
f_readsector	; passed in sector BC:HL to address DE
			SNAP	"init"
			push	de, bc, hl
			call	stdio_str
			db		"\r\nSD Started", 0
			call	SD_INIT
			call	stdio_str
			db		"\r\nInitialisation Finished", 0
			pop		hl
			pop		de
			SNAP	"seek"
			call	SD_SEEK		; to DE:HL
			call	stdio_str
			db		"\r\nSeek Finished", 0
			pop		hl
			ld		e, 1
			SNAP	"read"
			call	SD_READ		; HL = buffer, E=block count
			SNAP	"end"
			call	stdio_str
			db		"\r\nRead Finished", 0
			jp		good_end

; "Z"
f_spi_test
			ld		a, 'C'
			ld		[iy+DRIVE.idDrive], a
			ld		iy, test_drive
			ld		a, 0
			ld		[iy+DRIVE.iPartition], a

			call	mount_drive
			jp		good_end


;-------------------------------------------------------------------------------
; definitions of data structures used by FAT
;-------------------------------------------------------------------------------

; a partition entry in the boot record (0) of a drive
	struct	PARTITION
BootFlag	db		0
CHS_Begin	d24		0
TypeCode	db		0
CHS_End		d24		0
LBA_Begin	dd		0
nSectors	dd		0
	ends
	assert PARTITION == 16		; a size check

; the whole boot sector including 4 partitions
	struct	BOOT
			ds		3
BootTest	ds		8
			ds		435
Partition1	PARTITION
Partition2	PARTITION
Partition3	PARTITION
Partition4	PARTITION
sig1		db		0
sig2		db		0
	ends
	assert BOOT == 512

; volume records one for FAT12/16 and one for FAT32

	struct	VOLUME12
BS_jmpBoot		ds		3				; 0
BS_OEMName		ds		8				; 3
BPB_BytsPerSec	dw		0				; 11 Bytes per Sector, normally 512 but could be 512,1024,2048, 4096
BPB_SecPerClus	db		0				; 13 Sectors per Cluster, always a power of two (1,2,4...128)
BPB_RsvdSecCnt	dw		0				; 14 Number of Reserved Sectors, if none needed is used to pad the data area start to a cluster
BPB_NumFATs		db		0				; 16 Number of FATs, always 2 although 1 is officially allowed
BPB_RootEntCnt	dw		0				; 17 number of entries in root dir, FAT12/16 only with fixed root directory
BPB_TotSec16	dw		0				; 19 total sectors, FAT12/16 only
BPB_Media		db		0				; 21 Media type
BPB_FATSz16		dw		0				; 22 SectorPer FAT 12/16
BPB_SecPerTrk	dw		0				; 24 Sectors Per Track, only relevant to devices that care
BPB_NumHeads	dw		0				; 26 Number of heads, ditto
BPB_HiddSec		dd		0				; 28 zero
BPB_TotSec32	dd		0				; 32 number of sectors, FAT32 only

BS_DrvNum		db		0				; 36
BS_Reserved1	db		0				; 37
BS_BootSig		db		0				; 38
BS_VolID		dd		0				; 39
BS_VolLab		ds		11				; 43
BS_FilSysType	ds		8				; 54
fill1			ds		448				; 62

sig1			db		0				; 510 0x55
sig2			db		0				; 511 0xaa
	ends
	assert VOLUME12 == 512

	struct	VOLUME32
BS_jmpBoot		ds		3				; 0
BS_OEMName		ds		8				; 3
BPB_BytsPerSec	dw		0				; 11 Bytes per Sector, normally 512 but could be 512,1024,2048, 4096
BPB_SecPerClus	db		0				; 13 Sectors per Cluster, always a power of two (1,2,4...128)
BPB_RsvdSecCnt	dw		0				; 14 Number of Reserved Sectors, if none needed is used to pad the data area start to a cluster
BPB_NumFATs		db		0				; 16 Number of FATs, always 2 although 1 is officially allowed
BPB_RootEntCnt	dw		0				; 17 number of entries in root dir, FAT12/16 only with fixed root directory
BPB_TotSec16	dw		0				; 19 total sectors, FAT12/16 only
BPB_Media		db		0				; 21 Media type
BPB_FATSz16		dw		0				; 22 SectorPer FAT 12/16
BPB_SecPerTrk	dw		0				; 24 Sectors Per Track, only relevant to devices that care
BPB_NumHeads	dw		0				; 26 Number of heads, ditto
BPB_HiddSec		dd		0				; 28 zero
BPB_TotSec32	dd		0				; 32 number of sectors, FAT32 only

BPB_FATSz32		dd		0				; 36 Sectors Per FAT
BPB_ExtFlags	dw		0				; 40
BPB_FSVer		dw		0				; 42 must be zero
BPB_RootClus	dd		0				; 44 Root Directory First Cluster
BPB_FSInfo		dw		0				; 48
BPB_BkBootSec	dw		0				; 50 0 or 6
BPB_Reserved	ds		12				; 52 zeros
BS_DrvNum		db		0				; 64
BS_Reserved1	db		0				; 65
BS_BootSig		db		0				; 66
BS_VolID		dd		0				; 67
BS_VolLab		ds		11				; 71
BS_FilSysType	ds		8				; 82
fill2			ds		420				; 90

sig1			db		0				; 510 0x55
sig2			db		0				; 511 0xaa
	ends
	assert VOLUME32 == 512

; The structure that contains what we need to know about a DRIVE

; values for fat_type
NOT_FAT		equ		0
FAT12		equ		1
FAT16		equ		4
FAT32		equ		12

; to simplify error handling I have error codes and a macro to test flags
ERROR	macro	FAULT, ERRNO		; test for FAULT and error number
		jr		FAULT, .e1
		jr		.e2
.e1		ld		a, ERRNO
		jp		error_handler
.e2
		endm

	struct	DRIVE
idDrive					db		0		; zero or the character ie: 'A' in "A:/"
iPartition				db		0		; partition number
	// fat organisation parameters
fat_type				db		0		; FAT type
partition_begin_sector	dd		0		; first sector of the partition (must be zeroed)
fat_size				dd		0		; how many sectors in a FAT
fat_count				db		0		; number of FATs, usually 2
sectors_to_cluster_right_slide	db	0	; convert sectors to clusters by slide not multiply
sectors_in_cluster_mask	db		0		; remainder of sector % sectors_per_cluster
fat_begin_sector		dd		0		; first sector of first FAT
root_dir_first_sector	dd		0		; first sector of root directory
root_dir_entries		dw		0		; number of entries in root directory, zero for FAT32
cluster_begin_sector	dd		0		; first sector of data area
count_of_clusters		dd		0		; number of data clusters
	// fat management storage
last_fat_sector			dd		0		; FAT sector currently in buffer
fat_dirty				db		0		; needs to be written
fat_free_speedup		dd		0		; cluster where we last found free space
cwd						ds		200		; WIDE CHARS current working directory
fatPrefix				ds		1		; used to speed up FAT12 must be the bytes before the table
fatTable				ds		512		; sector of fat information
fatSuffix				ds		1		; only there to get overwritten
	ends

 display "size of DRIVE: ", /D, DRIVE
 display "Offset of DRIVE.fatTable: ", /D, DRIVE.fatTable

; A directory entry
	struct	DIRN
DIR_Name				ds		8		; 0  filename	(8.3 style)
DIR_Ext					ds		3		; 8  ext	NVH I added this
DIR_Attr				db		0		; 11 attribute bits
DIR_NTRes				db		0		; 12 0x08 make the name lower case, 0x10 make the extension lower case
DIR_CrtTimeTenth		db		0		; 13 Creation time tenths of a second 0-199
DIR_CrtTime				dw		0		; 14 Creation time, granularity 2 seconds
DIR_CrtDate				dw		0		; 16 Creation date
DIR_LstAccDate			dw		0		; 18 Last Accessed Date
DIR_FstClusHI			dw		0		; 20 high WORD of start cluster (FAT32 only)
DIR_WrtTime				dw		0		; 22 last modification time
DIR_WrtDate				dw		0		; 24 last modification date
DIR_FstClusLO			dw		0		; 26 low WORD of start cluster
DIR_FileSize			dd		0		; 28 file size
	ends
	assert DIRN == 32

;-------------------------------------------------------------------------------
; Read the boot sector from the drive and decide if it contains a partition
; table or if it is a one partition drive and it is a volume header.
; The either process it as a Volume header of load one.
; call with IY pointing to the DRIVE to fill in with the iDrive and
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
; initialise things
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nmount_drive"
			WHITE
			db		0
	endif
			call	fathw_init
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
			call	fathw_seek			; DE:HL
			ERROR	nz, 2
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nseek 0 OK"
			WHITE
			db		0
	endif

; read the boot sector
			ld		hl, fat_buffer
			ld		e, 1
			call	fathw_read
			ERROR	nz, 3
	if	fat_report
			call	stdio_str
			BLUE
			db		"\r\nread 0 OK"
			WHITE
			db		0
	endif

; basic confidence test (works for both BOOT or VOLUME)
			ld		hl, fat_buffer+BOOT.sig1
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
			ld		hl, fat_buffer + BOOT.BootTest
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
			ld		ix, fat_buffer + BOOT.Partition1
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
			ld		ix, fat_buffer + BOOT.Partition1
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
			call	fathw_seek			; DE:HL
			ERROR	nz, 7

	if fat_report
			call	stdio_str
			db		"\r\nRead VOLUME"
			WHITE
			db		0
	endif
			ld		hl, fat_buffer
			ld		e, 1
			call	fathw_read
			ERROR	nz, 8

; checks on a volume
			ld		hl, fat_buffer+BOOT.sig1
			ld		a, [hl]
			cp		a, 0x55
			ERROR	nz, 9
			inc		hl
			ld		a, [hl]
			cp		a, 0xaa
			ERROR	nz, 9

; process the data out of the volume
; NB: we jump to here is the BOOT isn't a boot
.rb7		ld		ix, fat_buffer
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
.rb9		ld		[iy+DRIVE.sectors_to_cluster_right_slide], d
			ld		[iy+DRIVE.sectors_in_cluster_mask], e
	if fat_report
			call	stdio_str
			db		"\r\nSectors per cluster: ",0
			ld		a, [ix+VOLUME32.BPB_SecPerClus]
			call	stdio_decimalB
			call	stdio_str
			db		"  slide: ",0
			ld		a, [iy+DRIVE.sectors_to_cluster_right_slide]
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
; but that involves some transient numbers so they go in local_temp
; total sectors (local)
			ld		de, 0
			ld		hl, [ix+VOLUME12.BPB_TotSec16]
			ld		a, h
			or		l
			jr		nz, .rb11
			ld		de, [ix+VOLUME32.BPB_TotSec32+2]
			ld		hl, [ix+VOLUME32.BPB_TotSec32]
.rb11		ld		[local_temp1], hl				; TotSec -> local_temp1
			ld		[local_temp1+2], de

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
			ld		[local_temp2], hl	; b16*32/512 can't be more than 4096
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

			ld		bc, [local_temp2]				; + RootDirSectors
			add		hl, bc
			ld		bc, 0
			sbc		de, bc

			ld		bc, [ix+VOLUME32.BPB_RsvdSecCnt]
			add		hl, bc
			ld		bc, 0
			ex		hl, de	: adc hl, bc : ex hl, de
			ld		[local_temp3], hl				; save the item to subtract
			ld		[local_temp3+2], de

			ld		hl, [local_temp1]				; TotSec
			ld		de,	[local_temp1+2]
			ld		bc, [local_temp3]				; get DataSec
			sub		hl, bc
			ld		bc, [local_temp2+2]
			sbc		de, bc

; drive->count_of_clusters = DataSec / volID->BPB_SecPerClus;
			ld		b, [iy+DRIVE.sectors_to_cluster_right_slide]
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
			CPDEHL	4085
			jr		nc,	.rb17		; FAT12
			ld		a, FAT16
			CPDEHL	65525
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
;	so just add local_temp2 ro our current DE:HL
			ld		bc, [local_temp2]
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

test_drive		DRIVE
fat_buffer		ds	512
local_temp1		dd	0
local_temp2		dd	0
local_temp3		dd	0
local_temp4		dd	0

