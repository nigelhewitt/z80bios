#pragma once

#pragma pack(1)			// Please no adding padding bytes to improve the bus speed Mr. C++

//-------------------------------------------------------------------------------------------------
// Routines in FAT.cpp
//-------------------------------------------------------------------------------------------------
void	error();							// windows error codes to readable text
void	dump(void* buffer, int cb=512);		// dump in familiar bytes/chars blocks
extern bool bVerbose;						// turn on process messages

// routines in FAT.cpp that need to be coded in Z80 speak
HANDLE	XX_OpenDevice(const char* what_to_open);						// hardware Open
bool	XX_ReadSector(HANDLE hDevice, uint32_t sector, void* buffer);	// hardware Read
bool	XX_WriteSector(HANDLE hDevice, uint32_t sector, void* buffer);	// hardware write
void*	XX_alloc(uint16_t nBytes);										// allocator
void	XX_free(void* item);											// de-allocator

