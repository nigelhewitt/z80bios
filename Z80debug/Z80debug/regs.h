#pragma once

#include "resource.h"

class REGS {
public:
	REGS(){}
	~REGS(){}
	static void ShowRegs();
	void unpackRegs(const char* text);
	void unpackMAP(const char* text);
	HWND hwnd(){ return hRegs; }
protected:
	BYTE A{}, F{};
	BYTE AA{}, FA{};
	WORD BC{}, DE{}, HL{};
	WORD BCA{}, DEA{}, HLA{};
	WORD IX{}, IY{}, SP{}, PC{};
	WORD PAGE[4]{};

private:
	HWND hRegs{};
	static void doReg(HWND hDlg, UINT id, const char* fmt, int value);
	static void doFlag(HWND hDlg, UINT id, bool v);
	static INT_PTR Proc(HWND hDlg, UINT wMessage, WPARAM wParam, LPARAM lParam);

	friend class DEBUG;
};

extern REGS* regs;
