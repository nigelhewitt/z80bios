//------------------------------------------------------------------------------------------
//
//		charset.cpp 		Added 2018 to manage UTF16 properly
//							Copyright © me I guess 2018
//
//			By Nigel Hewitt	All my own work - no one else is to blame
//
// -----------------------------------------------------------------------------------------

#include "framework.h"
#include "charset.h"

// THese are the routines to manage mapping between the various character sets and to resolve
// the whole concept of an index and a column

// The problem:
// char[] worked for 7 bit NC code
// It extended to DOS8 and WIN8 character sets reasonably cleanly as unsigned char.
// These shared the idea that an index into a line of characters equated to a column number.
// Once you go to Multi-byte or Unicode that all falls apart.

// Our files are in char[]. They can be DOS8 (or its subset WordStar), WIN8 or Multi-byte.
// We can write the screen with WIN8 so DOS8 needs to be translated.
// You cannot write Multi-byte to the screen.
// You need to convert char[] to WCHAR[] which is UTF-8 to UTF-16 and write that.
// Notice that a Unicode char can be 21 bits so even WCHAR may need two WCHARS to make a full character

// Now add the snag that we might be dealing with multi megabyte files
// a DWORD addresses 4294967296 values so 4Gbytes so DWORDs will do what I want.
// I prefer to use DWORD, an unsigned 32 bit, rather than anything compiler dependent like ULONG
// although we do have unsigned __int64 on tap if we get desperate.

// these are the routines I settled on
// Notice no throws, just nice clean error returns

// local copy of routine in Editor.cpp so we can unit test
UTF8 XXtoWIN(UNICODE c, bool &bad);
//=================================================================================================
// routines to handle individual characters in arrays
//=================================================================================================

