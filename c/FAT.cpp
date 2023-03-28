//=================================================================================================
//
// FAT.cpp
//
// This is the technology demonstrator for the FAT handler for the SD and FDD systems
// I can write and debug C++ far faster than assembler and if I keep it simple it is
// not a hard job to then convert it to Z80 code
// I am going to spell out my data types by using uint16_t style types as things like
// int, unsigned int et al do not always have the same bit length between PC variants
// let alone across platforms.

// Most of the ideas are taken from:
//		https://academy.cba.mit.edu/classes/networking_communications/SD/FAT.pdf
// It is obviously a Microsoft document but I can't find an official one on the Microsoft site.

// This is compiled as a Windows C++ Console application under VS2022
// !!! Run VS2022 'as Administrator' so this gets run 'as Administrator' too !!!!
// You need this as PhysicalDrive2 is a protected device

// I need to stick to Z80 translatable stuff so pointers not references,
// no class functions, no really fun C++20 library goodies et al.

// So:
// Functions and structures named with prefixes  XX_ YY_ and ZZ_
//	XX_ are provided from outside to do the actual hardware interface.
//      These are about reading and writing sectors of data to hardware.
//	YY_ are the internal FAT file system management stuff. This works in
//		wide characters and 512 byte sectors of disk
//	ZZ_ are the externally provided functions that provide a more familiar
//		interface with commonly known functions
// anything with out a suffix should be local to the module it compiles in
//
// The idea is that the outside world knows nothing but the ZZ_ functions/structures
//
// And.. Yes the code is a weird mix of windows and Z80 compatible but I can clean that up
// when translating and then the ZZ_ prefixes will go and it will look more reasonable.
//
//=================================================================================================
// WARNING! This code has nestable compatibility in that you can work on two or more file at
// once even in the sane device/folder but it does not have interruptible  reentrancy !!!!
//=================================================================================================

#include <cstdio>
#include <conio.h>
#include <io.h>
#include <fcntl.h>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>
#include <vector>

#include "FAT_XX.h"
//#include "FAT_YY.h"
#include "FAT_ZZ.h"

#pragma warning( disable: 6387 )	// I like 'no warnings' but some are just too tedious.

bool bVerbose = true;				// make then UI chatty

//==========================================================================================================================
//										FIRST THE WINDOWS INTERFACE STUFF
//==========================================================================================================================

//------------------------------------------------------------------------------------------------
//	global data for windows code filed in as we progress
//------------------------------------------------------------------------------------------------

// a place to save directory references in to make a UI to test things
struct DIRSTUFF {
	int		 index;					// id
	wchar_t	 longName[MAX_PATH+1];	// filename
	bool	 isDirectory;			// file or folder
	uint32_t start;					// first cluster
	uint32_t size;					// number of clusters
};
std::vector<DIRSTUFF> folder;

//-------------------------------------------------------------------------------------------------
// convert LastError() into readable text		(this being Microsoft I'm not promising 'useful')
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
// Dump bytes in the usual bytes/chars format
//-------------------------------------------------------------------------------------------------
void dump(void* buffer, int cb)
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
// get a number from the keyboard
//-------------------------------------------------------------------------------------------------
int getnum()
{
	char temp[20]{};
	for(int i=0; i<19; ++i){
		int c = _getch();			// get a keyboard key
		if(c=='\r'){
			temp[i] = 0;
			while(_kbhit())
				static_cast<void>(_getch());	// the stupid cast is to subvert [nodiscard]
			_putch('\n');
			return atoi(temp);
		}
		temp[i] = c;
		_putch(c);
	}
	while(_kbhit())
		static_cast<void>(_getch());
	return 0;
}

//-------------------------------------------------------------------------------------------------
// Open the target drive
//-------------------------------------------------------------------------------------------------

