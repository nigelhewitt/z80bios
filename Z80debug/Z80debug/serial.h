#pragma once
//=================================================================================================
//
//		serial.h	SERIAL is a class to wrap my old SERIALDRV tool for the debugger
//
//=================================================================================================

#include "safequeue.h"
#include "serialdrv.h"

class SERIALDRV;

class SERIAL {
public:
	SERIAL();
	~SERIAL();
	bool setup(std::string port, int baud);
	// characters to be transmitted
	void putc(char c){ tx.enqueue(c); };

	// handlers for characters to be received
	bool registerReceiver(int n, SafeQueue<char>* inbound);
	bool unregisterReceiver(int);

private:
	SERIALDRV *sd{};			// good old serial driver
	SafeQueue<char>tx{};		// incoming data to transmit

	// received data has to be steered to the right receiver
	int currentReceiver{};						// current receiver
	std::map<int,SafeQueue<char>*> receivers{};	// list of registered receivers
	bool post(char c);							// new received character for processing
	bool send(char c);							// send to currentReceiver
	int inputState{};							// input state machine
	char digit{};								// number it accumulates

	static void timerproc(HWND,UINT,UINT_PTR,DWORD);

};

extern SERIAL* serial;
