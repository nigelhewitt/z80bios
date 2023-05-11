// source.cpp : Defines the child window interface
//

#include "framework.h"
#include "source.h"
#include "util.h"
#include "charset.h"
#include "Z80debug.h"

//=====================================================================================================
// add a new source Window
//=====================================================================================================

SOURCE::SOURCE(std::string title, int _fileID, int _page)
{
	fileID	= _fileID;
	page	= _page;
	if(!process->files.contains(fileID)) return;

	PROCESS::FDEF* fdef = &process->files[fileID];
	fname = fdef->fn;


	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}
	// do the static members if we are the first
	if(hFont==0)
		hFont = CreateFont(20, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");
	if(hFontSmall==0)
		hFontSmall = CreateFont(15, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");
	if(regMessage==0)
		regMessage = RegisterWindowMessage("Z80debug-0");

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Z80source";
	mcs.szTitle	= title.c_str();
	mcs.hOwner	= hInstance;
	mcs.x		= CW_USEDEFAULT;
	mcs.y		= CW_USEDEFAULT;
	mcs.cx		= 900;
	mcs.cy		= CW_USEDEFAULT;
	mcs.style	= WS_HSCROLL | WS_VSCROLL;
	mcs.lParam	= (LPARAM)this;


	hSource = (HWND)SendMessage(hClient, WM_MDICREATE, 0, (LPARAM)&mcs);
	if(hSource == nullptr){
		// display some error message
		error();
	}
	else{
		SetFocus(hSource);
		fdef->hSource = hSource;
	}
}
SOURCE::~SOURCE()
{
	process->files[fileID].hSource = nullptr;
	SendMessage(hSource, WM_MDIDESTROY, (WPARAM)hSource, 0);
}

void SOURCE::Paint(HWND hWnd, HDC hdc)
{
#define LEFT_MG		65

	TEXTMETRIC tm;
	HGDIOBJ oldFont = SelectObject(hdc, hFont);
	GetTextMetrics(hdc, &tm);
	SelectObject(hdc, oldFont);

	INT tabs[]={ 20 };
	tabs[0] = 4 * tm.tmAveCharWidth;

	int start = GetScrollPos(hWnd, SB_VERT);
	RECT r;
	GetClientRect(hWnd, &r);
	HBRUSH hb = CreateSolidBrush(RGB(255,255,164));
	HBRUSH mb = CreateSolidBrush(RGB(157,120,0));
	r.left = LEFT_MG;
	FillRect(hdc, &r, hb);
	r.left=0;
	r.right=LEFT_MG-1;
	FillRect(hdc, &r, mb);

	// now do the line
	int leftMargin =  LEFT_MG + 5;
	int x = leftMargin;
	int i = start;
	char temp[20];
	for(int y=r.top; y<r.bottom && i<lines.size(); y += tm.tmHeight){
		// do the trap
		if(lines[i].trap!=0){
			Ellipse(hdc, 2, y+2, 22, y+20);
			sprintf_s(temp, sizeof temp, "%d", lines[i].trap);
			HGDIOBJ oldFont = SelectObject(hdc, hFontSmall);
			SIZE sz;
			GetTextExtentPoint32(hdc, temp, (int)strlen(temp), &sz);
			SetTextColor(hdc, RGB(0,0,0));
			SetBkMode(hdc, TRANSPARENT);
			TextOut(hdc, 12-(int)sz.cx/2, y+10-(int)sz.cy/2, temp, (int)strlen(temp));
			SelectObject(hdc, oldFont);
			SetBkMode(hdc, OPAQUE);
		}
		// do the value
		HGDIOBJ oldFont = SelectObject(hdc, hFont);
		if(lines[i].address>=0){
			SetTextColor(hdc, RGB(255,255,255));
			SetBkColor(hdc, RGB(157,120,0));
			sprintf_s(temp, sizeof temp, "%04X", lines[i].address);
			TextOut(hdc, 23, y, temp, (int)strlen(temp));
		}
		// do the line
		if(lines[i].hiLight==0){
			SetTextColor(hdc, RGB(0,0,0));
			SetBkColor(hdc, RGB(255,255,164));
		}
		else if(lines[i].hiLight==1){
			SetTextColor(hdc, RGB(255,255,255));
			SetBkColor(hdc, RGB(128,128,255));
		}
		else{
			SetTextColor(hdc, RGB(255,255,255));
			SetBkColor(hdc, RGB(128,0,0));
		}
		const char* text = lines[i++].text.c_str();
		WCHAR tempW[200]{};
		mbtowide((PUTF8)text, (PUTF16)tempW, _countof(tempW));
		TabbedTextOutW(hdc, x, y, tempW, (int)wcslen(tempW), 1, tabs, leftMargin);
		SelectObject(hdc, oldFont);
	}
	DeleteObject(hb);
	nLines = (r.bottom-r.top)/(int)tm.tmHeight+1;
	int nl = (int)lines.size() - nLines+2;
	if(nl<0) nl=0;
	SetScrollRange(hWnd, SB_VERT, 0, nl, TRUE);
}
//=================================================================================================
// pop up the file at the specified line number
//=================================================================================================
void SOURCE::PopUp(int file, int line, int highlight)
{
	PROCESS::FDEF &fdef = PROCESS::files[file];
	if(fdef.hSource==nullptr){
		std::string temp = std::format("Source: {} {} ({})", PROCESS::files[file].page, PROCESS::files[file].fn, file);
		SOURCE *s = new SOURCE(temp, file, PROCESS::files[file].page);
	}
	if(fdef.hSource){
		SendMessage(fdef.hSource, regMessage, 0, (LPARAM)(MAKELONG(line,highlight)));
		BringWindowToTop(fdef.hSource);
	}
}
void SOURCE::SetScroll(HWND hWnd)
{
	SCROLLINFO si = { 0 };
	si.cbSize = sizeof(SCROLLINFO);
	si.fMask = SIF_POS;
	si.nPos = nScroll;
	si.nTrackPos = 0;
	SetScrollInfo(hWnd, SB_VERT, &si, true);
	GetScrollInfo(hWnd, SB_VERT, &si);
	nScroll = si.nPos;
	InvalidateRect(hWnd, nullptr, TRUE);
}

LRESULT CALLBACK SOURCE::Proc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	SOURCE* sd = reinterpret_cast<SOURCE*>(GetWindowLongPtr(hWnd, 0));	// pointer to your data

	// Handle the private message
	if(sd && LOWORD(uMessage)==sd->regMessage){
		UpdateWindow(hWnd);
		int line = LOWORD(lParam);
		int highlight = HIWORD(lParam);

		for(auto& s : sd->lines)
			if(s.hiLight==highlight)
				s.hiLight = 0;
		sd->lines[line].hiLight = highlight;
		int n = line - sd->nLines/2;
		if(n<0) n=0;
		sd->nScroll = n;
		sd->SetScroll(hWnd);
		InvalidateRect(hWnd, nullptr, TRUE);
		return TRUE;
	}

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		// lParam is a pointer to a CREATESTRUCT
		// of which .lpCreateParams is a pointer to the MDICREATESTRUCT
		MDICREATESTRUCT* cv; cv = reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams);
		sd = reinterpret_cast<SOURCE*>(cv->lParam);
		SetWindowLongPtr(hWnd, 0, (LONG_PTR)sd);

		FILE *fin;
		if(fopen_s(&fin, sd->fname.c_str(), "r")==0){
			// just a tweak to get over the UTF8 signature
			BYTE b1=fgetc(fin), b2=fgetc(fin), b3=fgetc(fin);
			if(b1!=0xef || b2!=0xbb || b3!=0xbf)
				fseek(fin, 0, SEEK_SET);
			char temp[200];
			while(fgets(temp, sizeof temp, fin)!=nullptr){
				int i = (int)strlen(temp);
				if(i>1 && temp[i-1]=='\n') temp[i-1]=0;
				SOURCELINE sl;
				sl.text = temp;
				sl.trap = 0;
				sl.address = -1;
				sd->lines.push_back(sl);
			}
			fclose(fin);
			// get the number of the page -1 version of this file if it exists
			int xx;
			xx = PROCESS::getFileNameUnpaged(sd->fileID);		// -1 if none

			// sweep all lines for matching records
			for(PROCESS::SDL &s : PROCESS::sdl)
				if(((s.page==sd->page && s.source.file==sd->fileID)
							|| s.source.file==xx) && (s.type=='T' || s.type=='F' || s.type=='L')){
					int ix = s.source.line-1;
					SOURCELINE &r = sd->lines[ix];
 					r.address = s.value;
					if(s.type=='T') r.canTrap = true;
				}
		}
		return 0;

	case WM_PAINT:
		PAINTSTRUCT ps;
		HDC hdc; hdc = BeginPaint(hWnd, &ps);
		sd->Paint(hWnd, hdc);
		EndPaint(hWnd, &ps);
		return 0;

	case WM_VSCROLL:
		int action; action = LOWORD(wParam);
		HWND hScroll; hScroll = (HWND)lParam;
		switch(action){
		case SB_THUMBPOSITION:
		case SB_THUMBTRACK:
			sd->nScroll = HIWORD(wParam);
			break;
		case SB_LINEDOWN:
			++sd->nScroll;
			break;
		case SB_LINEUP:
			--sd->nScroll;
			break;
		case SB_PAGEDOWN:
			sd->nScroll += sd->nLines-2;
			break;
		case SB_PAGEUP:
			sd->nScroll -= sd->nLines-2;
			break;
		}
		sd->SetScroll(hWnd);
		return 0;

	case WM_MOUSEWHEEL:
		int move; move = (short)HIWORD(wParam);
		if(move>0)
			--sd->nScroll;
		if(move<0)
			++sd->nScroll;
		sd->SetScroll(hWnd);
		return 0;

	case WM_LBUTTONDOWN:
		int x; x = (short)LOWORD(lParam);
		int y; y = (short)HIWORD(lParam);
		TEXTMETRIC tm;
		hdc = GetDC(hWnd);
		HGDIOBJ old; old = SelectObject(hdc, sd->hFont);
		GetTextMetrics(hdc, &tm);
		SelectObject(hdc, old);
		ReleaseDC(hWnd, hdc);
		int line; line = y/tm.tmHeight + sd->nScroll;
		if(x>=0 && x<=22 && sd->lines[line].canTrap){
			if(sd->lines[line].trap){
				debug->freeTrap(sd->lines[line].trap);
				sd->lines[line].trap = 0;
			}
			else
				sd->lines[line].trap = debug->setTrap(sd->page, sd->lines[line].address);
			InvalidateRect(hWnd, nullptr, TRUE);
		}
		else if(x>=23 && x<=LEFT_MG){
			sd->lines[line].hiLight ^= 0x02;
			InvalidateRect(hWnd, nullptr, TRUE);
		}
		return 0;

	case WM_DESTROY:
		delete sd;
		break;		// use default processing
	}
	return DefMDIChildProc(hWnd, uMessage, wParam, lParam);
}
