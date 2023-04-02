;-------------------------------------------------------------------------------
; definitions of data structures used by FAT
;-------------------------------------------------------------------------------

 define MAX_PATH 90			; max length of a long filename

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
idDrive					db		0			; zero or the character ie: 'A' in "A:/"
iPartition				db		0			; partition number

// fat organisation parameters
fat_type				db		0			; FAT type
partition_begin_sector	dd		0			; first sector of the partition (must be zeroed)
fat_size				dd		0			; how many sectors in a FAT
fat_count				db		0			; number of FATs, usually 2
sector_to_cluster_slide	db		0			; convert sectors to clusters by slide not multiply
sectors_in_cluster_mask	db		0			; remainder of sector % sectors_per_cluster
fat_begin_sector		dd		0			; first sector of first FAT
root_dir_first_sector	dd		0			; first sector of root directory
root_dir_entries		dw		0			; number of entries in root directory, zero for FAT32
cluster_begin_sector	dd		0			; first sector of data area
count_of_clusters		dd		0			; number of data clusters

// fat management storage
last_fat_sector			dd		0			; FAT sector currently in buffer
fat_dirty				db		0			; needs to be written
fat_free_speedup		dd		0			; cluster where we last found free space
cwd						ds		MAX_PATH*2	; WIDE CHARS current working directory
fatPrefix				ds		1			; used to speed up FAT12 must be the bytes before the table
fatTable				ds		512			; sector of fat information
fatSuffix				ds		1			; only there to get overwritten
	ends

; display "size of DRIVE: ", /D, DRIVE
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

; a directory entry used for a long name
	struct DIRL
LDIR_Ord				db		0		; 0  Ordinal masked with 0x40 is the final one
LDIR_Name1				ds		10		; 1  first 5 wide characters
LDIR_attr				db		0		; 11 0x0f for a file name 0x3f for a folder name
LDIR_type				db		0		; 12 0
LDIR_ChkSum				db		0		; 13 checksum of the name in the short name
LDIR_Name2				ds		12		; 14 characters 6-11
LDIR_FstClusLO			dw		0		; 26 0
LDIR_Name3				ds		4		; 28 characters 12-13
	ends
	assert DIRL == 32


; This is the directory item
	struct	DIRECTORY
drive					dw		0			; pointer to the drive (ie: partition)
startCluster			dd		0			;
sector					dd		0			; the sector we are working through
sectorinbuffer			dd		0			;
slot					db		0			; next DIRN[] slot
buffer					ds		512			; where we read our directory sectors too
longPath				ds		MAX_PATH*2	; name of our folder
	ends

; a file/folder item
	struct	FILE
drive					dw		0			; pointer to our drive for cluster maths
dirn					ds		DIRN		; copy of our directory entry
startCluster			dd		0			; first cluster on disk
shortnamechecksum		db		0			; used to read longName

; working buffer
sector_in_buffer_abs	dd		0			; first sector of data on disk
sector_in_buffer_file	dd		0			; first sector of data in file
first_sector			dd		0			; first sector of first cluster
first_sector_file		dd		0			; speed up
filePointer				dd		0			; full file pointer
file_dirty				db		0			; buffer needs a flush before reuse

; file functions stuff
open_mode				db		0			; b0=open, b1=read, b2=write
; big things at the end
longName				ds		MAX_PATH*2	; long (real) filename
pathName				ds		MAX_PATH*2	; where we live
buffer					ds		512			; current work in progress sector
	ends

; DIR_Attr bits
 define ATTR_RO		0x01
 define ATTR_HIDE	0x02
 define ATTR_SYS	0x04
 define ATTR_VOL	0x08		// volume id
 define ATTR_DIR	0x10
 define ATTR_ARCH	0x20		// archive
; the other two bits should be zero

; file open_mode bits
 define	FOM_READ		0x01		// read mode
 define	FOM_WRITE		0x02		// write mode
 define FOM_MUSTEXIST	0x04		// file must exist
 define FOM_CLEAN		0x08		// if exists truncate to zero
 define	FOM_APPEND		0x10		// set file pointer to EOF
; internal flags in open_mode
 define FOM_OPEN		0x20		// file is open
 define FOM_DIRTY		0x40		// sector buffer needs writing
 define FOM_DIRDIRTY	0x80		// directory entry needs writing

 define EOF	0xffff
