// traffic.cpp
//

#include "framework.h"
#include "traffic.h"
#include "util.h"
#include "Z80debug.h"

TRAFFIC* traffic{};

void TRAFFIC::ShowTraffic(HWND hParent)
{
	if(traffic==nullptr)
		traffic = new TRAFFIC;
	if(traffic->hTraffic==nullptr)
		traffic->hTraffic = CreateDialog(hInstance, MAKEINTRESOURCE(IDD_TRAFFIC), hParent, Proc);
	ShowWindow(traffic->hTraffic, SW_SHOW);
}
//=================================================================================================
// Traffic dialog box
//=================================================================================================
INT_PTR TRAFFIC::Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	bool always;

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		SetTimer(hDlg, 0, 200, nullptr);
		always = GetProfile("setup", "show-traffic", false);
		SendDlgItemMessage(hDlg, IDC_ALWAYS, BM_SETCHECK, always ? BST_CHECKED : BST_UNCHECKED, 0);
		return TRUE;

	case WM_TIMER:
		if(traffic && traffic->inbound.count()){
			char temp[200];
			int i=0;
			while(i<(int)sizeof temp-1 && traffic->inbound.count())
				temp[i++] = traffic->inbound.dequeue();
			temp[i] = 0;

			int n = GetWindowTextLength(GetDlgItem(hDlg, IDC_DEBUGTERM));
			n += i + 10;
			char *buffer = new char[n];
			GetDlgItemText(hDlg, IDC_DEBUGTERM, buffer, n);
			strcat_s(buffer, n, temp);
			SetDlgItemText(hDlg, IDC_DEBUGTERM, buffer);
			delete[] buffer;
		}
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDC_ALWAYS:
			always = SendDlgItemMessage(hDlg, IDC_ALWAYS, BM_GETCHECK, 0, 0)!=0;
			PutProfile("setup", "show-traffic", always ? "true" : "false");
			return TRUE;

		case IDOK:
			SetDlgItemText(hDlg, IDC_DEBUGTERM, "");
			return TRUE;

		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			traffic->hTraffic = nullptr;
			return TRUE;
		}
		break;

	case WM_SIZE:
		{
			RECT rc;
			GetClientRect(hDlg, &rc);
			MoveWindow(GetDlgItem(hDlg, IDC_DEBUGTERM), rc.left+11, rc.top+5, rc.right-rc.left-15, rc.bottom-rc.top-41, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDC_ALWAYS), rc.left+11, rc.bottom-31, 120, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDOK), rc.right-170, rc.bottom-30, 76, 23, TRUE);
			MoveWindow(GetDlgItem(hDlg, IDCANCEL), rc.right-85, rc.bottom-30, 76, 23, TRUE);
			InvalidateRect(hDlg, nullptr, TRUE);
			break;
		}

	}
	return FALSE;
}
