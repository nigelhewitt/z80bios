// util.cpp
//

#include "framework.h"
#include "util.h"
#include "Z80debug.h"

//=====================================================================================================
// handler to unpack Windows error codes into text
//=====================================================================================================

void error(DWORD err)
{
	char temp[200];
	int cb = sizeof temp;
	if(err == 0)
		err = GetLastError();
	wsprintf(temp, "%X ", err);
	DWORD i = (DWORD)strlen(temp);
	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, nullptr, err, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), &temp[i], cb-i, nullptr);
	// now remove the \r\n we get on the end
	for(auto n = strnlen_s(temp, cb); n>3 && (temp[n-1] == '\r' || temp[n-1] == '\n'); temp[n-- - 1] = 0);		// yes it does compile
	MessageBox(nullptr, temp, "Error", MB_OK);
}
//=================================================================================================
// ini file handlers
//=================================================================================================

static const char* getIniFile()
{
	static char IniFileName[MAX_PATH]{};

	if(*IniFileName==0){
		GetModuleFileName(hInstance, IniFileName, sizeof IniFileName);
		char *p = strrchr(IniFileName, '.');
		strcpy(p, ".ini");
	}
	return IniFileName;
}
char* GetProfile(const char* section, const char* key, const char* def)
{
	static char temp[500];
	GetPrivateProfileString(section, key, def, temp, sizeof temp, getIniFile());
	return temp;
}
void PutProfile(const char* section, const char* key, const char* value)
{
	WritePrivateProfileString(section, key, value, getIniFile());
}
//=================================================================================================
// ComboBox drop down list save and restore
//=================================================================================================

//inline LRESULT PostDlgItemMessage(HWND hDlg, UINT id, UINT msg, WPARAM wParam, LPARAM lParam)
//{
//	return PostMessage(GetDlgItem(hDlg, id), msg, wParam, lParam);
//}
#define MAX_DROPS	10

// load a dialog box from the Profile
void DropLoad(HWND hDlg, UINT id)
{
	SendDlgItemMessage(hDlg, id, CB_RESETCONTENT, 0, 0);
	char section[20];
	sprintf_s(section, sizeof section, "DropBox-%d", id);

	for(int i=0; i<MAX_DROPS; ++i){
		char item[10];
		sprintf_s(item, sizeof item, "T%d", i+1);
		char* text = GetProfile(section, item, "");
		if(*text)
			SendDlgItemMessage(hDlg, id, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text));
	}
}
// add a new item to the profile
void DropSave(UINT id, const char* text)
{
	char section[20];
	sprintf_s(section, sizeof section, "DropBox-%d", id);

	// read in the current list
	char* items[MAX_DROPS]{};
	int nItems=0, nFound=-1;

	for(int i=0; i<MAX_DROPS; ++i){
		char item[10];
		sprintf_s(item, sizeof item, "T%d", i+1);
		char *p = GetProfile(section, item, "");
		items[i] = *p ? _strdup(p) : nullptr;
		if(items[i]){
			++nItems;
			if(strcmp(items[i], text)==0)
				nFound = i;
		}
	}

	if(nFound==0) return;					// already saved and is at the top, job finished

	// Now move the old ones down to make room for the new one at the top.
	// If it was found move the ones above it down so it moves to the top
	int bottom = nFound==-1 ? MAX_DROPS-1: nFound;

	for(int i=bottom; i>0; --i)				// move everybody down
		items[i] = items[i-1];
	items[0] = _strdup(text);				// insert new item at the top

	for(int i=0; i<MAX_DROPS; ++i){
		char item[10];
		sprintf_s(item, sizeof item, "T%d", i+1);
		if(items[i])
			PutProfile(section, item, items[i]);
		else
			PutProfile(section, item, nullptr);
		delete items[i];
	}
}

//=================================================================================================
// Browse for a folder
//=================================================================================================
static int CALLBACK BrowseForFolderCallback(HWND hwnd,UINT uMsg,LPARAM lp, LPARAM pData)
{
	char szPath[MAX_PATH];

	switch(uMsg){
	case BFFM_INITIALIZED:
		SendMessage(hwnd, BFFM_SETSELECTION, TRUE, pData);
		break;

	case BFFM_SELCHANGED:
		if (SHGetPathFromIDList((LPITEMIDLIST) lp ,szPath))
				SendMessage(hwnd, BFFM_SETSTATUSTEXT,0,(LPARAM)szPath);
		break;
	}
	return 0;
}
bool GetFolder(HWND hWnd, char *buffer, int cb, const char* title)
{
	BROWSEINFO bi;
	char szPath[MAX_PATH + 1];
	LPITEMIDLIST pidl;
	bool bResult = false;
	LPMALLOC pMalloc;

	if(SUCCEEDED(SHGetMalloc(&pMalloc))){
		bi.hwndOwner		= hWnd;
		bi.pidlRoot			= nullptr;
		bi.pszDisplayName	= nullptr;
		bi.lpszTitle		= title;
		bi.ulFlags			= BIF_STATUSTEXT; //BIF_EDITBOX
		bi.lpfn				= BrowseForFolderCallback;
		bi.lParam			= (LPARAM)buffer;

		pidl = SHBrowseForFolder(&bi);
		if(pidl){
			if(SHGetPathFromIDList(pidl, szPath)){
				bResult = true;
				strcpy(buffer, szPath);
			}
			pMalloc->Free(pidl);
			pMalloc->Release();
		}
	}
	return bResult;
}
//=================================================================================================
// Configuration dialog
//=================================================================================================

