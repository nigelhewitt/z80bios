// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

DEBUG debug{};
HWND DEBUG::hTraffic{};

void DEBUG::ShowTraffic()
{
	if(hTraffic==nullptr)
		hTraffic = CreateDialog(hInstance, MAKEINTRESOURCE(IDD_DBGTERM), hFrame, TrafficProc);
	ShowWindow(hTraffic, SW_SHOW);
	SendMessage(hTraffic, WM_USER, 0, 0);	// update
}

//=================================================================================================
// debugger traps
//=================================================================================================
int DEBUG::setTrap(int page, int address)
{
	for(int i=0; i<nTraps; ++i)
		if(traps[i].used==false){
			traps[i].used = true;
			traps[i].page = page;
			traps[i].address = address;
			nPleaseSetTrap = i+1;
			return i+1;
		}
	return 0;
}
//=================================================================================================
// the debugger thread
//=================================================================================================


// called by the debugger to get that character
//-------------------------------------------------------------------------------------------------
// unpack utilities
//-------------------------------------------------------------------------------------------------
void skip(const char* text, int& index)
{
	char c;
	while((c=text[index])==' ' || c=='\t' || c=='\r' || c=='\n')
		++index;
}
int tohex(char c)
{
	if(c>='0' && c<='9') return c-'0';
	if(c>='A' && c<='F') return c+10-'A';
	return c+10-'a';
}
BYTE unpackBYTE(const char* text, int &index)
{
	BYTE ret=0;
	skip(text, index);
	for(int i=0; i<2; ++i)
		if(isxdigit(text[index])){
			ret <<= 4;
			ret += tohex(text[index++]);
		}
	return ret;
}
WORD unpackWORD(const char* text, int& index)
{
	WORD ret=0;
	skip(text, index);
	for(int i=0; i<4; ++i)
		if(isxdigit(text[index])){
			ret <<= 4;
			ret += tohex(text[index++]);
		}
	return ret;
}
char tohexC(WORD b)
{
	b &= 0xf;
	if(b>9) return b-10+'A';
	return b+'0';
}
void packW(WORD w)
{
	debug.putc(tohexC(w>>12));
	debug.putc(tohexC(w>>8));
	debug.putc(tohexC(w>>4));
	debug.putc(tohexC(w));
}
void packB(BYTE b)
{
	debug.putc(tohexC(b>>4));
	debug.putc(tohexC(b));
}
void getBuffer(char *buffer, int cb)
{
	char c{};
	int i = 0;
	while(i<cb-2 && (c=debug.getc())!='@' && c!='?')
		buffer[i++] = c;
	buffer[i++] = c;			// keep the terminator
	buffer[i] = 0;
}
//=================================================================================================
// the debugger working thread
//=================================================================================================

enum { F_RUN = 1, F_STEP, F_KILL, F_BREAK };
int uiFlag{};
void DEBUG::run()  { uiFlag = F_RUN; }
void DEBUG::step() { uiFlag = F_STEP; }
void DEBUG::kill() { uiFlag = F_KILL;}
void DEBUG::pause(){ uiFlag = F_BREAK; }

