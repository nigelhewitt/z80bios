// terminal.cpp : Defines the child window interface
//

#include "framework.h"
#include "terminal.h"
#include "util.h"
#include "Z80debug.h"

TERMINAL* terminal;

TERMINAL::TERMINAL()
{
	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}
	hFont = CreateFont(20, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Z80terminal";
	mcs.szTitle	= "Terminal";
	mcs.hOwner	= hInstance;
	mcs.x		= CW_USEDEFAULT;
	mcs.y		= CW_USEDEFAULT;
	mcs.cx		= 800;
	mcs.cy		= 600;
	mcs.style	= WS_HSCROLL | WS_VSCROLL;
	mcs.lParam	= (LPARAM)this;

	hTerminal = (HWND)SendMessage(hClient, WM_MDICREATE, 0, (LPARAM)&mcs);
	if(hTerminal == nullptr){
		// display some error message
		error();
		return;
	}
	SetFocus(hTerminal);

	serial->registerReceiver(0, &inbound);
}
TERMINAL::~TERMINAL()
{
	clear();

	if(hTerminal)
		PostMessage(hTerminal, WM_DESTROY, 0, 0);

	serial->unregisterReceiver(0);
}

void TERMINAL::clear()
{
	nLines = 0;
	for(auto& f : lines)
		delete[] f;
	lines.clear();
	InvalidateRect(hTerminal, nullptr, TRUE);
}

// The real problem with data input is <backspace>. It wants to delete a character AND its colour
// implications. Originally I just let the ESC[ sequences transfer into the buffer and tried to
// unpick the mess when I got a <BS> but with WIDE characters and colour controls it all went to
// pieces on me.

// characters come in from the serial line in ones so we need to unpack stuff
void TERMINAL::AddChar(char c)
{
	switch(inputMode){		// state machine
	case 0:					// no special handling from previous
		break;

	case 1:					// got <ESC> expecting '['
		if(c=='['){
			inputMode = 2;
			currentDigits = 0;
			return;
		}
		inputMode = 0;		// not understood so just treat it as a char
		break;

	case 2:					// got <ESC>[ expecting digits or char
		if(isdigit(c)){
			currentDigits *= 10;
			currentDigits += c-'0';
			return;
		}
		switch(c){
		case 'm':
			if((currentDigits>-30 && currentDigits<=37) || (currentDigits>=90 && currentDigits<=97))
				currentFG = currentDigits;
			else if((currentDigits>-30 && currentDigits<=37) || (currentDigits>=90 && currentDigits<=97))
				currentBG = currentDigits;
			// ignore all else for now
			inputMode = 0;
			return;
		case 'J':			// clear screen
			// 0=cursor to end of screen, 1=cursor to beginning of screen,
			// 2=clear screen and home, 3=clear screen and scroll back buffer
			inputMode = 0;
			return;
		}
		// not understood so ignore
		inputMode = 0;
		return;

	case 3:					// second byte of a three byte Unicode
		currentLine[currentColumn].c |= (c&0x3f)<<6;
		inputMode = 4;
		break;

	case 4:					// third byte of a three byte Unicode or second byte of two
		currentLine[currentColumn].c |= c&0x3f;
		inputMode = 0;
		currentLine[currentColumn].fg = currentFG;
		currentLine[currentColumn].bg = currentBG;
		currentColumn++;
		inputMode = 0;
		break;
	}
	if(c==0x1b){
		inputMode = 1;
		return;
	}
	// 'standard character handling
	if(c=='\r'){
		currentColumn = 0;
		return;
	}
	if(c=='\n'){
		// count chars
		int nChars;
		for(nChars=0; nChars<_countof(currentLine) && currentLine[nChars].c; ++nChars);
		// copy to a new line array
		TERMINALCHAR* tc = new TERMINALCHAR[nChars+1];
		for(int i=0; i<nChars; tc[i]=currentLine[i], ++i);
		lines.push_back(tc);

		ZeroMemory(currentLine, sizeof currentLine);
		currentColumn = 0;								// naughty but helps
		return;
	}

	if(c==0x08){						// backspace
		if(currentColumn>0)
			currentLine[--currentColumn].c = 0;
		return;
	}
	if(c & 0x80){						// Unicode preamble
		if((c & 0xf0) == 0xe0){			// 3 byte
			inputMode = 3;
			currentLine[currentColumn].c = (c&0x0f)<<12;
			return;
		}
		else if((c & 0xe0) == 0xc0){	// 2 bytes
			inputMode = 4;
			currentLine[currentColumn].c = (c&0x1f)<<6;
			return;
		}
		return;						// not managed
	}
	// finally a 'real' standard character
	currentLine[currentColumn].c = c;
	currentLine[currentColumn].fg = currentFG;
	currentLine[currentColumn++].bg = currentBG;
}

