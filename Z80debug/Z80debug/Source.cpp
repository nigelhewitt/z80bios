// source.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

struct SOURCELINE {
	const char* text{};
	bool trap{};
	WORD address{};
};

struct SOURCEDATA {
	const char* fName{};
	std::vector<SOURCELINE> lines{};
	int nLines{};
	int nScroll{};
};


void Paint(HWND hWnd, HDC hdc, SOURCEDATA* sd)
{
	HGDIOBJ oldFont = SelectObject(hdc, hFont);
	TEXTMETRIC tm;
	GetTextMetrics(hdc, &tm);
	INT tabs[]={ 20 };
	tabs[0] = 4 * tm.tmAveCharWidth;

	int start = GetScrollPos(hWnd, SB_VERT);
	RECT r;
	GetClientRect(hWnd, &r);
	HBRUSH hb = CreateSolidBrush(RGB(255,255,255));
	FillRect(hdc, &r, hb);
	int x=0;
	int i = start;
	for(int y=r.top; y<r.bottom && i<sd->lines.size(); y += tm.tmHeight){
		const char* text = sd->lines[i++].text;
		TabbedTextOut(hdc, x, y, text, (int)strlen(text), 1, tabs, 0);
	}
	DeleteObject(hb);
	SelectObject(hdc, oldFont);
	sd->nLines = (r.bottom-r.top)/(int)tm.tmHeight+1;
	int nl = (int)sd->lines.size() - sd->nLines+2;
	if(nl<0) nl=0;
	SetScrollRange(hWnd, SB_VERT, 0, nl, TRUE);
}

LRESULT CALLBACK SourceWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	SOURCEDATA* sd = reinterpret_cast<SOURCEDATA*>(GetWindowLongPtr(hWnd, 0));	// pointer to your data

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		// lParam is a pointer to a CREATESTRUCT
		// of which .lpCreateParams is a pointer to the MDICREATESTRUCTW
		{
			sd = new SOURCEDATA;
			MDICREATESTRUCT* cv = reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams);
			sd->fName = _strdup(reinterpret_cast<char*>(cv->lParam));
			SetWindowLongPtr(hWnd, 0, (LONG_PTR)sd);

			FILE *fin;
			if(fopen_s(&fin, sd->fName, "r")==0){
				fgetc(fin); fgetc(fin); fgetc(fin);
				char temp[200];
				while(fgets(temp, sizeof temp, fin)!=nullptr){
					int i = (int)strlen(temp);
					if(i>1 && temp[i-1]=='\n') temp[i-1]=0;
					SOURCELINE sl;
					sl.text = _strdup(temp);
					sl.trap = false;
					sl.address = 0;
					sd->lines.push_back(sl);
				}
				fclose(fin);
			}
		}
		return 0;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDM_FORCHILD:
		{
			char temp[100];
			GetWindowText(hWnd, temp, sizeof temp);
			MessageBox(hWnd, "IDM_FORCHILD", temp, MB_OK);
			return 0;
		}
		}
		break;

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hWnd, &ps);
		Paint(hWnd, hdc, sd);
		EndPaint(hWnd, &ps);
		return 0;
	}

	case WM_VSCROLL:
	{
		auto action = LOWORD(wParam);
		HWND hScroll = (HWND)lParam;
		switch(action){
		case SB_THUMBPOSITION:
		case SB_THUMBTRACK:
			sd->nScroll = HIWORD(wParam);
			break;
		case SB_LINEDOWN:
			sd->nScroll += 30;
			break;
		case SB_LINEUP:
			sd->nScroll -= 30;
			break;
		}
		SCROLLINFO si = { 0 };
		si.cbSize = sizeof(SCROLLINFO);
		si.fMask = SIF_POS;
		si.nPos = sd->nScroll;
		si.nTrackPos = 0;
		SetScrollInfo(hWnd, SB_VERT, &si, true);
		GetScrollInfo(hWnd, SB_VERT, &si);
		sd->nScroll = si.nPos;

		InvalidateRect(hWnd, nullptr, TRUE);
		return 0;
	}
	break;

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

