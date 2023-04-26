#pragma once

#include "resource.h"

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
	} r1;
private:
	HWND hRegs{};
	static void doReg(HWND hDlg, UINT id, const char* fmt, int value);
	static void doFlag(HWND hDlg, UINT id, bool v);
	static INT_PTR Proc(HWND hDlg, UINT wMessage, WPARAM wParam, LPARAM lParam);

	static int get3(BYTE* b){ return (b[2]<<16) | (b[1]<<8) | b[0]; }
	friend class DEBUG;
};

extern REGS* regs;
