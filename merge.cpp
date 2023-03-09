// merge.cpp : combine multiple .bin files on 16Kborders
// see Systems\Stuff\stuff.sln

#include <cstdio>
#include <cstdint>

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
		printf( "merge  combine .bin files on 16K borders\r\n"
				"output.bin file1.bin file2.bin...\r\n");
		return -1;
	}
	FILE* fout;
	if(fopen_s(&fout, argv[1], "wb")!=0){			// create a new file or truncate the old one
		printf("Unable to open %s for writing\r\n", argv[1]);
		return -1;
	}
	for(int i=2; i<argc; ++i){
		FILE* fin;
		if(fopen_s(&fin, argv[i], "rb")!=0){
			printf("Unable to open %s for reading\r\n", argv[i]);
			return -1;
		}
		size_t fsize = fread(buffer, 1, N, fin);
		fclose(fin);
		if(fwrite(buffer, 1, N, fout)!=N){
			printf("Problem writing %s\r\n", argv[1]);
			return -1;
		}
		printf("File %s added %zd bytes (%zd spare)\r\n", argv[i], fsize, N-fsize);
	}
	fclose(fout);
	printf("%d Files merged into %s OK\r\n", argc-2, argv[1]);
	return 0;
}

