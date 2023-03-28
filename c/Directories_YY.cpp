//==========================================================================================================================
//											NOW THE DIRECTORIES STUFF
//==========================================================================================================================

#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>

#include "FAT_XX.h"
#include "FAT_YY.h"

uint16_t temp1[MAX_PATH], temp2[MAX_PATH];	// community text buffers

// the default device tells us which devices cwd to use
uint8_t	YY_defaultDevice = 'C';

//=================================================================================================
// Directory slots
//=================================================================================================
#define MAX_DIRECTORY	20
YY_DIRECTORY	directories[MAX_DIRECTORY]{};

static YY_DIRECTORY* GetDirectorySlot()
{
	for(int i=0; i<MAX_DIRECTORY; ++i)
		if(directories[i].drive == 0)
			return &directories[i];
	return nullptr;
}
static void FreeDirectorySlot(YY_DIRECTORY* dir)
{
	dir->drive = 0;		// keep this as a routine as we might allocate stuff later
}
int YY_Dused(){			// debug only
	int n=0;
	for(int i=0; i<MAX_DIRECTORY; ++i)
		if(directories[i].drive!=0)
			++n;
	return n;
}
#if _DEBUG
int UsedDirectorySlots()
{
	int n=0;
	for(int i=0; i<MAX_DIRECTORY; ++i)
		if(directories[i].drive!=0)
			++n;
	return n;
}
#endif
//-------------------------------------------------------------------------------------------------
// Unpack a long filename from a DIRL record
// NB: the parts are given in reverse order hence the shuffle at the end
//-------------------------------------------------------------------------------------------------
struct DIRL {
	uint8_t		LDIR_Ord;		// 0  Ordinal masked with 0x40 is the final one
	uint16_t	LDIR_Name1[5];	// 2  first 5 characters
	uint8_t		LDIR_attr;		// 11 0x0f for a filename 0x3f for a folder name
	uint8_t		LDIR_type;		// 12 0
	uint8_t		LDIR_ChkSum;	// 13 checksum of the name in the short name
	uint16_t	LDIR_Name2[6];	// 14 characters 6-11
	uint16_t	LDIR_FstClusLO;	// 26 0
	uint16_t	LDIR_Name3[2];	// 28 characters 12-13
};
static void UnpackLong(YY_FILE* file, YY_DIRN* dirn)
{
	assert(sizeof DIRL==32);

	DIRL *d = (DIRL*)dirn;
	if(d->LDIR_Ord & 0x40){		// if first
		for(int i=0; i<MAX_PATH; file->longName[i++]=0);
		file->shortnamechecksum = d->LDIR_ChkSum;
	}
	else{
		if(file->shortnamechecksum!=d->LDIR_ChkSum)
			printf("LongName checksum error type 1\n");
	}
	uint16_t index = ((d->LDIR_Ord & 0x3f)-1)*13;	// where we put these character in long name
	bool run=true;
	for(int j=0; run && j<5; ++j){
		if(d->LDIR_Name1[j]==0){ run=false; break; }
#pragma warning( push )
#pragma warning( disable: 6386 )
		file->longName[index++] = d->LDIR_Name1[j];
#pragma warning( pop)
	}
	for(int j=0; run && j<6; ++j){
		if(d->LDIR_Name2[j]==0){ run=false; break; }
		file->longName[index++] = d->LDIR_Name2[j];
	}
	for(int j=0; run && j<2; ++j){
		if(d->LDIR_Name3[j]==0){ run=false; break; }
		file->longName[index++] = d->LDIR_Name3[j];
	}
}
//--------------------------------------------------------------------------------------------------
// Make the flag letters for the folder display
//--------------------------------------------------------------------------------------------------