// convert a 21 bit Unicode character into one or two WCHARs using UTF-16 rules
// the index will return<max-1 so you can always write a trailing zero, max==0 is ignored
// increments working pointer
// returns number of WCHARs used or zero on error
int putchar(PUTF16 textW, DWORD& index, DWORD max, UNICODE key)
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
// convert a 21 bit Unicode character into one to four chars using UTF-8 rules
// the index will return<=max-1 so you can write a trailing zero, max==0 is ignored
// increments working pointer
// returns number of chars used or zero on error
int putchar(PUTF8 text, DWORD& index, DWORD max, UNICODE key)
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
// how many UTF8 bytes? (used for the status bar description)
int charbytes(UNICODE key)
{
	if((key>=0xd800 && key<=0xdfff) || key>0x10ffff)
		return 0;
	if(key<=0x7f)								// 7 bits
		return 1;
	if(key<=0x7ff)								// 11 bits
		return 2;
	if(key<=0xffff)								// 16 bits
		return 3;
	return 4;
}
// get a 21 bit Unicode character from a UTF16 (WCHAR) array and increment the pointer using UTF16 rules
// terminate on a \0 and don't increment the index so further calls also return the  \0
// return 0 for missing continuation or illegal
UNICODE getchar(PCUTF16 text, DWORD &index)
{
	UTF16 c = text[index];
	if(c==0)									// null
		return 0;

	if(c<0xd800 || c>=0xe000){					// one word
		++index;
		return c;
	}

	if((c & 0xdc00) != 0xd800)					// must be code 1
		return 0;

	UTF16 d = text[index+1];					// get the continuation word
	if(d==0)									// null is an error here
		return 0;

	if((d & 0xfc00)!=0xdc00)					// must be code 2
		return 0;

	index += 2;
	return ((c & 0x3ff)<<10 | (d & 0x3ff)) + 0x10000;
}
// get a 21 bit Unicode character from a UTF8 (char) array and increment the pointer using UTF-8 rules
// terminate on a \0 and don't increment the index as above
// return 0 for missing continuation or illegal
UNICODE getchar(PCUTF8 text, DWORD &index)
{
	// UTF-8 result can be up to 21 bits
	UNICODE c = text[index] & 0xff;
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
		UTF8 d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		index += 2;
		return c | (d & 0x3f);
	}

	if((c&0xf0)==0xe0){							// three bytes
		c  = (c & 0x0f) << 12;
		UTF8 d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		c |= (d & 0x3f) << 6;
		d = text[index+2] & 0xff;
		if(d==0 || (d & 0x80)!=0x80) return 0;	// bad continuation
		index += 3;
		return c | (d & 0x3f);
	}

	if((c&0xf8)==0xf0){							// four bytes
		c  = (c & 0x07) << 18;
		UTF8 d = text[index+1];
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
//=================================================================================================
// convert between multi-byte and wide
//=================================================================================================

bool mbtowide(PCUTF8 c, PUTF16 w, DWORD nw)
{
	DWORD ic=0, iw=0;
	UNICODE key;
	while(key=getchar(c, ic))
		if(!putchar(w, iw, nw, key)){
			w[iw] = 0;
		   return false;
		}
	w[iw] = 0;
	return true;
}
bool widetomb(PCUTF16 w, PUTF8 c, DWORD nc)
{
	DWORD ic=0, iw=0;
	UNICODE key;
	while(key=getchar(w, iw)){
		if(key==L'\r')
			continue;
		if(!putchar(c, ic, nc, key)){
			c[ic] = 0;
			return false;
		}
	}
	c[ic] = 0;
	return true;
}
//=================================================================================================
// convert between UTF-8 and WIN using \u1a9; and \U124; for hex and decimal representations
//=================================================================================================
#if 0
bool mbtocode(PCUTF8 m, PUTF8 c, DWORD cb, bool dec /*=false*/)
{
	DWORD im=0, ic=0;
	UNICODE key;
	while(key=getchar(m, im)){			// unpack UTF8
		bool bad = false;
		// first check for \ and trap it out as \\ to prevent snags
		if(m[im-1]=='\\'){
			if(ic+3>=cb){
				c[ic] = 0;
				return false;
			}
			c[ic++] = '\\';
			c[ic++] = '\\';
			continue;
		}
		UTF8 k = XXtoWIN(key, bad);		// can we make a simple windows char?
		if(!bad){						// that was easy then
			if(ic+2>=cb){
				c[ic] = 0;
				return false;
			}
			c[ic++] = k;
		}
		else{
			char temp[10];
			wsprintf(temp, dec?"\\U%d;":"\\u%x;", key);
			int j = strnlen_s(temp, _countof(temp));
			if(ic+j+1>=cb){
				c[ic] = 0;
				return false;
			}
			for(int i=0; i<j; c[ic++] = temp[i++]);
		}
	}
	c[ic] = 0;
	return true;
}
bool codetomb(PCUTF8 c, PUTF8 m, DWORD cb)
{
	DWORD ic=0, im=0;
	char k;
	while((k=c[ic++])!=0){
		if(k=='\\'){
			if(c[ic]=='\\'){		// is this the trapped \ ?
				m[im++] = '\\';
				++ic;
				continue;
			}
			else if(c[ic]=='u'){	// unpack hex
				++ic;
				UNICODE cx=0;
				while(ishex(c[ic])){
					cx *= 16;
					cx += tohex(c[ic++]);
				}
				if(c[ic++]!=';'){
					m[im] = 0;
					return false;
				}
				putchar(m, im, cb, cx);
				continue;
			}
			else if(c[ic]=='U'){	// unpack decimal
				++ic;
				UNICODE cx=0;
				while(isdigit(c[ic])){
					cx *= 10;
					cx += todigit(c[ic++]);
				}
				if(c[ic++]!=';'){
					m[im] = 0;
					return false;
				}
				putchar(m, im, cb, cx);
				continue;
			}
			else{
				m[im] = 0;
				return false;
			}
		}
		m[im++] = k;
	}
	m[im] = 0;
	return true;
}
#endif
//=================================================================================================
// move forward and back in the arrays
//=================================================================================================

bool nextchar(PCUTF16 text, DWORD &index)
{
	UTF16 c = text[index];
	if(c==0)									// null
		return false;

	if(c<0xd800 || c>=0xe000){					// one byte
		++index;
		return true;
	}
	UTF16 d = text[index+1];					// get the continuation byte
	if(d==0)									// null is an error here
		return false;

	index += 2;
	return (d & 0xfc00)==0xdc00;				// only 0 to 0x3ff allowed
}
bool nextchar(PCUTF8 text, DWORD &index)
{
	// UTF-8 result can be up to 21 bits
	UTF8 c = text[index];
	if(c==0)									// null
		return false;

	if((c&0x80)==0){							// one byte
		++index;
		return true;
	}

	if((c&0xc0)==0x80)							// error. this is the code for a continuation byte
		return false;

	if((c&0xe0)==0xc0){							// two bytes
		UTF8 d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		index += 2;
		return true;
	}

	if((c&0xf0)==0xe0){								// three bytes
		UTF8 d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		d = text[index+2];
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		index += 3;
		return true;
	}

	if((c&0xf8)==0xf0){								// four bytes
		UTF8 d = text[index+1];
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		d = text[index+2] & 0xff;
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		d = text[index+3];
		if(d==0 || (d & 0x80)!=0x80) return false;	// bad continuation
		index += 4;
		return true;
	}
	return false;
}
bool prevchar(PCUTF16 text, DWORD &index)
{
	if(index==0) return false;
	UTF16 c = text[index-1];
	if((c&0xfc00)==0xdc00){				// if a continuation UTF16
		if(index==1) return false;
		c = text[index-2];
		if((c&0xfc00)!=0xd800) return false;
		index -= 2;
	}
	else
		--index;
	return true;
}
bool prevchar(PCUTF8 text, DWORD &index)
{
	if(index==0) return false;
//	--index;
	UTF8 c = text[index-1];
	if(c==0) return false;						// a null, what is this doing here?

	if((c&0xc0)!=0x80){
		--index;
		return true;				// if not a continuation byte...
	}

	// processing for continuations
	if(index==1) return false;
	int continuations=1;
//	--index;
	while(continuations<3 && index-continuations && (text[index-continuations-1]&0xc0)==0x80){
		++continuations;
//		--index;
	}
	if(continuations>3 || index==0) return false;

	c = text[index-continuations-1];		// this must be the first byte of the stream

	if(		(continuations==1 && (c&0xe0)==0xc0)
		 || (continuations==2 && (c&0xf0)==0xe0)
		 || (continuations==3 && (c&0xf8)==0xf0)){
		index -= continuations + 1;
		return true;
	}
	return false;
}
//=================================================================================================
// convert between indexes and character counts (not column as it doesn't to tabs)
//=================================================================================================

bool indextochar(PCUTF16 text, DWORD index, DWORD &col)
{
	col = 0;
	DWORD i=0;
	while(i<index){
		if(!nextchar(text, i))
			return false;
		++col;
	}
	return i==index;
}
bool chartoindex(PCUTF16 text, DWORD col, DWORD &index)
{
	index = 0;
	DWORD i=0;
	while(i++<col)
		if(!nextchar(text, index))
			return false;
	return true;
}
bool indextochar(PCUTF8 text, DWORD index, DWORD &col)
{
	col = 0;
	DWORD i=0;
	while(i<index){
		if(!nextchar(text, i))
			return false;
		++col;
	}
	return i==index;
}
bool chartoindex(PCUTF8 text, DWORD col, DWORD &index)
{
	index = 0;
	DWORD i=0;
	while(i++<col)
		if(!nextchar(text, index))
			return false;
	return true;
}
//=================================================================================================
// routines to mimic normal string functions
//=================================================================================================

// count the elements
int length(PCUTF8 str)
{
	if(str==nullptr) return 0;
	int n=0;
	while(str[n]) ++n;
	return n;
}
// count the elements
int length(PCUTF16 strW)
{
	if(strW==nullptr) return 0;
	int n=0;
	while(strW[n]) ++n;
	return n;
}
// count the characters
int chars(PCUTF8 str)
{
	if(str==nullptr) return 0;
	int n=0;
	DWORD i=0;
	while(getchar(str, i)) ++n;
	return n;
}
// count the characters
int chars(PCUTF16 strW)
{
	if(strW==nullptr) return 0;
	int n=0;
	DWORD i=0;
	while(getchar(strW, i)) ++n;
	return n;
}
// strcpy()
bool copy(PUTF8 dest, int cb, PCUTF8 src, int n /* =-1 */)
{
	if(dest==nullptr || src==nullptr) return false;
	int i;
	for(i=0; src[i] && i<cb-1 && (n==-1 || i<n); ++i)
		dest[i] = src[i];
	dest[i] = 0;
	return src[i]==0 || i==n;
}
bool copy(PUTF16 dest, int cb, PCUTF16 src, int n /* =-1 */)
{
	if(dest==nullptr || src==nullptr) return false;
	int i;
	for(i=0; src[i] && i<cb-1 && (n==-1 || i<n); ++i)
		dest[i] = src[i];
	dest[i] = 0;
	return src[i]==0 || i==n;
}
// strdup()
PUTF8 duplicate(PCUTF8 str)
{
	int n=length(str);
	auto ptr = new UTF8[n+1];
	copy(ptr, n+1, str);
	return ptr;
}
PUTF16 duplicate(PCUTF16 strW)
{
	int n=length(strW);
	auto ptr = new UTF16[n+1];
	copy(ptr, n+1, strW);
	return ptr;
}
// strcmp strncmp, strcmpi, strncmpi
int compare(PCUTF8 str1, PCUTF8 str2, int n /* =-1 */)
{
	if(str1==nullptr) str1=reinterpret_cast<PCUTF8>("");
	if(str2==nullptr) str2=reinterpret_cast<PCUTF8>("");
	DWORD i1=0, i2=0;
	UNICODE c1{}, c2{};
	int i=0;
	do{
		c1 = getchar(str1, i1);
		c2 = getchar(str2, i2);
		if(c1<c2) return -1;
		if(c1>c2) return 1;
		++i;
	}while(c1 && c2 && (n==-1 || i<n));
	return 0;
}
int compare(PCUTF16 str1, PCUTF16 str2, int n /* =-1 */)
{
	if(str1==nullptr) str1=reinterpret_cast<PCUTF16>(L"");
	if(str2==nullptr) str2=reinterpret_cast<PCUTF16>(L"");
	DWORD i1=0, i2=0;
	UNICODE c1{}, c2{};
	int i=0;
	do{
		c1 = getchar(str1, i1);
		c2 = getchar(str2, i2);
		if(c1<c2) return -1;
		if(c1>c2) return 1;
		++i;
	}while(c1 && c2 && (n==-1 || i<n));
	return 0;
}
int comparei(PCUTF8 str1, PCUTF8 str2, int n /* =-1 */)
{
	if(str1==nullptr) str1=reinterpret_cast<PCUTF8>("");
	if(str2==nullptr) str2=reinterpret_cast<PCUTF8>("");
	DWORD i1=0, i2=0;
	UNICODE c1{}, c2{};
	int i=0;
	do{
		c1 = tolower(getchar(str1, i1));
		c2 = tolower(getchar(str2, i2));
		if(c1<c2) return -1;
		if(c1>c2) return 1;
		++i;
	}while(c1 && c2 && (n==-1 || i<n));
	return 0;
}
int comparei(PCUTF16 str1, PCUTF16 str2, int n /* =-1 */)
{
	if(str1==nullptr) str1=reinterpret_cast<PCUTF16>(L"");
	if(str2==nullptr) str2=reinterpret_cast<PCUTF16>(L"");
	DWORD i1=0, i2=0;
	UNICODE c1{}, c2{};
	int i=0;
	do{
		c1 = tolower(getchar(str1, i1));
		c2 = tolower(getchar(str2, i2));
		if(c1<c2) return -1;
		if(c1>c2) return 1;
		++i;
	}while(c1 && c2 && (n==-1 || i<n));
	return 0;
}
// strtok_s
static bool isinList(UNICODE c, PCUTF8 list)
{
	DWORD index=0;
	while(true){
		UNICODE k = getchar(list, index);
		if(k==0)
			return false;
		if(k==c)
			return true;
	}
}
// this is my personal version and not very posix
PUTF8 token(PUTF8 str, PCUTF8 delimiters, UTF8** context)
{
	if(str!=nullptr) *context = str;							// just starting
	else str = *context;										// or continue from where we were
	if(context==nullptr || *context==nullptr) return nullptr;	// we finished already

	// skip leading spaces
	if(isspace(*str)) ++str;				// all spaces are only one UTF8 element so easy
	if(*str==0){							// if we ran out...
		*context = nullptr;
		return nullptr;
	}
	PUTF8 save = str;						// save the start of token
	while(true){
		DWORD index=0;
		UNICODE c = getchar(str, index);
		if(c==0){							// end of string
			*context = nullptr;				// there is no next time
			return save;
		}
		if(isinList(c, delimiters)){		// a delimiter
			*context = str + index;			// next character
			*str = 0;						// delimiter
			return save;
		}
		str += index;
	}
}
// strcat()
bool concat(PUTF8 dest, DWORD cb, PCUTF8 src)
{
	DWORD n1 = length(dest);
	DWORD n2 = length(src);
	if(n1+n2+1>cb) return false;
	memcpy(dest+n1, src, n2+1);
	return true;
}
bool concat(PUTF16 dest, DWORD cb, PCUTF16 src)
{
	DWORD n1 = length(dest);
	DWORD n2 = length(src);
	if(n1+n2+1>cb) return false;
	memcpy(dest+n1, src, (n2+1)*sizeof(UTF16));
	return true;
}
// horrible little trick that assumes the buffer is 'big enough'
void insert(PUTF8 p, DWORD i, UTF8 c)
{
	DWORD n = length(p);
	memmove(p+i+1, p+i, n-i+1);	// don't forget to include the trailing null
	p[i] = c;
}

// Fixes for DOS and WS.  This works with my keyboard but...
UNICODE translateKey(UNICODE key)
{
	if(key==163)					// £ sign
		return L'£';
	if(key==172)					// ¬ sign
		return L'¬';
	return key;
}

//=================================================================================================
// copied from Editor.cpp
//=================================================================================================

UTF16 XXcp1252W[256] = {
	//    0      1      2      3      4      5      6      7      8      9      A      B      C      D      E      F
	L'⓵',  L'☺',  L'☻',  L'♥',  L'♦',  L'♣',  L'♠',  L'●',  L'◘',  L'\t', L'\n', L'♂',  L'♀',  L'♪',  L'♫',  L'☼',		// 0
	L'►',  L'◄',  L'↕',  L'‼',  L'¶',  L'§',  L'▬',  L'↨',  L'↑',  L'↓',  L'→',  L'←',  L'∟',  L'↔',  L'▲',  L'▼',		// 1
	L' ',  L'!',  L'\"', L'#',  L'$',  L'%',  L'&',  L'\'', L'(',  L')',  L'*',  L'+',  L',',  L'-',  L'.',  L'/',		// 2 U+20 - U+2F
	L'0',  L'1',  L'2',  L'3',  L'4',  L'5',  L'6',  L'7',  L'8',  L'9',  L':',  L';',  L'<',  L'=',  L'>',  L'?',		// 3 U+30 - U+3F
	L'@',  L'A',  L'B',  L'C',  L'D',  L'E',  L'F',  L'G',  L'H',  L'I',  L'J',  L'K',  L'L',  L'M',  L'N',  L'O',		// 4 U+40 - U+4F
	L'P',  L'Q',  L'R',  L'S',  L'T',  L'U',  L'V',  L'W',  L'X',  L'Y',  L'Z',  L'[',  L'\\', L']',  L'^',  L'_',		// 5 U+50 - U+5F
	L'`',  L'a',  L'b',  L'c',  L'd',  L'e',  L'f',  L'g',  L'h',  L'i',  L'j',  L'k',  L'l',  L'm',  L'n',  L'o',		// 6 U+60 - U+6F
	L'p',  L'q',  L'r',  L's',  L't',  L'u',  L'v',  L'w',  L'x',  L'y',  L'z',  L'{',  L'|',  L'}',  L'~',  L'⌂',		// 7 U+70 - U+7F
	L'€',  L'❷',  L'‚',  L'ƒ',  L'„',  L'…',  L'†',  L'‡',  L'ˆ',  L'‰',  L'Š',  L'‹',  L'Œ',  L'❸',  L'Ž',  L'❹',		// 8 U+80 - U+8F (81 8D and 8F no show)
	L'❺',  L'‘',  L'’',  L'“',  L'”',  L'•',  L'–',  L'–',  L'˜',  L'™',  L'š',  L'›',  L'œ',  L'❻',  L'ž',  L'Ÿ',		// 9 U+90 - U+9F (98 is an accent so no width, 90 9D missing, 9D 9E 9F dubious)
	L'❽',  L'¡',  L'¢',  L'£',  L'¤',  L'¥',  L'¦',  L'§',  L'¨',  L'©',  L'ª',  L'»',  L'¬',  L'❼',  L'®',  L'¯',		// A U+A0 - U+AF (A0 is nobreak space, AD is a character but not in the VS font)
	L'°',  L'±',  L'²',  L'³',  L'´',  L'µ',  L'¶',  L'·',  L'¸',  L'¹',  L'º',  L'»',  L'¼',  L'½',  L'¾',  L'¿',		// B U+B0 - U+BF
	L'À',  L'Á',  L'Â',  L'Ã',  L'Ä',  L'Å',  L'Æ',  L'Ç',  L'È',  L'É',  L'Ê',  L'Ë',  L'Ì',  L'Í',  L'Î',  L'Ï',		// C U+C0 - U+CF
	L'Ð',  L'Ñ',  L'Ò',  L'Ó',  L'Ô',  L'Õ',  L'Ö',  L'×',  L'Ø',  L'Ù',  L'Ú',  L'Û',  L'Ü',  L'Ý',  L'Ý',  L'ß',		// D U+D0 - U+DF
	L'à',  L'á',  L'â',  L'ã',  L'ä',  L'å',  L'æ',  L'ç',  L'è',  L'é',  L'ê',  L'ë',  L'ì',  L'í',  L'î',  L'ï',		// E U+E0 - U+EF
	L'ð',  L'ñ',  L'ò',  L'ó',  L'ô',  L'õ',  L'ö',  L'÷',  L'ø',  L'ù',  L'ú',  L'û',  L'ü',  L'ý',  L'þ',  L'ÿ'		// F U+F0 - U+FF
};

UTF8 XXtoWIN(UNICODE c, bool &bad)
{
	if(c>=0x20 && c<=0x7e) return c & 0xff;		//  speed up
	for(int i=0; i<0x20; ++i)
		if(c==XXcp1252W[i])
			return i;
	for(int i=0x7f; i<=0xff; ++i)
		if(c==XXcp1252W[i])
			return i;
	bad = true;
	return '?';
}
