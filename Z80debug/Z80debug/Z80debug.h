#pragma once

#include "resource.h"

extern HINSTANCE hInstance;
extern HWND hFrame, hClient;

void SetStatus(const char* text);	// set status text
extern bool bRegsPlease;