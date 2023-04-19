// FrameTemplate.cpp : Defines the entry point for the application.
//

#include "framework.h"
#include "Z80debug.h"

// Global Variables:
HINSTANCE hInstance;				// current instance
HWND hFrame, hClient, hToolbar;		// the outer frame and its inner client area
HWND hTerminal;
HFONT hFont, hFontSmall;
SERIAL* serial;
UINT regMessage;
bool bRegsPlease{}, bPopupPlease{};

#pragma comment(lib, "Comctl32.lib")

//=====================================================================================================
// handler to unpack Windows error codes into text
//=====================================================================================================

void error(DWORD err)
{
	char temp[200];
	int cb = sizeof temp;
	if(err == 0)
		err = GetLastError();
	wsprintf(temp, "%X ", err);
	DWORD i = (DWORD)strlen(temp);
	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, nullptr, err, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), &temp[i], cb-i, nullptr);
	// now remove the \r\n we get on the end
	for(auto n = strnlen_s(temp, cb); n>3 && (temp[n-1] == '\r' || temp[n-1] == '\n'); temp[n-- - 1] = 0);		// yes it does compile
	MessageBox(nullptr, temp, "Error", MB_OK);
}
//=====================================================================================================
// Message handler for about box.
//=====================================================================================================

INT_PTR CALLBACK About(HWND hDlg, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	switch(uMessage){
	case WM_INITDIALOG:
		return (INT_PTR)TRUE;

	case WM_COMMAND:
		switch LOWORD(wParam) {
		case IDOK:
		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			return (INT_PTR)TRUE;
		}
		break;
	}
	return (INT_PTR)FALSE;
}
//=====================================================================================================
// add a new source Window
//=====================================================================================================

HWND AddSource(const char* title, void* data)
{
	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Z80source";
	mcs.szTitle	= title;
	mcs.hOwner	= hInstance;
	mcs.x		= CW_USEDEFAULT;
	mcs.y		= CW_USEDEFAULT;
	mcs.cx		= CW_USEDEFAULT;
	mcs.cy		= CW_USEDEFAULT;
	mcs.style	= WS_HSCROLL | WS_VSCROLL;
	mcs.lParam	= (LPARAM)data;

	HWND hWnd = (HWND)SendMessage(hClient, WM_MDICREATE, 0, (LPARAM)&mcs);
	if(hWnd == nullptr){
		// display some error message
		error();
		return nullptr;
	}
	SetFocus(hWnd);
	return hWnd;
}
void RemoveSource(HWND hChild)
{
	SendMessage(hClient, WM_MDIDESTROY, (WPARAM)hChild, 0);
}
LRESULT SendToActiveChild(UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	auto hwnd = reinterpret_cast<HWND>(SendMessage(hClient, WM_MDIGETACTIVE, 0, 0));
	if(hwnd) return SendMessage(hwnd, uMessage, wParam, lParam);
	return 0;
}
void AddTerminal(void* data)
{
	if(hTerminal){
		PostMessage(hTerminal, WM_DESTROY, 0, 0);
		hTerminal = 0;
		return;
	}

	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Z80terminal";
	mcs.szTitle	= "Terminal";
	mcs.hOwner	= hInstance;
	mcs.x		= CW_USEDEFAULT;
	mcs.y		= CW_USEDEFAULT;
	mcs.cx		= 800;
	mcs.cy		= 600;
	mcs.style	= WS_HSCROLL | WS_VSCROLL;
	mcs.lParam	= (LPARAM)data;

	hTerminal = (HWND)SendMessage(hClient, WM_MDICREATE, 0, (LPARAM)&mcs);
	if(hTerminal == nullptr){
		// display some error message
		error();
		return;
	}
	SetFocus(hTerminal);
}
//=====================================================================================================
// GetStuff()		generic ask for text dialog
//=====================================================================================================
INT_PTR GetStuff(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	static std::tuple<char*,int> *stuff;

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
			stuff = (std::tuple<char*,int>*)lParam;
			SetWindowText(GetDlgItem(hDlg, IDC_STUFF), get<0>(*stuff));
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:
			GetWindowText(GetDlgItem(hDlg, IDC_STUFF), get<0>(*stuff), get<1>(*stuff));
		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			return TRUE;
		}
		break;
	}
	return FALSE;
}
//=====================================================================================================
// Add Toolbar
//=====================================================================================================
#define H_TOOLBAR 45
HIMAGELIST hImageList = nullptr;

