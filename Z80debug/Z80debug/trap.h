#pragma once


class DEBUG {
public:
	DEBUG(){
		waitObjects[0] = CreateEvent(nullptr, FALSE, FALSE, "Debugger Data Ready");
		waitObjects[1] = CreateEvent(nullptr, FALSE, FALSE, "Debugger Terminate");
	};
	~DEBUG(){};

	// Traps
	struct TRAP {
		int page{}, address{};
		bool used{};
	} *traps{};
	int nTraps=0;

	int setTrap(int page, int address);
	int nPleaseSetTrap{};
	void freeTrap(int n){ traps[n-1].used = false; }

	// debugger process thread
	HANDLE waitObjects[2]{};
	std::thread *deb{};
	void debugger();					// the thread routine
	void start(){
		deb = new std::thread([this](){ try{ debugger(); } catch(...){} });
	}
	void die(){ SetEvent(waitObjects[1]); }

	// character stream into/out of the debugger
	SafeQueue<char> data{};
	void debugChar(char c){
		data.enqueue(c);
		SetEvent(waitObjects[0]);
	}
	bool poll(){ return !data.empty(); }
	void flush(){
		while(!data.empty())
			traffic.enqueue(data.dequeue());
	}
	char getc(){
		char c = data.dequeue();
		traffic.enqueue(c);
		return c;
	}
	void putc(char c){
		traffic.enqueue(c);
		serial->send(c);
	}

	// traffic window
	static HWND hTraffic;
	SafeQueue<char> traffic{};

	void AddTraffic(const char* c){ while(*c) traffic.enqueue(*c++); }
	static INT_PTR TrafficProc(HWND hDlg, UINT wMessage, WPARAM wParam,  LPARAM lParam);
	void ShowTraffic();

	// state machine
	enum STATES { S_NEW, S_IDLE, S_RUN, S_TRAP };
	int state{S_NEW};

	// UI inputs
	void run();
	void step();
	void kill();
	void pause();

	void pleaseFetch(BYTE*, BYTE page, DWORD address, WORD count);
};

extern DEBUG debug;
