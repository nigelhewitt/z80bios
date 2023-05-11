#pragma once

#include "debug.h"
#include "process.h"

class SOURCE {
public:
	SOURCE(std::string title, int fileID, int _page);
	~SOURCE();
	static void PopUp(int file, int line, int highlight=0);

private:
	struct SOURCELINE {
		std::string text{};
		int hiLight{};
		bool canTrap{};
		int trap{};		// 0=no trap,  1-n
		int address{-1};
	};
	std::string fname{};
	int page{};
	int fileID{};
	std::vector<SOURCELINE> lines{};
	int nLines{};
	int nScroll{};

	HWND hSource{};
	HFONT hFont{}, hFontSmall{};
	void Paint(HWND hWnd, HDC hdc);
	void SetScroll(HWND hWnd);
	static LRESULT CALLBACK Proc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);

	inline static UINT regMessage{};
	static BOOL popupWorker(HWND hwnd, LPARAM lParam);
	friend int APIENTRY WinMain(HINSTANCE,HINSTANCE,LPSTR,int);
};
