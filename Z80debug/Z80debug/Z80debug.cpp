// FrameTemplate.cpp : Defines the entry point for the application.
//

#include "framework.h"
#include "serial.h"
#include "process.h"
#include "terminal.h"
#include "traffic.h"
#include "source.h"
#include "regs.h"
#include "mem.h"
#include "util.h"
#include "Z80debug.h"

#pragma comment(lib, "Comctl32.lib")

//=================================================================================================
//		IMPORTANT CONCEPT
//
// THere are three threads
//		The windows UI with all it's stops and starts
//		The serial data IO
//		The debugger
//
//=================================================================================================

// Global Variables:
HINSTANCE hInstance;				// current instance
HWND hFrame, hClient;				// the outer frame and its inner client area
HWND hToolbar, hStatus;				// toolbar and status 'button'

bool bRegsPlease{};					// requests from the debugger to the UI

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
// GetStuff()		generic ask for text dialog
//=====================================================================================================
INT_PTR Search(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	static std::tuple<char*,int> *stuff;

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		stuff = (std::tuple<char*,int>*)lParam;
		SetWindowText(GetDlgItem(hDlg, IDC_SEARCH), get<0>(*stuff));
		DropLoad(hDlg, IDC_SEARCH);
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:
			GetWindowText(GetDlgItem(hDlg, IDC_SEARCH), get<0>(*stuff), get<1>(*stuff));
			DropSave(IDC_SEARCH, get<0>(*stuff));

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
		{ 0,	0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 0,	IDM_SEARCH,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Find"},
		{ 1,	IDM_CONFIGURE,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Conf"},
		{ 0,	0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 2,	IDM_TERMINAL,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Term"},
		{ 3,	IDM_REGS,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Regs"},
		{ 4,	IDM_MEMORY,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Mem"},
		{ 5,	IDM_TRAFFIC,	TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Traffic"},
		{ 0,	0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 6,	IDM_RUN,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Run"},
		{ 7,	IDM_STEP,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Step"},
		{ 8,	IDM_BREAK,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Break"},
		{ 9,	IDM_KILL,		TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"Kill"},
		{ 10,	IDM_OS,			TBSTATE_ENABLED, buttonStyles,	{0}, 0, (INT_PTR)"OS"},
		{ 0,	0,				TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, 0},
		{ 100,	IDM_STATUS,		TBSTATE_ENABLED, BTNS_SEP,		{0}, 0, (INT_PTR)"Status"}

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

	hStatus = CreateWindowEx(0, "BUTTON", "STOPPED",
								WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
								420, 3, 200, 37,
								hToolbar, nullptr, hInstance, nullptr);

	// Resize the toolbar, and then show it.
	SendMessage(hToolbar, TB_AUTOSIZE, 0, 0);
	ShowWindow(hToolbar,  TRUE);

	return hToolbar;
}
void SetStatus(const char* text)
{
	SetWindowText(hStatus, text);
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
		int i = IDM_SOURCE, j=0;
		for(auto &s : PROCESS::files){
			char temp[100];
			if(s.second.page==100)			// ie: an SDL file
 				sprintf_s(temp, sizeof temp, " %s", s.second.fn);
			else if(s.second.minor){
				++i;
				continue;
			}
			else
				sprintf_s(temp, sizeof temp, "%d %s", s.second.page, s.second.fn);
			int bb=0;
			if(++j==25){
				j = 0;
				bb = MF_MENUBARBREAK;
			}
			AppendMenu(hSource, MF_STRING | bb, i++, temp);
		}

		if(!hClient)
			error();
		else
			ShowWindow(hClient, SW_SHOW);

		// create the working subsystems
		{
			char* temp = GetProfile("setup", "baud", "9600");
			int nBaud = strtol(temp, nullptr, 10);
			temp = GetProfile("setup", "port", "COM8");
			serial = new SERIAL;
			serial->setup(temp, nBaud);

			terminal = new TERMINAL;
			debug = new DEBUG;
			if(GetProfile("setup", "show-traffic", "false")[0]=='t')
				TRAFFIC::ShowTraffic(hWnd);
		}
		SetStatus("WAITING FOR HOST");
		SetTimer(hWnd, 1, 200, nullptr);
		return 0;
	}
	case WM_COMMAND:
		WORD cmd; cmd=LOWORD(wParam);
		if(cmd>=IDM_SOURCE && cmd<IDM_SOURCE+PROCESS::files.size()){
			char temp[100];
			int id = cmd-IDM_SOURCE;
			PROCESS::FDEF &f = PROCESS::files[id];
			if(f.hSource)
				SetWindowPos(f.hSource, HWND_TOP, 0,0,0,0,SWP_NOMOVE|SWP_NOREPOSITION);
			else{
				sprintf_s(temp, sizeof temp, "Source: %d %s", f.page, f.fn);
				new SOURCE(temp, id, f.page);
			}
			return 0;
		}
		switch(cmd){
		case IDM_SEARCH:
		{
			std::tuple<char*,int> x;
			char temp[100]{ "SectorToCluster"};
			x = { temp, 100 };
			DialogBoxParam(hInstance, MAKEINTRESOURCE(IDD_SEARCH), hWnd, Search, (LPARAM)&x);

			auto y = process->FindDefinition(temp);
			int file = get<0>(y);
			int line = get<2>(y);
			if(file<0)
				MessageBox(hWnd, "NOT FOUND", "", MB_OK);
			else
				SOURCE::PopUp(file, line);
			return 0;
		}

		case IDM_TERMINAL:
			if(terminal==nullptr)
				terminal = new TERMINAL;
			else
				terminal->clear();
			return 0;

		case IDM_CONFIGURE:
			Configure(hWnd);
			return 0;

		case IDM_TRAFFIC:
			TRAFFIC::ShowTraffic(hWnd);
			return 0;

		case IDM_REGS:
			REGS::ShowRegs();
			return 0;

		case IDM_RUN:
			debug->run();
			return 0;

		case IDM_STEP:
			debug->step();
			return 0;

		case IDM_KILL:
			debug->kill();
			return 0;

		case IDM_BREAK:
			debug->pause();
			return 0;

		case IDM_MEMORY:
			new MEM;
			return 0;

		case IDM_OS:
			debug->os();
			return 0;

		case IDM_ABOUT:
			DialogBox(hInstance, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
			return 0;

		case IDM_EXIT:
			DestroyWindow(hWnd);
			return 0;
		}
		break;

	case WM_TIMER:
		// a little inter-thread helpfulness
		if(bRegsPlease){
			REGS::ShowRegs();
			bRegsPlease = false;
		}
#if 0
		if(bPopupPlease){
			bPopupPlease = false;
			static int file=-1, line;
			if(file>=0)		// remove previous highlight
				PopUp(file, line, false);
			auto y = FindTrace(regs->PC);
			file = get<0>(y);
			line = get<1>(y);
			if(file<0)
				MessageBox(hWnd, "NOT FOUND", "", MB_OK);
			else
				PopUp(file, line);
		}
#endif
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
		delete debug;
		debug = nullptr;
//		delete terminal;
//		delete serial;
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
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_FRAME));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
	w.lpszMenuName	= MAKEINTRESOURCE(IDI_Z80debugger);
	w.lpszClassName	= "Z80frame";
	w.hIconSm		= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_SMALL));
	RegisterClassEx(&w);

	// Register the source file MDI child window
	w.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
	w.lpfnWndProc	= SOURCE::Proc;
	w.cbWndExtra	= sizeof LONG_PTR;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_SOURCE));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= nullptr;
	w.lpszMenuName	= nullptr;
	w.lpszClassName	= "Z80source";
	w.hIconSm		= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_SMALL));
	RegisterClassEx(&w);

	// Register the terminal MDI child window
	w.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
	w.lpfnWndProc	= TERMINAL::Proc;
	w.cbWndExtra	= sizeof LONG_PTR;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_TERMINAL));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= nullptr;
	w.lpszMenuName	= nullptr;
	w.hIconSm		= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_SMALL));
	w.lpszClassName	= "Z80terminal";
	RegisterClassEx(&w);

	// Perform application initialization:
	::hInstance = hInstance;			// Store instance handle in our global variable

	char* cwd = _strdup(GetProfile("setup", "folder", "D:"));
	SetCurrentDirectory(cwd);
	process = new PROCESS(cwd);			// and load the files

	hFrame = CreateWindowEx(0, "Z80frame", "Z80debugger", WS_OVERLAPPEDWINDOW,
					CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, LoadMenu(hInstance, MAKEINTRESOURCE(IDC_Z80debugger)), hInstance, nullptr);
	if(!hFrame) return 99;

	ShowWindow(hFrame, nCmdShow);
	UpdateWindow(hFrame);

	HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_Z80debugger));
	MSG msg;

	// Main message loop:
	while(GetMessage(&msg, nullptr, 0, 0)){
		if(regs && IsWindow(regs->hwnd()) && IsDialogMessage(regs->hwnd(), &msg))	// feed the modeless dialog
			continue;
		if(!TranslateMDISysAccel(hClient, &msg) && !TranslateAccelerator(hFrame, hAccelTable, &msg)){
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	return (int)msg.wParam;
}
