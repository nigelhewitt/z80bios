// traffic.cpp
//

#include "framework.h"
#include "mem.h"
#include "Z80debug.h"


//=================================================================================================
// Memory display
//=================================================================================================

MEM::MEM(DWORD _address, int _count)
{
	address = _address;
	count	= _count;
	array	= new BYTE[count];
	updated = false;
	hMem	= CreateDialogParam(hInstance, MAKEINTRESOURCE(IDD_MEMORY), hFrame, Proc, (LPARAM)this);
	ShowWindow(hMem, SW_SHOW);
	SendMessage(hMem, WM_USER, 0, 0);
	memList.push_back(this);
}
MEM::MEM()
{
	hMem	= CreateDialogParam(hInstance, MAKEINTRESOURCE(IDD_MEMORY), hFrame, Proc, (LPARAM)this);
	ShowWindow(hMem, SW_SHOW);
	SendMessage(hMem, WM_USER, 0, 0);
	memList.push_back(this);
}
MEM::~MEM()
{
	delete[] array;
	delete sc1;
	delete sc2;
}
#if 0
void DEBUG::pleaseFetch(MEMRxyz* md)
{
	dataTransfer.lock();
//	transfers.push_back(md);
	dataTransfer.unlock();
}
void DEBUG::pleaseStop(MEMRxyz* md)
{
	dataTransfer.lock();
//    transfers.erase(std::remove(transfers.begin(), transfers.end(), md), transfers.end());
	dataTransfer.unlock();
}
void DEBUG::pleasePoll(MEMRxyz *md) {}
void DEBUG::pleaseLock(){ dataTransfer.lock(); }
void DEBUG::pleaseUnlock(){ dataTransfer.unlock(); }
#endif

void MEM::SetScroll(HWND hWnd)
{
	SCROLLINFO si = { 0 };
	si.cbSize = sizeof(SCROLLINFO);
	si.fMask = SIF_POS;
	si.nPos = nScroll;
	si.nTrackPos = 0;
	SetScrollInfo(GetDlgItem(hWnd, IDC_MEMSCROLL), SB_CTL, &si, true);
	GetScrollInfo(GetDlgItem(hWnd, IDC_MEMSCROLL), SB_CTL, &si);
	nScroll = si.nPos;
	InvalidateRect(hWnd, nullptr, TRUE);
}

//================================================================================================
// Display memory data from the DEBUG thread
//================================================================================================

INT_PTR MEM::Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	char buffer[100];
	MEM* mem = reinterpret_cast<MEM*>(GetWindowLongPtr(hDlg, DWLP_USER));	// pointer to your data

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		mem = reinterpret_cast<MEM*>(lParam);
		SetWindowLongPtr(hDlg, DWLP_USER, (LONG_PTR)mem);
		DropLoad(hDlg, IDC_MEMORYADDR);
		DropLoad(hDlg, IDC_MEMORYCOUNT);
		SetTimer(hDlg, 0, 200, nullptr);
		mem->sc1 = new SUBCLASSWIN(GetDlgItem(hDlg, IDC_MEMORYADDR), hDlg, true);
		mem->sc2 = new SUBCLASSWIN(GetDlgItem(hDlg, IDC_MEMORYCOUNT), hDlg, true);
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:					// aka Refresh
redo:		GetDlgItemText(hDlg, IDC_MEMORYADDR, buffer, sizeof buffer);
			if(isalpha(buffer[0])){
				auto tp = process->FindDefinition(buffer);
				int file = get<0>(tp);
				if(file<0){
					MessageBox(hDlg, "NOT FOUND", "", MB_OK);
					return TRUE;
				}
				mem->address = get<2>(tp);
			}
			else{
				if(buffer[0]=='.')
					mem->address = strtol(buffer+1, nullptr, 10);
				else
					mem->address = strtol(buffer, nullptr, 16);
			}
			DropSave(IDC_MEMORYADDR, buffer);
			GetDlgItemText(hDlg, IDC_MEMORYCOUNT, buffer, sizeof buffer);
			if(buffer[0]=='.')
				mem->count = strtol(buffer+1, nullptr, 10);
			else
				mem->count = strtol(buffer, nullptr, 16);
			DropSave(IDC_MEMORYCOUNT, buffer);

			// refresh.....
			delete[] mem->array;
			mem->array = nullptr;
			if(mem->count)
				mem->array = new BYTE[mem->count];

			InvalidateRect(hDlg, nullptr, TRUE);
			return TRUE;

		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			debug->pleaseStop(mem);
			delete mem;
			return TRUE;
		}
		break;

	case WM_KEYDOWN:
		if(wParam==VK_RETURN)
			goto redo;
		return FALSE;

	case WM_TIMER:
		if(mem->updated){
			InvalidateRect(hDlg, nullptr, TRUE);
			mem->updated = false;
		}
		return TRUE;

	case WM_SIZE:
		{
			RECT rc;
			GetClientRect(hDlg, &rc);

			SCROLLINFO si = { sizeof SCROLLINFO, SIF_ALL };
			GetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si);
			// calculate screen lines
			mem->nLines = (rc.bottom-rc.top-67)/15;
			// how many 'off screen lines do we have?
			int nl = (mem->count+15)/16 - mem->nLines + 1;
			if(nl<0) nl=0;
			si.nMax = nl;					// set scroll range