void DEBUG::debugger()
{
	char buffer[200];
	char c;
	int index;

	while(true)
		switch(state){
		case S_NEW:
			// wait for the client to show up
			while((c=getc())!='@');

			// request the version and NTRAPS
			putc('i');
			getBuffer(buffer, sizeof buffer);
			index=0;							// step over the echo
			int ver; ver = unpackBYTE(buffer, index);
			int n; n   = unpackBYTE(buffer, index);
			if(nTraps==0){
				nTraps = n;
				traps = new TRAP[nTraps];
			}
			if(ver!=1 && n!=nTraps)
				AddTraffic(" INFO PROBLEM ");
			// set the hooks
			Sleep(200);
			flush();
			putc('h');
			getBuffer(buffer, sizeof buffer);
			state = S_TRAP;
			break;

		case S_IDLE:			// waiting for the UI
			Sleep(200);
			switch(uiFlag){
			case 0:
				break;
			case F_RUN:
				flush();
				putc('k');		// continue command
				state = S_RUN;
				break;
			case F_STEP:
				flush();
				putc('s');		// step command
				break;
			case F_KILL:
				break;
			}
			uiFlag = 0;
			if(debug.nPleaseSetTrap){
				int i=debug.nPleaseSetTrap - 1;
				debug.nPleaseSetTrap = 0;
				putc('+');
				putc(' ');
				packB(i);
				putc(' ');
				packB(debug.traps[i].page);
				putc(' ');
				packW(debug.traps[i].address);
				getBuffer(buffer, sizeof buffer);
			}
			break;

		case S_RUN:				// waiting for UI and trap
			if(poll() && getc()=='@'){
				state = S_TRAP;
				break;
			}
			Sleep(200);
			break;

		case S_TRAP:
			do{
				Sleep(200);
				flush();
				putc('q');			// not a command but cycles the system
				getBuffer(buffer, sizeof buffer);
			} while(buffer[0]!='?');
			// request the registers
			Sleep(200);
			flush();
			putc('r');
			getBuffer(buffer, sizeof buffer);
			unpackRegs(buffer, &regs);
			// request the memory of the page mapping
			Sleep(200);
			flush();
			putc('g');
			putc(' ');
			packW(0x34);
			putc(' ');
			packB(4);
			getBuffer(buffer, sizeof buffer);
			unpackMAP(buffer, &regs);
			bRegsPlease = true;
			bPopupPlease = true;
			state = S_IDLE;
			break;
		}
}