static INT_PTR CALLBACK Config(HWND hDlg, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	static int tBaud[] = { 1200, 2400, 4800, 9600, 14400, 19200, 28800, 38400, 57600, 115200 };
	char temp[100], *t;
	int i, j, index;

	switch(uMessage){
	case WM_INITDIALOG:
		SendDlgItemMessage(hDlg, IDC_PORT, CB_RESETCONTENT, 0, 0L);
		t = GetProfile("setup", "port", "");
		for(i=0, j=0; i<20; ++i){							// 20 is just arbitrary 'big'
			wsprintf(temp, "COM%d", i+1);
			COMMCONFIG cc;										// filter out ports that don't exist at the moment
			DWORD nn = sizeof(cc);
			if(GetDefaultCommConfig(temp, &cc, &nn)){
				SendDlgItemMessage(hDlg, IDC_PORT, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(temp));
				if(lstrcmp(temp, t)==0) index = j;		// save the index of our previous port
				++j;
			}
		}
		SendDlgItemMessage(hDlg, IDC_PORT, CB_SETCURSEL, index, 0);

		SendDlgItemMessage(hDlg, IDC_BAUD, CB_RESETCONTENT, 0, 0L);
		index = i= 0;
		t = GetProfile("setup", "baud", "");
		for(auto b : tBaud){
			wsprintf(temp, "%d", b);
			SendDlgItemMessage(hDlg, IDC_BAUD, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(temp));
			if(strcmp(temp, t)==0) index = i;
			++i;
		}
		SendDlgItemMessage(hDlg, IDC_BAUD, CB_SETCURSEL, index, 0);
		SetDlgItemText(hDlg, IDC_FOLDER, GetProfile("setup", "folder", ""));
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDC_FOLDERBROWSE:
			char fn[MAX_PATH];
			GetDlgItemText(hDlg, IDC_FOLDER, fn, sizeof fn);
			if(GetFolder(hDlg, fn, sizeof fn, "Select working folder"))
				SetDlgItemText(hDlg, IDC_FOLDER, fn);
			return TRUE;

		case IDOK:
			GetDlgItemText(hDlg, IDC_PORT, temp, sizeof temp);
			PutProfile("setup", "port", temp);
			GetDlgItemText(hDlg, IDC_BAUD, temp, sizeof temp);
			PutProfile("setup", "baud", temp);
			GetDlgItemText(hDlg, IDC_FOLDER, temp, sizeof temp);
			PutProfile("setup", "folder", temp);

		case IDCANCEL:
			EndDialog(hDlg, LOWORD(wParam));
			return TRUE;
		}
		break;
	}
	return FALSE;
}
void Configure(HWND hWnd)
{
	DialogBox(hInstance, MAKEINTRESOURCE(IDD_CONFIG), hWnd, Config);
}
//-------------------------------------------------------------------------------------------------
// unpack utilities
//-------------------------------------------------------------------------------------------------
void skip(const char* text, int& index)
{
	char c;
	while((c=text[index])==' ' || c=='\t' || c=='\r' || c=='\n')
		++index;
}
int tohex(char c)
{
	if(c>='0' && c<='9') return c-'0';
	if(c>='A' && c<='F') return c+10-'A';
	return c+10-'a';
}
BYTE unpackBYTE(const char* text, int &index)
{
	BYTE ret=0;
	skip(text, index);
	for(int i=0; i<2; ++i)
		if(isxdigit(text[index])){
			ret <<= 4;
			ret += tohex(text[index++]);
		}
	return ret;
}
WORD unpackWORD(const char* text, int& index)
{
	WORD ret=0;
	skip(text, index);
	for(int i=0; i<4; ++i)
		if(isxdigit(text[index])){
			ret <<= 4;
			ret += tohex(text[index++]);
		}
	return ret;
}
char tohexC(WORD b)
{
	b &= 0xf;
	if(b>9) return b-10+'A';
	return b+'0';
}
