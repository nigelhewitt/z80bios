// terminal.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

struct TERMINALDATA {
	std::vector<const char*> lines{};
	int nLines{};
	int nScroll{};
	char currentLine[300]{"\x1b[97m"};
	int currentColour{97};					// the number in ESC[97m
	int currentColumn{5};
	void AddChar(char c);
	int inputEscMode{};
	int currentDigit{};
	int tHeight{20};						// text height
};

void TERMINALDATA::AddChar(char c)
{
	switch(inputEscMode){		// 0=not in use, 1=got ESC, 2=got [
	case 0:
		break;
	case 1:
		if(c=='['){
			inputEscMode=2;
			currentDigit=0;
			break;
		}
		break;
	case 2:
		if(isdigit(c)){
			currentDigit *= 10;
			currentDigit += c-'0';
			break;
		}
		switch(c){
		case 'm':
			currentColour = currentDigit;
			break;
		case 'H':
			break;
		case 'J':
			break;
		}
		inputEscMode = 0;
	}
	if(c=='\r')
		currentColumn = 5;
	else if(c=='\n'){
		lines.push_back(_strdup(currentLine));
		ZeroMemory(currentLine, sizeof currentLine);
		sprintf(currentLine, "\x1b[%dm", currentColour);
		currentColumn = (int)strlen(currentLine);
	}
	else if(c=='\x1b'){
		currentLine[currentColumn++] = c;
		inputEscMode = 1;
	}
	else if(c)
		currentLine[currentColumn++] = c;
}

void pump(const char* str, TERMINALDATA *t)
{
	while(*str) t->AddChar(*str++);
}

std::tuple<COLORREF, bool> AnsiiCode(int n){
	switch(n){
	case 30:	return std::make_tuple(RGB(0,  0,  0),   true);		// Black
	case 40:	return std::make_tuple(RGB(0,  0,  0), 	 false);
	case 31:	return std::make_tuple(RGB(128,0,  0),   true);		// Red
	case 41:	return std::make_tuple(RGB(128,0,  0),   false);
	case 32:	return std::make_tuple(RGB(0,  128,0),   true);		// Green
	case 42:	return std::make_tuple(RGB(0,  128,0),   false);
	case 33:	return std::make_tuple(RGB(128,128,0),   true);		// Yellow
	case 43:	return std::make_tuple(RGB(128,128,0),   false);
	case 34:	return std::make_tuple(RGB(0,  0,  128), true);		// Blue
	case 44:	return std::make_tuple(RGB(0,  0,  128), false);
	case 35:	return std::make_tuple(RGB(128,0,  128), true);		// Magenta
	case 45:	return std::make_tuple(RGB(128,0,  128), false);
	case 36:	return std::make_tuple(RGB(0,  128,128), true);		// Cyan
	case 46:	return std::make_tuple(RGB(0,  128,128), false);
	case 37:	return std::make_tuple(RGB(128,128,128), true);		// White
	case 47:	return std::make_tuple(RGB(128,128,128), false);

	case 90:	return std::make_tuple(RGB(0,  0,  0),   true);		// 'Bright Black'
	case 100:	return std::make_tuple(RGB(0,  0,  0),   false);
	case 91:	return std::make_tuple(RGB(255,0,  0),   true);		// Bright Red
	case 101:	return std::make_tuple(RGB(255,0,  0),   false);
	case 92:	return std::make_tuple(RGB(0,  255,0),   true);		// Bright Green
	case 102:	return std::make_tuple(RGB(0,  255,0),   false);
	case 93:	return std::make_tuple(RGB(255,255,0),   true);		// Bright Yellow
	case 103:	return std::make_tuple(RGB(255,255,0),   false);
	case 94:	return std::make_tuple(RGB(0,  0,  255), true);		// Bright Blue
	case 104:	return std::make_tuple(RGB(0,  0,  255), false);
	case 95:	return std::make_tuple(RGB(255,0,  255), true);		// Bright Magenta
	case 105:	return std::make_tuple(RGB(255,0,  255), false);
	case 96:	return std::make_tuple(RGB(0,  255,255), true);		// Bright Cyan
	case 106:	return std::make_tuple(RGB(0,  255,255), false);
	case 97:	return std::make_tuple(RGB(255,255,255), true);		// Bright White
	case 107:	return std::make_tuple(RGB(255,255,255), false);
	}
	return std::make_tuple(RGB(255,255,255), true);
}

