// process.cpp : Defines the child window interface
//

#include "framework.h"
#include "process.h"

PROCESS* process{};

int crash(const char* obit)
{
	MessageBox(0, obit, "Z80Debugger", MB_OK);
	return 0;
}
PROCESS::PROCESS(const char* cwd)
{
	// Find all the .sdl files in this folder
	WIN32_FIND_DATA ffd;
	char fPath[MAX_PATH];
	strcpy_s(fPath, sizeof fPath, cwd);
	strcat_s(fPath, sizeof fPath, "\\*.sdl");
	HANDLE hFind = FindFirstFile(fPath, &ffd);
	if(hFind!=INVALID_HANDLE_VALUE)
		do
			ReadSDL(ffd.cFileName);
		while(FindNextFile(hFind, &ffd) != 0);
	// mark the page==-1 files that have a 'real' page so we can avoid listing them
	for(std::pair<const int,FDEF> &x : files)
		if(get<1>(x).page==-1)
			for(std::pair<const int,FDEF> &y : files)
				if(strcmp(get<1>(y).fn, get<1>(x).fn)==0 && get<1>(y).page!=-1)
					get<1>(x).minor = true;
}
PROCESS::~PROCESS()
{
}

//=================================================================================================
//	read the SDL file
//		<source file>|<src line>|<definition file>|<def line>|<page>|<value>|<type>|<data>
//=================================================================================================

// I don't want to have 1000 copies of the text "bios1.asm" so I'll index them
int PROCESS::getFileName(const char* p, int& index, int page)
{
	// first extract the file name
	char temp[100];
	int i;
	for(i=0; i<sizeof(temp)-1 && p[index] && p[index]!='|'; temp[i++] = p[index++]);
	temp[i] = 0;
	if(p[index]) ++index;		// move over the |

	if(strlen(temp)==0) return 0;

	// then find it in the map (running the map backwards)
	for(i=0; i<files.size(); ++i)
		if(_stricmp(temp, files[i].fn)==0 && files[i].page==page)
			return i;
	// doesn't exist so add it
	FDEF fdef{_strdup(temp), page, nextFileNumber, nullptr, false };
	files.emplace(std::make_pair(nextFileNumber, fdef));
	return nextFileNumber++;
}
int PROCESS::getFileNameUnpaged(int file)
{
	const char *fn = files[file].fn;
	for(int i=0; i<files.size(); ++i)
		if(files[i].page==-1 && strcmp(files[i].fn, fn)==0)
			return i;
	return -1;
}
// get an integer and move over a : but not a |
int PROCESS::getInt(const char* p, int& index)
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
void PROCESS::getLine(const char* p, int& index, SDL::LINEREF& lref, int page)
{
	lref.file  = getFileName(p, index, page);
	lref.line  = getInt(p, index);
	lref.start = getInt(p, index);
	lref.end   = getInt(p, index);
	if(p[index]) ++index;
}
bool PROCESS::readSDLline(char* p, SDL& s)
{
	int n = (int)strlen(p);
	if(n>1 && p[n-1]=='\n') p[n-1]=0;

	int index = 0;
	// we need that page number to sort out the filenames
	// so skip to that and get it first
	int px=0;
	{
		int i=0, j=0;
		for(; i<n && j<4; ++i)
			if(p[i]=='|') ++j;
		px = getInt(p, i);
	}
	getLine(p, index, s.source, px);
	getLine(p, index, s.definition, px);

	s.page = getInt(p, index);
	if(p[index]) ++index;
	s.value = getInt(p, index);
	if(p[index]) ++index;
	s.type = p[index];
	if(p[index]) ++index;

	// now the data which is a comma separated list
	for(int i=0; i<_countof(s.data); s.data[i++]=nullptr);

	char* d = p+index;
	char *next = nullptr;
	int i=0;
	char* tok = strtok_s(d, ",", &next);
	if(tok)
		do
			s.data[i++] = _strdup(tok);
		while(i<_countof(s.data) && (tok=strtok_s(nullptr, ",", &next))!=nullptr);
	return true;
}
int PROCESS::ReadSDL(const char* fname)
{
	FILE* fin;
	if(fopen_s(&fin, fname, "r")!=0)
		return crash("failed to open SDL file");
	FDEF fdef{_strdup(fname), 0, nextFileNumber, nullptr};
	files.emplace(std::make_pair(nextFileNumber++, fdef));

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

std::tuple<int, int, int, int>PROCESS::FindTrace(WORD address16)
{
	for(SDL s : sdl)
		if(s.type=='T' && s.value == address16)
			return { s.source.file, s.page, s.source.line-1, s.value };
	return { -1,0,0,0 };
}
std::tuple<int, int, int, int>PROCESS::FindDefinition(const char* item)
{
	for(SDL s : sdl)
		if((s.type=='F' && strcmp(s.data[0], item)==0)
					|| (s.type=='L' && strcmp(s.data[1], item)==0))
			return { s.source.file, s.page, s.source.line-1, s.value };
	return { -1,0,0,0 };
}
