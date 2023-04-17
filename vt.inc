;===============================================================================
; define the Z80 org 0 system structure
;===============================================================================
			struct	Z
			ds		3				; JP rst0
cr_af		ds		2
			ds		3				; JP cpm
			ds		3				; JP rst08
def_address	ds		4				; 3 byte bios default address
def_port	ds		1				; bios default port
			ds		3				; JP rst10
preTick		ds		1				; uint8	 ticks per second
Ticks		ds		4				; uint32 time in seconds
			ds		3				; JP rst18
led_buffer	ds		1				; led buffer LD1=b3 LD2=b0 (active low)
snap_mode	ds		1				; 0=SNAP macro, 1=RST 0x08
last_error	ds		2				; last error number
cr_ret		ds		1
			ds		3				; JP rst20
cr_sp		ds		2				; call ROM function storage
cr_ram		ds		1				; RAM FN handled as a dw
cr_fn		ds		1
			ds		1
			ds		3				; JP rst28
			ds		1
cmd_exp		ds		4
			ds		3				; JP rst30
savePage	ds		4				; save the page selections
			ds		1
			ds		3				; JP rst38
rtc_buffer	ds		31
			ds		10
overflow	dw		0				; used as a stack overflow test
			ds		3				; JP nmi
			ends
