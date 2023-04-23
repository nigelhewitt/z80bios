// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "regs.h"
#include "debug.h"
#include "util.h"
#include "Z80debug.h"

REGS* regs{};

void REGS::doReg(HWND hDlg, UINT id, const char* fmt, int value)
{
	char temp[10];
	sprintf_s(temp, sizeof temp, fmt, value);
	SetDlgItemText(hDlg, id, temp);
}
void REGS::doFlag(HWND hDlg, UINT id, bool v)
{
	CheckDlgButton(hDlg, id, v ? BST_CHECKED : BST_UNCHECKED);
}
INT_PTR REGS::Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	char temp[10];

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		for(int i=0; i<32; ++i){
			char temp[10];
			sprintf_s(temp, sizeof temp, "ROM%d", i);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE1), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE2), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE3), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE4), CB_ADDSTRING, 0, (LPARAM)temp);
		}
		for(int i=0; i<32; ++i){
			sprintf_s(temp, sizeof temp, "RAM%d", i);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE1), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE2), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE3), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE4), CB_ADDSTRING, 0, (LPARAM)temp);
		}
		return TRUE;

	case WM_USER:
		doReg(hDlg, IDC_AH,   "x%02X", regs->A);
		doReg(hDlg, IDC_AD,   "%d",    regs->A);
		doReg(hDlg, IDC_BCH,  "x%04X", regs->BC);
		doReg(hDlg, IDC_BCD,  "%d",	   regs->BC);
		doReg(hDlg, IDC_DEH,  "x%04X", regs->DE);
		doReg(hDlg, IDC_DED,  "%d",    regs->DE);
		doReg(hDlg, IDC_HLH,  "x%04X", regs->HL);
		doReg(hDlg, IDC_HLD,  "%d",    regs->HL);
		doReg(hDlg, IDC_AHA,  "x%02X", regs->AA);
		doReg(hDlg, IDC_ADA,  "%d",    regs->AA);
		doReg(hDlg, IDC_BCHA, "x%04X", regs->BCA);
		doReg(hDlg, IDC_BCDA, "%d",    regs->BCA);
		doReg(hDlg, IDC_DEHA, "x%04X", regs->DEA);
		doReg(hDlg, IDC_DEDA, "%d",    regs->DEA);
		doReg(hDlg, IDC_HLHA, "x%04X", regs->HLA);
		doReg(hDlg, IDC_HLDA, "%d",    regs->HLA);
		doReg(hDlg, IDC_IXH,  "x%04X", regs->IX);
		doReg(hDlg, IDC_IXD,  "%d",    regs->IX);
		doReg(hDlg, IDC_IYH,  "x%04X", regs->IY);
		doReg(hDlg, IDC_IYD,  "%d",    regs->IY);
		doReg(hDlg, IDC_PC,   "x%04X", regs->PC);
		doReg(hDlg, IDC_SP,   "x%04X", regs->SP);

		doFlag(hDlg, IDC_FLAG_S,  regs->F  & 0x80);
		doFlag(hDlg, IDC_FLAG_Z,  regs->F  & 0x40);
		doFlag(hDlg, IDC_FLAG_H,  regs->F  & 0x10);
		doFlag(hDlg, IDC_FLAG_P,  regs->F  & 0x04);
		doFlag(hDlg, IDC_FLAG_N,  regs->F  & 0x02);
		doFlag(hDlg, IDC_FLAG_C,  regs->F  & 0x01);
		doFlag(hDlg, IDC_FLAG_SA, regs->FA & 0x80);
		doFlag(hDlg, IDC_FLAG_ZA, regs->FA & 0x40);
		doFlag(hDlg, IDC_FLAG_HA, regs->FA & 0x10);
		doFlag(hDlg, IDC_FLAG_PA, regs->FA & 0x04);
		doFlag(hDlg, IDC_FLAG_NA, regs->FA & 0x02);
		doFlag(hDlg, IDC_FLAG_CA, regs->FA & 0x01);

		for(int i=0; i<4; ++i)
			SendDlgItemMessage(hDlg, IDC_PAGE1+i, CB_SETCURSEL, regs->PAGE[i], 0);
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDOK:
			return TRUE;
		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			regs->hRegs = nullptr;
			return TRUE;
		}
		break;
	}
	return FALSE;
}

void REGS::unpackRegs(const char* text)
{
	// sp af bc de hl ix iy pc af' bc' de' hl'
	int index = 0;
	SP  = unpackWORD(text, index);
	IY  = unpackWORD(text, index);
	IX  = unpackWORD(text, index);
	HL  = unpackWORD(text, index);
	DE  = unpackWORD(text, index);
	BC  = unpackWORD(text, index);
	A   = unpackBYTE(text, index);
	F   = unpackBYTE(text, index);
	PC  = unpackWORD(text, index);
	AA  = unpackBYTE(text, index);
	FA  = unpackBYTE(text, index);
	BCA = unpackWORD(text, index);
	DEA = unpackWORD(text, index);
	HLA = unpackWORD(text, index);
	SendMessage(hRegs, WM_USER, 0, 0);	// update
}
void REGS::unpackMAP(const char* text)
{
	// page0 page1 page2 page3
	int index = 0;
	for(int i=0; i<4; PAGE[i++]  = unpackBYTE(text, index));
	SendMessage(hRegs, WM_USER, 0, 0);	// update
}
void REGS::ShowRegs()
{
	if(regs==nullptr)
		regs = new REGS;
	if(regs->hRegs==nullptr)
		regs->hRegs = CreateDialog(hInstance, MAKEINTRESOURCE(IDD_REGS), hFrame, REGS::Proc);
	ShowWindow(regs->hRegs, SW_SHOW);
	SendMessage(regs->hRegs, WM_USER, 0, 0);	// update
	UpdateWindow(regs->hRegs);					// wait for the dust to settle
}
