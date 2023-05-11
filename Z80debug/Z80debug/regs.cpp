// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "regs.h"
#include "debug.h"
#include "util.h"
#include "Z80debug.h"

REGS* regs{};

// IMPORTANT: The IDC number are arranged in incrementing sets to make this subroutine friendly

static UINT restoreButtons[] = {
	IDC_RESTORE_A, IDC_RESTORE_AD, IDC_RESTORE_F, IDC_RESTORE_FD, IDC_RESTORE_BC, IDC_RESTORE_BCD,
	IDC_RESTORE_DE, IDC_RESTORE_DED, IDC_RESTORE_HL, IDC_RESTORE_HLD, IDC_RESTORE_IX, IDC_RESTORE_IY,
	IDC_RESTORE_PAGE0, IDC_RESTORE_PAGE1, IDC_RESTORE_PAGE2, IDC_RESTORE_PAGE3,
	IDC_RESTORE_PC, IDC_RESTORE_SP };

void REGS::doFlag(HWND hDlg, UINT id, BYTE v)
{
	CheckDlgButton(hDlg, id,   (v&0x80) ? BST_CHECKED : BST_UNCHECKED);
	CheckDlgButton(hDlg, id+1, (v&0x40) ? BST_CHECKED : BST_UNCHECKED);
	CheckDlgButton(hDlg, id+2, (v&0x10) ? BST_CHECKED : BST_UNCHECKED);
	CheckDlgButton(hDlg, id+3, (v&0x04) ? BST_CHECKED : BST_UNCHECKED);
	CheckDlgButton(hDlg, id+4, (v&0x02) ? BST_CHECKED : BST_UNCHECKED);
	CheckDlgButton(hDlg, id+5, (v&0x01) ? BST_CHECKED : BST_UNCHECKED);
}
void REGS::doReg8(HWND hDlg, UINT id, int value)
{
	char temp[10];
	sprintf_s(temp, sizeof temp, "%02XH", value);
	SetDlgItemText(hDlg, id, temp);
	sprintf_s(temp, sizeof temp, "%d", value);
	SetDlgItemText(hDlg, id+1, temp);
}
void REGS::doReg16(HWND hDlg, UINT id, int value)
{
	char temp[10];
	sprintf_s(temp, sizeof temp, "%04XH", value);
	SetDlgItemText(hDlg, id, temp);
	sprintf_s(temp, sizeof temp, "%d", value);
	SetDlgItemText(hDlg, id+1, temp);
}
void REGS::doReg20(HWND hDlg, UINT id, int value20, int value16)
{
	char temp[10];
	sprintf_s(temp, sizeof temp, "%06XH", value20);
	SetDlgItemText(hDlg, id, temp);
	sprintf_s(temp, sizeof temp, "%04XH", value16);
	SetDlgItemText(hDlg, id+1, temp);
}
void REGS::save(UINT id, UINT v)
{
	switch(id){
	case IDC_AH:
	case IDC_AD:
		r1.r2.A = v;
		break;
	case IDC_AHA:
	case IDC_ADA:
		r1.r2.AD = v;
		break;
	case IDC_BCH:
	case IDC_BCD:
	case IDC_RESTORE_BC:
		r1.r2.BC = v;
		break;
	case IDC_BCHA:
	case IDC_BCDA:
	case IDC_RESTORE_BCD:
		r1.r2.BCD = v;
		break;
	case IDC_DEH:
	case IDC_DED:
	case IDC_RESTORE_DE:
		r1.r2.DE = v;
		break;
	case IDC_DEHA:
	case IDC_DEDA:
	case IDC_RESTORE_DED:
		r1.r2.DED = v;
		break;
	case IDC_HLH:
	case IDC_HLD:
	case IDC_RESTORE_HL:
		r1.r2.HL = v;
		break;
	case IDC_HLHA:
	case IDC_HLDA:
	case IDC_RESTORE_HLD:
		r1.r2.DED = v;
		break;
	case IDC_IXH:
	case IDC_IXD:
	case IDC_RESTORE_IX:
		r1.r2.IX = v;
		break;
	case IDC_IYH:
	case IDC_IYD:
	case IDC_RESTORE_IY:
		r1.r2.IY = v;
		break;
	}
}