COLORREF TERMINAL::AnsiCode(int n){
	switch(n){
	case 30:							// Black
	case 40:	return RGB(0,0,0);
	case 31:							// Red
	case 41:	return RGB(128,0,0);
	case 32:							// Green
	case 42:	return RGB(0,128,0);
	case 33:							// Yellow
	case 43:	return RGB(128,128,0);
	case 34:							// Blue
	case 44:	return RGB(0,0,128);
	case 35:							// Magenta
	case 45:	return RGB(128,0,128);
	case 36:							// Cyan
	case 46:	return RGB(0,128,128);
	case 37:							// White
	case 47:	return RGB(128,128,128);

	case 90:							// 'Bright Black'
	case 100:	return RGB(0,0,0);
	case 91:							// Bright Red
	case 101:	return RGB(255,0,0);
	case 92:							// Bright Green
	case 102:	return RGB(0,255,0);
	case 93:							// Bright Yellow
	case 103:	return RGB(255,255,0);
	case 94:							// Bright Blue
	case 104:	return RGB(80,80,255);
	case 95:							// Bright Magenta
	case 105:	return RGB(255,0,255);
	case 96:							// Bright Cyan
	case 106:	return RGB(0,255,255);
	case 97:							// Bright White
	case 107:	return RGB(255,255,255);
	}
	return RGB(255,255,255);
}

// Now we have to wrap TabTextOut with something to do the colour changes
void TERMINAL::WrapTab(HDC hdc, TERMINALCHAR* text, int& x, int y, INT* tabs)
{
	if(text->c==0) return;			// blank lines are easy

	// What we will do is accumulate a string until the colours change.
	// Then output it on the old colour and then start accumulating another
	int i=0;			// character index into text[]
	int bi = 0;			// index into temp[]
	WCHAR temp[200];	// arbitrary sized buffer
	int startPoint = x;	// callers start pint
	// initial text colours
	int fg = text->fg;
	int bg = text->bg;

	do{
		TERMINALCHAR c = text[i];
		// do we need to flush the buffer? (end of buffer or change of colour)
		if((c.c==0 || c.fg != fg || c.bg != bg) && bi!=0){
			temp[bi] = 0;							// terminating null
			// convert the codes into RGB
			SetTextColor(hdc, AnsiCode(fg));
			SetBkColor(hdc, AnsiCode(bg));
			DWORD ret = TabbedTextOutW(hdc, x, y, temp, bi, 1, tabs, 0);
			x += LOWORD(ret);			// width
			bi = 0;
			fg = c.fg;
			bg = c.bg;
		}
		// if that was a null we've finished
		if(text[i].c==0) break;
		temp[bi++] = text[i++].c;
	}while(true);
}

void TERMINAL::tPaint(HWND hWnd, HDC hdc)
{
	HGDIOBJ oldFont = SelectObject(hdc, hFont);
	TEXTMETRIC tm;
	GetTextMetrics(hdc, &tm);
	INT tabs[]={ 20 };
	tabs[0] = 4 * tm.tmAveCharWidth;
	tHeight = tm.tmHeight;

	int start = GetScrollPos(hWnd, SB_VERT);
	int X = 5;			// start of text
	RECT r;
	GetClientRect(hWnd, &r);
	HBRUSH hb = CreateSolidBrush(RGB(0,0,0));
	FillRect(hdc, &r, hb);
	int x=X, y=0;
	int i = start;
	for(y=r.top; y<r.bottom && i<lines.size(); y += tm.tmHeight){
		x = X;
		TERMINALCHAR* text = lines[i++];
		WrapTab(hdc, text, x, y, tabs);
	}
	x = X;
	WrapTab(hdc, currentLine, x, y, tabs);
	SetCaretPos(caretX=x, caretY=y);

	DeleteObject(hb);
	SelectObject(hdc, oldFont);
}
void TERMINAL::SetScroll(HWND hWnd)
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

LRESULT CALLBACK TERMINAL::Proc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	TERMINAL* td = reinterpret_cast<TERMINAL*>(GetWindowLongPtr(hWnd, 0));	// pointer to TERMINAL

	switch(LOWORD(uMessage)){
	case WM_CREATE:
		// lParam is a pointer to a CREATESTRUCT
		// of which .lpCreateParams is a pointer to the MDICREATESTRUCTW
		{
			MDICREATESTRUCT* cv = reinterpret_cast<MDICREATESTRUCT*>((reinterpret_cast<CREATESTRUCT*>(lParam))->lpCreateParams);
			td = reinterpret_cast<TERMINAL*>(cv->lParam);
			SetWindowLongPtr(hWnd, 0, (LONG_PTR)td);
			SetTimer(hWnd, 1, 200, nullptr);
		}
		return 0;

	case WM_TIMER:
		if(!td->inbound.empty()){
			while(!td->inbound.empty())
				td->AddChar(td->inbound.dequeue());

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
		serial->putc((char)wParam);
		return 0;

	case WM_SETFOCUS:
		CreateCaret(hWnd, nullptr, 3, td->tHeight);
		ShowCaret(hWnd);
		SetCaretPos(td->caretX, td->caretY);
		break;

	case WM_KILLFOCUS:
		DestroyCaret();
		break;

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hWnd, &ps);
		td->tPaint(hWnd, hdc);
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

	case WM_MOUSEWHEEL:
		int move; move = (short)HIWORD(wParam);
		if(move>0)
			--td->nScroll;
		if(move<0)
			++td->nScroll;
		td->SetScroll(hWnd);
		return 0;


	case WM_DESTROY:
		td->hTerminal = nullptr;
		delete terminal;
		terminal = nullptr;
		break;		// use default processing
	}
	return DefMDIChildProc(hWnd, uMessage, wParam, lParam);
}
