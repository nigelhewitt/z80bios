#pragma once

#include "safequeue.h"
#include "resource.h"

class TRAFFIC;
extern TRAFFIC* traffic;

class TRAFFIC {
public:
	TRAFFIC(){}
	~TRAFFIC(){};
	static void ShowTraffic();
	static void putc(char c){ if(traffic) traffic->inbound.enqueue(c); }

private:
	HWND hTraffic{};
	static INT_PTR CALLBACK Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam);

	SafeQueue<char> inbound;
};