bool REGS::doEditMessage(HWND hDlg, WPARAM wParam, LPARAM lParam)
{
	char temp[20];
	if(HIWORD(wParam)!=EN_CHANGE) return false;
	int id = LOWORD(wParam);
	UINT v;
	static int only_me{};
	if(only_me && id!=only_me) return false;			// eat the message

	switch(id){
	case IDC_AH:
	case IDC_AHA:
		GetDlgItemText(hDlg, id, temp, sizeof temp);
		v = strtol(temp, nullptr, 16) & 0xff;
		sprintf_s(temp, sizeof temp, "%d", v);
		only_me = id;
		SetDlgItemText(hDlg, id+1, temp);
		save(id, v);
		only_me = 0;
		ShowWindow(GetDlgItem(hDlg, id+2), SW_SHOW);
		return true;
	case IDC_AD:
	case IDC_ADA:
		GetDlgItemText(hDlg, id, temp, sizeof temp);
		v = strtol(temp, nullptr, 10) & 0xff;
		sprintf_s(temp, sizeof temp, "%02XH", v);
		only_me = id;
		SetDlgItemText(hDlg, id-1, temp);
		save(id, v);
		only_me = 0;
		ShowWindow(GetDlgItem(hDlg, id+1), SW_SHOW);
		return false;
	case IDC_BCH:
	case IDC_BCHA:
	case IDC_DEH:
	case IDC_DEHA:
	case IDC_HLH:
	case IDC_HLHA:
	case IDC_IXH:
	case IDC_IYH:
		GetDlgItemText(hDlg, id, temp, sizeof temp);
		v = strtol(temp, nullptr, 16) & 0xffff;
		sprintf_s(temp, sizeof temp, "%d", v);
		only_me = id;
		SetDlgItemText(hDlg, id+1, temp);
		save(id, v);
		only_me = 0;
		ShowWindow(GetDlgItem(hDlg, id+2), SW_SHOW);
		return true;
	case IDC_BCD:
	case IDC_BCDA:
	case IDC_DED:
	case IDC_DEDA:
	case IDC_HLD:
	case IDC_HLDA:
	case IDC_IXD:
	case IDC_IYD:
		GetDlgItemText(hDlg, id, temp, sizeof temp);
		v = strtol(temp, nullptr, 10) & 0xffff;
		sprintf_s(temp, sizeof temp, "%04XH", v);
		only_me = id;
		SetDlgItemText(hDlg, id-1, temp);
		save(id, v);
		only_me = 0;
		ShowWindow(GetDlgItem(hDlg, id+1), SW_SHOW);
		return false;
	}
	return false;
}
bool REGS::doRestoreMessage(HWND hDlg, WPARAM wParam, LPARAM lParam)
{
	int id = LOWORD(wParam);
	switch(id){
	case IDC_RESTORE_A:
		r1.r2.A = rbak.r2.A;
		doReg8(hDlg, IDC_AH, r1.r2.A);
dw:		ShowWindow(GetDlgItem(hDlg, id), SW_HIDE);
		break;
	case IDC_RESTORE_AD:
		r1.r2.AD = rbak.r2.AD;
		doReg8(hDlg, IDC_AHA, r1.r2.AD);
		goto dw;
	case IDC_RESTORE_F:
		r1.r2.F = rbak.r2.F;
		doFlag(hDlg,  IDC_FLAG_S,	r1.r2.F);
		goto dw;
	case IDC_RESTORE_FD:
		r1.r2.FD = rbak.r2.FD;
		doFlag(hDlg,  IDC_FLAG_SA,	r1.r2.FD);
		goto dw;
	case IDC_RESTORE_BC:
		r1.r2.BC = rbak.r2.BC;
		doReg16(hDlg, IDC_BCH, r1.r2.BC);
		goto dw;
	case IDC_RESTORE_BCD:
		r1.r2.BCD = rbak.r2.BCD;
		doReg16(hDlg, IDC_BCH, r1.r2.BCD);
		goto dw;
	case IDC_RESTORE_DE:
		r1.r2.DE = rbak.r2.DE;
		doReg16(hDlg, IDC_DEH, r1.r2.DE);
		goto dw;
	case IDC_RESTORE_DED:
		r1.r2.DED = rbak.r2.DED;
		doReg16(hDlg, IDC_BCH, r1.r2.DED);
		goto dw;
	case IDC_RESTORE_HL:
		r1.r2.HL = rbak.r2.HL;
		doReg16(hDlg, IDC_HLH, r1.r2.HL);
		goto dw;
	case IDC_RESTORE_HLD:
		r1.r2.HLD = rbak.r2.HLD;
		doReg16(hDlg, IDC_HLH, r1.r2.HLD);
		goto dw;
	case IDC_RESTORE_IX:
		r1.r2.IX = rbak.r2.IX;
		doReg16(hDlg, IDC_IXH, r1.r2.IX);
		goto dw;
	case IDC_RESTORE_IY:
		r1.r2.IY = rbak.r2.IY;
		doReg16(hDlg, IDC_IYH, r1.r2.IY);
		goto dw;
	case IDC_RESTORE_PAGE0:
	case IDC_RESTORE_PAGE1:
	case IDC_RESTORE_PAGE2:
	case IDC_RESTORE_PAGE3:
	case IDC_RESTORE_PC:
	case IDC_RESTORE_SP:
		return false;
	}
	return false;
}

