// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "debug.h"
#include "regs.h"
#include "process.h"
#include "source.h"
#include "mem.h"
#include "terminal.h"
#include "util.h"
#include "Z80debug.h"

DEBUG* debug{};				// create the one global item

//=================================================================================================
// debugger traps
//=================================================================================================
int DEBUG::setTrap(int page, int address)
{
	for(int i=0; i<nTraps; ++i)
		if(traps[i].used==false){
			traps[i].used = true;
			traps[i].page = page;
			traps[i].address = address;
			nPleaseSetTrap = i+1;
			return i+1;
		}
	return 0;
}
void DEBUG::freeTrap(int n)
{
	nPleaseFreeTrap = n;
	traps[n-1].used = false;
}
//=================================================================================================
// the debugger thread
//=================================================================================================
bool iswhite(char c)
{
	return c==' ' || c=='\t' || c=='\r' || c=='\n';
}
void DEBUG::packW(WORD w)
{
	putc(tohexC(w>>12));
	putc(tohexC(w>>8));
	putc(tohexC(w>>4));
	putc(tohexC(w));
}
void DEBUG::packB(BYTE b)
{
	putc(tohexC(b>>4));
	putc(tohexC(b));
}
bool DEBUG::getBuffer(char *buffer, int cb, int timeout)
{
	uint64_t ticks;
	if(timeout==0)
		ticks = 0xffffffffffffffff;
	else
		ticks = GetTickCount64()+timeout;

	char c{};
	int i = 0;
	while(ticks>GetTickCount64()){
		while(!bytesIn.empty()){
			c = bytesIn.dequeue();
			if(traffic) traffic->putc(c);
			if(!iswhite(c)){
				buffer[i++] = c;
				if(i>cb-2 || c=='@' || c=='?'){
					buffer[i] = 0;
					return c=='@';
				}
			}
		}
		Sleep(50);
		if(!runOK) throw 1;
	}
	buffer[i] = 0;
	return false;
}
int DEBUG::getc(int timeout)
{
	if(timeout==0)
		timeout = 86400000L;	// one day

	uint64_t time = GetTickCount64()+timeout;	// mSecs
	while(time>GetTickCount64()){
		if(!bytesIn.empty()){
		char c = bytesIn.dequeue();
		if(traffic) traffic->putc(c);
		if(!iswhite(c))
			return c & 0xff;
		}
		if(!runOK) throw 1;
		Sleep(50);
	}
	return -1;
}

void DEBUG::getType()
{
	char c[3];
	c[0] = getc();
	c[1] = getc();
	c[2] = 0;
	int index=0;
	type = unpackBYTE(c, index);
}

void DEBUG::sendCommand(const char* fmt, ...)
{
	Sleep(200);
	flush();

	va_list args;
	char temp[100];
	va_start(args, fmt);
	vsprintf_s(temp, sizeof temp, fmt, args);
	va_end(args);
	char* p = temp;
	while(*p)
		putc(*p++);
	char temp2[200];
	sprintf_s(temp2, sizeof temp2, "Sending: \'%s\'", temp);
	SetStatus(temp2);
}
// try to get unstuck from a communication breakdown
bool DEBUG::recycle()
{
	AddTraffic("\r\nRECYCLE\r\n");
	// eat the incoming queue until things stop for half a second
	for(int i=0; i<10; ++i){
		getc(500);
		sendCommand("q");			// doesn't exist
		char temp[20];
		getBuffer(temp, sizeof temp, 500);				// should get back "?"
		return true;
	}
	return false;
}
//=================================================================================================
// check if the registers have been updates and if so send them
//=================================================================================================
void DEBUG::do_regs()
{
	if(regs->changed()){
		sendCommand("t %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x %04x"
					" %04x %04x %04x %04x %04x",
					regs->r1.W[0],  regs->r1.W[1],  regs->r1.W[2],  regs->r1.W[3],
					regs->r1.W[4],  regs->r1.W[5],  regs->r1.W[6],  regs->r1.W[7],
					regs->r1.W[8],  regs->r1.W[9],  regs->r1.W[10], regs->r1.W[11],
					regs->r1.W[12], regs->r1.W[13], regs->r1.W[14], regs->r1.W[15],
					regs->r1.W[16], regs->r1.W[17]);
		char temp[20];
		getBuffer(temp, sizeof temp, 500);				// should get back "?"
	}
	flush();
}
//=================================================================================================
// the debugger working thread
//=================================================================================================

enum { F_RUN = 1, F_STEP, F_RESET, F_BREAK, F_OS };
int uiFlag{};

void DEBUG::run()	{ std::lock_guard<std::mutex> lock(mx); uiFlag = F_RUN; }
void DEBUG::step()	{ std::lock_guard<std::mutex> lock(mx); uiFlag = F_STEP; }
void DEBUG::reset()	{ std::lock_guard<std::mutex> lock(mx); uiFlag = F_RESET;}
void DEBUG::pause()	{ std::lock_guard<std::mutex> lock(mx); uiFlag = F_BREAK; }
void DEBUG::os()	{ std::lock_guard<std::mutex> lock(mx); uiFlag = F_OS; }

