#pragma once

// useful text to uintN_t casts
#define U8	const uint8_t*
#define U16	const uint16_t*

//#define ZZ_FILE YY_FILE
struct ZZ_FILE {
	void* file_stuff{};
};
struct ZZ_FOLDER {
	void* folder_stuff{};
};
struct ZZ_DRIVE {
	void* drive_stuff{};
};

#if _DEBUG
int UsedFileSlots();
int UsedDirectorySlots();
int UsedZZthings();
#endif

// defined data
extern uint8_t ZZ_CWD[MAX_PATH];		// starts a "C:\"

#define ZZ_EOF	0xffff

// defined functions
ZZ_FILE*		ZZ_fopen(const uint8_t* pathname, const uint8_t *mode);	// usual fopen letters
ZZ_FILE*		ZZ_fopenD(ZZ_FILE* file, const uint8_t *mode);	// usual fopen letters
void			ZZ_fclose(ZZ_FILE* fp);
uint32_t		ZZ_fread(void* buffer, uint16_t count, ZZ_FILE* fp);
uint32_t		ZZ_fwrite(void* buffer, uint16_t count, ZZ_FILE* fp);
uint16_t		ZZ_fgetc(ZZ_FILE* fp);
uint8_t*		ZZ_fgets(uint8_t* buffer, uint16_t count, ZZ_FILE* fp);
int				ZZ_fputc(uint8_t c, ZZ_FILE* fp);
int				ZZ_fputs(uint8_t* str, ZZ_FILE* fp);
uint8_t			ZZ_fseek(ZZ_FILE* fp, int32_t offset, uint8_t origin); // 0=current, 1=end, 2=start
uint32_t		ZZ_ftell(ZZ_FILE*fp);
bool			ZZ_isDIR(ZZ_FILE* file);
bool			ZZ_isFILE(ZZ_FILE* file);
uint8_t			ZZ_isOpen(ZZ_FILE* file);
const uint8_t*	ZZ_longpath(ZZ_FILE* fp);
const uint8_t*	ZZ_longname(ZZ_FILE* fp);
uint32_t		ZZ_filesize(ZZ_FILE* fp);

ZZ_FOLDER*		ZZ_openfolder(const uint8_t* pathname);
bool			ZZ_changefolder(ZZ_FOLDER* folder, const uint8_t* path);
ZZ_FILE*		ZZ_findnextfile(ZZ_FOLDER* folder);
void			ZZ_resetfolder(ZZ_FOLDER* folder);
uint8_t*		ZZ_folderpathname(ZZ_FOLDER* fol);
void			ZZ_closefolder(ZZ_FOLDER* folder);

const char*		ZZ_writefiledesc(ZZ_FILE* fp);