HANDLE XX_OpenDevice(const char* nameDevice)
{
	HANDLE hf = CreateFile(nameDevice , GENERIC_READ | GENERIC_WRITE,
				FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0  /*FILE_FLAG_NO_BUFFERING*/, nullptr);

	if(hf!=INVALID_HANDLE_VALUE){
		printf("Opened device OK:  %s\n", nameDevice);
		return hf;
	}
	return INVALID_HANDLE_VALUE;
}
//-------------------------------------------------------------------------------------------------
// Read a sector from the device
//-------------------------------------------------------------------------------------------------
bool XX_ReadSector(HANDLE hDevice, uint32_t sector, void* buffer)
{
	assert(sizeof LONG==4);		// it is a signed DWORD isn't it? and that is a int32_t?
								// but it is used here where an unsigned makes more sense

	union {						// SetFilePointer works with old DWORD so pack/unpack things
		LONG b[2];				// a single (unsigned)LONG only addresses up to 4G
		uint64_t c;
	} a;
	a.c = (uint64_t)sector*512;	// byte address

	if(SetFilePointer(hDevice, a.b[0], &a.b[1], FILE_BEGIN)==INVALID_SET_FILE_POINTER) return false;
	DWORD nRead;
	// ReadFile at HW level only works on sector size address boundaries and in sector size or multiples blocks
	// for this application no worries.
	// HOWEVER it only works in one of my card holders which is more perplexing...
	bool ret = ReadFile(hDevice, buffer, 512, &nRead, nullptr)!=0	// return not zero on success
		&& nRead == 512;

//	if(bVerbose) printf("\nRead Sector %lu OK\n", sector);
	return ret;
}
//-------------------------------------------------------------------------------------------------
// Write a sector to the device
//-------------------------------------------------------------------------------------------------
bool XX_WriteSector(HANDLE hDevice, uint32_t sector, void* buffer)
{
	union {						// as above
		LONG b[2];
		uint64_t c;
	} a;
	a.c = (uint64_t)sector*512;	// byte address

	if(SetFilePointer(hDevice, a.b[0], &a.b[1], FILE_BEGIN)==INVALID_SET_FILE_POINTER) return false;
	DWORD nWrite;
	bool ret = WriteFile(hDevice, buffer, 512, &nWrite, nullptr)!=0	// return not zero on success
		&& nWrite == 512;

//	if(bVerbose) printf("Write Sector %lu OK\n", sector);
	return ret;
}
//-------------------------------------------------------------------------------------------------
// Memory management functions
//-------------------------------------------------------------------------------------------------
void* XX_alloc(uint16_t nbytes)
{
	return new BYTE[nbytes];
}
void XX_free(void* item)
{
	delete[] (BYTE*)item;
}
//-------------------------------------------------------------------------------------------------
// main
//-------------------------------------------------------------------------------------------------

