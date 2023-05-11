//=================================================================================================
//
//			SERIALDRV.CPP		Common code library for the terminal
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

SERIALDRV::SERIALDRV(std::string name, int baud)
{
	open(name, baud);
}
SERIALDRV::~SERIALDRV()
{
	close();
}
//=================================================================================================
// Hardware oriented routines
//=================================================================================================

bool SERIALDRV::open(std::string name, int baud)
{
	if(name.empty()) return false;
	PortName = name;
	nBaud = baud;
	_ok = false;
	iBuffer = 0;
	nBuffer = 0;

	if(PortName.empty()) return _ok;

	std::string nx = PortName;
	if(nx.length()>4)									// special handling for COM10+
		nx = "\\\\.\\" + PortName;
	handle = CreateFile(nx.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
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
bool SERIALDRV::close()
{
	if(handle!=INVALID_HANDLE_VALUE){
		CloseHandle(handle);
		_ok = false;
	}
	return true;
}
DWORD SERIALDRV::error()
{
	static DWORD err;
	ClearCommError(handle, &err, NULL);
	err &= CE_BREAK | CE_FRAME | CE_OVERRUN | CE_RXOVER | CE_RXPARITY;
	return err;
}
//=================================================================================================
// public routines
//=================================================================================================
bool SERIALDRV::send(char c)
{
	return _ok && write(&c, 1)==1;
}

bool SERIALDRV::send(LPCSTR s, size_t cb)	// send data a block of stuff, if it is null terminated leave off cb
{
	if(cb==0) cb=lstrlen(s);
	return _ok && write(s, cb)==cb;
}
int SERIALDRV::getc()						// get a single character (or -1)
{
	if(!_ok || !poll()) return -1;
	int c = buffer[iBuffer++] & 0xff;		// mask as char is signed so it extends
	nBuffer--;
	if(iBuffer==sizeof(buffer)) iBuffer=0;
	return c;
}
int SERIALDRV::get(char* b, size_t cb)		// get anything
{
	if(!_ok || !poll()) return 0;
	// copy out the data
	int i;
	for(i=0; i<cb-1 && nBuffer; b[i++]=getc());
	b[i] = 0;
	return i;
}
bool SERIALDRV::gets(char* b, size_t cb)		// get a string that did have a \r at the end
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
// set/get DTR/RTS
void SERIALDRV::setDTR(bool val)
{
	EscapeCommFunction(handle, (dtr=val) ? SETDTR : CLRDTR);
}
void SERIALDRV::setRTS(bool val)
{
	EscapeCommFunction(handle, (rts=val) ? SETRTS : CLRRTS);
}
//=================================================================================================
// private routines
//=================================================================================================
int SERIALDRV::read(LPSTR buffer, size_t cbBuffer)
{
	if(!_ok) return 0;
	DWORD n=0;
	if(ReadFile(handle, buffer, (DWORD)cbBuffer, &n, nullptr)==0)
		return 0;
	return n;
}
int SERIALDRV::write(LPCSTR buffer, size_t cbBuffer)
{
	if(!_ok) return 0;
	if(cbBuffer==0) cbBuffer=lstrlen(buffer);
	if(cbBuffer==0) return 0;
	DWORD n=0;
	if(!::WriteFile(handle, buffer, (DWORD)cbBuffer, &n, nullptr) || n==0) return 0;
	return n;
}
bool SERIALDRV::poll()										// poll the receiver
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
				size_t xx = iBuffer-i;						// avoid stupid warning
				size_t k = read(buffer+i, xx);				// read from i to iBuffer
				nBuffer += k;
			}
		}
	}
	return _ok && nBuffer;								// return true if there is data
}
