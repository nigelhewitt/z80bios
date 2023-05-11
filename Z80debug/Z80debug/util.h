#pragma once

#include "framework.h"
#include "resource.h"

void error(DWORD err=0);
std::string getIniFile();
std::string GetProfile(std::string section, std::string key, std::string def);
inline std::string GetProfile(std::string section, std::string key, const char* def){
	return GetProfile(section, key, std::string(def));
}
int  GetProfile(std::string section, std::string key, int def);
bool GetProfile(std::string section, std::string key, bool def);

void PutProfile(std::string section, std::string key, std::string value);
void DropSave(UINT id, std::string text);
void DropLoad(HWND hDlg, UINT id);
bool GetFolder(HWND hWnd, std::string &buffer, std::string title);
void Configure(HWND hWnd);

//-------------------------------------------------------------------------------------------------
// unpack utilities
//-------------------------------------------------------------------------------------------------
void skip(const char* text, int& index);
int  tohex(char c);
BYTE unpackBYTE(const char* text, int &index);
WORD unpackWORD(const char* text, int& index);
char tohexC(WORD b);

// std::vector delete item by value (first only)
// use as: remove_by_value<MEM*>(&memList, this);
template<class T>
void remove_by_value(std::vector<T>*v, T value){
	auto i=std::find(v->begin(), v->end(), value);
	if(i!=v->end()) v->erase(i);
}
int comparei(std::string a, std::string b);