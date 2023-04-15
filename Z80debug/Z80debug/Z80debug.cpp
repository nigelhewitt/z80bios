// FrameTemplate.cpp : Defines the entry point for the application.
//

#include "framework.h"
#include "Z80debug.h"

// Global Variables:
HINSTANCE hInstance;				// current instance
HWND hFrame, hClient;				// the outer frame and its inner client area
HFONT hFont;
SERIAL* serial;

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
// add a new child Window
//=====================================================================================================

HWND AddChild(const char* title, void* data = nullptr)
{
	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Child";
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
void RemoveChild(HWND hChild)
{
	SendMessage(hClient, WM_MDIDESTROY, (WPARAM)hChild, 0);
}
LRESULT SendToActiveChild(UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	auto hwnd = reinterpret_cast<HWND>(SendMessage(hClient, WM_MDIGETACTIVE, 0, 0));
	if(hwnd) return SendMessage(hwnd, uMessage, wParam, lParam);
	return 0;
}
HWND AddTerminal(void* data = nullptr)
{
	if(IsIconic(hFrame)){
		ShowWindow(hFrame, SW_RESTORE);
		SetForegroundWindow(hFrame);
		UpdateWindow(hFrame);
	}

	MDICREATESTRUCT mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass	= "Terminal";
	mcs.szTitle	= "Terminal";
	mcs.hOwner	= hInstance;
	mcs.x		= CW_USEDEFAULT;
	mcs.y		= CW_USEDEFAULT;
	mcs.cx		= 800;
	mcs.cy		= 600;
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
//=====================================================================================================
// add a new child dialog - this is a wrapper to do lots of dialogs
//=====================================================================================================
#if 0
HWND CreateMDIDialog(LPCWSTR szTitle, LPCWSTR szTemplate, DLGPROC proc, LPARAM lParam)
{
	// Build the DLGDATA struct with the details needed for running the dialog
	auto dld		 = new DLGDATA;
	dld->szTitle	 = szTitle;
	dld->szTemplate	 = szTemplate;
	dld->proc		 = proc;
	dld->lParam		 = lParam;

	// Then create a new MDI child using our MDIDialog registered class
	MDICREATESTRUCTW mcs{};					// do not use CreateWindow() for MDI children
	mcs.szClass   = L"MDIDialog";
	mcs.szTitle   = szTitle;
	mcs.hOwner    = hInstance;
	mcs.x         = CW_USEDEFAULT;
	mcs.y         = CW_USEDEFAULT;
	mcs.cx		  = 300;					// size is nominal
	mcs.cy		  = 150;
	mcs.style     = 0;
	mcs.lParam	  = reinterpret_cast<LPARAM>(dld);

	return reinterpret_cast<HWND>(SendMessage(hClient, WM_MDICREATE, 0, reinterpret_cast<LPARAM>(reinterpret_cast<LPMDICREATESTRUCT>(&mcs))));
}
void RemoveMDIDialog(HWND hWnd)
{
	SendMessage(hClient, WM_MDIDESTROY, reinterpret_cast<WPARAM>(GetParent(hWnd)), 0L);
}
#endif
//=====================================================================================================
//  WndProc(HWND, UINT, WPARAM, LPARAM)
//=====================================================================================================

#define WINDOWMENU		2		// zero index of "Windows" menu to append the children list to
#define SOURCEMENU		1

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

		HMENU hSource = GetSubMenu(GetMenu(hWnd), SOURCEMENU);
		int i = IDM_SOURCE;
		for(auto s : files)
			AppendMenu(hSource, MF_STRING,++i, s);

		if(!hClient)
			error();
		else
			ShowWindow(hClient, SW_SHOW);
		serial = new SERIAL("COM7", 115200);

		AddTerminal(nullptr);
		return 0;
	}
	case WM_COMMAND:
		WORD cmd; cmd=LOWORD(wParam);
		if(cmd>=IDM_SOURCE && cmd<IDM_SOURCE+files.size()){
			char temp[100];
			sprintf_s(temp, sizeof temp, "Source: %s", files[cmd-IDM_SOURCE-1]);
			AddChild(temp, (void*)files[cmd-IDM_SOURCE-1]);
			return 0;
		}
		switch(cmd){
		case IDM_FORCHILD:
			return SendToActiveChild(uMessage, wParam, lParam);

		case IDM_ABOUT:
			DialogBox(hInstance, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
			return 0;

		case IDM_EXIT:
			DestroyWindow(hWnd);
			return 0;
		}
		break;

	case WM_SIZE:
		MoveWindow(hClient, 0, 0, LOWORD(lParam), HIWORD(lParam), TRUE);
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
	w.lpszClassName	= "Frame";
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
	w.lpszClassName	= "Child";
	RegisterClassEx(&w);

	// Register an MDI child window
	w.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
	w.lpfnWndProc	= TerminalWndProc;
	w.cbWndExtra	= sizeof LONG_PTR;
	w.hIcon			= LoadIcon(hInstance, MAKEINTRESOURCE(IDI_Child));
	w.hCursor		= LoadCursor(nullptr, IDC_ARROW);
	w.hbrBackground	= nullptr;
	w.lpszMenuName	= nullptr;
	w.lpszClassName	= "Terminal";
	RegisterClassEx(&w);
#if 0
	// Register the MDI dialog container
	w.style			= 0;
	w.lpfnWndProc	= MDIDialogProc;
	w.cbWndExtra	= sizeof(LONG_PTR);

	w.lpszClassName  = L"MDIDialog";
	RegisterClassEx(&w);
#endif

	// Perform application initialization:
	::hInstance = hInstance;			// Store instance handle in our global variable

	SetCurrentDirectory("D:\\Systems\\Z80\\bios\\");
	if(ReadSDL("bios0.sdl")==0){
		MessageBox(0, "No SDL file details", "Z80debugger", MB_OK);
		return 0;
	}
	hFont = CreateFont(20, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, 0, DEFAULT_QUALITY, FIXED_PITCH, "Cascadia Code");


	hFrame = CreateWindowEx(0, "Frame", "Z80debugger", WS_OVERLAPPEDWINDOW,
					CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, LoadMenu(hInstance, MAKEINTRESOURCE(IDC_Z80debugger)), hInstance, nullptr);

	if(!hFrame) return 99;

	ShowWindow(hFrame, nCmdShow);
	UpdateWindow(hFrame);

	HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_Z80debugger));
	MSG msg;

	// Main message loop:
	while(GetMessage(&msg, nullptr, 0, 0)){
		if(!TranslateMDISysAccel(hClient, &msg) && !TranslateAccelerator(hFrame, hAccelTable, &msg)){
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	return (int)msg.wParam;
}
