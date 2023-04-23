#pragma once

#include "safequeue.h"
#include "serial.h"
#include "traffic.h"


class MEM;

// the whole idea is to keep the debugger separate from the Windows UI so they
// don't end up waiting for one another.

class DEBUG {
public:
	DEBUG(){
		waitObjects[0] = CreateEvent(nullptr, FALSE, FALSE, "Debugger Data Ready");
		waitObjects[1] = CreateEvent(nullptr, FALSE, FALSE, "Debugger Terminate");
		serial->registerReceiver(1, &bytesIn);
		start();
	}
	~DEBUG(){}
	int setTrap(int page, int address);
	void freeTrap(int n){ traps[n-1].used = false; }

	enum STATE { S_NEW, S_ENTERIDLE, S_IDLE, S_RUN, S_TRAP, S_ERROR };
	STATE DebugState(){ return state; }

	// routines called by main thread routines in the Windows UI
	void pleaseFetch(MEM* md){}
	void pleaseStop(MEM* md){}
	bool pleasePoll(MEM* md){ return false; }
	void pleaseLock(){}
	void pleaseUnlock(){}

	// UI inputs
	void run();
	void step();
	void kill();
	void pause();
	void die(){ SetEvent(waitObjects[1]); }

private:
	// Traps
	struct TRAP {
		int page{}, address{};
		bool used{};
	} *traps{};
	int nTraps=0;

	int nPleaseSetTrap{};

	// debugger process thread
	void debugger();					// the thread routine
	void showStatus(byte type);
	void setupMode();
	void enteridleMode();
	void idleMode();
	void runMode();
	void trapMode();


	HANDLE waitObjects[2]{};
	std::thread *deb{};
	void start(){
		deb = new std::thread([this](){ try{ debugger(); } catch(...){} });
	}

	// character stream into/out of the debugger
	SafeQueue<char> bytesIn;

	// base thread routine to pass stuff to the debugger
	void debugChar(char c){
		bytesIn.enqueue(c);
		SetEvent(waitObjects[0]);
	}
	// routines called by the debugger to access inbound data
	bool poll(){ return !bytesIn.empty(); }
	int getc(int timeout=0);		// masked 0xff or -1 on timeout, timeout=0 waits forever
	void flush(){
		while(!bytesIn.empty())
			traffic->putc(bytesIn.dequeue());
	}
	bool getBuffer(char *buffer, int cb, int timeout=0); // until @ or ?

	// routine called by the debugger to send serial data
	void putc(char c){
		if(traffic) traffic->putc(c);
		serial->putc(c);
	}
	void sendCommand(const char* fmt, ...);
	bool recycle();

	// traffic window is just a debugger on the debugger
	void AddTraffic(const char* c){ if(traffic) while(*c) traffic->putc(*c++); }

	// state machine
	STATE state{S_NEW};
	byte type{};
	void getType();

	// get data from the Z80 to display
	// request routines

	std::mutex dataTransfer;

	// share a couple of utilities
	void packW(WORD w);
	void packB(BYTE b);
};

extern DEBUG* debug;				// there is only one
