#pragma once
//-------------------------------------------------------------------------------------------------
// a frig to manage 3 byte (24bit) numbers which just don't feature in the C++ game plan
//-------------------------------------------------------------------------------------------------

struct uint24_t {		// it looks more official with a name like this
private:
	uint8_t a[3];		// ls byte first
public:
	uint32_t	get()			{ return  a[0] + (a[1]<<8) + (a[2]<<16); }
	void		set(uint32_t v)	{ a[0] = v&0xff; a[1] = (v>>8)&0xff; a[2] = (v>>16)&0xff; }
};

//=================================================================================================
// Global things we read/deduce when we open a partition.
// Once we have these we can loose the boot sector and the volume ID
//=================================================================================================
enum { UNKNOWN_FAT, FAT12, FAT16, FAT32 };
struct YY_DRIVE {
	HANDLE		hDevice{};								// link to the device
	uint8_t		idDrive{};								// zero or the character ie: 'A' in "A:/"
	uint16_t	cwd[MAX_PATH]{};						// current working directory

	// fat organisation parameters
	uint8_t		fat_type{UNKNOWN_FAT};					// FAT type
	uint32_t	partition_begin_sector{0};				// first sector of the partition (must be zeroed)
	uint32_t	fat_size{};								// how many sectors in a FAT
	uint8_t		sectors_to_cluster_right_slide{};		// convert sectors to clusters by slide not multiply
	uint8_t		sectors_in_cluster_mask{};				// remainder of sector%sectors_per_cluster
	uint32_t	fat_begin_sector{};						// first sector of first FAT
	uint32_t	root_dir_first_sector{};				// first sector of root directory
	uint16_t	root_dir_entries{};						// number of entries in root directory, zero for FAT32
	uint32_t	cluster_begin_sector{};					// first sector of data area
	uint32_t	count_of_clusters;						// number of data clusters
	// fat management storage
	uint8_t		fatPrefix{};							// used to speed up FAT12 must be the bytes before the table
	uint8_t		fatTable[512]{};						// sector of fat information
	uint8_t		fatSuffix{};							// only there to get overwritten
	uint32_t	last_fat_sector{0xffffffff};			// FAT sector currently in buffer
	uint8_t		fat_dirty{};							// needs to be written
	uint32_t	fat_free_speedup{};						// cluster where we last found free space
};

// there are 4 types of directory entry
// Normal, Unused (first byte is 0xe5), End of Directory (first byte is zero), Long Filename text (see later)
struct YY_DIRN {
	uint8_t		DIR_Name[8];			// 0  filename	(8.3 style)
	uint8_t		DIR_Ext[3];				// 8  ext	NVH I added this
	uint8_t		DIR_Attr;				// 11 attribute bits
	uint8_t		DIR_NTRes;				// 12 0x08 make the name lower case, 0x10 make the extension lower case
	uint8_t		DIR_CrtTimeTenth;		// 13 Creation time tenths of a second 0-199
	uint16_t	DIR_CrtTime;			// 14 Creation time, granularity 2 seconds
	uint16_t	DIR_CrtDate;			// 16 Creation date
	uint16_t	DIR_LstAccDate;			// 18 Last Accessed Date
	uint16_t	DIR_FstClusHI;			// 20 high WORD of start cluster (FAT32 only)
	uint16_t	DIR_WrtTime;			// 22 last modification time
	uint16_t	DIR_WrtDate;			// 24 last modification date
	uint16_t	DIR_FstClusLO;			// 26 low WORD of start cluster
	uint32_t	DIR_FileSize;			// 28 file size
};

struct YY_DIRSECT {						// a sector of directory can hold 16 entries
	YY_DIRN entry[16];
};

// This is the directory item
struct YY_DIRECTORY {
	YY_DRIVE*		drive{};				// the drive (ie: partition)
	uint32_t		startCluster{};
	uint32_t		sector{};				// the sector we are working through
	uint32_t		sectorinbuffer{0xffffffff};
	YY_DIRSECT		buffer{};				// where we read our directory sectors too
	uint8_t			slot{};					// next DIRN[] slot
	uint16_t		longPath[MAX_PATH]{};	// name of our folder
};

