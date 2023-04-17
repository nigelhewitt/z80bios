#pragma once

#include "resource.h"
#include "serialdrv.h"


//struct DLGDATA {
//	int stuff;
//};
//=================================================================================================
// in Z80debug.cpp
//=================================================================================================
extern HINSTANCE hInstance;
extern HWND hFrame, hClient;
extern HFONT hFont, hFontSmall;
extern SERIAL* serial;
extern UINT regMessage;
void error(DWORD err=0);
HWND AddSource(const char* title, void* data);
HWND AddTerminal(void* data);

//=================================================================================================
// in source.h
//=================================================================================================
LRESULT CALLBACK SourceWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);

//=================================================================================================
// in source.h
//=================================================================================================
LRESULT CALLBACK TerminalWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);
void PopUp(int file, int line);

//=================================================================================================
// in processs.h
//=================================================================================================
struct LINEREF {
	int file{};
	int line{};
	int start{};
	int end{};
};
struct SDL {
	LINEREF source{};
	LINEREF definition{};
	int page{};
	int value{-1};
	char type{};
	const char* data[10]{};
};
struct FDEF { const char* fn; int fx; int page; bool show; int id; };
extern std::vector<FDEF>files;
extern std::vector<SDL> sdl;

int ReadSDL(const char* fname);
std::tuple<int,int,int> FindTrace(BYTE page, WORD address16);
std::tuple<int,int,int> FindDefinition(const char* item);
const char* getFileName(int file);
int gefFileNameUnpaged(int file);

//=================================================================================================
// in trap.cpp
//=================================================================================================

int getTrap(int page, int address);
void freeTrap(int n);
