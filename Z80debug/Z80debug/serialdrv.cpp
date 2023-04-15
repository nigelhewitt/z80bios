//=================================================================================================
//
//			SERIAL.CPP		Common code library for the terminal
//
//			Copyright Combro 1996
//			Code by Nigel V.Hewitt		started 22nd October 1996
//
//		Use in conjunction with SERIAL.CPP to provide Win32 coms i/o
//
//=================================================================================================

#include "framework.h"
#include "serialdrv.h"

//=================================================================================================
// Serial port stuff
//=================================================================================================

SERIAL::SERIAL(LPCSTR name, int baud)
{
	open(name, baud);
}
SERIAL::~SERIAL()
{
	close();
}
//=================================================================================================
// Hardware oriented routines
//=================================================================================================

bool SERIAL::open(LPCSTR name, int baud)
{
	if(name==nullptr || *name==0) return false;
	strcpy_s(szPortName, sizeof(szPortName), name);
	nBaud = baud;
	_ok = false;
	iBuffer = 0;
	nBuffer = 0;

	if(szPortName[0]==0) return _ok;

	char nx[20]="";
	if(strlen(szPortName)>4)									// special handling for COM10+
		strcpy_s(nx, sizeof(nx), "\\\\.\\");
	strcat_s(nx, sizeof(nx), szPortName);
	handle = CreateFile(nx, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if(handle==INVALID_HANDLE_VALUE){
bad:
		err = GetLastError();
		return _ok;
	}

	if(!SetupComm(handle, 100, 10)) return _ok;

	COMMTIMEOUTS cto = { MAXDWORD, 0, 0, 0, 1000 };			// return immediately
	if(!SetCommTimeouts(handle, &cto)) goto bad;

	if(!GetCommState(handle, &dcb)) goto bad; 				// get current
	dcb.BaudRate = nBaud;	 								// current baud rate
	dcb.ByteSize = 8;										// number of bits/byte, 4-8

	dcb.StopBits = 0;										// 0,1,2 = 1, 1.5, 2
	dcb.Parity	 = 0;										// 0-4=none,odd,even,mark,space

	dcb.fOutX 	= FALSE;									// XON/XOFF out flow control
	dcb.fInX	= FALSE;									// XON/XOFF in flow control
	dcb.fParity	= FALSE;									// enable parity checking
	dcb.fBinary = 0;

	dcb.XonChar	 = 0x11;									// ASCII_XON
	dcb.XoffChar = 0x13;									// ASCII_XOFF
	dcb.XonLim	 = 100 ;
	dcb.XoffLim	 = 100 ;

	// DTR and RTS we set to inactive
	dcb.fDtrControl = DTR_CONTROL_DISABLE;
	dtr = false;
	dcb.fRtsControl = RTS_CONTROL_DISABLE;
	rts = false;
	SetCommState(handle, &dcb);								// might fail but....

	_ok = true;
	return _ok;
}
bool SERIAL::close()
{
	if(handle!=INVALID_HANDLE_VALUE){
		CloseHandle(handle);
		_ok = false;
	}
	logging(false, false);
	return true;
}
DWORD SERIAL::error()
{
	static DWORD err;
	ClearCommError(handle, &err, NULL);
	err &= CE_BREAK | CE_FRAME | CE_OVERRUN | CE_RXOVER | CE_RXPARITY;
	return err;
}
//=================================================================================================
// public routines
//=================================================================================================
bool SERIAL::send(char c)			// send data a block of stuff, if it is null terminated leave off cb
{
	return _ok && write(&c, 1)==1;
}

bool SERIAL::send(LPCSTR s, size_t cb)			// send data a block of stuff, if it is null terminated leave off cb
{
	if(cb==0) cb=lstrlen(s);
	return _ok && write(s, cb)==cb;
}
int SERIAL::getc()							// get a single character (or -1)
{
	if(!_ok || !poll()) return -1;
	int c = buffer[iBuffer++] & 0xff;		// mask as char is signed so it extends
	nBuffer--;
	if(iBuffer==sizeof(buffer)) iBuffer=0;
	return c;
}
int SERIAL::get(char* b, size_t cb)			// get anything
{
	if(!_ok || !poll()) return 0;
	// copy out the data
	int i;
	for(i=0; i<cb-1 && nBuffer; b[i++]=getc());
	b[i] = 0;
	return i;
}
bool SERIAL::gets(char* b, size_t cb)		// get a string that did have a \r at the end
{
	if(!_ok || !poll()) return false;
	// search for a '\r'
	int found = -1, i;
	for(i=0; found==-1 && i<nBuffer; i++)
		if(buffer[(iBuffer+i)%sizeof(buffer)]=='\r')
			found = i;
	if(found==-1) return false;
	// copy out the data
	for(i=0; i<cb-1 && i<found; b[i++]=getc());
	b[i] = 0;
	getc();					// remove and discard the \r
	return true;
}
// check if the port has close and try to reopen it
void SERIAL::check()
{
	static int n=0;		// this is called at 100mS and that is too fast
	if(++n>4){
		n=0;

	}
}
// set/get DTR/RTS
void SERIAL::setDTR(bool val)
{
	EscapeCommFunction(handle, (dtr=val) ? SETDTR : CLRDTR);
}
void SERIAL::setRTS(bool val)
{
	EscapeCommFunction(handle, (rts=val) ? SETRTS : CLRRTS);
}
//=================================================================================================
// private routines
//=================================================================================================
int SERIAL::read(LPSTR buffer, size_t cbBuffer)
{
	if(!_ok) return 0;
	DWORD n=0;
	if(ReadFile(handle, buffer, (DWORD)cbBuffer, &n, NULL) && n)
		if(n)
			read_log(buffer, n);
	return n;
}
int SERIAL::write(LPCSTR buffer, size_t cbBuffer)
{
	if(!_ok) return 0;
	if(cbBuffer==0) cbBuffer=lstrlen(buffer);
	if(cbBuffer==0) return 0;
	DWORD n=0;
	if(!::WriteFile(handle, buffer, (DWORD)cbBuffer, &n, NULL) || n==0) return 0;
	write_log(buffer, n);
	return n;
}
bool SERIAL::poll()										// poll the receiver
{
	if(_ok && nBuffer<sizeof(buffer)){						// if ok with space to fill
		if(nBuffer==0){
			iBuffer = 0;									// index of next character to read
			nBuffer = read(buffer, sizeof(buffer));			// number of bytes in the buffer = read the whole buffer in one
		}
		else{
			int i = (iBuffer+nBuffer)%sizeof(buffer);		// index of next 'in' location
			if(i>iBuffer){									// if the free space wraps
				int k = read(buffer+i, sizeof(buffer)-i);	// read from i to end of buffer
				nBuffer += k;
				i += k;
				i %= sizeof(buffer);						// might wrap to zero
			}
			if(iBuffer>i){									// not an else as we may have just wrapped
				size_t k = read(buffer+i, iBuffer-i);		// read from i to iBuffer
				nBuffer += k;
			}
		}
	}
	return _ok && nBuffer;								// return true if there is data
}
//=================================================================================================
// diagnostics
//=================================================================================================

void SERIAL::read_log(char* bx, size_t cb)
{
	if(logFile==0 || cb==0) return;
	if(!read_mode){
		counter = WriteFile(logFile, "\r\n<rx>: ");
		read_mode = true;
	}
	expand(bx, cb);
}
void SERIAL::write_log(const char* bx, size_t cb)
{
	if(logFile==0 || cb==0) return;
	if(read_mode){
		counter = WriteFile(logFile, "\r\n<tx>: ");
		read_mode = false;
	}
	expand(bx, cb);
}
void SERIAL::setlog(const char *log)
{
	bool was_logging = false;
	if(logFile){
		was_logging = true;
		logging(false, false);
	}
	strcpy_s(szLogFile, sizeof(szLogFile), log);
	if(was_logging)
		logging(true, false);
}
void SERIAL::logging(bool on, bool newFile)
{
	if(on && logFile==0 && szLogFile[0]){
		logFile = CreateFile(szLogFile, GENERIC_WRITE, FILE_SHARE_READ, 0, newFile? CREATE_ALWAYS : OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
		if(logFile==INVALID_HANDLE_VALUE){
			logFile = 0;
			return;
		}
		if(!newFile)
			SetFilePointer(logFile, 0, 0, FILE_END);
		counter = WriteFile(logFile, "<START>\r\n<tx>: ");
		read_mode = false;
		return;
	}
	if(!on && logFile){
		WriteFile(logFile, "\r\n<END>\r\n");
		CloseHandle(logFile);
		logFile = 0;
	}
}
void SERIAL::record(const char* str)
{
	if(logFile)
		counter += WriteFile(logFile, str);
}
void SERIAL::expand(const char* bx, size_t cb)
{
	DWORD n;
	for(int i=0; i<cb; i++){
		BYTE c=bx[i];
		if(c=='\r')
			n = WriteFile(logFile, "<CR>");
		else if(c=='\n'){
			WriteFile(logFile, "<LF>\r\n");
			counter = n = 0;
		}
		else if(c=='\n')
			n = WriteFile(logFile, "<CR>");
		else if(c=='\t')
			n = WriteFile(logFile, "<TAB>");
		else if(c==0)
			n = WriteFile(logFile, "<NUL>");
		else if(c==0x7f)
			n = WriteFile(logFile, "<DEL>");
		else if(c=='\b')
			n = WriteFile(logFile, "<BS>");
		else if(c=='\x1b')
			n = WriteFile(logFile, "<ESC>");
		else if(c<0x20){
			char temp[10];
			wsprintf(temp, "<x%02X>", c);
			n = WriteFile(logFile, temp);
		}
		else
			::WriteFile(logFile, &c, 1, &n, 0);
		counter += n;
		if(counter>100){
			WriteFile(logFile, "\r\n");
			counter = 0;
		}
	}
	FlushFileBuffers(logFile);		// so if we crash it's on disk.
}
