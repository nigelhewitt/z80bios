#pragma once

#include "resource.h"

// shut up about the align not effecting WORDS. I know
#pragma warning( push )
#pragma warning( disable : 4359 )

class REGS {
public:
	REGS(){}
	~REGS(){}
	static void ShowRegs();
	void unpackRegs(const char* text);
	HWND hwnd(){ return hRegs; }
protected:
	union R1{
		__declspec(align(1)) struct R2 {
			R2(){};
			WORD BC{};
			BYTE F{},A{};
			WORD HL{}, PC16{}, SP16{}, DE{};
			BYTE FD{}, AD{};
			WORD BCD{}, DED{}, HLD{}, IX{}, IY{};
			BYTE PAGE[4]{};
			BYTE RET{};
			BYTE MODE{};
			BYTE PC20[3]{}, SP20[3]{};
		} r2;
		WORD W[18]{};
		R1(){};
	} r1, rbak;
#pragma warning( pop )

private:
	HWND hRegs{};
	bool modified{};

	static void doFlag(HWND hDlg, UINT id, BYTE v);
	static void doReg8(HWND hDlg, UINT id, int value);
	static void doReg16(HWND hDlg, UINT id, int value);
	static void doReg20(HWND hDlg, UINT id, int value20, int value16);
	bool doEditMessage(HWND hDlg, WPARAM wParam, LPARAM lParam);
	bool doRestoreMessage(HWND hDlg, WPARAM wParam, LPARAM lParam);
	void save(UINT id, UINT v);
	static INT_PTR Proc(HWND hDlg, UINT wMessage, WPARAM wParam, LPARAM lParam);

	static int get3(BYTE* b){ return (b[2]<<16) | (b[1]<<8) | b[0]; }
	friend class DEBUG;
};

extern REGS* regs;
#define	WM_UPDATE_REGS WM_APP+10