// Now we have to wrap TabTextOut with something to do the colour changes
void WrapTab(HDC hdc, const char* text, int x, int y, INT* tabs)
{
	// What we will do is accumulate a string until we get an ESC or null.
	// Then output it on the old colour and then start accumulating another
	int i=0;			// character index into text[]
	int bi = 0;			// index into temp[]
	char temp[200];		// arbitrary sized buffer
	int startPoint = x;	// callers start pint
	// initial text colours
	COLORREF fg = RGB(255,255,255);
	COLORREF bg = RGB(0,0,0);

	do{
		char c = text[i];
		// do we need to flush the buffer?
		if((c==0x1b || c==0) && bi!=0){
			temp[bi] = 0;
			SetTextColor(hdc, fg);
			SetBkColor(hdc, bg);
			WCHAR tempW[200];
			MultiByteToWideChar(CP_UTF8, MB_PRECOMPOSED, temp, -1, tempW, _countof(tempW));
			DWORD ret = TabbedTextOutW(hdc, x, y, tempW, bi, 1, tabs, 0);
			x += LOWORD(ret);	// width
			bi = 0;
		}
		// if that was a null we've finished
		if(c==0) break;

		if(c==0x1b && text[i+1]=='['){
			i+=2;
			int n=0;
			while(isdigit(text[i])){ n*=10; n+=text[i++]-'0'; }
			switch(text[i++]){
			case 'm':					// foreground colour
			{
				auto cx = AnsiiCode(n);
				if(get<1>(cx))	fg = std::get<0>(cx);
				else			bg = std::get<0>(cx);
				break;
			}
			case 'H':
			case 'J':
			default:
				break;
			}
		}
		else{
			temp[bi++] = c;
			++i;
		}
	}while(true);
	SetCaretPos(x, y);
}

void tPaint(HWND hWnd, HDC hdc, TERMINALDATA* td)
{
	HGDIOBJ oldFont = SelectObject(hdc, hFont);
	TEXTMETRIC tm;
	GetTextMetrics(hdc, &tm);
	INT tabs[]={ 20 };
	tabs[0] = 4 * tm.tmAveCharWidth;
	td->tHeight = tm.tmHeight;

	int start = GetScrollPos(hWnd, SB_VERT);
	RECT r;
	GetClientRect(hWnd, &r);
	HBRUSH hb = CreateSolidBrush(RGB(0,0,0));
	FillRect(hdc, &r, hb);
	int x=0, y=0;
	int i = start;
	for(y=r.top; y<r.bottom && i<td->lines.size(); y += tm.tmHeight){
		const char* text = td->lines[i++];
		WrapTab(hdc, text, x, y, tabs);
	}
	WrapTab(hdc, td->currentLine, x, y, tabs);

	DeleteObject(hb);
	SelectObject(hdc, oldFont);
}

LRESULT CALLBACK TerminalWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	TERMINALDATA* td = reinterpret_cast<TERMINALDATA*>(GetWindowLongPtr(hWnd, 0));	// pointer to your data

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		// lParam is a pointer to a CREATESTRUCT
		// of which .lpCreateParams is a pointer to the MDICREATESTRUCTW
		{
			td = new TERMINALDATA;
			MDICREATESTRUCT* cv = reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams);
			SetWindowLongPtr(hWnd, 0, (LONG_PTR)td);
			pump("Hello World\r\n", td);
			pump("\x1b[92mGreen Two lines != traffic\r\n", td);
			pump("Third Line \x1b[31mto Red\r\n", td);
			SetTimer(hWnd, 1, 200, nullptr);
		}
		return 0;

	case WM_TIMER:
		int c; c=0;
		while((c=serial->getc())!=-1)
			td->AddChar(c);
		if(c){
			RECT r;
			GetClientRect(hWnd, &r);

			SCROLLINFO si = { sizeof SCROLLINFO, SIF_ALL };
			GetScrollInfo(hWnd, SB_VERT, &si);

			// calculate screen lines
			td->nLines = (r.bottom-r.top)/td->tHeight + 1;

			// how many 'off screen lines do we have?
			int nl; nl = (int)td->lines.size() - td->nLines+2;
			if(nl<0) nl=0;
			si.nMax = nl;					// set scroll range

			si.nPos = si.nMax;				// scroll to the bottom
			SetScrollInfo(hWnd, SB_VERT, &si, true);

			InvalidateRect(hWnd, nullptr, TRUE);	// repaint
		}
		return 0;

	case WM_CHAR:
		serial->send((char)wParam);
		return 0;


	case WM_SETFOCUS:
		CreateCaret(hWnd, nullptr, 3, td->tHeight);
		ShowCaret(hWnd);
		break;

	case WM_KILLFOCUS:
		DestroyCaret();
		break;

	case WM_COMMAND:
//		switch(LOWORD(wParam)){
//		}
		break;

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hWnd, &ps);
		tPaint(hWnd, hdc, td);
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
			td->nScroll = HIWORD(wParam);
			break;
		case SB_LINEDOWN:
			td->nScroll += 30;
			break;
		case SB_LINEUP:
			td->nScroll -= 30;
			break;
		}
		SCROLLINFO si = { 0 };
		si.cbSize = sizeof(SCROLLINFO);
		si.fMask = SIF_POS;
		si.nPos = td->nScroll;
		si.nTrackPos = 0;
		SetScrollInfo(hWnd, SB_VERT, &si, true);
		GetScrollInfo(hWnd, SB_VERT, &si);
		td->nScroll = si.nPos;

		InvalidateRect(hWnd, nullptr, TRUE);
		return 0;
	}
	break;

	case WM_DESTROY:
		break;		// use default processing
	}
	return DefMDIChildProc(hWnd, uMessage, wParam, lParam);
}
