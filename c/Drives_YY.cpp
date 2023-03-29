//==============================================================================================================
//			DRIVE/PARTITION ORIENTED STUFF
//==============================================================================================================

#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>

#include "FAT_XX.h"
#include "FAT_YY.h"

//=================================================================================================
//
// This file provides
//		YY_DRIVE* YY_MountDrive(uint8_t idDevice)
// which is called with the drive letter and returns a pointer to the shared YY_DRIVE
// to access that file system. The table map[] (below_ interprets the letter to an
// actual physical device.
//
//=================================================================================================

#define N_DRIVES		4		// max drives

// definitions for the various drives
YY_DRIVE	yy_drives[N_DRIVES]{};

// the default device tells us which devices cwd to use
uint8_t	YY_defaultDrive = 'C';

struct MAP {
	uint8_t			id;
	const uint8_t	device[25];
	uint8_t			partition;
} map[] {
	{	'A',	"\\\\.\\A:",			 0 },		// floppy default
	{	'B',	"\\\\.\\B:",			 1 },		// my floppy isn't partitioned
	{	'C',	"\\\\.\\PhysicalDrive2", 0 },		// SD card partition 1
	{	'D',	"\\\\.\\PhysicalDrive2", 1 },		// SD card partition 2
	{	'E',	"\\\\.\\PhysicalDrive2", 2 },		// SD card partition 3
	{	'F',	"\\\\.\\PhysicalDrive2", 3 }		// SD card partition 4
};

//-------------------------------------------------------------------------------------------------
// Read the  partition definitions et al.
// That is in sector 0 of the SD card but floppies normally don't do partitions so beware...
//-------------------------------------------------------------------------------------------------
struct BOOT_SECTOR {
	uint8_t jmp[3];
	uint8_t test[8];					// if this says "MSDOS5.0" think floppy with no partition table
	uint8_t	fill[435];					// this is where the 'boot' code goes
	struct PARTITION {					// partition table
			uint8_t		BootFlag;
			uint24_t	CHS_Begin;
			uint8_t		Type_Code;
			uint24_t	CHS_End;
			uint32_t	LBA_Begin;
			uint32_t	nSectors;
	} Partitions[4];
	uint8_t sig1;
	uint8_t sig2;
};
//-------------------------------------------------------------------------------------------------
// read the boot sector
// return 0==error, 1=it read OK but this is not a partition table, 2 = good partition stuff
//--------------------------------------------------------------------------------------------------
static int ReadBootSector(HANDLE hDevice, BOOT_SECTOR* boot)
{
	assert(sizeof BOOT_SECTOR==512);

	if(!XX_ReadSector(hDevice, 0, (LPVOID)boot)) return false;
//	dump(boot, 512);
	if(boot->sig1!=0x55 || boot->sig2!=0xaa){
		printf("Bad signature in BOOT SECTOR.  ");
		return 0;								// return error
	}
	// If this is a Micro$oft formatted floppy or small device it (usually) has a signature in
	// what is blank space that implies we are straight into what is 'partition' one
	if(memcmp(boot->test, "MSDOS5.0", 8)==0)
		return 1;								// OK but not a partition table

	if(bVerbose){
		const char* mbr[] = { "Empty", "FAT12", "02", "0x03", "FAT16", "05", "FAT16B", "07", "FAT-L", "09", "0a", "FAT32-CHS", "FAT32-LBA" };
		for(int i=0; i<4; ++i){
			auto p = boot->Partitions[i];
			if(p.Type_Code<=12)
				printf("Partition %d, Boot: %s, Type: %9s, CHS-Begin: %10" PRIu32 ", CHS-End: %10" PRIu32 ", LBA-Begin: %10" PRIu32 ", LBA-nSectors: %10" PRIu32 "\n",
							i+1, p.BootFlag?"true":"false", mbr[p.Type_Code], p.CHS_Begin.get(), p.CHS_End.get(), p.LBA_Begin, p.nSectors);
			else
				printf("Partition %d, Boot: %s, Type: %9x, CHS-Begin: %10" PRIu32 ", CHS-End: %10" PRIu32 ", LBA-Begin: %10" PRIu32 ", LBA-nSectors: %10" PRIu32 "\n",
							i+1, p.BootFlag?"true":"false", p.Type_Code, p.CHS_Begin.get(), p.CHS_End.get(), p.LBA_Begin, p.nSectors);
		}
	}
	return 2;									// OK partition data
}
//-------------------------------------------------------------------------------------------------
// MountDrive() aka Read the FAT12/16/32 partition first sector
//-------------------------------------------------------------------------------------------------