bool AddToolbar(HWND hParent)
{
	const int bitmapSize	= 16;
	const DWORD buttonStyles = BTNS_AUTOSIZE;

	DWORD backgroundColor = RGB(240,240,240); //Must be 256 colour bitmap or less !!!;
	COLORMAP colorMap;
	colorMap.from = RGB(192, 192, 192);
	colorMap.to = backgroundColor;
	HBITMAP hbm = CreateMappedBitmap(hInstance, IDB_TOOLBAR, 0, &colorMap, 1);

	TBBUTTON tbButtons[] = {
		{ 0, 0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 0, IDM_SEARCH,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Find"},
		{ 0, 0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 1, IDM_TERMINAL,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Term"},
		{ 2, IDM_REGS,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Regs"},
		{ 3, IDM_TRAFFIC,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Traffic"},
		{ 4, IDM_CONFIGURE,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Conf"},
		{ 0, 0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 5, IDM_RUN,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Run"},
		{ 6, IDM_STEP,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Step"},
		{ 7, IDM_KILL,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Kill"},
		{ 8, IDM_BREAK,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Break"},
		{ 0, 0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 9, IDM_MEMORY,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Mem"}

	};
	const int numButtons	= _countof(tbButtons);

	// Create the image list.
	hImageList = ImageList_Create(bitmapSize, bitmapSize,		// Dimensions of individual bitmaps.
									ILC_COLOR16 | ILC_MASK,		// Ensures transparent background.
									numButtons, 0);

	// Create the toolbar.
	hToolbar = CreateWindowEx(0, TOOLBARCLASSNAME, nullptr,
									WS_CHILD | TBSTYLE_WRAPABLE, 0, 0, 0, 0,
									hParent, nullptr, hInstance, nullptr);

	if(hToolbar == nullptr){
		error();
		return false;
	}

	TBADDBITMAP tb;
	tb.hInst = NULL;
	tb.nID = (UINT_PTR)hbm;
	SendMessage(hToolbar, TB_ADDBITMAP, 16, (LPARAM)&tb);

	// Add buttons.
	SendMessage(hToolbar, TB_BUTTONSTRUCTSIZE, (WPARAM)sizeof(TBBUTTON), 0);
	SendMessage(hToolbar, TB_ADDBUTTONS,	   (WPARAM)numButtons,		 (LPARAM)&tbButtons);

	// Resize the toolbar, and then show it.
	SendMessage(hToolbar, TB_AUTOSIZE, 0, 0);
	ShowWindow(hToolbar,  TRUE);

	return hToolbar;
}
//=====================================================================================================
//  WndProc(HWND, UINT, WPARAM, LPARAM)
//=====================================================================================================

#define WINDOWMENU		3		// zero index of "Windows" menu to append the children list to
#define SOURCEMENU		2

LRESULT CALLBACK FrameWndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	switch(uMessage){
	case WM_CREATE:
	{
		CLIENTCREATESTRUCT ccs{};
		ccs.hWindowMenu = GetSubMenu(GetMenu(hWnd), WINDOWMENU);
		ccs.idFirstChild = IDM_WINDOWCHILD;

		// Create the MDI client window.
		hClient = CreateWindowEx(0, "MDICLIENT", nullptr,
			WS_CHILD | WS_CLIPCHILDREN | WS_VSCROLL | WS_HSCROLL,
			0, 0, 0, 0, hWnd, (HMENU)0xCAC, hInstance, (LPSTR)&ccs);

		AddToolbar(hWnd);

		HMENU hSource = GetSubMenu(GetMenu(hWnd), SOURCEMENU);
		int i = IDM_SOURCE;
		for(auto &s : files){
			char temp[100];
			if(!s.show)
				continue;
			if(s.page==100)			// ie: an SDL file
 				sprintf_s(temp, sizeof temp, " %s", s.fn);
			else
				sprintf_s(temp, sizeof temp, "%d %s", s.page, s.fn);
			s.id = ++i;
			AppendMenu(hSource, MF_STRING,i, temp);
		}

		if(!hClient)
			error();
		else
			ShowWindow(hClient, SW_SHOW);
		{
			char* temp = GetProfile("setup", "baud", "9600");
			int nBaud = strtol(temp, nullptr, 10);
			temp = GetProfile("setup", "port", "COM8");
			serial = new SERIAL(temp, nBaud);
		}

		AddTerminal(nullptr);
		debug.start();			// in a separate thread
		SetTimer(hWnd, 1, 200, nullptr);
		return 0;
	}
	case WM_COMMAND:
		WORD cmd; cmd=LOWORD(wParam);
		if(cmd>=IDM_SOURCE && cmd<IDM_SOURCE+files.size()){
			char temp[100];
			for(FDEF f : files){
				if(f.id==cmd){
					sprintf_s(temp, sizeof temp, "Source: %d %s", f.page, f.fn);
					AddSource(temp, (void*)&f);
					break;
				}
			}
			return 0;
		}
		switch(cmd){
//		case IDM_FORCHILD:
//			return SendToActiveChild(uMessage, wParam, lParam);

		case IDM_SEARCH:
		{
			std::tuple<char*,int> x;
			char temp[100]{ "SectorToCluster"};
			x = { temp, 100 };
			DialogBoxParam(hInstance, MAKEINTRESOURCE(IDD_GETSTUFF), hWnd, GetStuff, (LPARAM)&x);

			auto y = FindDefinition(temp);
			int file = get<0>(y);
			int line = get<1>(y);
			if(file<0)
				MessageBox(hWnd, "NOT FOUND", "", MB_OK);
			else
				PopUp(file, line);
			return 0;
		}

		case IDM_TERMINAL:
			if(hTerminal==nullptr)
				AddTerminal(nullptr);
			return 0;

		case IDM_CONFIGURE:
			return 0;

		case IDM_TRAFFIC:
			debug.ShowTraffic();
			return 0;

		case IDM_REGS:
			ShowRegs();
			return 0;

		case IDM_RUN:
			debug.run();
			return 0;

		case IDM_STEP:
			debug.step();
			return 0;

		case IDM_KILL:
			debug.kill();
			return 0;

		case IDM_BREAK:
			debug.pause();
			return 0;

		case IDM_MEMORY:
			ShowMemory();
			return 0;

		case IDM_ABOUT:
			DialogBox(hInstance, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
			return 0;

		case IDM_EXIT:
			debug.die();
			DestroyWindow(hWnd);
			return 0;
		}
		break;

	case WM_TIMER:
		// a little inter-thread helpfulness
		if(bRegsPlease){
			bRegsPlease = false;
			ShowRegs();
		}
		if(bPopupPlease){
			bPopupPlease = false;
			static int file=-1, line;
			if(file>=0)		// remove previous highlight
				PopUp(file, line, false);
			auto y = FindTrace(regs.PC);
			file = get<0>(y);
			line = get<1>(y);
			if(file<0)
				MessageBox(hWnd, "NOT FOUND", "", MB_OK);
			else
				PopUp(file, line);
		}
		return 0;

	case WM_SIZE:
		MoveWindow(hToolbar, 0, 0, H_TOOLBAR, HIWORD(lParam), TRUE);
		MoveWindow(hClient,0,  H_TOOLBAR, LOWORD(lParam), HIWORD(lParam)-H_TOOLBAR, TRUE);
		return 0;

	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hdc = BeginPaint(hWnd, &ps);

		EndPaint(hWnd, &ps);
		return 0;
	}

	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	}
	return DefFrameProc(hWnd, hClient, uMessage, wParam, lParam);
}
//=====================================================================================================
// WinMain - this is where we make most of our planets
//=====================================================================================================

int APIENTRY WinMain(	_In_ HINSTANCE		hInstance,
						_In_opt_ HINSTANCE	hPrevInstance,
						_In_ LPSTR			lpCmdLine,
						_In_ int			nCmdShow)
{
	// Register the Window Class
	WNDCLASSEX w{};
	w.cbSize		= sizeof(WNDCLASSEX);
	w.style			= 0;
	w.lpfnWndProc	= FrameWndProc;
	w.cbClsExtra	= 0;
	w.cbWndExtra	= 0;
	w.hInstance		= hInstance;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_Child));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
	w.lpszMenuName	= MAKEINTRESOURCE(IDI_Z80debugger);
	w.lpszClassName	= "Z80frame";
	w.hIconSm		= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_SMALL));
	RegisterClassEx(&w);

	// Register an MDI child window
	w.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
	w.lpfnWndProc	= SourceWndProc;
	w.cbWndExtra	= sizeof LONG_PTR;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_Child));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= nullptr;
	w.lpszMenuName	= nullptr;
	w.lpszClassName	= "Z80source";
	RegisterClassEx(&w);

	// Register an MDI child window
	w.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
	w.lpfnWndProc	= TerminalWndProc;
	w.cbWndExtra	= sizeof LONG_PTR;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_Child));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= nullptr;
	w.lpszMenuName	= nullptr;
	w.lpszClassName	= "Z80terminal";
	RegisterClassEx(&w);

	// Perform application initialization:
	::hInstance = hInstance;			// Store instance handle in our global variable

	const char* cwd = "D:\\Systems\\Z80\\bios\\";
	SetCurrentDirectory(cwd);
	getIniFile();

	// Find all the .sdl files in this folder
	{
		WIN32_FIND_DATA ffd;
		char fPath[MAX_PATH];
		strcpy_s(fPath, sizeof fPath, cwd);
		strcat_s(fPath, sizeof fPath, "*.sdl");
		HANDLE hFind = FindFirstFile(fPath, &ffd);
		if(hFind!=INVALID_HANDLE_VALUE)
			do
				ReadSDL(ffd.cFileName);
			while(FindNextFile(hFind, &ffd) != 0);
	}

	hFont = CreateFont(20, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");
	hFontSmall = CreateFont(15, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");

	hFrame = CreateWindowEx(0, "Z80frame", "Z80debugger", WS_OVERLAPPEDWINDOW,
					CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, LoadMenu(hInstance, MAKEINTRESOURCE(IDC_Z80debugger)), hInstance, nullptr);
	UINT regMessage = RegisterWindowMessage("Z80debug-0");
	if(!hFrame) return 99;

	ShowWindow(hFrame, nCmdShow);
	UpdateWindow(hFrame);

	HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_Z80debugger));
	MSG msg;

	// Main message loop:
	while(GetMessage(&msg, nullptr, 0, 0)){
		if(IsWindow(hRegs) && IsDialogMessage(hRegs, &msg))			// feed the modeless dialog
			continue;
		if(!TranslateMDISysAccel(hClient, &msg) && !TranslateAccelerator(hFrame, hAccelTable, &msg)){
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	return (int)msg.wParam;
}