static const char* MakeFlags(uint8_t att)
{
	static char flags[7];
	flags[0] = (att & ATTR_RO)		? 'R': '.';		// read only
	flags[1] = (att & ATTR_HIDE)	? 'H': '.';		// hidden
	flags[2] = (att & ATTR_SYS)		? 'S': '.';		// system
	flags[3] = (att & ATTR_VOL)		? 'V': '.';		// volume id
	flags[4] = (att & ATTR_DIR)		? 'D': '.';		// directory
	flags[5] = (att & ATTR_ARCH)	? 'A': '.';		// archive
	flags[6] = 0;
	return flags;
}
//-------------------------------------------------------------------------------------------------
// When there isn't a long file name make one from the short name
// use the DIR_NTRes flag bits: 0x08 make the name lower case, 0x10 make the extension lower case
//-------------------------------------------------------------------------------------------------
static void MakeLongFromShort(uint8_t *shortName, uint16_t *longName, uint8_t flags)
{
	int j=0;
	if(flags & 0x08)
		for(int i=0; i<8; longName[j++] = tolower(shortName[i++]));
	else
		for(int i=0; i<8; longName[j++] = shortName[i++]);

	while(j && longName[j-1]==' ') --j;								// remove trailing spaces
	int k=j;														// save the current length
	longName[j++] = '.';
	if(flags & 0x10)
		for(int i=8; i<11; longName[j++] = tolower(shortName[i++]));
	else
		for(int i=8; i<11; longName[j++] = shortName[i++]);
	while(j && (longName[j-1]==' ' || (longName[j-1]=='.') && j>k)) --j;	// remove trailing spaces and if there is no extension the , too
	longName[j] = 0;
}
//-------------------------------------------------------------------------------------------------
// AddPath()	append more path but understand '.' and '..'
//-------------------------------------------------------------------------------------------------
void YY_AddPath(uint16_t* dest, uint16_t* src)			// both buffers are MAX_PATH
{
	if(wcscmp((wchar_t*)src, L".")==0)
		return;
	if(wcscmp((wchar_t*)src, L"..")==0){
		for(int i=(int)wcslen((wchar_t*)dest)-1; i>0; --i){
			dest[i] = 0;
			if(dest[i-1]=='/') return;
		}
	}
	else{
		wcscat_s((wchar_t*)dest, MAX_PATH, (wchar_t*)src);
		wcscat_s((wchar_t*)dest, MAX_PATH, L"/");
	}
}
//-------------------------------------------------------------------------------------------------
// YY_OpenDirectory()	Get a directory
//-------------------------------------------------------------------------------------------------

// Some thoughts on directories for FAT
// Directories must form a chain back to the root or we are going to just have to regenerate it
// to actually update anything so...
// Any call to 'open' a directory must either be passed in a parent directory and an item from
// that directory  for us to connect too or, if the parent is nullptr, it ignores the item
// and opens the root.
// BEWARE: we have to work in wide characters as that's what the directories do

// Read through a path "stuff-abc/def/gei/" starting from the pointer, say 6 and copy abc into the buffer
// moving the index to past the delimiter ie 10
static bool getToken(uint16_t* text, uint16_t &index, uint16_t* buffer)
{
	uint16_t outIndex=0;
	uint16_t c;
	while((c=text[index])!=0){
		if(c==L'\\' || c=='/'){
			++index;
			buffer[outIndex] = 0;
			return outIndex!=0;
		}
		buffer[outIndex++] = c;
		++index;
	}
	buffer[outIndex] = 0;
	return outIndex!=0;
}
// find the entry for path in dir and assume its start_sector and add it to the longPath
bool YY_ChangeDirectory(YY_DIRECTORY* dir, uint16_t* path)
{
	if(path[0]==L'.' && path[1]==0)		// do the easy one first with a shortcut
		return dir;
	// notice that both "." and ".." are valid directory items
	YY_FILE* file;
	YY_ResetDirectory(dir);
	while((file=YY_NextDirectoryItem(dir))!=nullptr){
		if(YY_isDIR(file) && YY_matchName(file, path)){
			YY_AddPath(dir->longPath, path);
			dir->startCluster = file->startCluster;
			dir->sector = 0;
			dir->slot = 0;
			YY_FreeFileSlot(file);
			return true;
		}
		YY_FreeFileSlot(file);
	}
	return false;
}
// open with a path:
// if it starts with "A:" you have selected a drive, if not you get the default
// if it has "/" or "\\" next you have selected the root directory, if not the CWD of that device
// then you get folder\folder"  or	"\folder\folder\"

