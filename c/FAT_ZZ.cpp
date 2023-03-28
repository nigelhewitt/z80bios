//==============================================================================================================
//			FILE ORIENTED STUFF
//==============================================================================================================

#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>

#include "FAT_XX.h"
#include "FAT_YY.h"
#include "FAT_ZZ.h"

//=================================================================================================
// semi static ZZ_DRIVE/FOLDER/FILE allocator
//=================================================================================================
#define N_THINGS 100
struct ZZ_THING { void* y; } zz_things[N_THINGS]{};		// they are all the same so...

static ZZ_THING* getthing(void* p){
	for(int i=0; i<N_THINGS; ++i)
		if(zz_things[i].y==nullptr){
			zz_things[i].y = p;
			return &zz_things[i];
		}
	return nullptr;
}
static void freething(void* t)
{
	((ZZ_THING*)t)->y = nullptr;
}
#if _DEBUG
int UsedZZthings()
{
	int n=0;
	for(int i=0; i<N_THINGS; ++i)
		if(zz_things[i].y!=nullptr)
			++n;
	return n;
}
#endif

ZZ_DRIVE*	allocateDRIVE(YY_DRIVE* y)	{ return (ZZ_DRIVE*)getthing(y); }
void		freeDRIVE(ZZ_DRIVE* z)		{ z->drive_stuff = nullptr; }
ZZ_FOLDER*	allocateFOLDER(YY_DIRECTORY* y){ return (ZZ_FOLDER*)getthing(y); }
void		freeFOLDER(ZZ_FOLDER* z)	{ YY_CloseDirectory((YY_DIRECTORY*)(z->folder_stuff)); z->folder_stuff = nullptr; }
ZZ_FILE*	allocateFILE(YY_FILE* y)	{ return (ZZ_FILE*)getthing(y); }
void		freeFILE(ZZ_FILE* z)		{ YY_CloseFile((YY_FILE*)(z->file_stuff)); z->file_stuff = nullptr; }

// find the index of the first character of the actual file name.ext
#if 0
static uint16_t split(const uint8_t* full)
{
	uint16_t n=0;
	while(full[n]!=0) ++n;		// search to the end
	if(n==0) return 0;			// not good
	while(n>0){
		if(full[n-1]=='/' || full[n-1]=='\\') return n;
		--n;
	}
	return 0;
}
#endif
//=================================================================================================
// text management for utf8/utf16 translation
//=================================================================================================
// slots and a next slot pointer
uint8_t textslot[20][MAX_PATH];
uint8_t nslot=0;

static uint8_t* totext(const uint16_t* in=nullptr){
	if(++nslot>=20) nslot=0;
	if(in==nullptr) return textslot[nslot];
	return YY_ToNarrow(textslot[nslot], MAX_PATH, in);
}
// again in wide
uint16_t wideslot[20][MAX_PATH];
uint8_t wslot=0;

static uint16_t* towide(const uint8_t* in){
	if(in==nullptr) return nullptr;
	if(++wslot>=20) wslot=0;
	return YY_ToWide(wideslot[nslot], MAX_PATH, in);
}
//=================================================================================================
// File routines
//=================================================================================================

inline YY_FILE* getfile(ZZ_FILE* fz){ if(fz==nullptr) return nullptr; return (YY_FILE*)(fz->file_stuff); }

const uint8_t* ZZ_longpath(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy==nullptr) return (uint8_t*)u8"";
	return totext(fy->pathName);
}
const uint8_t* ZZ_longname(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy==nullptr) return (uint8_t*)u8"";
	return totext(fy->longName);
}
uint32_t ZZ_filesize(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy==nullptr) return 0;
	return fy->dirn.DIR_FileSize;
}
// translate two character mode code in the working bit flags
struct { uint8_t mode1, mode2; uint8_t code; } modes[] = {
	'r',  0,	FOM_READ | FOM_MUSTEXIST,
	'w',  0,	FOM_WRITE | FOM_CLEAN,
	'a',  0,	FOM_WRITE | FOM_APPEND,
	'r',  '+',	FOM_READ | FOM_WRITE | FOM_MUSTEXIST,
	'w',  '+',	FOM_READ | FOM_WRITE | FOM_CLEAN,
	'a',  '+',	FOM_READ | FOM_WRITE | FOM_APPEND
};

ZZ_FILE* ZZ_fopen(const uint8_t* pathname, const uint8_t* mode)
{
	uint8_t code{};
	for(int a=0; a<_countof(modes); ++a)
		if(modes[a].mode1 == mode[0] && modes[a].mode2 == mode[1]){
			code = modes[a].code;
			break;
		}
	if(code==0) return nullptr;

	YY_FILE* file = YY_OpenFile(towide(pathname), code);
	if(file==nullptr) return nullptr;
	return allocateFILE(file);
}
ZZ_FILE* ZZ_fopenD(ZZ_FILE* fz, const uint8_t* mode)
{
	uint8_t code{};
	for(int a=0; a<_countof(modes); ++a)
		if(modes[a].mode1 == mode[0] && modes[a].mode2 == mode[1]){
			code = modes[a].code;
			break;
		}
	if(code==0) return nullptr;

	YY_FILE* fy = getfile(fz);
	fy = YY_OpenFileDirect(fy, code);
	if(fy==nullptr) return nullptr;
	return fz;
}

