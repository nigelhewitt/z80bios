#pragma once

#include "framework.h"

class PROCESS {
public:
	PROCESS(const char* dir);
	~PROCESS();
	std::string getFileName(int file){ return files[file].fn; }
	std::tuple<int, int, int, int>FindDefinition(const char* item);
	std::tuple<int, int, int, int>FindTrace(WORD address16);

private:
	// files: rather than have 15000 copies of the same string for the filename
	//		  I use a number being the key of a map
	struct FDEF {				// definition of a file as displayed by SOURCE
		std::string fn{};		// name
		int  page{};			// page number to interpret the lines
		int  fileID{};
		HWND hSource{};			// window (if it exists)
		bool minor{};			// if page==-1 there is another paged version
	};
	inline static std::map<int, FDEF>files{};	// files

	struct SDL {				// details from the SDL files
		struct LINEREF {		// the lineno field contains optional start and finish columns
			int file{};
			int line{};
			int start{};		// I don't try to use these because I don't think they are set
			int end{};
		};
		LINEREF source{};		// the source file that references
		LINEREF definition{};	// the definitions file that defines
		int   page{};			// memory page if applicable
		int   value{-1};		// value
		char  type{};			// type of field (see assembler help)
		const char* data[10]{};	// optional comma delimited more data (type dependant)
	};
	inline static std::vector<SDL> sdl{};		// accumulated wisdom of the ages

	inline static int nextFileNumber{};

private:
	// workers for reading SDL files
	static int getFileName(const char* p, int& index, int page);
	static int getFileNameUnpaged(int file);

	int  getInt(const char* p, int& index);
	void getLine(const char* p, int& index, SDL::LINEREF& lref, int page);
	bool readSDLline(char* p, SDL& s);
	int  ReadSDL(const char* fname);

	friend class SOURCE;
	friend LRESULT CALLBACK FrameWndProc(HWND,UINT,WPARAM,LPARAM);

};
extern PROCESS* process;
