;===============================================================================
;
;	fat-folder.asm		The code that understands FAT and disk systems
;
;===============================================================================

;-------------------------------------------------------------------------------
; Unpack a long filename from a DIRL record
; NB: the parts are given in reverse order
; call with	IY = FILE	where we build the filename
;			IX = DIRN	the directory entry
;-------------------------------------------------------------------------------

UnpackLong
;
;	DIRL *d = (DIRL*)dirn;
;	if(d->LDIR_Ord & 0x40){		// if first
;		for(int i=0; i<MAX_PATH; file->longName[i++]=0);
;		file->shortnamechecksum = d->LDIR_ChkSum;
;	}
;	else{
;		if(file->shortnamechecksum!=d->LDIR_ChkSum)
;			printf("LongName checksum error type 1\n");
;	}
;	uint16_t index = ((d->LDIR_Ord & 0x3f)-1)*13;	// where we put these character in long name
;	bool run=true;
;	for(int j=0; run && j<5; ++j){
;		if(d->LDIR_Name1[j]==0){ run=false; break; }
;		file->longName[index++] = d->LDIR_Name1[j];
;	}
;	for(int j=0; run && j<6; ++j){
;		if(d->LDIR_Name2[j]==0){ run=false; break; }
;		file->longName[index++] = d->LDIR_Name2[j];
;	}
;	for(int j=0; run && j<2; ++j){
;		if(d->LDIR_Name3[j]==0){ run=false; break; }
;		file->longName[index++] = d->LDIR_Name3[j];
;	}
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