//			si.nPos = si.nMax;				// scroll to the bottom
			SetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si, true);

			MoveWindow(GetDlgItem(hDlg, IDOK), rc.right-170, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDCANCEL), rc.right-85, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_LCNT), rc.right-103, rc.top+5, 30, 20, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMORYCOUNT), rc.right-68, rc.top+3, 60, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMSCROLL), rc.right-27, rc.top+31, 15, rc.bottom-rc.top-65, TRUE);
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
			rc.right -= 28;
			MoveToEx(hdc, rc.left, rc.top, nullptr);
			LineTo(hdc, rc.right, rc.top);
			LineTo(hdc, rc.right, rc.bottom);
			LineTo(hdc, rc.left, rc.bottom);
			LineTo(hdc, rc.left, rc.top);

			HRGN hrgn = CreateRectRgn(rc.left+2, rc.top+2, rc.right-2, rc.bottom-2);
			SelectClipRgn(hdc, hrgn);
			for(int row=0; row<mem->nLines+2; ++row){		// row is screen rows
				int r = row + mem->nScroll;					// r is file rows
				int y = rc.top + 5 + 15*row;
				if(y>rc.bottom) break;
				char temp[8];
				// draw the address
				if(r*16 < mem->count){
					MoveToEx(hdc, rc.left+280, y+7, nullptr);
					LineTo(hdc, rc.left+285, y+7);
					int p = mem->address>>14;
					sprintf_s(temp, sizeof temp, "%s%d ", p>=32?"ROM":"RAM", p%32);
					TextOut(hdc, rc.left+5, y, temp, 5);
					sprintf_s(temp, sizeof temp, "%04X", (mem->address + r*16)&0xffff);
					TextOut(hdc, rc.left+65, y, temp, 4);
				}
				for(int col=0; col<16; ++col){
					int index = r*16+col;
					if(index < mem->count){
						BYTE b = mem->array[index];
						// draw the hex bytes
						sprintf_s(temp, sizeof temp, "%02X", b);
						TextOut(hdc, rc.left+125+col*24, y, temp, 2);
						// draw the characters
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


	case WM_VSCROLL:
	{
		auto action = LOWORD(wParam);
		HWND hScroll = (HWND)lParam;
		switch(action){
		case SB_THUMBPOSITION:
		case SB_THUMBTRACK:
			mem->nScroll = HIWORD(wParam);
			break;
		case SB_LINEDOWN:
			mem->nScroll += 30;
			break;
		case SB_LINEUP:
			mem->nScroll -= 30;
			break;
		}
		SCROLLINFO si = { 0 };
		si.cbSize = sizeof(SCROLLINFO);
		si.fMask = SIF_POS;
		si.nPos = mem->nScroll;
		si.nTrackPos = 0;
		SetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si, true);
		GetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si);
		mem->nScroll = si.nPos;

		InvalidateRect(hDlg, nullptr, TRUE);
		return 0;
	}

	case WM_MOUSEWHEEL:
		int move; move = (short)HIWORD(wParam);
		if(move>0)
			--mem->nScroll;
		if(move<0)
			++mem->nScroll;
		mem->SetScroll(hDlg);
		return 0;

	}
	return FALSE;
}