void ZZ_fclose(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		YY_CloseFile(fy);
	freeFILE(fz);
}
uint32_t ZZ_fread(void* buffer, uint16_t count, ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){
		uint16_t i=0;
		while(i<count){
			uint16_t c = YY_getc(fy);
			if(c==ZZ_EOF)
				return i;
			((uint8_t*)buffer)[i++] = c & 0xff;
		}
		return count;
	}
	return 0;
}
uint16_t ZZ_fgetc(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return YY_getc(fy);
	return 0;
}
uint8_t* ZZ_fgets(uint8_t* buffer, uint16_t count, ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){
		uint16_t i=0;
		while(i<count-1){
			uint16_t c = YY_getc(fy);
			if(c==ZZ_EOF){
				if(i==0) return nullptr;
				buffer[i] = 0;
				return buffer;
			}
			if(c=='\n'){
				buffer[i] = 0;
				return buffer;
			}
			buffer[i++] = c & 0xff;
		}
		buffer[i] = 0;
		return buffer;
	}
	return nullptr;
}
uint32_t ZZ_fwrite(void* buffer, uint16_t count, ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){




	}
	return 0;
}
int ZZ_fputc(uint8_t c, ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){



	}
	return 0;
}
int ZZ_fputs(uint8_t* str, ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){


	}
	return 0;
}
uint8_t ZZ_fseek(ZZ_FILE* fz, int32_t offset, uint8_t origin)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr){
		switch(origin){
		case 0:				// SEEK_SET
			if(offset<0 || offset>fy->dirn.DIR_FileSize) return 1;
			fy->filePointer = offset;
			return 0;
		case 1:				// SEEK_CUR
			if(offset<0 && -offset>fy->filePointer) return 1;
			if(offset>0 && (offset+fy->filePointer) > fy->dirn.DIR_FileSize) return 1;
			fy->filePointer += offset;
			return 0;
		case 2:				// SEEK_END
			if(offset>0) return 1;
			if(-offset>fy->dirn.DIR_FileSize) return 1;
			fy->filePointer = fy->dirn.DIR_FileSize+offset;
			return 0;
		}
	}
	return 1;
}
uint32_t ZZ_ftell(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return fy->filePointer;
	return 0;
}
const char* ZZ_writefiledesc(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return YY_WriteDirectoryItem(fy, totext(), MAX_PATH);
	return "";
}
bool ZZ_isDIR(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return YY_isDIR(fy);
	return false;
}
bool ZZ_isFILE(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return YY_isFILE(fy);
	return false;
}
uint8_t ZZ_isOpen(ZZ_FILE* fz)
{
	YY_FILE* fy = getfile(fz);
	if(fy!=nullptr)
		return YY_isOpen(fy);
	return false;
}
//=================================================================================================
// folder routines
//=================================================================================================
inline YY_DIRECTORY* getfolder(ZZ_FOLDER* fz){ if(fz==nullptr) return nullptr; return (YY_DIRECTORY*)(fz->folder_stuff); }

ZZ_FOLDER* ZZ_openfolder(const uint8_t* pathname)
{
	assert(ZZ_EOF==YY_EOF);

	return allocateFOLDER(YY_OpenDirectory(towide(pathname)));
}
bool ZZ_changefolder(ZZ_FOLDER* fz, const uint8_t* path )
{
	YY_DIRECTORY* fy = getfolder(fz);
	if(fy!=nullptr)
		return YY_ChangeDirectory(fy, towide(path));
	return false;
}
ZZ_FILE* ZZ_findnextfile(ZZ_FOLDER* fz)
{
	YY_DIRECTORY* fy = getfolder(fz);
	if(fy!=nullptr){
		YY_FILE* file = YY_NextDirectoryItem(fy);
		if(file==nullptr) return nullptr;
		return allocateFILE(file);
	}
	return nullptr;
}
void ZZ_resetfolder(ZZ_FOLDER* fz)
{
	YY_DIRECTORY* fy = getfolder(fz);
	if(fy!=nullptr)
		YY_ResetDirectory(fy);
}
uint8_t* ZZ_folderpathname(ZZ_FOLDER* fz)
{
	YY_DIRECTORY* fy = getfolder(fz);
	if(fy!=nullptr)
		return totext(fy->longPath);
	return (uint8_t*)"";
}
void ZZ_closefolder(ZZ_FOLDER* fz)
{
	YY_DIRECTORY* fy = getfolder(fz);
	if(fy!=nullptr)
		YY_CloseDirectory(fy);
}
