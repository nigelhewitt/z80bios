// process.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

int crash(const char* obit)
{
	MessageBox(0, obit, "Z80Debugger", MB_OK);
	return 0;
}

//=================================================================================================
//	read the SDL file
//		<source file>|<src line>|<definition file>|<def line>|<page>|<value>|<type>|<data>
//=================================================================================================

std::vector<const char*>files{};
std::vector<SDL> sdl{};

// I don't want to have 1000 copies of "bios1.asm" so I'll index them
int getFileName(const char* p, int& index)
{
	// first get the file name
	char temp[100];
	int i;
	for(i=0; i<sizeof(temp)-1 && p[index] && p[index]!='|'; temp[i++] = p[index++]);
	temp[i] = 0;
	if(p[index]) ++index;		// move over the |

	if(strlen(temp)==0) return 0;

	// then find it in the vector
	for(i=0; i<files.size(); ++i)
		if(_stricmp(temp, files[i])==0)
			return i;
	files.push_back(_strdup(temp));
	return i;
}
// get an integer and move over a : but not a |
int getInt(const char* p, int& index)
{
	int i=0;
	bool neg = false;
	if(p[index]=='-'){
		neg = true;
		++index;
	}
	while(isdigit(p[index])){
		i *= 10;
		i += p[index++] - '0';
	}
	if(p[index]==':') ++index;
	return neg? -i : i;
}
// the line numbers are lineNo[:colStart[:colEnd]]
void getLine(const char* p, int& index, LINEREF& lref)
{
	lref.file = getFileName(p, index);
	lref.line = getInt(p, index);
	lref.start = getInt(p, index);
	lref.end = getInt(p, index);
	if(p[index]) ++index;
}
bool readSDLline(char* p, SDL& s)
{
	int n = (int)strlen(p);
	if(n>1 && p[n-1]=='\n') p[n-1]=0;

	int index = 0;
	getLine(p, index, s.source);
	getLine(p, index, s.definition);
	s.page = getInt(p, index);
	if(p[index]) ++index;
	s.value = getInt(p, index);
	if(p[index]) ++index;
	s.type = p[index];
	if(p[index]) ++index;
	s.data = _strdup(p+index);
	return true;
}
int ReadSDL(const char* fname)
{
	FILE* fin;
	if(fopen_s(&fin, fname, "r")!=0)
		return crash("failed to open SDL file");
	files.push_back(_strdup(fname));

	char temp[100];

	if(fgets(temp, sizeof(temp), fin)==nullptr)
		return crash("bad line one on SDL");	// version
	if(strcmp(temp, "|SLD.data.version|1\n")!=0)
		return crash("wrong version");

	if(fgets(temp, sizeof(temp), fin)==nullptr)
		return crash("bad line one on SDL");	// keywords

	while(fgets(temp, sizeof(temp), fin)!=nullptr){
		SDL s;
		readSDLline(temp, s);
		sdl.push_back(s);
	}
	fclose(fin);
	return (int)sdl.size();
}
