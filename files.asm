;===============================================================================
;
;	files.asm		The code that understands FAT and disk systems
;
;===============================================================================

;	OpenDirectory	call with DE=WCHAR* path, returns IY=DIRECTORY* CY on OK
;	ResetDirectory	IY=DIRECTORY* resets so starts from beginning again
;	NextDirectoryItem IY=DIRECTORY*, IX=FILE* to fill in, NC on finished
;	WriteDirectoryItem IX=FILE*, HL=chars, DE=maxChars

test_folder		db	'C',0, ':',0, '/',0, 0,0
test_file		FILE
test_text		ds	MAX_PATH+85

f_dircommand
			ld		de, test_folder
			call	OpenDirectory
.fd1		ld		ix, test_file
			ld		hl, test_text
			ld		de, MAX_PATH+85
			call	NextDirectoryItem
			jr		nc, .fd2
			ld		hl, test_text
			call	WriteDirectoryItem
			call	stdio_text
			call	stdio_str
			db		"\r\n",0
			jr		.fd1
.fd2		scf
			ret

;===============================================================================
;
;	define EOF	0xffff
;
; These are the functions I wish to emulate
;
;	FILE*		fopen(uint8_t* pathname, uint8_t *mode);
;	FILE*		fopenD(FILE* file, uint8_t *mode);
;	void		fclose(FILE* fp);
;	uint32_t	fread(void* buffer, uint16_t count, FILE* fp);
;	uint32_t	fwrite(void* buffer, uint16_t count, FILE* fp);
;	uint16_t	fgetc(FILE* fp);
;	uint8_t*	fgets(uint8_t* buffer, uint16_t count, FILE* fp);
;	int			fputc(uint8_t c, FILE* fp);
;	int			fputs(uint8_t* str, FILE* fp);
;	uint8_t		fseek(FILE* fp, int32_t offset, uint8_t origin);
;	uint32_t	ftell(FILE*fp);
;	bool		isDIR(FILE* file);
;	bool		isFILE(FILE* file);
;	uint8_t		isOpen(FILE* file);
;	uint8_t*	longpath(FILE* fp);
;	uint8_t*	longname(FILE* fp);
;	uint32_t	filesize(FILE* fp);
;
;	FOLDER*		openfolder(uint8_t* pathname);
;	bool		changefolder(FOLDER* folder, uint8_t* path);
;	FILE*		findnextfile(FOLDER* folder);
;	void		resetfolder(FOLDER* folder);
;	uint8_t*	folderpathname(FOLDER* fol);
;	void		closefolder(FOLDER* folder);
;
;	char*		writefiledesc(FILE* fp);
;
;===============================================================================
