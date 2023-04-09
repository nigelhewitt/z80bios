;===============================================================================
;
; CPM.asm		Provide the CP/M access stuff in the header
;				http://www.gaby.de/cpm/manuals/archive/cpm22htm/ch5.htm
;
;===============================================================================

; To emulate CP/M functionality we have a JP instruction at 0x0005 to here
; ideally that would point to the first byte of system used memory so that is
; considered the top of available ram

; The function number is passed in C and address information in DE
; single bytes are returned in A and double bytes in HL
; a zero is returned if the call is OOR
; for weird reasons always return with A=L and B=H

cpm_start	equ	$

			db		"<CM/P driver>"
cpm			ld		a, c			; get the requested function number
			cp		41				;
			jr		c, c2			; nc if to big
c1			xor		a				; the 'bad' ending
			ld		l, a
			ld		b, h
			ret

c2			ld		hl, cpm_table
			add		l
			ld		l, a
			ld		a, h
			adc		0
			ld		h, a
			jp		[hl]

cpm_table	dw		cpm_reset				; 0
			dw		cpm_console_input		; 1
			dw		cpm_console_output		; 2
			dw		cpm_reader_input		; 3
			dw		cpm_punch_output		; 4
			dw		cpm_list_output			; 5
			dw		cpm_direct_console_io	; 6
			dw		cpm_get_io_byte			; 7
			dw		cmp_set_io_byte			; 8
			dw		cpm_print_string		; 9
			dw		cpm_read_console_buffer	; 10
			dw		cpm_get_console_status	; 11
			dw		cpm_version_number		; 12
			dw		cpm_reset_disk_system	; 13
			dw		cpm_select_disk			; 14
			dw		cpm_open_file			; 15
			dw		cpm_close_file			; 16
			dw		cpm_search_first		; 17
			dw		cpm_search_next			; 18
			dw		cpm_delete_file			; 19
			dw		cpm_read_sequential		; 20
			dw		cpm_write_sequential	; 21
			dw		cpm_make_file			; 22
			dw		cpm_rename_file			; 23
			dw		cpm_login_vector		; 24
			dw		cpm_current_disk		; 25
			dw		cpm_set_DMA				; 26
			dw		cpm_get_alloc			; 27
			dw		cpm_write_protect		; 28 (depreciated in 1982)
			dw		cpm_get_ro_vector		; 29
			dw		cpm_set_file_attributes	; 30
			dw		cpm_get_disk_params		; 31
			dw		cpm_user_code			; 32 (depreciated in 1982)
			dw		cpm_read_random			; 33
			dw		cpm_write_random		; 34
			dw		cpm_file_size			; 35
			dw		cpm_set_random			; 36
			dw		cpm_reset_drive			; 37
			dw		c1						; 38
			dw		c1						; 39
			dw		cpm_write_random_fill	; 40



cpm_reset:
cpm_console_input:
	nop
cpm_console_output:
cpm_reader_input:
cpm_punch_output:
	nop
cpm_list_output:
cpm_direct_console_io:
cpm_get_io_byte:
cmp_set_io_byte:
cpm_print_string:
cpm_read_console_buffer:
cpm_get_console_status:
cpm_version_number:
cpm_reset_disk_system:
cpm_select_disk:
cpm_open_file:
cpm_close_file:
cpm_search_first:
cpm_search_next:
cpm_delete_file:
cpm_read_sequential:
cpm_write_sequential:
cpm_make_file:
cpm_rename_file:
cpm_login_vector:
cpm_current_disk:
cpm_set_DMA:
cpm_get_alloc:
cpm_write_protect:
cpm_get_ro_vector:
cpm_set_file_attributes:
cpm_get_disk_params:
cpm_user_code:
cpm_read_random:
cpm_write_random:
cpm_file_size:
cpm_set_random:
cpm_reset_drive:
cpm_write_random_fill:
			ret

 if SHOW_MODULE
	 	DISPLAY "cpm size: ", /D, $-cpm_start
 endif
