// merge.cpp : combine multiple .bin files on 16Kborders
// see Systems\Stuff\stuff.sln

#include <cstdio>
#include <cstdint>
#include <string.h>
#include <stdlib.h>

// let's get some ground rules agreed before we start
#ifndef RC_INVOKED
#ifndef _MBCS
#error HOLD THE BUS! This lot works in Multibyte not Unicode or ASCII
#endif

#if _MSVC_LANG < 202002L
#error I refuse to consider anything less than C++20 or cooler
#endif
#endif

#define N	16*1024			// block size
uint8_t buffer[N]{};

int main(int argc, char* argv[])
{
	if(argc<3){
		printf( "merge  combines .bin files on 16K borders\r\n"
				"merge [-z nblocks] output.bin file1.bin file2.bin...\r\n");
		return -1;
	}

	int argOP    = 1;			// next argument (output file)
	bool bZero   = false;
	uint8_t fill = 0xff;
	int nBlocks  = 0;

	if(strcmp(argv[1], "-z")==0){
		bZero = true;
		nBlocks = atoi(argv[2]);
		fill = 0;
		argOP = 3;
	}
	FILE* fout;
	if(fopen_s(&fout, argv[argOP], "wb")!=0){			// create a new file or truncate the old one
		printf("Unable to open %s for writing\r\n", argv[argOP]);
		return -1;
	}

	int i;
	int argF = argOP+1;			// first input file argument

	for(i=0; argF+i<argc; ++i){
		FILE* fin;
		if(fopen_s(&fin, argv[argF+i], "rb")!=0){
			printf("Unable to open %s for reading\r\n", argv[argF+i]);
			return -1;
		}

		for(int j=0; j<N; buffer[j++]=fill);		// pre-fill buffer to 0xff or zero

		size_t fsize = fread(buffer, 1, N, fin);
		fclose(fin);
		if(fwrite(buffer, 1, N, fout)!=N){
			printf("Problem writing %s\r\n", argv[argOP]);
			return -1;
		}
		printf("File %s added %zd bytes (%zd spare)\r\n", argv[argF+i], fsize, N-fsize);
	}
	// optional zero fill
	if(bZero && i<nBlocks){
		for(int j=0; j<N; buffer[j++]=fill);		// pre-fill buffer to 0xff or zero
		for(; i<nBlocks; ++i){
			for(int j=0; j<4; ++j)
				sprintf_s((char*)buffer+j*4*1024, N/4, "SECTOR %d", i*4+j);
			if(fwrite(buffer, 1, N, fout)!=N){
				printf("Problem writing %s\r\n", argv[argOP]);
				return -1;
			}
		}
	}
	fclose(fout);
	printf("%d Files merged into %s OK\r\n", argc-argF, argv[argOP]);
	return 0;
}

