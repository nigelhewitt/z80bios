#pragma once

// Start by getting the names right not for the compiler but for readability
// I use chars et al for windows internal stuff but my data has to be very specific or it gets in a mess
// (things starting __ are 'implementation reserved' so we must never define one but these are legal)
using UNICODE	= unsigned __int32;			// 21 bit Unicode char
using UTF8		= unsigned __int8;			// a single element in a UTF-8 stream
using UTF16		= unsigned __int16;			// a single element in a UTF-16 stream
using PUTF8		= unsigned __int8*;			// pointers
using PUTF16	= unsigned __int16*;
using PCUTF8	= const unsigned __int8*;	// const pointers
using PCUTF16	= const unsigned __int16*;
using QWORD		= unsigned __int64;			// printf as "%I64d"

// put a char into an array moving up the index
// if max==0 I ignore it but beware...)
int putchar(PUTF16 textW, DWORD& index, DWORD max, UNICODE key);
int putchar(PUTF8 text, DWORD& index, DWORD max, UNICODE key);
int charbytes(UNICODE key);					// number of UTF8s required

// get a char from an array
UNICODE getchar(PCUTF16 text, DWORD &index);
UNICODE getchar(PCUTF8 text, DWORD &index);

// convert between UTF-8 and UTF-16
bool mbtowide(PCUTF8 c, PUTF16 w, DWORD nw);
bool widetomb(PCUTF16 w, PUTF8 c, DWORD nc);

// convert between UTF-8 and WIN using \u1a9 and \U124
//bool mbtocode(PCUTF8 m, PUTF8 mb, DWORD cb, bool dec=false);
//bool codetomb(PCUTF8 c, PUTF8 mb, DWORD cb);


// move forward and back in arrays allowing for characters being 1,2,3,4 bytes
bool nextchar(PCUTF16 text, DWORD &index);
bool nextchar(PCUTF8 text, DWORD &index);
bool prevchar(PCUTF16 text, DWORD &index);
bool prevchar(PCUTF8 text, DWORD &index);

// now convert the counters (col is the number of the displayable character)
bool indextochar(PCUTF16 text, DWORD index, DWORD &col);
bool chartoindex(PCUTF16 text, DWORD col, DWORD &index);
bool indextochar(PCUTF8 text, DWORD index, DWORD &col);
bool chartoindex(PCUTF8 text, DWORD col, DWORD &index);

// mimic standard Windows/posix functions
// element counts (NOT character counts)
int length(PCUTF8 str);
int length(PCUTF16 strW);
// displayable character counts
int chars(PCUTF8 str);
int chars(PCUTF16 str);
// strcpy_s() and strncpy_s
bool copy(PUTF8 dest, int cb, PCUTF8 src, int n=-1);
inline bool copy(PUTF8 dest, int cb, const char* src, int n=-1){ return copy(dest, cb, reinterpret_cast<PCUTF8>(src), n); }
bool copy(PUTF16 dest, int cb, PCUTF16 src, int n=-1);
inline bool copy(PUTF16 dest, int cb, const WCHAR* src, int n=-1) { return copy(dest, cb, reinterpret_cast<PCUTF16>(src), n); }
// strdup()   must be removed with delete[]
PUTF8  duplicate(PCUTF8 str);
PUTF16 duplicate(PCUTF16 strW);
// strcmp strncmp, strcmpi, strncmpi
int compare(PCUTF8 str1, PCUTF8 str2, int n=-1);
int compare(PCUTF16 str1, PCUTF16 str2, int n=-1);
int comparei(PCUTF8 str1, PCUTF8 str2, int n=-1);
int comparei(PCUTF16 str1, PCUTF16 str2, int n=-1);
// strtok_s
PUTF8 token(PUTF8 str, PCUTF8 delimiters, UTF8** context);
inline PUTF8 token(PUTF8 str, const char* delimiters, UTF8** context){ return token(str, reinterpret_cast<PCUTF8>(delimiters), context); }

// strcat_s
bool concat(PUTF8 dest, DWORD cb, PCUTF8 src);
inline bool concat(PUTF8 dest, DWORD cb, const char* src){ return concat(dest, cb, reinterpret_cast<PCUTF8>(src)); }
bool concat(PUTF16 dest, DWORD cb, PCUTF16 src);
inline bool concat(PUTF16 dest, DWORD cb, const WCHAR* src){ return concat(dest, cb, reinterpret_cast<PCUTF16>(src)); }

void insert(PUTF8 p, DWORD index, UTF8 c);			// insert a single char

inline bool isspace(UTF8 c){ return c==' ' || c=='\t'; }
inline bool isupper(UTF8 c){ return c>='A' && c<='Z'; }
inline bool islower(UTF8 c){ return c>='a' && c<='z'; }
inline bool isalpha(UTF8 c){ return (c>='a' && c<='z') || (c>='A' && c<='Z'); }
inline bool isdigit(UTF8 c){ return c>='0' && c<='9'; }
inline bool ishex  (UTF8 c){ return (c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'); }

inline bool isspace(UTF16 c){ return c==' ' || c=='\t'; }
inline bool isupper(UTF16 c){ return c>='A' && c<='Z'; }
inline bool islower(UTF16 c){ return c>='a' && c<='z'; }
inline bool isalpha(UTF16 c){ return (c>='a' && c<='z') || (c>='A' && c<='Z'); }
inline bool isdigit(UTF16 c){ return c>='0' && c<='9'; }
inline bool ishex  (UTF16 c){ return (c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'); }

inline bool isspace(UNICODE c){ return c==' ' || c=='\t'; }
inline bool isupper(UNICODE c){ return c>='A' && c<='Z'; }
inline bool islower(UNICODE c){ return c>='a' && c<='z'; }
inline bool isalpha(UNICODE c){ return (c>='a' && c<='z') || (c>='A' && c<='Z'); }
inline bool isdigit(UNICODE c){ return c>='0' && c<='9'; }
inline bool ishex  (UNICODE c){ return (c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'); }

inline UTF8    tolower(UTF8 c)   { if(isupper(c)) return c|0x20;  return c; }
inline UTF8    toupper(UTF8 c)   { if(islower(c)) return c&~0x20; return c; }
inline UTF16   tolower(UTF16 c)  { if(isupper(c)) return c|0x20;  return c; }
inline UTF16   toupper(UTF16 c)  { if(islower(c)) return c&~0x20; return c; }
inline UNICODE tolower(UNICODE c){ if(isupper(c)) return c|0x20;  return c; }
inline UNICODE toupper(UNICODE c){ if(islower(c)) return c&~0x20; return c; }

inline int tohex(UTF8 c)     { if(c>='0' && c<='9') return c-'0'; if(c>='a' && c<='f') return c-'a'+10; if(c>='A' && c<='F') return c-'A'+10; return 0; }
inline int tohex(UTF16 c)    { if(c>='0' && c<='9') return c-'0'; if(c>='a' && c<='f') return c-'a'+10; if(c>='A' && c<='F') return c-'A'+10; return 0; }
inline int tohex(UNICODE c)  { if(c>='0' && c<='9') return c-'0'; if(c>='a' && c<='f') return c-'a'+10; if(c>='A' && c<='F') return c-'A'+10; return 0; }
inline int todigit(UTF8 c)   { if(c>='0' && c<='9') return c-'0'; return 0; }
inline int todigit(UTF16 c)  { if(c>='0' && c<='9') return c-'0'; return 0; }
inline int todigit(UNICODE c){ if(c>='0' && c<='9') return c-'0'; return 0; }

// a fix for DOS and WS for £ and ¬
UNICODE translateKey(UNICODE key);
