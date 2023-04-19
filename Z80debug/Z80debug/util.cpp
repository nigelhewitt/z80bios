// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

//=================================================================================================
// ini file handlers
//=================================================================================================

char IniFileName[MAX_PATH]{};

void getIniFile()
{
	if(*IniFileName) return;
	GetModuleFileName(hInstance, IniFileName, sizeof IniFileName);
	char *p = strrchr(IniFileName, '.');
	strcpy(p, ".ini");
}
char* GetProfile(const char* section, const char* key, const char* def)
{
	static char temp[100];
	GetPrivateProfileString(section, key, def, temp, sizeof temp, IniFileName);
	return temp;
}
void PutProfile(const char* section, const char* key, const char* value)
{
	WritePrivateProfileString(section, key, value, IniFileName);
}
//=================================================================================================
// ComboBox drop down list save and restore
//=================================================================================================
void DropSave(UINT id, const char* text){}
void DropLoad(HWND hDlg, UINT id){}
