//==========================================================================================================================
//										NOW THE CLUSTER/SECTOR STUFF
//==========================================================================================================================

#include <cstdio>
#include <cstdint>
#include <cassert>
#include <inttypes.h>		// see: https://en.cppreference.com/w/cpp/types/integer for printf'ing silly things
#include <windows.h>

#include "FAT_XX.h"
#include "FAT_YY.h"

//-------------------------------------------------------------------------------------------------
// Convert cluster number into sector address using the information in YY_DRIVE
// BEWARE: clusters are 'in this partition' while sectors are hardware absolute
//-------------------------------------------------------------------------------------------------

// Quick description of a FAT table entry

// The data area of a partition of media is divided into groups of sectors called clusters.
// There is 1,2,4,8...128 sectors to a cluster set in the definition but being a binary fraction
// I crunch the multiplier into a slide with a mask to do remainders.
// Each cluster of sectors has a FAT entry that either tells you if the sector is free, damaged,
// reserved or gives you a link to the next cluster in the chain for that file or directory.
// Hence  the FAT table is a list of numbers, one for each cluster.
// Finding the value for a FAT16 or FAT32 file is easy as they are just fit in a sector and you
// can get the right value very simply however there is a huge game in doing FAT12 as one and a
// half bytes doesn't have friendly factors in a 2 dominated world.
// also note that the clusters are numbered from 2 as 0 and 1 have special meanings.

// The top 4 bits of a FAT32 entry are reserved (FAT28?)
// 0  cluster is free
// ff6/fff6/ffffff6 cluster is reserved, do not use
// ff7/fff7/ffffff7 cluster is defective, do not use
// ff8-ffe/fff8/fffe/ffffff8-ffffffe reserved
// fff/ffff/ffffffff allocated and end of chain
// else is the number of next cluster in the chain

// Convert from a cluster number in a partition to the absolute sector number on the media
// of the first sector in that cluster
uint32_t YY_ClusterToSector(YY_DRIVE* drive, uint32_t c)
{
	return drive->cluster_begin_sector + ((c - 2) << drive->sectors_to_cluster_right_slide);
}
// Convert from an absolute sector number to the cluster number containing that sector.
uint32_t YY_SectorToCluster(YY_DRIVE* drive, uint32_t s)	// cluster containing sector
{
	return ((s - drive->cluster_begin_sector) >> drive->sectors_to_cluster_right_slide) + 2;
}
//-------------------------------------------------------------------------------------------------
// Cluster handling by FAT
//-------------------------------------------------------------------------------------------------
// I have a buffer in the YY_DRIVE to hold a 'current fat sector I'm working on' so I need to now
// if I have written to it so I know to save it before I reuse the buffer for another cluster.

// Flush the FAT buffer to both FAT tables
void YY_FlushFAT(YY_DRIVE* drive)
{
	if(drive->fat_dirty){
		XX_WriteSector(drive->hDevice, drive->last_fat_sector + drive->fat_begin_sector,				 &drive->fatTable);
		XX_WriteSector(drive->hDevice, drive->last_fat_sector + drive->fat_begin_sector+drive->fat_size, &drive->fatTable);
		drive->fat_dirty = false;
	}
}
// Read and cache a FAT sector
static void* GetFatSector(YY_DRIVE* drive, uint32_t required_fat_sector)
{
	if(drive->last_fat_sector!=required_fat_sector){
		YY_FlushFAT(drive);
		XX_ReadSector(drive->hDevice, required_fat_sector + drive->fat_begin_sector, &drive->fatTable);	// read HW sector
		drive->last_fat_sector = required_fat_sector;
//		dump(fatTable, 512);
	}
	return drive->fatTable;
}
//-------------------------------------------------------------------------------------------------
// First an explanation about how I handle FAT12 because it is the messy one to do fast and compact.
// This is my fifth method and fine tuned for speed.
// Why worry isn't it history? well my 1.44Mb FDD is FAT12 so I need it. The version I have not
// seen is FAT16.
// So... 12 bit FAT entries close packed. That's one and a half bytes LSbits first
//
//		byte0						byte1							byte2
//		A0 A1 A2 A3 A4 A5 A6 A7		A8 A9 A10 A11 B0 B1 B2 B3		B4 B5 B5 B6 B7 B8 B9 B10 B11
//
// Well one and a half is not a factor of 512 so packing means we get overlap.
// I reason that three FAT sectors are 1536 bytes and that's exactly 1024 12 bit entries so I propose to
// consider a FAT table to be sequence of 3 sector blocks (actually as 12 bits can only address 4096
// clusters there will never be more than 4 of these 3 sector blocks).
// There might not be 4 and the number of blocks might not be a multiple of three but there will be
// drive->fat_size sectors which will contain enough sectors to contain drive->count_of_clusters entries.
//
// Of those 1024 entries only two need special handling due to overhanging the sector boundaries
// so I want to pick them out for special treatment and not slow handling the other 1022 down.
//
// Similarly with the two 12 bit elements in three bytes it seems better handle them in 'pairs' totalling
// three bytes per pair. Consider them 'even' and 'odd' as all 'even' elements decode one way and
// all 'odd' elements decode in the other way.
//
// So: A 'triad' of sectors contain 512 pairs
// It would be nice to just read three sectors into one big buffer but it's hardly needed as reducing
// the number of media reads is the main speed issue.
//
//	 sector 0 contains 170 pairs, then another 'even' entry and 4 spare bits of the overhanging 'odd' entry
//	 sector 1 contains 1 byte that is part of the overhanging 'odd' entry, 170 more pairs, then another
//				byte of overhanging 'even'
//	 sector 2 contains 4 bits of overhanging 'even', an 'odd' entry and finally 170 pairs. Total 1024

