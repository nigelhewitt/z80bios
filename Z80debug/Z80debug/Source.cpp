// source.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

struct SOURCELINE {
	const char* text{};
	bool hiLight{};
	bool canTrap{};
	int trap{};		// 0=no trap,  1-n
	int address{-1};
};

struct SOURCEDATA {
	FDEF fdef{};
	int page{};
	std::vector<SOURCELINE> lines{};
	int nLines{};
	int nScroll{};
};


void Paint(HWND hWnd, HDC hdc, SOURCEDATA* sd)
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
	for(int y=r.top; y<r.bottom && i<sd->lines.size(); y += tm.tmHeight){
		// do the trap
		if(sd->lines[i].trap!=0){
			Ellipse(hdc, 2, y+2, 22, y+20);
			sprintf_s(temp, sizeof temp, "%d", sd->lines[i].trap);
			HGDIOBJ oldFont = SelectObject(hdc, hFontSmall);
			SIZE sz;
			GetTextExtentPoint32(hdc, temp, (int)strlen(temp), &sz);
			SetTextColor(hdc, RGB(0,0,0));
			SetBkMode(hdc, TRANSPARENT);
			TextOut(hdc, 12-(int)sz.cx/2, y+10-(int)sz.cy/2, temp, (int)strlen(temp));
			SelectObject(hdc, oldFont);
		}
		// do the value
		HGDIOBJ oldFont = SelectObject(hdc, hFont);
		if(sd->lines[i].address>=0){
			SetTextColor(hdc, RGB(256,256,256));
			SetBkColor(hdc, RGB(157,120,0));
			sprintf_s(temp, sizeof temp, "%04X", sd->lines[i].address);
			TextOut(hdc, 23, y, temp, (int)strlen(temp));
		}
		// do the line
		if(sd->lines[i].hiLight){
			SetTextColor(hdc, RGB(255,255,255));
			SetBkColor(hdc, RGB(128,128,255));
		}
		else{
			SetTextColor(hdc, RGB(0,0,0));
			SetBkColor(hdc, RGB(255,255,164));
		}
		const char* text = sd->lines[i++].text;
		TabbedTextOut(hdc, x, y, text, (int)strlen(text), 1, tabs, leftMargin);
		SelectObject(hdc, oldFont);
	}
	DeleteObject(hb);
	sd->nLines = (r.bottom-r.top)/(int)tm.tmHeight+1;
	int nl = (int)sd->lines.size() - sd->nLines+2;
	if(nl<0) nl=0;
	SetScrollRange(hWnd, SB_VERT, 0, nl, TRUE);
}
//=================================================================================================
// pop up the file at the specified line number
//=================================================================================================
struct POPUP {
	int file;
	int line;
	bool bDone;
};
BOOL popupWorker(HWND hwnd, LPARAM lParam)
{
	char temp[100];
	GetClassName(hwnd, temp, sizeof temp);
	if(strcmp(temp, "Z80source")!=0) return TRUE;		// continue the enumeration
	SendMessage(hwnd, regMessage, 0, lParam);
	return TRUE;
}
void PopUp(int file, int line)
{
	static POPUP p;
	p = { file, line, false };
	EnumChildWindows(hFrame, &popupWorker, (LPARAM)&p);
	if(!p.bDone){
		char temp[200];
		sprintf_s(temp, sizeof temp, "Source: %d %s", files[file].page, files[file].fn);
		HWND hwnd = AddSource(temp, (void*)&files[file]);
		SendMessage(hwnd, regMessage, 0, (LPARAM)&p);
	}
}
void SetScroll(HWND hWnd, SOURCEDATA* sd)
{
	SCROLLINFO si = { 0 };
	si.cbSize = sizeof(SCROLLINFO);
	si.fMask = SIF_POS;
	si.nPos = sd->nScroll;
	si.nTrackPos = 0;
	SetScrollInfo(hWnd, SB_VERT, &si, true);
	GetScrollInfo(hWnd, SB_VERT, &si);
	sd->nScroll = si.nPos;
	InvalidateRect(hWnd, nullptr, TRUE);
}