void head(){
	printf(" File Slots: %d/100    Directory slots: %d/20  ZZ slots: %d/100\n",
		UsedFileSlots(), UsedDirectorySlots(), UsedZZthings());
}
void skip_preamble(ZZ_FILE* fp)
{
	if(ZZ_filesize(fp)>=3){
		uint8_t x[3];
		x[0] = (uint8_t)ZZ_fgetc(fp);
		x[1] = (uint8_t)ZZ_fgetc(fp);
		x[2] = (uint8_t)ZZ_fgetc(fp);
		if(x[0]!=0xef || x[1]!=0xbb || x[2]!=0xbf)
			ZZ_fseek(fp, 0, 0);
	}
}
int main()
{
	SetConsoleOutputCP(CP_UTF8);				// with these set we can print utf8
//	setvbuf(stdout, nullptr, _IOFBF, 1000);		// but %ls still won't do wchar_t >0xff

    printf("FAT reader\n==========\n");
	system("wmic diskdrive list brief");			// list things so we know what "PhysicalDevice2" really is

	//=============================================================================
	// STEP 1:
	// Open a file, well two files
	//=============================================================================
	// I will put this file on both test devices
	const uint8_t* fn = (U8)u8"A:/bios/test.edc";
	ZZ_FILE* fp = ZZ_fopen(fn, (U8)"r");	// open file to read
	printf("===========================================================================================================\n");
	if(fp==nullptr)
		printf("Failed to open %s\n", fn);
	else{
		printf("Opened %s\n", fn);
		skip_preamble(fp);
		uint8_t buffer[150];
		while(ZZ_fgets(buffer, sizeof buffer, fp))
			puts((char*)buffer);
		ZZ_fclose(fp);
	}
	printf("===========================================================================================================\n");

	fn = (U8)u8"C:\\bios\\test.edc";
	fp = ZZ_fopen((U8)fn, (U8)"r");	// open file to read
	printf("===========================================================================================================\n");
	if(fp==nullptr)
		printf("Failed to open %s\n", fn);
	else{
		printf("Opened %s\n", fn);
		skip_preamble(fp);
		uint8_t buffer[150];
		while(ZZ_fgets(buffer, sizeof buffer, fp))
			puts((char*)buffer);
		ZZ_fclose(fp);
	}
	printf("===========================================================================================================\n");

	//=============================================================================
	// STEP 2:
	// Open folders
	//=============================================================================

	ZZ_FOLDER *fa{};
	ZZ_FOLDER *fb{};
	std::vector<ZZ_FILE*> folder{};

root:
	if(fa) ZZ_closefolder(fa);
	if(fb) ZZ_closefolder(fb);
	 fa = ZZ_openfolder((uint8_t*)u8"A:/");		// open root directory
	 fb = ZZ_openfolder((uint8_t*)u8"C:\\");

again:
	head();
	ZZ_resetfolder(fa);
	ZZ_resetfolder(fb);

	// clean up before we just 'clear'
	for(auto z : folder)
		ZZ_fclose(z);
	folder.clear();
	head();

	printf("\nDirectory of %s\n", (char*)ZZ_folderpathname(fa));
	printf("    Date         Time      Attr       Size  Start Sect   Name\n");
	ZZ_FILE* file;
	uint16_t item = 1;
	while((file = ZZ_findnextfile(fa))!=nullptr){
		printf("%3d %s\n", item++, ZZ_writefiledesc(file));
		folder.push_back(file);
	}
	fflush(stdout);

	uint16_t itemX = item-1;
	printf("\nDirectory of %s\n", (char*)ZZ_folderpathname(fb));
	printf("    Date         Time      Attr       Size  Start Sect   Name\n");
	while((file = ZZ_findnextfile(fb))!=nullptr){
		printf("%3d %s\n", item++, ZZ_writefiledesc(file));
		folder.push_back(file);
	}
	fflush(stdout);

	//=============================================================================
	// STEP 3:
	// get a UI selection
	//=============================================================================
	item = 0;
	head();
	printf("\nSelect a folder or a text file by number (-1 to quit/0 for root folder): ");

	int nn = getnum();
	if(nn < 0) goto bad;
	if(nn == 0)  goto root;
	if(nn > folder.size()) goto again;
	item = nn-1;		// go unsigned

	file = folder[item];

	if(ZZ_isDIR(file)){
		if(item<itemX)	ZZ_changefolder(fa, ZZ_longname(file));
		else			ZZ_changefolder(fb, ZZ_longname(file));
	}
	else if(ZZ_isFILE(file)){
		printf("===========================================================================================================\n"
			  "listing file %s%s\n", ZZ_longpath(file), ZZ_longname(file));

		ZZ_FILE* fp = ZZ_fopenD(file, (U8)"r");	// open file to read
		if(fp==nullptr)
			printf("Failed to open %s\n", fn);
		else{
			skip_preamble(fp);
			uint8_t buffer[150];
			while(ZZ_fgets(buffer, sizeof buffer, fp))
				puts((char*)buffer);
			ZZ_fclose(fp);
		}
		printf("\n===========================================================================================================\n");
	}
	goto again;

bad:
	return 0;
}