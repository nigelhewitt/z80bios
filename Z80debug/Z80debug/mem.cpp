// traffic.cpp
//

#include "framework.h"
#include "mem.h"
#include "Z80debug.h"


//=================================================================================================
// Memory display
//=================================================================================================

MEM::MEM(DWORD address16, int _count)
{
	const std::lock_guard<std::mutex> lock(memListMutex);
	address = address16;
	count	= _count;
	array	= new BYTE[count];
	hMem	= CreateDialogParam(hInstance, MAKEINTRESOURCE(IDD_MEMORY), hFrame, Proc, (LPARAM)this);
	ShowWindow(hMem, SW_SHOW);
	memList.push_back(this);
}
MEM::MEM()
{
	const std::lock_guard<std::mutex> lock(memListMutex);
	hMem	= CreateDialogParam(hInstance, MAKEINTRESOURCE(IDD_MEMORY), hFrame, Proc, (LPARAM)this);
	ShowWindow(hMem, SW_SHOW);
	memList.push_back(this);
}
MEM::~MEM()
{
	const std::lock_guard<std::mutex> lock(memListMutex);
	delete[] array;
	array = nullptr;
	delete sc1;
	delete sc2;
	remove_by_value<MEM*>(&memList, this);
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
void MEM::doScroll(HWND hDlg)
{
	RECT rc;
	GetClientRect(hDlg, &rc);

	SCROLLINFO si = { sizeof SCROLLINFO, SIF_ALL };
	GetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si);
	// calculate screen lines
	nLines = (rc.bottom-rc.top-72)/15;		// 72=top margin + bottom margin + x start
	// how many 'off screen lines do we have?
	int nl = (count+15)/16 - nLines - 1;
	if(hexAlign && (address & 0xf)!=0) ++nl;
	if(nl<0) nl=0;
	si.nMax  = nl + nLines;					// set scroll range
	si.nPage = nLines;
	SetScrollInfo(GetDlgItem(hDlg, IDC_MEMSCROLL), SB_CTL, &si, true);
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
		mem->doScroll(hDlg);
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:					// aka Refresh
redo:		{
				DWORD addr  = mem->address;
				int	  count = mem->count;
				GetDlgItemText(hDlg, IDC_MEMORYADDR, buffer, sizeof buffer);
				if(isalpha(buffer[0]) || buffer[0]=='_'){
					auto tp = process->FindDefinition(buffer);
					int file = get<0>(tp);
					if(file<0)
						goto tryNumber;					// No found try hex eg E400
					addr = get<3>(tp);
					int page = get<1>(tp);
					addr = (page<<14) | (addr & 0x3fff);	// c24to20
				}
				else{
tryNumber:			if(buffer[0]=='.')
						addr = strtol(buffer+1, nullptr, 10);
					else
						addr = strtol(buffer, nullptr, 16);
				}
				DropSave(IDC_MEMORYADDR, buffer);
				GetDlgItemText(hDlg, IDC_MEMORYCOUNT, buffer, sizeof buffer);
				if(buffer[0]=='.')
					count = strtol(buffer+1, nullptr, 10);
				else
					count = strtol(buffer, nullptr, 16);
				DropSave(IDC_MEMORYCOUNT, buffer);

				// refresh.....
				{
					const std::lock_guard<std::mutex> lock(mem->transfer);
					delete[] mem->array;
					mem->array	 = nullptr;
					mem->address = addr;
					mem->count	 = count;
					if(mem->count)
						mem->array = new BYTE[mem->count];
					mem->updated = false;
				}
			}
			InvalidateRect(hDlg, nullptr, TRUE);
			return TRUE;

		case IDC_HEXALIGN:
			mem->hexAlign = IsDlgButtonChecked(hDlg, IDC_HEXALIGN)==BST_CHECKED;
			mem->SetScroll(hDlg);
			InvalidateRect(hDlg, nullptr, TRUE);
			return TRUE;

		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			delete mem;
			return TRUE;
		}
		break;

	case WM_KEYDOWN:
		if(wParam==VK_RETURN)
			goto redo;
		return FALSE;

	case WM_TIMER:
		if(mem->updated && !mem->painted){
			mem->doScroll(hDlg);
			InvalidateRect(hDlg, nullptr, TRUE);
		}
		mem->painted = mem->updated;
		return TRUE;

	case WM_SIZE:
		{
			RECT rc;
			GetClientRect(hDlg, &rc);
//			const std::lock_guard<std::mutex> lock(mem->transfer);

			mem->doScroll(hDlg);
			MoveWindow(GetDlgItem(hDlg, IDOK), rc.right-170, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDCANCEL), rc.right-85, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_LCNT), rc.right-103, rc.top+5, 30, 20, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMORYCOUNT), rc.right-68, rc.top+3, 60, 200, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMSCROLL), rc.right-27, rc.top+31, 15, rc.bottom-rc.top-65, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_MEMORYADDR), rc.left+80, rc.top+3, rc.right-rc.left-196, 200, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_HEXALIGN), rc.left+10, rc.bottom-30, 76, 23, TRUE);
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
			mem->nLines = (rc.bottom-rc.top)/15;

			HRGN hrgn = CreateRectRgn(rc.left+2, rc.top+2, rc.right-2, rc.bottom-2);
			SelectClipRgn(hdc, hrgn);
			if(mem->updated){
				int iCol = mem->hexAlign ? (mem->address & 0xf) : 0;
				for(int row=0; row<mem->nLines+2; ++row){		// row is screen rows
					int r = row + mem->nScroll;					// r is file rows
					int y = rc.top + 5 + 15*row;
					if(y>rc.bottom) break;
					char temp[8];
					// draw the address
					if(r*16-iCol < mem->count){
						MoveToEx(hdc, rc.left+302, y+7, nullptr);
						LineTo(hdc, rc.left+306, y+7);
						int p = mem->address>>14;
						sprintf_s(temp, sizeof temp, "%s%d ", p>=32?"ROM":"RAM", p%32);
						TextOut(hdc, rc.left+5, y, temp, 5);
						sprintf_s(temp, sizeof temp, "%04X", (mem->address-iCol + r*16)&0xffff);
						TextOut(hdc, rc.left+65, y, temp, 4);
					}
					SetTextAlign(hdc, TA_CENTER | TA_TOP | TA_NOUPDATECP); // centre
					int start = mem->hexAlign && row==0 && mem->nScroll==0 ? iCol : 0;
					for(int col=start; col<16; ++col){
						int index = r*16+col-iCol;
						if(index < mem->count ){
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
					SetTextAlign(hdc, TA_LEFT | TA_TOP | TA_NOUPDATECP); // restore normality
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
			++mem->nScroll;
			break;
		case SB_LINEUP:
			--mem->nScroll;
			break;
		case SB_PAGEDOWN:
			++mem->nScroll += mem->nLines;
			break;
		case SB_PAGEUP:
			--mem->nScroll -= mem->nLines;
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