void DEBUG::showStatus(byte type, bool force)
{
	static byte oldType{0xaa};
	if(type!=oldType || force){
		oldType = type;

		if(type==0)
			SetStatus("READY");
		else if(type==1)
			SetStatus("NMI BREAK");
		else if(type==2)
			SetStatus("TRAP RST");
		else if(type>=3 && type<=nTraps+2){
			int page = traps[type-3].page;
			bool RAM = (page & 0x20)!=0;
			char buffer[100];
			// we talk about traps 1 to 10 but index then 0-9
			sprintf_s(buffer, sizeof buffer, "TRAP %d at %s%d:%04X", type-2,
							RAM?"ROM":"RAM", page&0x1f, regs->r1.r2.PC16);
			SetStatus(buffer);
		}
		else
			SetStatus("CONFUSED");
	}
}
//=================================================================================================
// setupMODE		just started or restarted
//=================================================================================================
void DEBUG::setupMode()
{
	char c;

	SetStatus("WAITING FOR HOST");
	// wait for the client to show up
	while((c=getc(500))!='*')				// infinite loop
		if(uiFlag) break;
	getType();
	while((c=getc())!='@');
	SetStatus("GETTING HOST DATA");

	// request the version and NTRAPS
	sendCommand("i");
	char buffer[100];
	if(getBuffer(buffer, sizeof buffer)){
		int index=0;							// step over the echo
		int ver = unpackBYTE(buffer, index);
		int n   = unpackBYTE(buffer, index);
		if(nTraps==0){
			nTraps = n;
			traps = new TRAP[nTraps];
		}
		if(ver!=1 && n!=nTraps)
		AddTraffic(" VERSION MISS-MATCH ");
	}
	else
		AddTraffic(" INFO PROBLEM ");

	state = S_ENTERIDLE;
}
//=================================================================================================
// enteridleMODE		the Z80 has just entered the debugger and need the details
//=================================================================================================
void DEBUG::enteridleMode()
{
	SetStatus("GETTING CURRENT DATA");
	// request the registers
	bRegsPlease = true;
	while(bRegsPlease) Sleep(100);
	sendCommand("r");
	char buffer[100];
	getBuffer(buffer, sizeof buffer);
	regs->unpackRegs(buffer);

	auto t = process->FindTrace(regs->r1.r2.PC16);
	if(get<0>(t)>=0)
		SOURCE::PopUp(get<0>(t), get<2>(t), 1);

	// set all MEMs to request mode
	if(!MEM::memList.empty())
		for(auto& m : MEM::memList)
			m->updated = false;

	state = S_IDLE;
	showStatus(type, true);
}
//=================================================================================================
// idleMODE		the Z80 is in the debugger and waiting for instructions
//=================================================================================================
void DEBUG::idleMode()
{
	char temp[100];

	{
		std::lock_guard<std::mutex> lock(mx);
		switch(uiFlag){
		case 0:
			break;
		case F_RUN:
			do_regs();
			flush();
			sendCommand("k");		// continue command
			if(getBuffer(temp, sizeof temp)){
				state = S_RUN;
				SetStatus("RUN");
			}
			uiFlag = 0;
			break;
		case F_STEP:
			do_regs();
			flush();
			sendCommand("s");		// step command
			if(getBuffer(temp, sizeof temp)){
				state = S_RUN;
				SetStatus("RUN");
			}
			uiFlag = 0;
			break;
		case F_RESET:
			recycle();
			uiFlag = 0;
			break;
		case F_BREAK:
			state = S_ENTERIDLE;	// refresh mem
			uiFlag = 0;
			break;
		case F_OS:
			do_regs();
			flush();
			sendCommand("z");
			if(getBuffer(temp, sizeof temp)){
				state = S_RUN;
				SetStatus("OS");
				terminal->top();	// bring to top
			}
			uiFlag = 0;
			break;
		}
	}

	// check for a trap request
	if(debug->nPleaseSetTrap){
		int i=debug->nPleaseSetTrap - 1;
		debug->nPleaseSetTrap = 0;
		sendCommand("+ %02X %02X %04X", i, debug->traps[i].page, debug->traps[i].address);
		char buffer[100];
		if(getBuffer(buffer, sizeof buffer))
			SetStatus("IDLE");
	}
	// and the converse
	if(debug->nPleaseFreeTrap){
		int i=debug->nPleaseFreeTrap - 1;
		debug->nPleaseFreeTrap = 0;
		sendCommand("- %02X", i);
		char buffer[100];
		if(getBuffer(buffer, sizeof buffer))
			SetStatus("IDLE");
	}

	// check for a memory request
	{
		const std::lock_guard<std::mutex> lock(MEM::memListMutex);
		if(!MEM::memList.empty())
			for(auto& m : MEM::memList){
				const std::lock_guard<std::mutex> lock(m->transfer);
				if(!m->updated && m->count && m->array){
					for(int i=0; i<m->count; i+=100){
						char temp[250];
						int n = 100;
						if(m->count-i<n) n = m->count-i;
						sendCommand("g %05X %02X", m->address+i, n);
						getBuffer(temp, sizeof temp);
						int index = 0;
						for(int j=0; j<n; ++j)
							m->array[i+j] = unpackBYTE(temp, index);
					}
					m->updated = true;
				}
			}
	}

}
//=================================================================================================
// runMODE		the Z80 is running
//=================================================================================================
void DEBUG::runMode()
{
	if(poll() && getc()=='*'){
		state = S_TRAP;
	}
	Sleep(200);
}
//=================================================================================================
// trapMODE		the Z80 had just trapped
//=================================================================================================
void DEBUG::trapMode()
{
	getType();		// we just got a '*'
	Sleep(200);
	flush();
	state = S_ENTERIDLE;
}
//=================================================================================================
// Main debugger loop
//=================================================================================================

void DEBUG::debugger()
{
	try{
		while(runOK)
			switch(state){
			case S_NEW:
				setupMode();
				break;

			case S_ENTERIDLE:		// get status
				enteridleMode();
				break;

			case S_IDLE:			// waiting for the UI
				idleMode();
				break;

			case S_RUN:				// waiting for UI and trap
				runMode();
				break;

			case S_TRAP:
				trapMode();
				break;
		}
	}
	catch(...){}
}