INT_PTR REGS::Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam)
{
	char temp[10];

	switch(LOWORD(wMessage)){
	case WM_INITDIALOG:
		for(int i=0; i<32; ++i){
			char temp[10];
			sprintf_s(temp, sizeof temp, "ROM%d", i);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE0), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE1), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE2), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE3), CB_ADDSTRING, 0, (LPARAM)temp);
		}
		for(int i=0; i<32; ++i){
			sprintf_s(temp, sizeof temp, "RAM%d", i);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE0), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE1), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE2), CB_ADDSTRING, 0, (LPARAM)temp);
			SendMessage(GetDlgItem(hDlg, IDC_PAGE3), CB_ADDSTRING, 0, (LPARAM)temp);
		}
		return TRUE;

	case WM_UPDATE_REGS:
		doFlag(hDlg,  IDC_FLAG_S,	regs->r1.r2.F);
		doFlag(hDlg,  IDC_FLAG_SA,	regs->r1.r2.FD);
		doReg8(hDlg,  IDC_AH,		regs->r1.r2.A);
		doReg8(hDlg,  IDC_AHA,		regs->r1.r2.AD);
		doReg16(hDlg, IDC_BCH,		regs->r1.r2.BC);
		doReg16(hDlg, IDC_BCHA,		regs->r1.r2.BCD);
		doReg16(hDlg, IDC_DEH,		regs->r1.r2.DE);
		doReg16(hDlg, IDC_DEHA,		regs->r1.r2.DED);
		doReg16(hDlg, IDC_HLH,		regs->r1.r2.HL);
		doReg16(hDlg, IDC_HLHA,		regs->r1.r2.HLD);
		doReg16(hDlg, IDC_IXH,		regs->r1.r2.IX);
		doReg16(hDlg, IDC_IYH,		regs->r1.r2.IY);
		doReg20(hDlg, IDC_PC20,		get3(regs->r1.r2.PC20), regs->r1.r2.PC16);
		doReg20(hDlg, IDC_SP20,		get3(regs->r1.r2.SP20), regs->r1.r2.SP16);

		for(int i=0; i<4; ++i)
			SendDlgItemMessage(hDlg, IDC_PAGE0+i*2, CB_SETCURSEL, regs->r1.r2.PAGE[i], 0);

		// hide all 'Restore' buttons
		for(UINT id : restoreButtons)
			ShowWindow(GetDlgItem(hDlg, id), SW_HIDE);

		sprintf_s(temp, sizeof temp, "%0XH", regs->r1.r2.RET);
		SetDlgItemText(hDlg, IDC_RET, temp);
		SetDlgItemInt(hDlg, IDC_MODE, regs->r1.r2.MODE, FALSE);

		return TRUE;

	case WM_COMMAND:
		if(regs->doEditMessage(hDlg, wParam, lParam))
			return TRUE;
		if(regs->doRestoreMessage(hDlg, wParam, lParam))
			return TRUE;
		switch(LOWORD(wParam)){
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
	for(int i=0; i<18; ++i)
		r1.W[i] = unpackWORD(text, index);
	rbak = r1;			// copy for the 'restore' buttons
	modified = false;
	SendMessage(hRegs, WM_UPDATE_REGS, 0, 0);	// update
}
void REGS::ShowRegs()
{
	if(regs==nullptr)
		regs = new REGS;
	if(regs->hRegs==nullptr)
		regs->hRegs = CreateDialog(hInstance, MAKEINTRESOURCE(IDD_REGS), hFrame, REGS::Proc);
	ShowWindow(regs->hRegs, SW_SHOW);
	SendMessage(regs->hRegs, WM_UPDATE_REGS, 0, 0);	// update
	UpdateWindow(regs->hRegs);					// wait for the dust to settle
}