// a file/folder item
struct YY_FILE {
	YY_DRIVE		*drive{};				// 0 is free, our drive for cluster maths
	YY_DIRN			dirn{};					// copy of our directory entry
	uint32_t		startCluster{};			// first cluster on disk
	uint16_t		longName[MAX_PATH]{};	// long (real) filename
	uint16_t		pathName[MAX_PATH]{};	// where we live
	uint8_t			shortnamechecksum{};	// used to read longName
	// working buffer
	uint32_t		sector_in_buffer_abs{};	// first sector of data on disk
	uint32_t		sector_in_buffer_file{};// first sector of data in file
	uint32_t		first_sector{};			// first sector of first cluster
	uint32_t		first_sector_file{};	// speed up
	uint8_t			buffer[512]{};			// current work in progress sector
	uint32_t		filePointer{};			// full file pointer
	uint8_t			file_dirty{};			// buffer needs a flush before reuse
	// file functions stuff
	uint8_t			open_mode{};			// b0=open, b1=read, b2=write
};
// DIR_Attr bits
#define ATTR_RO		0x01
#define ATTR_HIDE	0x02
#define ATTR_SYS	0x04
#define ATTR_VOL	0x08		// volume id
#define ATTR_DIR	0x10
#define ATTR_ARCH	0x20		// archive
// the other two bits should be zero

// file open_mode bits
#define	FOM_READ		0x01		// read mode
#define	FOM_WRITE		0x02		// write mode
#define FOM_MUSTEXIST	0x04		// file must exist
#define FOM_CLEAN		0x08		// if exists truncate to zero
#define	FOM_APPEND		0x10		// set file pointer to EOF
// internal flags in open_mode
#define FOM_OPEN		0x20		// file is open
#define FOM_DIRTY		0x40		// sector buffer needs writing
#define FOM_DIRDIRTY	0x80		// directory entry needs writing

#define YY_EOF	0xffff

//=================================================================================================
//  Subroutines
//=================================================================================================

// Routine in Drive_YY.cpp
YY_DRIVE*		YY_MountDrive(uint8_t idDevice);

// Routines in Clusters_YY.cpp
uint32_t		YY_ClusterToSector(YY_DRIVE* drive, uint32_t c);
uint32_t		YY_SectorToCluster(YY_DRIVE* drive, uint32_t s);
void			YY_FlushFAT(YY_DRIVE* drive);
uint32_t		YY_GetClusterEntry(YY_DRIVE* drive, uint32_t cluster);
void			YY_SetClusterEntry(YY_DRIVE* drive, uint32_t cluster, uint32_t value);
uint32_t		YY_AllocateCluster(YY_DRIVE* drive);
uint32_t		YY_GetNextSector(YY_DRIVE* drive, uint32_t current_sector);

// Routines/Data in Directories_YY.cpp
extern uint8_t	YY_defaultDrive;
void			YY_AddPath(uint16_t* dest, uint16_t* src);
YY_DIRECTORY*	YY_OpenDirectory(uint16_t* path);
bool			YY_ChangeDirectory(YY_DIRECTORY* dir, uint16_t* path);
void			YY_ResetDirectory(YY_DIRECTORY* dir);

void			YY_CloseDirectory(YY_DIRECTORY* dir);
void			YY_DirFlush(YY_DIRECTORY* dir);
YY_FILE*		YY_NextDirectoryItem(YY_DIRECTORY* dir);
const char*		YY_WriteDirectoryItem(YY_FILE* file, uint8_t* buffer, int cb=0);

// Routines in Files_YY.cpp
YY_FILE*		YY_GetFileSlot();
void			YY_FreeFileSlot(YY_FILE* file);
bool			YY_isDIR(YY_FILE* file);
bool			YY_isFILE(YY_FILE* file);
uint8_t			YY_isOpen(YY_FILE* file);
bool			YY_matchName(YY_FILE* file, uint16_t* name);
YY_FILE*		YY_OpenFile(uint16_t* path, uint8_t mode);
YY_FILE*		YY_OpenFileDirect(YY_FILE* file, uint8_t mode);
void			YY_CloseFile(YY_FILE* file);
uint16_t		YY_getc(YY_FILE* file);

// Routines in Chars_YY.cpp
uint16_t*		YY_ToWide(uint16_t* output, uint16_t cbOut, const uint8_t* input, uint16_t cbIn=0xffff);
uint8_t*		YY_ToNarrow(uint8_t* output, uint16_t cbOut, const uint16_t* input, uint16_t cbIn=0xffff);

// debugs
int YY_Dused();
int YY_Fused();
