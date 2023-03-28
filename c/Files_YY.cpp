//==========================================================================================================================
//											NOW THE FAT STUFF
//==========================================================================================================================

#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>

#include "FAT_XX.h"
#include "FAT_YY.h"

//=================================================================================================
// File slots
//=================================================================================================
#define MAX_FILES	100
YY_FILE	files[MAX_FILES]{};

YY_FILE* YY_GetFileSlot()
{
	for(int i=0; i<MAX_FILES; ++i)
		if(files[i].drive == 0)
			return &files[i];
	return nullptr;
}
void YY_FreeFileSlot(YY_FILE* file)
{
	if(file!=nullptr)
		file->drive = 0;		// keep this as a routine as we might allocate stuff later
}
#if _DEBUG
int UsedFileSlots()
{
	int n=0;
	for(int i=0; i<MAX_FILES; ++i)
		if(files[i].drive!=0)
			++n;
	return n;
}
#endif
bool YY_isDIR(YY_FILE* file)
{
	return (file->dirn.DIR_Attr & (ATTR_DIR | ATTR_VOL)) == ATTR_DIR;
}
bool YY_isFILE(YY_FILE* file)
{
	return (file->dirn.DIR_Attr & (ATTR_DIR | ATTR_VOL)) == 0;
}
uint8_t YY_isOpen(YY_FILE* file)
{
	return (file->open_mode ^ FOM_OPEN)!=0;
}
bool YY_matchName(YY_FILE* file, uint16_t* name)
{
	uint16_t* p = file->longName;
	for(int i=0; i<MAX_PATH; ++i){
		if(p[i]==0 && name[i]==0) return true;
		if(tolower(p[i])!=tolower(name[i])) return false;
	}
	return false;
}
YY_FILE* YY_OpenFileDirect(YY_FILE* file, uint8_t mode)
{
	file->open_mode = mode | FOM_OPEN;
	file->sector_in_buffer_abs  = 0xffffffff;
	file->sector_in_buffer_file = 0xffffffff;
	file->first_sector = YY_ClusterToSector(file->drive, file->startCluster);
	if((mode & (FOM_WRITE|FOM_APPEND))==(FOM_WRITE|FOM_APPEND))
		file->filePointer = file->dirn.DIR_FileSize;
	return file;
}
YY_FILE* YY_OpenFile(uint16_t* pathname, uint8_t mode)
{
	// first we need to divide the file and the folder
	int i;
	for(i=0; pathname[i]; ++i);		// move to the end of the name
	if(i==0) return 0;				// wot name?
	while(i && pathname[i-1]!='\\' && pathname[i-1]!='/') --i;	// move to path/name delimiter (might be none)
	uint16_t save = pathname[i];
	pathname[i] = 0;
	YY_DIRECTORY* dir = YY_OpenDirectory(pathname);		// does all the CWD drive and path stuff
	pathname[i] = save;									// restore the path
	if(dir==nullptr) return nullptr;					// failed to find the folder

	// now search the folder for the file
	YY_FILE* file{};
	while((file = YY_NextDirectoryItem(dir))!=nullptr){
		if(YY_isFILE(file) && YY_matchName(file, &pathname[i])){
			YY_CloseDirectory(dir);
			return YY_OpenFileDirect(file, mode);
		}
		YY_CloseFile(file);
	}
	YY_CloseDirectory(dir);
	return nullptr;
}
void YY_CloseFile(YY_FILE* file)
{
	// if we have written to the file
	//		flush file stuff
	//		update 'accessed' date/time
	// if(we need to rewrite the directory entry...
	//		re-find the directory sector as it might be changed
	//		flush directory stuff
	YY_FreeFileSlot(file);
}
//-------------------------------------------------------------------------------------------------
// Manage files
//-------------------------------------------------------------------------------------------------
bool YY_DeleteFile(YY_FILE*)
{
	return false;
}
bool YY_DeleteFile(uint8_t* pathname)
{
	return false;
}
uint64_t YY_SeekFile(YY_FILE* fp, uint64_t dest, uint8_t mode)
{
	return 0;
}
uint64_t YY_TellFile(YY_FILE*)
{
	return 0;
}
//-------------------------------------------------------------------------------------------------
// ReadBlock()		get the next 512byte block, returns bytes (1-512), 0=EOF, -ve error
//-------------------------------------------------------------------------------------------------
/*uint8_t	YY_ReadBlock(YY_FILE* file, void* buffer)
{
	if(file->dirn.DIR_FileSize <= file->filePointer)		// run out is run out
		return 0;
	uint32_t remains = file->dirn.DIR_FileSize - file->filePointer;
	if(remains>512) remains = 512;

	if(!XX_ReadSector(file->drive->hDevice, file->sector, buffer)) return -1;
	file->filePointer += remains;
	file->sector = YY_GetNextSector(file->drive, file->sector);
	return remains;
}*/
//-------------------------------------------------------------------------------------------------
// WriteBlock()		write the next 512byte block, returns true on OK
//-------------------------------------------------------------------------------------------------
/*bool YY_WriteBlock(YY_FILE* file, void* buffer)
{
	// is this a 'first write' and we need a staring cluster?
	if(file->sector==0){
		uint32_t newCluster = YY_AllocateCluster(file->drive);
		if(newCluster==0) return false;						// CAB
		file->startCluster = newCluster;
		file->sector = YY_ClusterToSector(file->drive, newCluster);
		file->file_dirty = true;
	}
	else{
		uint32_t sector = YY_GetNextSector(file->drive, file->sector);	// try and step through our cluster
		if(sector==0){								// end of cluster
			uint32_t newCluster = YY_AllocateCluster(file->drive);
			if(newCluster==0) return false;
			YY_SetClusterEntry(file->drive, YY_SectorToCluster(file->drive, file->sector), newCluster);
			file->sector = YY_ClusterToSector(file->drive, newCluster);
		}
		else
			file->sector = sector;
	}

	if(!XX_WriteSector(file->drive->hDevice, file->sector, buffer)) return false;
	file->sector = YY_GetNextSector(file->drive, file->sector);
	return true;
}*/

// read a 'sector in file' into the buffer
static uint8_t readsector(YY_FILE* file, uint32_t required_sector_in_file)
{
	uint32_t abs_sector  = file->first_sector;
	uint32_t file_sector = 0;

	// a quick short cut
	if(required_sector_in_file > file->sector_in_buffer_file){
		abs_sector  = file->sector_in_buffer_abs;
		file_sector = file->sector_in_buffer_file;
	}
	// count up - normally this will be one call to next
	while(file_sector<required_sector_in_file){
		abs_sector = YY_GetNextSector(file->drive, abs_sector);
		++file_sector;
	}
	if(!XX_ReadSector(file->drive->hDevice, abs_sector, file->buffer)) return 0;
	file->sector_in_buffer_abs  = abs_sector;
	file->sector_in_buffer_file = file_sector;
	return 1;
}

uint16_t YY_getc(YY_FILE* file)
{
	if(file->filePointer>= file->dirn.DIR_FileSize)
		return YY_EOF;
	uint16_t required_sector_in_file = file->filePointer/512;
	if(required_sector_in_file != file->sector_in_buffer_file)
		if(readsector(file, required_sector_in_file) == 0)
			return YY_EOF;
	uint16_t index = file->filePointer % 512;
	++file->filePointer;
	return file->buffer[index];
}
