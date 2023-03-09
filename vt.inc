;===============================================================================
; define the Z80 org 0 system structure
;===============================================================================
			struct	Z
			ds		3				; JP rst0
spare		ds		2
			ds		3				; JP cpm
			ds		3				; JP rst08
def_address	ds		3				; 3 byte bios default address
def_port	ds		2				; bios default port
			ds		3				; JP rst10
preTick		ds		1				; uint8	 ticks per second
Ticks		ds		4				; uint32 time in seconds
			ds		3				; JP rst18
led_buffer	ds		1				; led buffer LD1=b3 LD2=b0 (active low)
snap_mode	ds		1				; 0=SNAP macro, 1=RST 0x08
last_error	ds		2				; last error number
			ds		1				; spare
			ds		3				; JP rst20
cr_sp		ds		2				; call ROM function storage
cr_rom		ds		1
cr_fn		ds		1
cr_ret		ds		1
			ds		3				; JP rst28
			ds		5
			ds		3				; JP rst30
			ds		5
			ds		3				; JP rst38
bios1_wedge	ds		43
			ds		3				; JP nmi
			ends