// Start with the workers to put/get entries in a simple byte array
static uint16_t get12bitsA(uint8_t *array, uint16_t index)
{
	uint16_t pair = index/2;			// counting in pairs of entries (3 bytes)
	if((index&1)==0)					// consider the bytes as a b c	   v11v10v9 v8 v7 v6 v5 v4 v3 v2 v1 v0
		return array[pair*3] | ((array[pair*3+1]&0xf)  << 8);			// b3 b2 b1 b0 a7 a6 a5 a4 a3 a2 a1 a0
	else
		return ((array[pair*3+1] & 0xf0)>>4) | ((array[pair*3+2])<<4);	// c7 c6 c5 c4 c3 c2 c1 c0 b7 b6 b5 b4
}
static void set12bitsA(uint8_t *array, uint16_t index, uint16_t value)
{
	uint16_t pair = index/2;
	if((index&1)==0){														// v11v10v9 v8 v7 v6 v5 v4 v3 v2 v1 v0
		array[pair*3]	= value & 0xff;										// b3 b2 b1 b0 a7 a6 a5 a4 a3 a2 a1 a0
		array[pair*3+1] = (array[pair*3+1] & 0xf0) | ((value>>8) &0x0f);
	}
	else {
		array[pair*3+1]	= (array[pair*3+1] & 0xf) | ((value & 0xf)<<4);		// c7 c6 c5 c4 c3 c2 c1 c0 b7 b6 b5 b4
		array[pair*3+2] = value>>4;
	}
}
// now use them to read a FAT12 and get an entry
static uint32_t get12bitsFAT(YY_DRIVE* drive, uint16_t index)
{
	uint8_t triad = index/1024;				// which triad of sectors?
	index %=  1024;							// index within that triad
	if(index<341){														// 0-340 that's 170 pairs and the whole of 340 (even)
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);		// get the first sector of the triad
		return get12bitsA(array, index);
	}
	else if(index==341){												// the last 4 bits of sector0 and the first 8 bits of sector1
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);		// get the first sector of the triad
		drive->fatPrefix = array[511];									// save the overlap byte in front of the buffer
		array = (uint8_t*)GetFatSector(drive, triad*3+1) - 2;			// get the second sector of the triad
																		// set the array pointer 2 bytes before the actual sector
																		// pointing to the pair 340/341 as 0/1
		return get12bitsA(array, 1);									// get the 'odd' member of a pair (we only need one byte as we never access 340=0
	}
	else if(index<682){													// 342-681 inclusive completely within the second sector
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1) + 1;	// get the second sector of the triad
																		// set the pointer to after the overlapped element 341 so it points to 342
		return get12bitsA(array, index-342);
	}
	else if(index==682){												// this time our overlap is a whole byte and an even item
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1);		// get the second sector of the triad
		drive->fatPrefix = array[511];									// copy the byte
		array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;			// get the third sector of the triad offset the array down 1 to include the extra byte
		return get12bitsA(array, 0);									// return the first item in the array
	}
	else{																// 683-1023 inclusive an odd byte and 170 pairs all completely within sector three
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;	// get the third sector of the triad offset back one byte to the apparent start of 682
		return get12bitsA(array, index-682);							// 683->index 1 so we never needed array[0]
	}
}
// as above but write an entry to the FAT12
static void set12bitsFAT(YY_DRIVE* drive, uint16_t index, uint16_t value)
{
	uint8_t triad = index/1024;				// which triad of sectors?
	index %=  1024;							// index within that triad
	if(index<341){														// 0-340 inclusive completely within the first sector...
																		// that's 170 pairs and the 2 bytes left contain all of 340 and part of 341
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);		// get the first sector of the triad
		set12bitsA(array, index, value);
		drive->fat_dirty;
		return;
	}
	else if(index==341){												// divided the last 4 bits of sector 0 and the first 8 bits of sector1
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+0);		// get the first sector of the triad
		drive->fatPrefix = array[511];									// save the last byte of sector0 before sector1
		set12bitsA(array, 341, value);									// write to sector0, spills a byte into fatSuffix
		drive->fat_dirty = true;										// ensure the write
		array = (uint8_t*)GetFatSector(drive, triad*3+1) - 2;			// get the second sector of the triad
		set12bitsA(array, 1, value);									// put the 'odd' member of a pair spills into fatPrefix
		drive->fat_dirty;
		return;
	}
	else if(index<682){													// 342-681 inclusive completely within second sector
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1) + 1;	// get the second sector of the triad
		set12bitsA(array, index-342, value);
		drive->fat_dirty;
		return;
	}
	else if(index==682){
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+1);		// get the second sector of the triad
		set12bitsA(array, 341, value);
		drive->fat_dirty = true;
		array = (uint8_t*)GetFatSector(drive, triad*3+2) - 1;			// get the third sector of the triad
		set12bitsA(array, 0, value);									// spills into fatPrefix
		drive->fat_dirty = true;
		return;
	}
	else{																// 683-1023 inclusive completely within sector three
		uint8_t* array = (uint8_t*)GetFatSector(drive, triad*3+2)-1;	// get the third sector of the triad
		set12bitsA(array, index-682, value);							// 683->index 1 so we never need array[0]
		drive->fat_dirty = true;
		return;
	}
}
//=================================================================================================
// Manage cluster entries for all FAT types
//=================================================================================================
// Get the FAT entry for a specific Cluster
uint32_t YY_GetClusterEntry(YY_DRIVE* drive, uint32_t cluster)
{
	if(drive->fat_type==FAT32)
		return ((uint32_t*)GetFatSector(drive, cluster/128))[cluster%128] & 0xfffffff;	// not the top 4 bits

	if(drive->fat_type==FAT16)
		return ((uint16_t*)GetFatSector(drive, cluster/256))[cluster%256];

//	if(drive->fat_type==FAT12)						// implicit
		return get12bitsFAT(drive, cluster);
}
// As above but write the entry
void YY_SetClusterEntry(YY_DRIVE* drive, uint32_t cluster, uint32_t value)
{
	if(drive->fat_type==FAT32){
		uint32_t* array = (uint32_t*)GetFatSector(drive, cluster/128);
		uint32_t v = array[cluster%128] & 0xf0000000;		// preserve the top 4 bits
		v |= value & 0x0fffffff;
		array[cluster%128] = v;
		drive->fat_dirty = true;
		return;
	}

	if(drive->fat_type==FAT16){
		uint16_t* array = (uint16_t*)GetFatSector(drive, cluster/256);
		array[cluster%256] = value & 0xffff;
		drive->fat_dirty = true;
		return;
	}
	if(drive->fat_type==FAT12){
		set12bitsFAT(drive, cluster, value & 0xfff);
		drive->fat_dirty = true;
		return;
	}
}
// Find an unallocated fat cluster and mark it as 'end of chain' and return its cluster number
// return 0 on disk full
// To try and speed things up I save a value for the last fat sector I found a space in so I
// don't repeat searching from the bottom. I clear this if I do a file delete as that might
// release more clusters lower in the list.
uint32_t YY_AllocateCluster(YY_DRIVE* drive)
{
again:
	// Again I have three separate systems rather than try and put the switch in every loop
	if(drive->fat_type==FAT32){
		for(uint32_t sector=drive->fat_free_speedup; sector<drive->fat_size; ++sector){
			uint32_t* array = (uint32_t*)GetFatSector(drive, sector);
			uint32_t clusters_to_go = drive->count_of_clusters - sector*128;	// break out the limit for speed
			for(uint16_t t=0; t<128 && t<clusters_to_go; ++t){
				uint32_t v = array[t];
				if((t & 0xfffffff)==0){		// unallocated
					v |= 0x0fffffff;		// mark as 'end of chain' (preserve the top 4 bits)
					array[t] = v;
					drive->fat_dirty = true;
					drive->fat_free_speedup = sector;
					return t + sector*128;
				}
			}
		}
end:	if(drive->fat_free_speedup){		// failed so dump the speed-up and try again
			drive->fat_free_speedup = 0;
			goto again;
		}
		return 0;			// really failed
	}
	if(drive->fat_type==FAT16){
		for(uint32_t sector = drive->fat_free_speedup; sector<drive->fat_size; ++sector){
			uint16_t* array = (uint16_t*)GetFatSector(drive, sector);
			uint32_t clusters_to_go = drive->count_of_clusters - sector*256;	// break out the limit for speed
			for(uint16_t t=0; t<256 && t<clusters_to_go; ++t){
				uint16_t v = array[t];
				if(t==0){					// unallocated
					array[t] = 0xffff;		// allocated as end of chain
					drive->fat_dirty = true;
					drive->fat_free_speedup = sector;
					return t + sector*256;
				}
			}
		}
		goto end;
	}
	// If we get here it's FAT12 time again
	for(uint32_t sector=drive->fat_free_speedup; sector<drive->fat_size; sector+=3){	// do them 3 at a time as usual
		uint32_t clusters_to_go = drive->count_of_clusters - (sector/3)*1023;			// break out the limit for speed
		// sector 0
		uint8_t* array = (uint8_t*)GetFatSector(drive, sector);
		for(uint16_t index=0; index<341 && index<clusters_to_go; ++index){	// do 0-340 inclusive that's 170 pairs and one extra
			uint16_t element = get12bitsA(array, index);				// which leaves us 4 bytes to overhang
			if(element==0){
				set12bitsA(array, index, 0xfff);						// mark End of Chain
				drive->fat_dirty = true;
				drive->fat_free_speedup = sector;
				return (sector/3)*1024 + index;							// return index
			}
		}
		// do the overlap on 341
		if(341<clusters_to_go){
			drive->fatPrefix = array[511];						// copy the last byte, we want 4 bits as an 'odd' element
			array = (uint8_t*)GetFatSector(drive, sector+1)-2;	// set the array start at -2 so the pair containing 341 is the first
			uint16_t element = get12bitsA(array, 1);			// get element 1 (so I don't need array[0])
			if(element==0){
				set12bitsA(array, 1, 0xfff);					// mark End of Chain overwrites into fatPrefix
				drive->fat_dirty = true;
				array = (uint8_t*)GetFatSector(drive, sector);	// get sector 1 to do the bits in there
				set12bitsA(array, 341, 0xfff);					// write the end of chain (overflows into fatSuffix)
				drive->fat_dirty = true;
				drive->fat_free_speedup = sector;
				return (sector/3)*1024 + 341;					// return index
			}
		}
		// do the sector+1 which we already have in buffer at -2 hence index 0 = 340 and index 2 is 342
		for(uint16_t index=342; index<681 && index<clusters_to_go; ++index){		// do 342-681 inclusive
			uint16_t element = get12bitsA(array, index-340);				// allow for array being '-2'
			if(element==0){
				set12bitsA(array, index-340, 0xfff);						// mark End of Chain
				drive->fat_dirty = true;
				drive->fat_free_speedup = sector;
				return (sector/3)*1024 + index;								// return index
			}
		}
		// do the overlap at 682
		if(682<clusters_to_go){
			drive->fatPrefix = array[511];							// copy the last byte
			array = (uint8_t*)GetFatSector(drive, sector+2)-1;		// -1 so index0 is 682 (even)
			uint16_t element = get12bitsA(array, 0);
			if(element==0){
				set12bitsA(array, 0, 0xfff);					// mark End of Chain
				drive->fat_dirty = true;
				array = (uint8_t*)GetFatSector(drive, sector+1);
				array[511] = 0xff;								// simpler
				drive->fat_dirty = true;
				drive->fat_free_speedup = sector;
				return (sector/3)*1024 + 682;					// return index
			}
		}
		// do the sector+1 which we already have in buffer at -2 hence index 0 = 340 and index 2 is 342
		for(uint16_t index=683; index<1024 && index<clusters_to_go; ++index){	// do 342-681 inclusive
			uint16_t element = get12bitsA(array, index-682);				// allow for array being '-2'
			if(element==0){
				set12bitsA(array, index-682, 0xfff);						// mark End of Chain
				drive->fat_dirty = true;
				drive->fat_free_speedup = sector;
				return (sector/3)*1024 + index;								// return index
			}
		}
	}
	goto end;	// we failed but try again without the speed-up just in case...
}
//-------------------------------------------------------------------------------------------------
// get the next sector in a file
//-------------------------------------------------------------------------------------------------
uint32_t YY_GetNextSector(YY_DRIVE* drive, uint32_t current_sector)
{
	if(current_sector < drive->cluster_begin_sector)	// beware the FAT12/FAT16 root directory
		return ++current_sector >= drive->cluster_begin_sector ? 0 : current_sector;

	uint32_t x = (current_sector+1) & drive->sectors_in_cluster_mask;
	if(x) return current_sector+1;
	// if x==0 we have reached the end of the cluster
	uint32_t n = YY_GetClusterEntry(drive, YY_SectorToCluster(drive, current_sector));
	if(n==0xfffffff) return 0;										// EOF
	return YY_ClusterToSector(drive, n);								// first sector in cluster
}
