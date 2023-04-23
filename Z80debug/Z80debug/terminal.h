#pragma once

#include "safequeue.h"
#include "serial.h"

class TERMINAL {							// stored data for the Terminal device
public:
	TERMINAL();
	~TERMINAL();
	void AddChar(char c);					// add a character to the current line
	void clear();							// clear screen

private:
	SafeQueue<char> inbound{};				// incoming bytes
	struct TERMINALCHAR {
		WCHAR c{};							// wide char
		BYTE  fg{}, bg{};					// foreground and background colours
	};
	std::vector<TERMINALCHAR*> lines{};		// lines of text
	int nLines{};							// number of lines in the buffer
	int nScroll{};							// how far we are scrolled
	int tHeight{20};						// text height

	// working details accumulating a new line
	TERMINALCHAR currentLine[300]{};		// current line being input
	int currentColumn{};					// column of that line
	int inputMode{};						// state machine to unpick multi-byte inputs
	int currentDigits{};					// digits for an escape code
	int currentFG{37}, currentBG{40};		// current FG/BG colours using ANSI numbers

	//tools
	void pump(const char* p){ while(*p) AddChar(*p++); }
	COLORREF AnsiCode(int n);

	// routines for the WindowProc
	HWND hTerminal{};
	HFONT hFont{};
	void WrapTab(HDC hdc, TERMINALCHAR* text, int& x, int y, INT* tabs);
	void tPaint(HWND hWnd, HDC hdc);
	static LRESULT CALLBACK Proc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);

	void SetScroll(HWND hWnd);
	int caretX{}, caretY{};
	friend int APIENTRY WinMain(HINSTANCE,HINSTANCE,LPSTR,int);
};

extern TERMINAL* terminal;
