// header.h : include file for standard system include files,
// or project specific include files
//

#pragma once

#define _CRT_SECURE_NO_WARNINGS			// as sprintf_s corrupts the buffer I have to use sprintf

#include "targetver.h"

#define WIN32_LEAN_AND_MEAN             // Exclude rarely-used stuff from Windows headers
// Windows Header Files
#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>

// C RunTime Header Files
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <memory>

// good ol' standard library
#include <algorithm>
#include <cctype>
#include <string>
#include <vector>
#include <tuple>
#include <thread>
#include <queue>
#include <mutex>
#include <map>
#include <format>
#include <condition_variable>
