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

std::string getIniFile()
{
	static std::string IniFileName{};

	if(IniFileName.empty()){
		char temp[MAX_PATH];
		GetModuleFileName(hInstance, temp, sizeof temp);
		char *p = strrchr(temp, '.');
		strcpy(p, ".ini");
		IniFileName = temp;
	}
	return IniFileName;
}
std::string GetProfile(std::string section, std::string key, std::string def)
{
	static char temp[500];
	GetPrivateProfileString(section.c_str(), key.c_str(), def.c_str(), temp, sizeof temp, getIniFile().c_str());
	return temp;
}
bool GetProfile(std::string section, std::string key, bool def)
{
	std::string d = def ? "true" : "false";
	std::string res = GetProfile(section, key, d);
	return res[0]=='t';
}
int GetProfile(std::string section, std::string key, int def)
{
	try{
		std::string d = std::format("{}", def);
		std::string res = GetProfile(section, key, d);
		return std::stoi(res);
	}
	catch(...){			// std::stoi throws on error
		return def;
	}
}
void PutProfile(std::string section, std::string key, std::string value)
{
	WritePrivateProfileString(section.c_str(), key.c_str(), value.c_str(), getIniFile().c_str());
}
//=================================================================================================
// comparei case insensitive compare:	returns -1/0/1
//		return 1 if a>b					ie: a comes lexically after b
//=================================================================================================
int comparei(std::string a, std::string b)
{
	size_t na = a.length(), nb = b.length(), nc = min(na, nb);
	for(size_t i=0; i<nc; ++i){
		if(std::tolower(a[i]) > std::tolower(b[i])) return  1;
		if(std::tolower(a[i]) < std::tolower(b[i])) return -1;
	}
	// at the end of the shortest string...
	if(na>nb) return  1;		// a is longer so a is after b
	if(na<nb) return -1;
	return 0;					// they are identical
}
//=================================================================================================
// ComboBox drop down list save and restore
//=================================================================================================

#define MAX_DROPS	10

// load a dialog box from the Profile
void DropLoad(HWND hDlg, UINT id)
{
	SendDlgItemMessage(hDlg, id, CB_RESETCONTENT, 0, 0);
	std::string section = std::format("DropBox-{0}", id);

	for(int i=0; i<MAX_DROPS; ++i){
		std::string item = std::format("T{0}", i+1);
		std::string text = GetProfile(section, item, "");
		if(!text.empty())
			SendDlgItemMessage(hDlg, id, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text.c_str()));
	}
}
// add a new item to the profile
void DropSave(UINT id, std::string text)
{
	std::string section = std::format("DropBox-{0}", id);

	// read in the current list
	std::vector<std::string> items{};

	for(int i=0; i<MAX_DROPS; ++i){
		std::string item = std::format("T{0}", i+1);
		std::string p = GetProfile(section, item, "");
		if(!p.empty() && p!=text)
			items.push_back(p);
	}
	items.insert(items.begin(), text);		// insert at the beginning

	for(int i=0; i<MAX_DROPS && i<items.size(); ++i){
		std::string item = std::format("T{0}", i+1);
		if(!items[i].empty())
			PutProfile(section, item, items[i]);
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
bool GetFolder(HWND hWnd, std::string &buffer, std::string title)
{
	BROWSEINFO bi;
	char szPath[MAX_PATH+1], szBuffer[MAX_PATH+1];
	LPITEMIDLIST pidl;
	bool bResult = false;
	LPMALLOC pMalloc;
	strcpy_s(szBuffer, sizeof szBuffer, buffer.c_str());

	if(SUCCEEDED(SHGetMalloc(&pMalloc))){
		bi.hwndOwner		= hWnd;
		bi.pidlRoot			= nullptr;
		bi.pszDisplayName	= nullptr;
		bi.lpszTitle		= title.c_str();
		bi.ulFlags			= BIF_STATUSTEXT; //BIF_EDITBOX
		bi.lpfn				= BrowseForFolderCallback;
		bi.lParam			= (LPARAM)szBuffer;

		pidl = SHBrowseForFolder(&bi);
		if(pidl){
			if(SHGetPathFromIDList(pidl, szPath)){
				bResult = true;
				buffer = szPath;
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
	char temp[100];
	int i, j, index=0;
	std::string t;

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
				if(lstrcmp(temp, t.c_str())==0) index = j;		// save the index of our previous port
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
			if(strcmp(temp, t.c_str())==0) index = i;
			++i;
		}
		SendDlgItemMessage(hDlg, IDC_BAUD, CB_SETCURSEL, index, 0);
		SetDlgItemText(hDlg, IDC_FOLDER, GetProfile("setup", "folder", "").c_str());
		return TRUE;

	case WM_COMMAND:
		switch(LOWORD(wParam)){
		case IDC_FOLDERBROWSE:
			char temp[MAX_PATH];
			GetDlgItemText(hDlg, IDC_FOLDER, temp, sizeof temp);
			t = temp;
			if(GetFolder(hDlg, t, "Select working folder"))
				SetDlgItemText(hDlg, IDC_FOLDER, t.c_str());
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
