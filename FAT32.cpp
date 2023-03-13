// FAT32.cpp : This file contains the 'main' function. Program execution begins and ends there.
//
// including ideas taken from:
//		https://www.pjrc.com/tech/8051/ide/fat32.html

// !!!! Run VS 'as Administrator' so this get run 'as Administrator' too !!!!
// PhysicalDrive2 is a protected thingie


#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>
#include <vector>

#pragma warning( disable: 6387 )

bool bVerbose = true;

//==========================================================================================================================
//										FIRST THE WINDOWS INTERFACE STUFF
//==========================================================================================================================

//------------------------------------------------------------------------------------------------
//	global data for windows code filed in as we progress
//------------------------------------------------------------------------------------------------
HANDLE sd;

struct DIRSTUFF {
	int		 index;
	char	 shortName[20], longName[MAX_PATH+1];
	bool	 directory;
	uint32_t start;
	uint32_t size;
};
std::vector<DIRSTUFF> folder;

//-------------------------------------------------------------------------------------------------
// convert LastError() into readable text
//-------------------------------------------------------------------------------------------------
void error()
{
	DWORD err = GetLastError();
	char errMsg[256];
	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, nullptr, err,
                      MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), errMsg, 255, nullptr);
    OutputDebugString(errMsg);
    printf("Error %u: %s\n", err, errMsg);
}
//-------------------------------------------------------------------------------------------------
// dump in the usual bytes/chars format
//-------------------------------------------------------------------------------------------------
void dump(void* buffer, int cb=512)
{
	uint8_t *buf = (uint8_t*)buffer;
	for(int i=0; i<cb; i+=16){
		int n = cb-i, j;
		if(n>16) n=16;
		printf("%04X ", i);
		for(j=0; j<n; j++)
			printf("%02X ", buf[i+j]);
		for( ;j<16; j++)
			printf("   ");
		printf("   ");
		for(j=0; j<n; j++){
			uint8_t c= buf[i+j];
			if(c<0x20 || c>=0x7f) c = ' ';
			printf("%c ", c);
		}
		printf("\n");
	}
}
//-------------------------------------------------------------------------------------------------
// Open the SD card
//		In my case I have the SSD and the HDD as Physical Drives 0 and 1
//		2 comes and goes as I plug in the USB
//-------------------------------------------------------------------------------------------------
HANDLE OpenSD()
{
	return CreateFile("\\\\.\\PhysicalDrive2", GENERIC_READ | GENERIC_WRITE,
				FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0  /*FILE_FLAG_NO_BUFFERING*/, nullptr);
}
//-------------------------------------------------------------------------------------------------
// Read sector from the SD card
//-------------------------------------------------------------------------------------------------
bool ReadSector(uint32_t sector, void* buffer)
{
	union {						// SetFilePointer works with old DWORD so pack/unpack things
		LONG b[2];
		uint64_t c;
	} a;
	a.c = (uint64_t)sector*512;	// byte address

	if(SetFilePointer(sd, a.b[0], &a.b[1], FILE_BEGIN)==INVALID_SET_FILE_POINTER) return false;
	DWORD nRead;
	// ReadFile at HW level only works on sector size address boundaries and in sector size or multiples blocks
	// for this application no worries.
	// HOWEVER it only works in one of my card holders...
	bool ret = ReadFile(sd, buffer, 512, &nRead, nullptr)!=0	// return not zero on success
		&& nRead == 512;

	if(bVerbose)
		printf("\nRead Sector %lu OK\n", sector);
	return ret;
}
//-------------------------------------------------------------------------------------------------
// Write sector to the SD card
//-------------------------------------------------------------------------------------------------
bool WriteSector(uint32_t sector, void* buffer)
{
	union {						// SetFilePointer works with old DWORD so pack/unpack things
		LONG b[2];
		uint64_t c;
	} a;
	a.c = (uint64_t)sector*512;	// byte address

	if(SetFilePointer(sd, a.b[0], &a.b[1], FILE_BEGIN)==INVALID_SET_FILE_POINTER) return false;
	DWORD nWrite;
	bool ret = WriteFile(sd, buffer, 512, &nWrite, nullptr)!=0	// return not zero on success
		&& nWrite == 512;

	if(bVerbose)
		printf("Write Sector %lu OK\n", sector);
	return ret;
}
//==========================================================================================================================
//											NOW THE FAT32 STUFF
//==========================================================================================================================
#pragma pack(1)			// no adding padding to improve bus speed please Mr. C++
//-------------------------------------------------------------------------------------------------
// Read partition definitions et al.
// That is in sector 0 of the SD card
//-------------------------------------------------------------------------------------------------