// I experimented with more readable names but it makes it a lot easier to read the Microsoft documentation keeping their mangled 14 character names
struct FAT_VOL_ID {
	uint8_t		BS_jmpBoot[3];					// 0
	uint8_t		BS_OEMName[8];					// 3
	uint16_t	BPB_BytsPerSec;					// 11 Bytes per Sector, normally 512 but could be 512,1024,2048, 4096
	uint8_t		BPB_SecPerClus;					// 13 Sectors per Cluster, always a power of two (1,2,4...128)
	uint16_t	BPB_RsvdSecCnt;					// 14 Number of Reserved Sectors, if none needed is used to pad the data area start to a cluster
	uint8_t		BPB_NumFATs;					// 16 Number of FATs, always 2 although 1 is officially allowed
	uint16_t	BPB_RootEntCnt;					// 17 number of entries in root dir, FAT12/16 only with fixed root directory
	uint16_t	BPB_TotSec16;					// 19 total sectors, FAT12/16 only
	uint8_t		BPB_Media;						// 21 Media type
	uint16_t	BPB_FATSz16;					// 22 SectorPer FAT 12/16
	uint16_t	BPB_SecPerTrk;					// 24 Sectors Per Track, only relevant to devices that care
	uint16_t	BPB_NumHeads;					// 26 Number of heads, ditto
	uint32_t	BPB_HiddSec;					// 28 zero
	uint32_t	BPB_TotSec32;					// 32 number of sectors, FAT32 only
	union{
		// FAT12/16 version
		struct{
			uint8_t		BS_DrvNum;				// 36
			uint8_t		BS_Reserved1;			// 37
			uint8_t		BS_BootSig;				// 38
			uint32_t	BS_VolID;				// 39
			uint8_t		BS_VolLab[11];			// 43
			uint8_t		BS_FilSysType[8];		// 54
			uint8_t		fill1[448];				// 62
		};
		// FAT32 version
		struct{
			uint32_t	BPB_FATSz32;			// 36 Sectors Per FAT
			uint16_t	BPB_ExtFlags;			// 40
			uint16_t	BPB_FSVer;				// 42 must be zero
			uint32_t	BPB_RootClus;			// 44 Root Directory First Cluster
			uint16_t	BPB_FSInfo;				// 48
			uint16_t	BPB_BkBootSec;			// 50 0 or 6
			uint8_t		BPB_Reserved[12];		// 52 zeros
			uint8_t		BS_DrvNum32;			// 64 (name not Microsoft due to duplication in FAT12/16)
			uint8_t		BS_Reserved1_32;		// 65 (ditto)
			uint8_t		BS_BootSig32;			// 66 (ditto)
			uint32_t	BS_VolID32;				// 67 (ditto)
			uint8_t		BS_VolLab32[11];		// 71 (ditto)
			uint8_t		BS_FilSysType32[8];		// 82 (ditto)
			uint8_t		fill2[420];				// 90
		};
	};
	uint8_t		sig1;							// 510 0x55
	uint8_t		sig2;							// 511 0xaa
};


