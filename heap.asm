;===============================================================================
;
;	heap.asm		Access to all that other RAM
;
;===============================================================================
heap_start		equ	$

; I want access to the rest of the 256K bytes of RAM so I need an allocator
; and management system.

; Initial concept is to use the 'heap' model so I have allocate() and free()
; routines returning pointer and some sort of table to manage things.
; However this is a Z80 so it need to be 16bit friendly.

; My current idea is to allocate large chunks using a 16bit pointer to a 20bit
; pointer which is the allocation unit.

; There are 16 x 16K pages of RAM, so far I have used 6 leaving 160K
HEAP_START		equ		RAM6		; inclusive heap pool
HEAP_END		equ		RAM15

; the working functions are
;	HeapInit
;			Sets up thing to start, discards any previous allocations
;	HeapDefrag
;			this is allowed to shuffle the memory about to defragment things
;			the 16bit pointer will not change but the underlying 20bit will
;	HeapAllocate
;			call with bytes required in DE,
;			returns CY on OK, allocation pointer in HL
;	HeapFree
;			call with the allocation pointer in HL
;	HeapMap1
;	HeapMap2
;			call with pointer in HL, returns HL to allocation using PAGE1/2
;	HeapUnmap1
;	HeapUnmap2
;			no parameters, just swaps back RAM1/2
;
; Then there are 'heap aware' copy functions to just stash things
;	ToHeap
;		call with HL as a 16bit pointer to local source
;				  DE as a 16bit pointer to the heap 20bit as destination
;	FromHeap
;		call with HL as 16bit pointer to 20bit heap reference as source
;				  DE as 16bit local destination

; I already have the routine bank_ldir that will do the minimum number of bank
; swaps to complete the transaction even id source and destination overlap
; multiple 16K borders
;
; banked memory LDIR	copy from C:HL to B:DE for IX counts
;						destination must be RAM, IX==0 results in 64K copy
;						works the 'stack free' trick
;						return CY = good

HEAPBLOCK	struct
			db		flags			; b0=allocated
			dw		size			; size in bytes
			db		ram				; which RAM
			dw		ptr				; start address
			ends

 if SHOW_MODULE
	 	DISPLAY "heap size: ", /D, $-heap_start
 endif