// a frig to read 3 byte (24bit) numbers which aren't in the C++ cstdint mindset
struct uint24_t {
	uint8_t a[3];
	uint32_t get(){ return a[0] + (a[1]<<8) + (a[2]<<16); }
	void set(uint32_t v){ a[0] = v&0xff; a[1] = (v>>8)&0xff; a[2] = (v>>16)&0xff; }
};

struct SECTOR0 {
	uint8_t	fill[446];					// this is where the 'boot' code goes
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

bool ReadPartitionTable(SECTOR0* sector0)
{
	assert(sizeof(SECTOR0)==512);

	if(!ReadSector(0, (LPVOID)sector0)) return false;

	if(sector0->sig1!=0x55 || sector0->sig2!=0xaa){
		printf("Bad signature in SECTOR0.  ");
		return false;
	}
	if(bVerbose){
		for(int i=0; i<4; ++i){
			auto p = sector0->Partitions[i];
			printf("Partition %d, Boot: %s, Type: 0x%x, CHS-Begin: %" PRIu32 ", CHS-End: %" PRIu32 ", LBA-Begin: %" PRIu32 ", LBA-nSectors: %" PRIu32 "\n",
						i+1, p.BootFlag?"true":"false", p.Type_Code, p.CHS_Begin.get(), p.CHS_End.get(), p.LBA_Begin, p.nSectors);
		}
	}
	return true;
}
//-------------------------------------------------------------------------------------------------
// Read the FAT32 first sector
//-------------------------------------------------------------------------------------------------

struct FAT32_VOL_ID {
	uint8_t		BS_jmpBoot[3];
	uint8_t		BS_OEMname[8];
	uint16_t	BPB_BytesPerSector;		// Bytes per Sector					0x0b
	uint8_t		BPB_SectorsPerCluster;	// Sectors per Cluster				0x0d	always a power of two (,2,4...128)
	uint16_t	BPB_ReservedSectors;	// Number of Reserved Sectors		0x0e
	uint8_t		BPB_NumberOfFATs;		// Number of FATs					0x10
	uint8_t		fill2[19];
	uint32_t	BPB_SectorsPerFAT;		// Sectors Per FAT					0x24  from here and above FAT32 is different from FAT12/16
	uint8_t		fill3[4];
	uint32_t	BPB_RootCluster;		// Root Directory First Cluster		0x2c
	uint8_t		fill4[462];
	uint8_t		sig1;					// 0x55								0x1fe
	uint8_t		sig2;					// 0xaa
};

// Global things we deduce when we open a partition
uint32_t fat_begin_lba;
uint32_t cluster_begin_lba;
uint8_t  sectors_to_cluster_right_slide;
uint8_t  sectors_in_cluster_mask;
uint32_t root_dir_first_cluster;

// to convert a/n where n is a power of two into a>>i (more Z80 friendly)
uint8_t toSlide(uint8_t n)
{
	int i = -1;
	while(n){
		++i;
		n >>= 1;
	}
	return i;
}
bool OpenPartition(int nPartition)
{
	assert(sizeof(FAT32_VOL_ID)==512);

	SECTOR0 sector0;
	if(!ReadPartitionTable(&sector0)) return false;

	SECTOR0::PARTITION *p = &sector0.Partitions[nPartition];
	if(p->Type_Code!=0x0b && p->Type_Code!=0x0c){
		printf("Partition %d not FAT32\n", nPartition+1);
		return false;
	}
	FAT32_VOL_ID volID;

	if(!ReadSector(p->LBA_Begin, &volID)) return false;

	if(volID.sig1!=0x55 || volID.sig2!=0xaa){
		printf("Bad signature in FAT32_VOL_ID:  ");
		return false;
	}
	// now generate our working variables
	fat_begin_lba					= sector0.Partitions[nPartition].LBA_Begin + volID.BPB_ReservedSectors;
	cluster_begin_lba				= sector0.Partitions[nPartition].LBA_Begin + volID.BPB_ReservedSectors + (volID.BPB_NumberOfFATs * volID.BPB_SectorsPerFAT);
	sectors_to_cluster_right_slide	= toSlide(volID.BPB_SectorsPerCluster);
	sectors_in_cluster_mask			= volID.BPB_SectorsPerCluster-1;				// eg: convert 32 into 31 aka 0x1f etc
	root_dir_first_cluster			= volID.BPB_RootCluster;

	if(bVerbose){
		printf("Partition:  %d\n", nPartition+1);
		printf("Byte/Sec:   %u\n", volID.BPB_BytesPerSector);
		printf("Sectors per FAT:  %u\n", volID.BPB_SectorsPerFAT);
		printf("Sectors per Cluster:  %u  shift: %u  mask: 0x%02x\n", volID.BPB_SectorsPerCluster, sectors_to_cluster_right_slide, sectors_in_cluster_mask);
		printf("Reserved Sectors:  %u\n", volID.BPB_ReservedSectors);
		printf("Number of FATS:  %d\n", volID.BPB_NumberOfFATs);
		printf("Root Directory first cluster:  %u\n", volID.BPB_RootCluster);
		printf("fat_begin_lba:  %" PRIu32 "\n", fat_begin_lba);
		printf("cluster_begin_lba:  %" PRIu32 "\n\n", cluster_begin_lba);
	}
	return true;
}
//-------------------------------------------------------------------------------------------------
// Convert cluster number into sector address
// BEWARE: clusters are 'in this partition' while sectors are SD hardware
//-------------------------------------------------------------------------------------------------

uint32_t ClusterToSector(uint32_t c)
{
	return cluster_begin_lba + ((c - 2) << sectors_to_cluster_right_slide);
}
uint32_t SectorToCluster(uint32_t s)	// cluster containing sector
{
	return ((s - cluster_begin_lba) >> sectors_to_cluster_right_slide) + 2;
}
//-------------------------------------------------------------------------------------------------
// Get next cluster
//-------------------------------------------------------------------------------------------------
uint32_t GetNextCluster(uint32_t current_cluster)
{
	static uint32_t fatTable[128];				// next cluster numbers
	static uint32_t last_sector=0xffffffff;		// FAT sector currently in buffer

	uint32_t required_fat_sector = current_cluster/128;				// sector in the FAT
	if(last_sector!=required_fat_sector){
		ReadSector(required_fat_sector + fat_begin_lba, &fatTable);	// read HW sector
		last_sector = required_fat_sector;
	}
	return fatTable[current_cluster%128];							// 0xffffffff on end of chain
}
uint32_t GetNextSector(uint32_t current_sector)
{
	uint32_t x = (current_sector+1) & sectors_in_cluster_mask;
	if(x) return current_sector+1
		;
	// if x==0 we have reached the end
	uint32_t n = GetNextCluster(SectorToCluster(current_sector));
	if(n==0xffffffff) return 0;										// EOF
	return  ClusterToSector(n);										// first sector in cluster
}
//-------------------------------------------------------------------------------------------------
// Unpack a long filename from a DIRL record
// NB: the parts are given in reverse order hence the shuffle at the end
//-------------------------------------------------------------------------------------------------
struct DIRL {
	uint8_t		fill1;
	uint16_t	ch1[5];
	uint8_t		DIR_attr;
	uint16_t	fill2;
	uint16_t	ch2[6];
	uint16_t	fill3;
	uint16_t	ch3[2];
};
void UnpackLong(uint16_t* buffer, void* dirn)
{
	assert(sizeof(DIRL)==32);

	DIRL *d = (DIRL*)dirn;

	uint16_t local[14];					// there are 13 chars in each entry
	int i=0;
	bool run=true;
	for(int j=0; run && j<5; ++j){
		if(d->ch1[j]==0){ run=false; break; }
		local[i++] = d->ch1[j];
	}
	for(int j=0; run && j<6; ++j){
		if(d->ch2[j]==0){ run=false; break; }
		local[i++] = d->ch2[j];
	}
	for(int j=0; run && j<2; ++j){
		if(d->ch3[j]==0){ run=false; break; }
		local[i++] = d->ch3[j];
	}
	local[i] = 0;

	uint16_t temp[MAX_PATH];
	wcscpy_s((wchar_t*)temp, MAX_PATH, (wchar_t*)buffer);
	wcscpy_s((wchar_t*)buffer, MAX_PATH, (wchar_t*)local);
	wcscat_s((wchar_t*)buffer, MAX_PATH, (wchar_t*)temp);
}
//--------------------------------------------------------------------------------------------------
// Make the flag letters for the folder display
//--------------------------------------------------------------------------------------------------
// DIR_Attr bits
#define ATTR_RO		0x01
#define ATTR_HIDE	0x02
#define ATTR_SYS	0x04
#define ATTR_VOL	0x08		// volume id
#define ATTR_DIR	0x10
#define ATTR_ARCH	0x20		// archive
// the other two bits should be zero

const char* MakeFlags(uint8_t att)
{
	static char flags[7];
	flags[0] = (att & ATTR_RO)		? 'R': '.';
	flags[1] = (att & ATTR_HIDE)	? 'H': '.';
	flags[2] = (att & ATTR_SYS)		? 'S': '.';
	flags[3] = (att & ATTR_VOL)		? 'V': '.';		// volume id
	flags[4] = (att & ATTR_DIR)		? 'D': '.';
	flags[5] = (att & ATTR_ARCH)	? 'A': '.';		// archive
	flags[6] = 0;
	return flags;
}
//-------------------------------------------------------------------------------------------------
// When there isn't a long file name make one from the short name
//-------------------------------------------------------------------------------------------------
void MakeLongFromShort(uint8_t *shortName, uint16_t *longName)
{
	int j=0;
	for(int i=0; i<8; longName[j++] = shortName[i++]);
	while(j && longName[j-1]==' ') --j;								// remove trailing spaces
	int k=j;														// save the current length
	longName[j++] = '.';
	for(int i=8; i<11; longName[j++] = shortName[i++]);
	while(j && (longName[j-1]==' ' || (longName[j-1]=='.') && j>k)) --j;	// remove trailing spaces and if there is no extension the , too
	longName[j] = 0;
}
//-------------------------------------------------------------------------------------------------
// FirstDirectoryItem() Get a directory entry
// NextDirectoryItem()
//-------------------------------------------------------------------------------------------------
// there are 4 types of directory entry
// Normal, Unused (first byte is 0xe5), End of Directory (first byte is zero), Long Filename text (see later)
struct DIRN {
	uint8_t		DIR_Name[8];		// filename	(8.3 style)					0x00
	uint8_t		DIR_Ext[3];			// ext									0x08
	uint8_t		DIR_Attr;			// attribute bits						0x0b
	uint8_t		DIR_NTres;
	uint8_t		DIR_CrtTimeTenth;
	uint16_t	DIR_CrtTime;
	uint16_t	DIR_CrtDate;
	uint16_t	DIR_LastAccessedDate;
	uint16_t	DIR_firstClusterHi;	//										0x14
	uint16_t	DIR_WriteTime;
	uint16_t	DIR_WriteDate;
	uint16_t	DIR_firstClusterLo;	//										0x1a
	uint32_t	DIR_FileSize;		//										0x1c
};

struct DIRSECT {
	DIRN entry[16];
};

// current folder
uint16_t currentFolder[MAX_PATH];
uint32_t currentFolder_start;

// a file/folder item
struct FILEx {
	DIRN dirm;
	uint16_t longName[MAX_PATH];
	uint16_t folderPath;		// long
	uint32_t filePointer;
	uint32_t startCluster;
};
struct DIRECTORYx {
	uint32_t longPath;			// name of our folder
	uint32_t sector;			// the sector we are working through
	uint8_t	 slot;				// next DIRN[] slot
	uint32_t startSector;
	DIRSECT buffer;				// where we read out sectors too
};

// reads the directory and returns the first item
// return true if we have an item
// provided you give it a different
bool NextDirectoryItem(DIRECTORYx& dir, FILEx& file);		// protect the forward reference

bool FirstDirectoryItem(DIRECTORYx &dir, FILEx &file, uint32_t isect=0)			// default looks up start of root directory
{
	assert(sizeof(DIRN)==32);
	assert(sizeof(DIRSECT)==512);

	if(isect==0) isect = ClusterToSector(root_dir_first_cluster);
	dir.startSector = isect;
	dir.sector = isect;
	if(!ReadSector(dir.sector, &dir.buffer)) return false;
	dir.slot=0;
	return NextDirectoryItem(dir, file);
}
bool NextDirectoryItem(DIRECTORYx& dir, FILEx& file)
{
	for(int j=0; j<MAX_PATH; file.longName[j++]=0);

	while(true){
		// is it time for a new sector?
		if(dir.slot>=16){
			dir.sector = GetNextSector(dir.sector);
			if(dir.sector==0) return false;
			if(!ReadSector(dir.sector, &dir.buffer)) return false;
//			dump(&dir.buffer, 512);
			dir.slot = 0;
		}
		// next entry
		while(dir.slot<16){
			DIRN* d = &dir.buffer.entry[dir.slot];
			if((d->DIR_Attr & 0x0f)==0x0f){
//				printf("long filename text\n");
				UnpackLong(file.longName, d);
			}
			else if(d->DIR_Name[0]==0xe5){
//				printf("%3d   unused entry\n", i+1);
			}
			else if(d->DIR_Name[0]==0){
//				printf("%3d   end of directory\n", i+1);
				return false;
			}
			else{
				char fn[20]{};									// short file name with packing to 8.3
				for(int j=0; j<8; fn[j]=d->DIR_Name[j], ++j);
				fn[8] = '.';
				for(int j=0; j<3; fn[j+9]=d->DIR_Ext[j], ++j);

				file.startCluster = ((uint32_t)d->DIR_firstClusterHi<<16) | d->DIR_firstClusterLo;

				if(file.longName[0]==0)								// do we have a long file name accumulated
					MakeLongFromShort(d->DIR_Name, file.longName);	// No, so build one
				memcpy(&file.dirm, d, sizeof(DIRN));										// copy in verbatim
				//!!!!!!!!!!!!!!!!!! need folder path
				++dir.slot;			// ready for next time
				return true;
			}
			++dir.slot;
		}
	}
}
const char* makeTime(uint16_t time)
{
	static char temp[15];
	int seconds = time & 0x1f;
	time >>= 5;
	int minutes = time & 0x3f;
	time >>= 6;
	int hours = time & 0x1f;
	sprintf_s(temp, sizeof(temp), "%02d:%02d:%02d", hours, minutes, seconds*2);
	return temp;
}
const char* makeDate(uint16_t date)
{
	static char temp[15];
	int day = date & 0x1f;
	date >>= 5;
	int month = date & 0xf;
	date >>= 4;
	int year = date & 0x7f;
	sprintf_s(temp, sizeof(temp), "%04d/%02d/%02d", year+1980, month, day);
	return temp;
}
const char* WriteDirectoryItem(FILEx file)
{
	static char buffer[MAX_PATH+100];
	sprintf_s(buffer, sizeof(buffer), "%10s %10s  %6s %8u  %10" PRIu32 "   %ls",
			makeDate(file.dirm.DIR_WriteDate), makeTime(file.dirm.DIR_WriteTime), MakeFlags(file.dirm.DIR_Attr), file.dirm.DIR_FileSize, file.startCluster, (wchar_t*)file.longName);
	return buffer;
}
//-------------------------------------------------------------------------------------------------
// printTextFile()
//-------------------------------------------------------------------------------------------------
void printTextFile(uint32_t start_cluster, uint32_t fSize)
{
	uint32_t sector = ClusterToSector(start_cluster);
	// this had better be a text file or some things gonna blow...
	printf("==============================================================================================================\n");
	while(fSize){
		char buffer[512];
		ReadSector(sector, buffer);
		for(int i=0; i<512 && fSize; --fSize){
			char c = buffer[i++];
			if(c=='\t'){
				putchar(' ');		// a personal conceit as I consider tabs to be 4 spaces
				putchar(' ');
				putchar(' ');
				putchar(' ');
			}
			else
				putchar(c);
		}
		sector = GetNextSector(sector);
	}
	printf("\n==============================================================================================================\n");
}
//-------------------------------------------------------------------------------------------------
// main
//-------------------------------------------------------------------------------------------------

int main()
{
	std::vector<FILEx> folder;
	DIRECTORYx dir;
	FILEx file;
	int item;
	uint32_t folderSector;

    printf("FAT32 reader\n");

	// open the SD card
	sd = OpenSD();
	if(sd == INVALID_HANDLE_VALUE){
		printf("Open failed.  ARE YOU IN ADMINISTRATOR MODE? ARE YOU USING 'THE RIGHT' ADAPTER? ");
		error();
		return 0;
	}

	if(!OpenPartition(0)){							// partition 0
		printf("Failed to get first partition data. ");
		error();
		goto bad;
	}

root:
	folderSector = 0;	// triggers root directory

dir:
	item = 0;
	folder.clear();
	if(!FirstDirectoryItem(dir, file, folderSector)){
		printf("We have a problem Houston\n");
		goto bad;
	}
	do{
		++item;
		printf("%3d %s\n", item, (char*)WriteDirectoryItem(file));
		folder.push_back(file);
	}while(NextDirectoryItem(dir, file));

	printf("\nSelect a folder or a text file by number (-1 to quit/0 for root folder): ");
	scanf_s("%d", &item);
	if(item==-1) goto bad;
	if(item==0)  goto root;
	if(item>folder.size()) goto dir;
	auto element = folder[item-1];					// count from 1 on the screen
	if(element.dirm.DIR_Attr & ATTR_DIR){
		printf("\n\n");
		if(element.startCluster==0) folderSector = 0;
		else						folderSector = ClusterToSector(element.startCluster);
		goto dir;
	}
	printf("\n\nPrinting: %ls\n", (wchar_t*)element.longName);
	printTextFile(element.startCluster, element.dirm.DIR_FileSize);
	printf("\n\n");
	goto dir;
bad:
	CloseHandle(sd);
	return 0;
}
