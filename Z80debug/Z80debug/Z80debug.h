#pragma once

#include "resource.h"
#include "serialdrv.h"

LRESULT CALLBACK SourceWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK TerminalWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);

struct DLGDATA {
	int stuff;
};
extern HINSTANCE hInstance;
extern HWND hFrame, hClient;
extern HFONT hFont;
extern SERIAL* serial;

void error(DWORD err=0);
int ReadSDL(const char* fname);

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
	int value{};
	char type{};
	const char* data{};
};
extern std::vector<const char*>files;
extern std::vector<SDL> sdl;