// convert division by n where n is a power of two into >>m (which is far more Z80 friendly)
static uint8_t toSlide(uint8_t n)
{
	int i = -1;
	while(n){
		++i;
		n >>= 1;
	}
	return i;
}
YY_DRIVE* YY_MountDrive(uint8_t idDevice)
{
	assert(sizeof FAT_VOL_ID==512);

	// are they asking for a device we already have?
	int n;						// index for devices
	for(n=0; n<N_DRIVES; ++n)
		if(yy_drives[n].idDrive==idDevice)
			return &yy_drives[n];
	// w need a new one: find an empty slot
	YY_DRIVE *drive = nullptr;
	for(n=0; n<N_DRIVES; ++n)
		if(yy_drives[n].idDrive==0){
			drive = &yy_drives[n];
			break;
		}
	if(drive==nullptr) return nullptr;		// run out of drive slots

	// we have a slot but does the request make sense?
	// check if we have a definition for this in as map[]
	int m;							// index for maps
	for(m=0; m < _countof(map); ++m)
		if(map[m].id==idDevice)
			break;
	if(m==_countof(map)) return nullptr;	// unknown device

	// OK but does it exist now?
	// ie: is there a disk in the drive of a card in the slot?
	drive->hDevice = XX_OpenDevice((char*)map[m].device);
	if(drive->hDevice == INVALID_HANDLE_VALUE){
		// error message for Windows technology demonstrator
		printf("Open failed.  ARE YOU IN ADMINISTRATOR MODE? ARE YOU USING 'THE RIGHT' ADAPTER?\n");
		error();
		return nullptr;
	}

	BOOT_SECTOR* boot = (BOOT_SECTOR*)drive->fatTable;	// I can use this as it isn't needed yet
	bool bNoPartitions{};								// set if there is no partition table and this is sector zero

	int res = ReadBootSector(drive->hDevice, boot);		// what sort of boot sector do we have?
	if(res==0){					// 0 = error
		printf("Read Error on sector 0\n");
		return nullptr;
	}
	if(res==1 && map[m].partition){	// 1 = start of a partition not a partition list
		printf("Device is not partitioned but partition %u was requested\n", map[m].partition+1);
		return nullptr;
	}
	if(map[m].partition>3){			// 2 = contains a partition list
		printf("Partition %u was requested\n", map[m].partition+1);
		return nullptr;
	}

	if(res==2){		// if partitioned
		drive->partition_begin_sector = boot->Partitions[map[m].partition].LBA_Begin;
		BOOT_SECTOR::PARTITION *p = &boot->Partitions[map[m].partition];
		if(p->Type_Code!=0x01 && p->Type_Code!=0x04 && (p->Type_Code!=0x0c)){
			printf("Partition %d not FAT12/16/32\n", map[m].partition+1);
			return nullptr;
		}
	}
	else		//  res!=2
		drive->partition_begin_sector = 0;

	// Now we are setting up a FAT
	FAT_VOL_ID* volID = (FAT_VOL_ID*)drive->fatTable;	// finished with boot so reuse the buffer

	if(!XX_ReadSector(drive->hDevice, drive->partition_begin_sector, volID)){
		printf("Failed to read sector %u for partition ID\n", drive->partition_begin_sector);
		return nullptr;
	}

	if(volID->sig1!=0x55 || volID->sig2!=0xaa){
		printf("Bad signature in FAT_VOL_ID\n");
		return nullptr;
	}
	// I assume this all over the place so check it now
	if(volID->BPB_BytsPerSec!=512){
		printf("Bytes per sector not 512\n");
		return nullptr;
	}

	// OK we're committed to this partition, put the details in the drive
	drive->idDrive = idDevice;		// 'A' or such

	// We need to determine the FAT type from the data.
	// The Microsoft specification tells us how to do it by cluster count
	uint32_t RootDirSectors = ((volID->BPB_RootEntCnt * 32) + (volID->BPB_BytsPerSec - 1)) / volID->BPB_BytsPerSec;	// zero for FAT32
	if(volID->BPB_FATSz16 != 0)
		drive->fat_size = volID->BPB_FATSz16;
	else
		drive->fat_size = volID->BPB_FATSz32;
	uint32_t TotSec;					// total sectors
	if(volID->BPB_TotSec16 != 0)
		TotSec = volID->BPB_TotSec16;
	else
		TotSec = volID->BPB_TotSec32;
	uint32_t DataSec = TotSec - (volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size) + RootDirSectors);
	drive->count_of_clusters = DataSec / volID->BPB_SecPerClus;
	if(drive->count_of_clusters < 4085)
		drive->fat_type = FAT12;
	else if(drive->count_of_clusters < 65525)
		drive->fat_type = FAT16;
	else
		drive->fat_type = FAT32;

	// now generate the rest of our working variables
	drive->sectors_to_cluster_right_slide	= toSlide(volID->BPB_SecPerClus);		// divide by a power of two
	drive->sectors_in_cluster_mask			= volID->BPB_SecPerClus-1;				// eg: convert 32 into 31 aka 0x1f to get remainders
	drive->fat_begin_sector					= drive->partition_begin_sector + volID->BPB_RsvdSecCnt;
	drive->root_dir_first_sector			= drive->partition_begin_sector + volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size);
	drive->root_dir_entries					= volID->BPB_RootEntCnt;
	drive->cluster_begin_sector				= drive->partition_begin_sector + volID->BPB_RsvdSecCnt + (volID->BPB_NumFATs * drive->fat_size) + RootDirSectors;

	drive->cwd[0] = drive->idDrive;	drive->cwd[1] = L':';	drive->cwd[2] = L'/';	drive->cwd[3] = 0;
	drive->last_fat_sector	 = 0xfffffff;		// we have nothing in the fatTable buffer
	drive->fat_dirty		 = false;			// so it doesn't need writing
	drive->fat_free_speedup	 = 0;				// and we have no idea yet where the spaces are

	if(bVerbose){
		const char* flist[] = { "0", "12", "16", "32" };
		printf("FAT%s\n", flist[drive->fat_type]);
		printf("Partition:  %d\n", map[m].partition+1);
		printf("Byte/Sec:   %u\n", volID->BPB_BytsPerSec);
		printf("Partition begin sector: %u\n", drive->partition_begin_sector);
		printf("Sectors per FAT:  %u\n", drive->fat_size);
		printf("Total cluster for data: %u\n", drive->count_of_clusters);
		printf("Sectors per Cluster:  %u  shift: %u  mask: 0x%02x\n", volID->BPB_SecPerClus, drive->sectors_to_cluster_right_slide, drive->sectors_in_cluster_mask);
		printf("Reserved Sectors:  %u\n", volID->BPB_RsvdSecCnt);
		printf("Number of FATS:  %d\n", volID->BPB_NumFATs);
		printf("Root Directory first sector:  %u\n", drive->root_dir_first_sector);
		printf("fat_begin_sector:  %" PRIu32 "\n", drive->fat_begin_sector);
		printf("cluster_begin_sector:  %" PRIu32 "\n", drive->cluster_begin_sector);
		printf("Root Directory first sector:  %u\n", drive->root_dir_first_sector);
		printf("Root Directory entries:  %u\n", drive->root_dir_entries);
		uint8_t temp[MAX_PATH];
		printf("CWD: %s\n\n", (char*)YY_ToNarrow(temp, sizeof temp, drive->cwd));
	}
	return drive;
}