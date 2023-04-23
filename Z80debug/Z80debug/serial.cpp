//=================================================================================================
//
//		serial.cpp	SERIAL is a class to wrap my old SERIALDRV tool for the debugger
//
//=================================================================================================

#include "framework.h"
#include "serial.h"

SERIAL* serial{};


SERIAL::SERIAL()
{
	SetTimer(nullptr, 25, 100, SERIAL::timerproc);
}
SERIAL::~SERIAL()
{
	delete sd;
	KillTimer(nullptr, 25);
}
bool SERIAL::setup(const char* port, int baud)
{
	if(sd) delete sd;
	sd = new SERIALDRV(port, baud);
	return sd!=nullptr && sd->ok();
}
bool SERIAL::registerReceiver(int n, SafeQueue<char>* inbound)
{
	if(receivers.contains(n))
		return false;
	receivers.emplace(std::make_pair(n, inbound));
	return true;
}
bool SERIAL::unregisterReceiver(int n)
{
	if(!receivers.contains(n))
		return false;
	receivers.extract(n);
	return true;
}
void SERIAL::timerproc(HWND,UINT,UINT_PTR,DWORD)
{
	int c;
	if(serial && serial->sd){
		while((c=serial->sd->getc())!=-1)
			serial->post(c);
		while(!serial->tx.empty())
			serial->sd->send(serial->tx.dequeue());
	}
}

bool SERIAL::send(char c)
{
	if(receivers.contains(currentReceiver))
		receivers[currentReceiver]->enqueue(c);
	return true;
}
bool SERIAL::post(char c)
{
	// we switch receiver using the ESC[n? code
	// the system is over complicated but open ended for adding file transfer et al later
	switch(inputState){
	case 0:					// normal
		if(c==0x1b){		// <ESC>
			inputState = 1;
			return true;
		}
		return send(c);

	case 1:
		if(c=='['){
			inputState = 2;
			return true;
		}
		inputState = 0;
		return send(0x1b) && send(c);

	case 2:
		if(isdigit(c)){
			inputState = 3;
			digit = c;
			return true;
		}
		inputState = 0;
		return send(0x1b) && send('[') && send(c);

	case 3:
		if(c=='?'){				// a non-ANSI code (I hope)
			currentReceiver = digit-'0';
			return true;
		}
		else{
			inputState = 0;
			return send(0x01b) && send('[') && send(digit) && send(c);
		}
	}
	return true;
}

