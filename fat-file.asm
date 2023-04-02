;===============================================================================
;
;	fat-file.asm		The code that understands FAT and disk systems
;	Important contributions
;
;===============================================================================

;-------------------------------------------------------------------------------
; matchwstr		match wide char strings
;				HL=WCHAR*  DL=WCHAR*	return CY on match
;-------------------------------------------------------------------------------

_chcmpi		ld		a, [hl]			; LSbyte of WCHAR
			inc		hl
			call	isupper			; bad test
			jr		nc, .ch1
			or		0x20			; to lower
.ch1		ld		c, a

			ld		a, [de]
			inc		de
			call	isupper
			jr		nc, .ch2
			or		0x20
.ch2		cp		c
			ret		nz

			ld		a, [hl]
			inc		hl
			ld		b, a

			ld		a, [de]
			inc		de
			cp		b
			ret

matchwstr	push	bc, hl, de
.ms1		call	_chcmpi
			jr		nz, .ms2		; fail
			ld		a, b
			or		c
			jr		nz, .ms1		; loop
			scf
			jr		.ms3
; fail
.ms2		or		a
.ms3		pop		de, hl, bc
			ret

;-------------------------------------------------------------------------------
; isDir		test a FILE* in IX and return CY if it is a folder
;-------------------------------------------------------------------------------
isDir		ld		a, [ix+FILE.dirn + DIRN.DIR_Attr]
			and		ATTR_DIR
			ret		z			; and never sets CY
			scf
			ret

;-------------------------------------------------------------------------------
; matchName		test the FIL* in IX against long name in DE
;				return
; IX=FILE*, DE=WCHAR*
matchName	or		a
			ret
