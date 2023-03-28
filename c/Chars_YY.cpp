//==========================================================================================================================
//										NOW THE CHARACTER SET STUFF
//==========================================================================================================================

#include <inttypes.h>
//#include "FAT_YY.h"

//================================================================================================================
// Character functions
//================================================================================================================
static uint32_t UTF16toUnicode(const uint16_t* text, uint16_t &index)
{
	uint16_t c = text[index];
	if(c==0)									// null
		return 0;

	if(c<0xd800 || c>=0xe000){					// one word
		++index;
		return c;
	}

	if((c & 0xdc00) != 0xd800)					// must be code 1
		return 0;

	uint16_t d = text[index+1];					// get the continuation word
	if(d==0)									// null is an error here
		return 0;

	if((d & 0xfc00)!=0xdc00)					// must be code 2
		return 0;

	index += 2;
	return ((c & 0x3ff)<<10 | (d & 0x3ff)) + 0x10000;
}
static uint32_t UTF8toUnicode(const uint8_t* text, uint16_t &index)
{
	// UTF-8 result can be up to 21 bits
	uint32_t c = text[index] & 0xff;
	if(c==0)									// null
		return 0;

	if((c&0x80)==0){							// one byte
		++index;
		return c;
	}

	if((c&0xc0)==0x80)							// error. this is the code for a continuation byte
		return 0;

	if((c&0xe0)==0xc0){							// two bytes
		c  = (c & 0x1f) << 6;
		uint8_t d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		index += 2;
		return c | (d & 0x3f);
	}

	if((c&0xf0)==0xe0){							// three bytes
		c  = (c & 0x0f) << 12;
		uint8_t d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		c |= (d & 0x3f) << 6;
		d = text[index+2] & 0xff;
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		index += 3;
		return c | (d & 0x3f);
	}

	if((c&0xf8)==0xf0){							// four bytes
		c  = (c & 0x07) << 18;
		uint8_t d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		c |= (d & 0x3f) << 12;
		d = text[index+2] & 0xff;
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		c |= (d & 0x3f) << 6;
		d = text[index+3] & 0xff;
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		index += 4;
		return c | (d & 0x3f);
	}
	return 0;
}
static int UnicodetoUTF16(uint16_t* textW, uint16_t& index, uint16_t max, uint32_t key)
{
	// taken from Wikipedia's UTF-16 page
	if((key>=0xd800 && key<0xe000) || key>0x10ffff) return 0;
	if(max && index>=max-1) return 0;
	if(key<0x10000){									// a one char value
		textW[index++] = key & 0xffff;
		return 1;
	}
	if(max && index>=max-2) return 0;
	key -= 0x10000;
	textW[index++] = ((key>>10) & 0x3ff) | 0xd800;	// high surrogate
	textW[index++] = (key & 0x3ff) | 0xdc00;		// low surrogate
	return 2;
}
static int UnicodetoUTF8(uint8_t* text, uint16_t& index, uint16_t max, uint32_t key)
{
	if((key>=0xd800 && key<=0xdfff) || key>0x10ffff)
		return 0;
	if(key<=0x7f){									// 7 bits
		if(max && index>=max-1) return 0;
		text[index++] = key & 0x7f;
		return 1;
	}
	if(key<=0x7ff){									// 11 bits
		if(max && index>=max-2) return 0;
		text[index++] = ((key>>6) & 0x1f) | 0xc0;
		text[index++] = (key & 0x3f)      | 0x80;
		return 2;
	}
	if(key<=0xffff){								// 16 bits
		if(max && index>=max-3) return 0;
		text[index++] = ((key>>12) & 0xf)  | 0xe0;
		text[index++] = ((key>>6) & 0x3f)  | 0x80;
		text[index++] = (key & 0x3f)       | 0x80;
		return 3;
	}
	if(max && index>=max-4) return 0;
	text[index++] = ((key>>18) & 0x7)  | 0xf0;		// 21 bits
	text[index++] = ((key>>12) & 0x3f) | 0x80;
	text[index++] = ((key>>6) & 0x3f)  | 0x80;
	text[index++] = (key & 0x3f)       | 0x80;
	return 4;
}

//=================================================================================================
// String functions
//=================================================================================================

uint16_t*  YY_ToWide(uint16_t* output, uint16_t cbOut, const uint8_t* input, uint16_t cbIn)
{
	uint16_t i=0, n=0;
	while(n<cbOut-1 && i<cbIn){
		uint32_t c = UTF8toUnicode(input, i);
		if(c==0 || UnicodetoUTF16(output, n, cbOut, c)==0) break;
	}
	output[n] = 0;
	return output;
}
uint8_t* YY_ToNarrow(uint8_t* output, uint16_t cbOut, const uint16_t* input, uint16_t cbIn)
{
	uint16_t i=0, n=0;
	while(n<cbOut-1 && i<cbIn){
		uint32_t c = UTF16toUnicode(input, i);
		if(c==0 || UnicodetoUTF8(output, n, cbOut, c)==0) break;
	}
	output[n] = 0;
	return output;
}
