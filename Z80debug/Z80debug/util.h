#pragma once

#include "framework.h"
#include "resource.h"

void error(DWORD err=0);
const char* getIniFile();
char* GetProfile(const char* section, const char* key, const char* def);
void PutProfile(const char* section, const char* key, const char* value);
void DropSave(UINT id, const char* text);
void DropLoad(HWND hDlg, UINT id);
bool GetFolder(HWND hWnd, char *buffer, int cb, const char* title);
void Configure(HWND hWnd);

//-------------------------------------------------------------------------------------------------
// unpack utilities
//-------------------------------------------------------------------------------------------------
void skip(const char* text, int& index);
int tohex(char c);
BYTE unpackBYTE(const char* text, int &index);
WORD unpackWORD(const char* text, int& index);
char tohexC(WORD b);