YY_DIRECTORY* YY_OpenDirectory(uint16_t* path)
{
	uint8_t driveLetter = YY_defaultDrive;
	uint16_t index = 0;
	if(path[1]==L':'){
		driveLetter = (uint8_t)path[0];
		index = 2;
	}
	YY_DRIVE* drive = YY_MountDrive(driveLetter);	// mount or hook into an already mounted drive
	if(drive==nullptr)	return nullptr;

	YY_DIRECTORY* dir = GetDirectorySlot();	// get a slot to put our new YY_DIRECTORY in
	if(dir==nullptr) return nullptr;

	// set up some starting values as if it is "" or "A:\" this is what they get
	dir->drive			= drive;						// own the slot
	dir->startCluster	= 0;							// start from root
	dir->sector			= 0;							// not yet
	dir->sectorinbuffer = 0xffffffff;					// none yet
	dir->slot			= 0;
	dir->longPath[0]	= drive->idDrive;				// make the "A:\" start for the path
	dir->longPath[1]	= L':';
	dir->longPath[2]	= L'/';
	dir->longPath[3]	= 0;

	if(path[index]!=L'\\' && path[index]!=L'/'){		// if no / use CWD for that drive
		uint16_t cwdIndex=3;							// the CWD is at least "A:\"
		while(getToken(drive->cwd, cwdIndex, temp1))	// read path element into temp and increment index
			if(!YY_ChangeDirectory(dir, temp1)){		// move up one level
				FreeDirectorySlot(dir);
				return nullptr;
			}
	}
	else
		++index;								// step over / to start of first folder

	while(getToken(path, index, temp1))
		if(!YY_ChangeDirectory(dir, temp1)){
			FreeDirectorySlot(dir);
			return nullptr;
		}
	YY_ResetDirectory(dir);
	return dir;
}
void YY_ResetDirectory(YY_DIRECTORY* dir)
{
	if(dir->startCluster==0)
		dir->sector = dir->drive->root_dir_first_sector;
	else
		dir->sector = YY_ClusterToSector(dir->drive, dir->startCluster);
	dir->slot = 0;
}
YY_FILE* YY_NextDirectoryItem(YY_DIRECTORY* dir)
{
	YY_FILE* file = YY_GetFileSlot();
	if(file==nullptr) return nullptr;

	for(int j=0; j<MAX_PATH; file->longName[j++]=0);

	// load the buffer for YY_NextDirectoryItem
	if(dir->sectorinbuffer != dir->sector)
		if(!XX_ReadSector(dir->drive->hDevice, dir->sector, &dir->buffer))
			return nullptr;
	dir->sectorinbuffer = dir->sector;

	while(true){
		// is it time for a new sector?
		if(dir->slot>=16){
//			YY_DirFlush(dir);					// <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
			dir->sector = YY_GetNextSector(dir->drive, dir->sector);
			if(dir->sector==0) return nullptr;
			if(!XX_ReadSector(dir->drive->hDevice, dir->sector, &dir->buffer)) return nullptr;
//			dump(&dir->buffer, 512);
			dir->slot = 0;
		}
		// next entry
		while(dir->slot<16){
			YY_DIRN* d = &dir->buffer.entry[dir->slot];
			if(d->DIR_Name[0]==0xe5){
//				printf("%3d   unused entry\n", i+1);
			}
			else if(d->DIR_Name[0]==0){
//				printf("%3d   end of directory\n", i+1);
				return nullptr;
			}
			else if((d->DIR_Attr & 0x0f)==0x0f){
//				printf("long filename text\n");
				UnpackLong(file, d);
			}
			else{
				file->startCluster = ((uint32_t)d->DIR_FstClusHI<<16) | d->DIR_FstClusLO;

				if(file->longName[0]==0)											// do we have a long file name accumulated
					MakeLongFromShort(d->DIR_Name, file->longName, d->DIR_NTRes);	// No, so build one
				else{
#pragma warning( push )
#pragma warning(disable: 6201 )			// yes I know but they're together
					uint8_t csum = 0;
					for(int i=0; i<11; ++i)		// page 32
						csum = ((csum & 1) ? 0x80 : 0) + (csum >> 1) + d->DIR_Name[i];
					if(csum != file->shortnamechecksum)
						printf("LongName checksum error type 2\n");
#pragma warning( pop )
				}
				memcpy(&file->dirn, d, sizeof YY_DIRN);								// copy in verbatim
				file->filePointer = 0;
				++dir->slot;					// ready for next time
				file->drive = dir->drive;		// until we do this the slot is not ours.
				memcpy(file->pathName, dir->longPath, MAX_PATH);
//				file->dir = dir;
				return file;
			}
			++dir->slot;
		}
	}
}
// close a whole directory tree
void YY_CloseDirectory(YY_DIRECTORY* dir)
{
	dir->drive = 0;
}
//=================================================================================================
// text description of YY_FILE
//=================================================================================================
static const char* makeTime(uint16_t time)
{
	static char temp[15];
	int seconds = time & 0x1f;
	time >>= 5;
	int minutes = time & 0x3f;
	time >>= 6;
	int hours = time & 0x1f;
	sprintf_s(temp, sizeof temp, "%02d:%02d:%02d", hours, minutes, seconds*2);
	return temp;
}
static const char* makeDate(uint16_t date)
{
	static char temp[15];
	int day = date & 0x1f;
	date >>= 5;
	int month = date & 0xf;
	date >>= 4;

	int year = date & 0x7f;
	sprintf_s(temp, sizeof temp, "%04d/%02d/%02d", year+1980, month, day);
	return temp;
}
const char* YY_WriteDirectoryItem(YY_FILE* file, uint8_t* buffer, int cb)
{
	uint8_t temp[MAX_PATH];
	sprintf_s((char*)buffer, cb, "%10s %10s  %6s %8u  %10" PRIu32 "   %s",
			makeDate(file->dirn.DIR_WrtDate), makeTime(file->dirn.DIR_WrtTime), MakeFlags(file->dirn.DIR_Attr),
			file->dirn.DIR_FileSize, file->startCluster,
			YY_ToNarrow(temp, sizeof temp, file->longName));
	return (char*)buffer;
}
