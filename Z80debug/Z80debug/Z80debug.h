#pragma once

#include "resource.h"
#include "serialdrv.h"
#include "safequeue.h"

//=================================================================================================
// in Z80debug.cpp
//=================================================================================================
extern HINSTANCE hInstance;
extern HWND hFrame, hClient;
extern HFONT hFont, hFontSmall;
extern HWND hTerminal;
extern SERIAL* serial;
extern UINT regMessage;
extern bool bRegsPlease, bPopupPlease;

void error(DWORD err=0);
HWND AddSource(const char* title, void* data);
void AddTerminal(void* data);

#include "trap.h"

//=================================================================================================
// in source.h
//=================================================================================================
LRESULT CALLBACK SourceWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);

//=================================================================================================
// in source.cpp
//=================================================================================================
LRESULT CALLBACK TerminalWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);
void PopUp(int file, int line, bool highlight=true);

//=================================================================================================
// in processs.cpp
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
std::tuple<int,int,int,int> FindTrace(WORD address16);
std::tuple<int,int,int,int> FindDefinition(const char* item);
const char* getFileName(int file);
int gefFileNameUnpaged(int file);

//=================================================================================================
// in regs.cpp
//=================================================================================================

struct REGS {
	BYTE A{}, F{};
	BYTE AA{}, FA{};
	WORD BC{}, DE{}, HL{};
	WORD BCA{}, DEA{}, HLA{};
	WORD IX{}, IY{}, SP{}, PC{};
	WORD PAGE[4]{};
};
extern REGS regs;
extern HWND hRegs;
void unpackRegs(const char* text, REGS* regs);
void unpackMAP(const char* text, REGS* regs);
void ShowRegs();

//========================
// in trap
//=================================

BYTE unpackBYTE(const char* text, int &index);
WORD unpackWORD(const char* text, int& index);
void packW(WORD w);
void packB(BYTE b);
void ShowMemory();

//====================================
// in util.cpp
//================================
void getIniFile();
char* GetProfile(const char* section, const char* key, const char* def);
void PutProfile(const char* section, const char* key, const char* value);
void DropSave(UINT id, const char* text);
void DropLoad(HWND hDlg, UINT id);
