;===============================================================================
;
;	fat-file.asm		The code that understands FAT and disk systems
;	Important contributions
;
;===============================================================================

;-------------------------------------------------------------------------------
; isDir		test a FILE* in IX and return CY if it is a folder
;-------------------------------------------------------------------------------
isDir		ld		a, [ix+FILE.dirn + DIRN.DIR_Attr]
			and		ATTR_DIR
			ret		z			; and never sets CY
			scf
			ret

;-------------------------------------------------------------------------------
; matchName		test the FILE* in IX with wanted item WCHAR* DE
;				return CY on match
;-------------------------------------------------------------------------------
matchName	push	hl, bc
			ld		hl, ix
			ld		bc,	FILE.longName
			add		hl, bc
			call	strcmp16		; returns CY on match
			pop		bc, hl
			ret
