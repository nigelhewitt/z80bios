#pragma once

#include "safequeue.h"
#include "resource.h"

class TRAFFIC;
extern TRAFFIC* traffic;

class TRAFFIC {
public:
	TRAFFIC(){}
	~TRAFFIC(){};
	static void ShowTraffic(HWND);
	static void putc(char c){ if(traffic) traffic->inbound.enqueue(c); }
	static void puts(const char* str){ while(*str) putc(*str++); }
private:
	HWND hTraffic{};
	static INT_PTR CALLBACK Proc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam);

	SafeQueue<char> inbound;
};
