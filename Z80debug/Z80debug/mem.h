#pragma once

#include "resource.h"
#include "process.h"
#include "debug.h"
#include "util.h"
#include "subclasswin.h"


class MEM {
public:
	MEM(DWORD address, int count);
	MEM();
	~MEM();

protected:
	DWORD address{};
	int   count{};
	BYTE  *array{};
	bool  updated{};

private:
	HWND hMem{};
	SUBCLASSWIN *sc1{}, *sc2{};
	int nScroll{}, nLines{};
	void SetScroll(HWND);
	static INT_PTR Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam);
	inline static std::vector<MEM*> memList;
	friend class DEBUG;
};