LRESULT CALLBACK SourceWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	SOURCEDATA* sd = reinterpret_cast<SOURCEDATA*>(GetWindowLongPtr(hWnd, 0));	// pointer to your data

	// Handle the private message
	if(LOWORD(uMessage)==regMessage){
		UpdateWindow(hWnd);
		POPUP* p; p = (POPUP*)lParam;
		if(sd->fdef.fx == p->file){
			p->bDone = true;
			sd->lines[p->line-1].hiLight = true;
			int n = p->line - sd->nLines/2;
			if(n<0) n=0;
			sd->nScroll = n;
			SetScroll(hWnd, sd);
			InvalidateRect(hWnd, nullptr, TRUE);
			return FALSE;				// stop enumerating
		}
		return TRUE;		// continue enumeration
	}

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		// lParam is a pointer to a CREATESTRUCT
		// of which .lpCreateParams is a pointer to the MDICREATESTRUCTW
		sd = new SOURCEDATA;
		MDICREATESTRUCT* cv; cv = reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams);
		sd->fdef = *(FDEF*)cv->lParam;
		sd->page = sd->fdef.page;
		SetWindowLongPtr(hWnd, 0, (LONG_PTR)sd);

		FILE *fin;
		if(fopen_s(&fin, sd->fdef.fn, "r")==0){
			fgetc(fin); fgetc(fin); fgetc(fin);
			char temp[200];
			while(fgets(temp, sizeof temp, fin)!=nullptr){
				int i = (int)strlen(temp);
				if(i>1 && temp[i-1]=='\n') temp[i-1]=0;
				SOURCELINE sl;
				sl.text = _strdup(temp);
				sl.trap = 0;
				sl.address = -1;
				sd->lines.push_back(sl);
			}
			fclose(fin);
			// get the number of the page -1 version of this file if it exists
			int xx; xx = gefFileNameUnpaged(sd->fdef.fx);		// -1 if none

			for(SDL &s : sdl)
				if(((s.page==sd->page && s.source.file==sd->fdef.fx) || s.source.file==xx)
						&& (s.type=='T' || s.type=='D' || s.type=='L')){
					sd->lines[s.source.line-1].address = s.value;
					sd->lines[s.source.line-1].canTrap = s.type=='T';
				}
		}
		return 0;

	case WM_PAINT:
		PAINTSTRUCT ps;
		HDC hdc; hdc = BeginPaint(hWnd, &ps);
		Paint(hWnd, hdc, sd);
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
		SetScroll(hWnd, sd);
		return 0;

	case WM_MOUSEWHEEL:
		int move; move = (short)HIWORD(wParam);
		if(move>0)
			--sd->nScroll;
		if(move<0)
			++sd->nScroll;
		SetScroll(hWnd, sd);
		return 0;

	case WM_LBUTTONDOWN:
		int x; x = (short)LOWORD(lParam);
		int y; y = (short)HIWORD(lParam);
		TEXTMETRIC tm;
		hdc = GetDC(hWnd);
		HGDIOBJ old; old = SelectObject(hdc, hFont);
		GetTextMetrics(hdc, &tm);
		SelectObject(hdc, old);
		ReleaseDC(hWnd, hdc);
		int line; line = y/tm.tmHeight + sd->nScroll;
		if(x>=0 && x<=22 && sd->lines[line].canTrap){
			if(sd->lines[line].trap){
				freeTrap(sd->lines[line].trap);
				sd->lines[line].trap = 0;
			}
			else
				sd->lines[line].trap = getTrap(sd->page, sd->lines[line].address);
			InvalidateRect(hWnd, nullptr, TRUE);
		}
		else if(x>=23 && x<=LEFT_MG){
			sd->lines[line].hiLight = !sd->lines[line].hiLight;
			InvalidateRect(hWnd, nullptr, TRUE);
		}
		return 0;

	case WM_DESTROY:
		break;		// use default processing
	}
	return DefMDIChildProc(hWnd, uMessage, wParam, lParam);
}
#if 0
LRESULT CALLBACK MDIDialogProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	struct DS {
		DLGDATA*	dld;
		HWND		hDlg;
		int			iWide, iHigh;
	} *ds;

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		ds = new DS;
		SetWindowLongPtr(hWnd, 0, reinterpret_cast<LONG_PTR>(ds));

		ds->dld  = reinterpret_cast<DLGDATA*>((reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams))->lParam);

		ds->hDlg = CreateDialogParam(hInstance, ds->dld->szTemplate, hWnd, ds->dld->proc, ds->dld->lParam);
		RECT rWnd, rClient, rDlg;
		GetWindowRect(hWnd, &rWnd);					// total size and position
		GetWindowRect(ds->hDlg, &rDlg);				// dialog size
		SetParent(ds->hDlg, hWnd);
		GetClientRect(hWnd, &rClient);				// current client size
		ds->iWide = (rDlg.right-rDlg.left) + (rWnd.right-rWnd.left) - (rClient.right-rClient.left);
		ds->iHigh = (rDlg.bottom-rDlg.top) + (rWnd.bottom-rWnd.top) - (rClient.bottom-rClient.top);
		SetWindowPos(hWnd, nullptr, 0, 0, ds->iWide, ds->iHigh, SWP_NOMOVE | SWP_NOZORDER);
		SetWindowPos(ds->hDlg, nullptr, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
		break;

	case WM_GETMINMAXINFO:
		ds = reinterpret_cast<DS*>(GetWindowLongPtr(hWnd, 0));
		if(ds){
			(reinterpret_cast<MINMAXINFO*>(lParam))->ptMinTrackSize.x = ds->iWide;
			(reinterpret_cast<MINMAXINFO*>(lParam))->ptMinTrackSize.y = ds->iHigh;
			(reinterpret_cast<MINMAXINFO*>(lParam))->ptMaxTrackSize.x = ds->iWide;
			(reinterpret_cast<MINMAXINFO*>(lParam))->ptMaxTrackSize.y = ds->iHigh;
		}
		break;

	case WM_DESTROY:
		ds = reinterpret_cast<DS*>(GetWindowLongPtr(hWnd, 0));
		if(ds){
			DestroyWindow(ds->hDlg);
			SetWindowLong(hWnd, 0, 0);
			delete ds->dld;
			delete ds;
		}
		break;
	}
	return DefMDIChildProc(hWnd, uMessage, wParam, lParam);
}
void KillMDIDialog(HWND hWnd)
{
	SendMessage(hClient, WM_MDIDESTROY, reinterpret_cast<WPARAM>(GetParent(hWnd)), 0L);
}
#endif

