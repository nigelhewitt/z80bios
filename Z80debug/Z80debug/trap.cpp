// trap.cpp : Defines the child window interface
//

#include "framework.h"
#include "Z80debug.h"

struct TRAP {
	int page{}, address{};
	bool used{};
};
#define NTRAPS 10
TRAP traps[NTRAPS];


int getTrap(int page, int address)
{
	for(int i=0; i<NTRAPS; ++i)
		if(traps[i].used==false){
			traps[i].used = true;
			traps[i].page = page;
			traps[i].address = address;
			return i+1;
		}
	return 0;
}
void freeTrap(int n)
{
	traps[n-1].used = false;
}