//=================================================================================================
// Traffic dialog box
//=================================================================================================
INT_PTR DEBUG::TrafficProc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
	SetTimer(hDlg, 0, 200, nullptr);
		return TRUE;

	case WM_TIMER:
		if(debug.traffic.count()){
			char text[200];
			int i=0;
			while(i<(int)sizeof text-1 && debug.traffic.count())
				text[i++] = debug.traffic.dequeue();
			text[i] = 0;

			int n = GetWindowTextLength(GetDlgItem(hDlg, IDC_DEBUGTERM));
			n += i + 10;
			char *buffer = new char[n];
			GetDlgItemText(hDlg, IDC_DEBUGTERM, buffer, n);
			strcat_s(buffer, n, text);
			SetDlgItemText(hDlg, IDC_DEBUGTERM, buffer);
			delete[] buffer;
		}
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:
			SetDlgItemText(hDlg, IDC_DEBUGTERM, "");
			return TRUE;
		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			hTraffic = nullptr;
			return TRUE;
		}
		break;
	}
	return FALSE;
}
//=================================================================================================
// Memory display
//=================================================================================================
struct MEMDATA {
	BYTE  page{};
	DWORD address{};
	int   count{};
	BYTE  *array{};
	bool  enable{};
};
INT_PTR MemProc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	char buffer[100];
	MEMDATA* md = reinterpret_cast<MEMDATA*>(GetWindowLongPtr(hDlg, DWLP_USER));	// pointer to your data

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		md = new MEMDATA;
		SetWindowLongPtr(hDlg, DWLP_USER, (LONG_PTR)md);
		DropLoad(hDlg, IDC_MEMORYADDR);
		DropLoad(hDlg, IDC_MEMORYCOUNT);
		SetTimer(hDlg, 0, 200, nullptr);
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:					// aka Refresh
reload:		GetDlgItemText(hDlg, IDC_MEMORYADDR, buffer, sizeof buffer);
			if(isalpha(buffer[0])){
				auto tp = FindDefinition(buffer);
				int file = get<0>(tp);
				if(file<0){
					MessageBox(hDlg, "NOT FOUND", "", MB_OK);
					return TRUE;
				}
				md->address = get<3>(tp);
				md->page = get<0>(tp);
				DropSave(IDC_MEMORYADDR, buffer);
			}
			else{
				if(buffer[0]=='.')
					md->address = strtol(buffer+1, nullptr, 10);
				else
					md->address = strtol(buffer, nullptr, 16);
			}
			GetDlgItemText(hDlg, IDC_MEMORYCOUNT, buffer, sizeof buffer);
			if(buffer[0]=='.')
				md->count = strtol(buffer+1, nullptr, 10);
			else
				md->count = strtol(buffer, nullptr, 16);
			DropSave(IDC_MEMORYCOUNT, buffer);

			// refresh.....
			delete[] md->array;
			md->array = nullptr;
			if(md->count){
				md->array = new BYTE[md->count];
				debug.pleaseFetch(md->array, md->page, md->address, md->count);
				for(int i=0; i<md->count; md->array[i] = i & 0xff, ++i);
			}
			InvalidateRect(hDlg, nullptr, TRUE);
			return TRUE;

		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			delete md;
			return TRUE;
		}
		break;

	case WM_TIMER:
		bool en; en=debug.state==DEBUG::S_IDLE;
		if(en!=md->enable){
			EnableWindow(GetDlgItem(hDlg, IDOK), en);
			if(en) goto reload;
		}
		return TRUE;

	case WM_SIZE:
		{
			RECT rc;
			GetClientRect(hDlg, &rc);
			MoveWindow(GetDlgItem(hDlg, IDOK), rc.right-170, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDCANCEL), rc.right-85, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_LCNT), rc.right-103, rc.top+5, 30, 20, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMORYCOUNT), rc.right-68, rc.top+3, 60, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMORYADDR), rc.left+80, rc.top+3, rc.right-rc.left-196, 23, TRUE);
			InvalidateRect(hDlg, nullptr, TRUE);
			break;
		}

	case WM_PAINT:
		{
			HDC hdc;
			PAINTSTRUCT ps;
			hdc = BeginPaint(hDlg, &ps);
			RECT rc;
			GetClientRect(hDlg, &rc);
			rc.top += 32;
			rc.left += 10;
			rc.bottom -= 35;
			rc.right -= 10;
			MoveToEx(hdc, rc.left, rc.top, nullptr);
			LineTo(hdc, rc.right, rc.top);
			LineTo(hdc, rc.right, rc.bottom);
			LineTo(hdc, rc.left, rc.bottom);
			LineTo(hdc, rc.left, rc.top);

			HRGN hrgn = CreateRectRgn(rc.left+2, rc.top+2, rc.right-2, rc.bottom-2);
			SelectClipRgn(hdc, hrgn);
			for(int row=0; row<100;++row){
				int y = rc.top + 5 + 15*row;
				if(y>rc.bottom) break;
				char temp[8];
				if(row*16<md->count){
					MoveToEx(hdc, rc.left+280, y+7, nullptr);
					LineTo(hdc, rc.left+285, y+7);
					sprintf_s(temp, sizeof temp, "%s%d ", md->page>=32?"ROM":"RAM", md->page%32);
					TextOut(hdc, rc.left+5, y, temp, 5);
					sprintf_s(temp, sizeof temp, "%04X", md->address + row*16);
					TextOut(hdc, rc.left+65, y, temp, 4);
				}
				for(int col=0; col<16; ++col){
					int index = row*16+col;
					if(index < md->count){
						BYTE b = md->array[row*16+col];
						sprintf_s(temp, sizeof temp, "%02X", b);
						TextOut(hdc, rc.left+125+col*24, y, temp, 2);
						if(b<0x20 || b>=0x7f)
							temp[0] = ' ';
						else
							temp[0] = b;
						temp[1] = 0;
						TextOut(hdc, rc.left+510+col*10, y, temp, 1);
					}
				}
			}
			EndPaint(hDlg, &ps);
		}
		break;
	}
	return FALSE;
}
void ShowMemory()
{
	HWND hMem = CreateDialog(hInstance, MAKEINTRESOURCE(IDD_MEMORY), hFrame, MemProc);
	ShowWindow(hMem, SW_SHOW);
	SendMessage(hMem, WM_USER, 0, 0);
}
//================================================================================================
// Fetch memory data from the DEBUG thread
//================================================================================================
void DEBUG::pleaseFetch(BYTE* buffer, BYTE page, DWORD address, WORD count)
{
}
