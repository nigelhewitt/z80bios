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
		serial->registerReceiver(1, &bytesIn);
		runOK = true;
		deb = new std::thread([this](){ try{ debugger(); } catch(...){} });
	}
	~DEBUG(){
		runOK = false;
		deb->join();		// wait for it...
	}
	int setTrap(int page, int address);
	void freeTrap(int n);

	enum STATE { S_NEW, S_ENTERIDLE, S_IDLE, S_RUN, S_TRAP, S_ERROR };
	STATE DebugState(){ return state; }

	// UI inputs
	void run();
	void step();
	void kill();
	void pause();

private:
	// Traps
	struct TRAP {
		int page{}, address{};
		bool used{};
	} *traps{};
	int nTraps=0;

	int nPleaseSetTrap{};
	int nPleaseFreeTrap{};

	// debugger process thread
	void debugger();					// the thread routine
	void showStatus(byte type, bool force=false);
	void setupMode();
	void enteridleMode();
	void idleMode();
	void runMode();
	void trapMode();


	std::thread *deb{};
	bool runOK{true};

	// character stream into/out of the debugger
	SafeQueue<char> bytesIn;

	// base thread routine to pass stuff to the debugger
	void debugChar(char c){
		bytesIn.enqueue(c);
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
