sjasmplus --lst=bios0.lst --raw=bios0.bin `
  bios.asm map.asm maths.asm serial.asm stdio.asm cpm.asm `
  rtc.asm ctc.asm pio.asm rom.asm

sjasmplus --lst=bios1.lst --raw=bios1.bin `
	bios1.asm serial.asm stdio.asm maths.asm map.asm `
	error.asm spi.asm sd.asm

sjasmplus --lst=bios2.lst --raw=bios2.bin `
	bios2.asm serial.asm stdio.asm maths.asm map.asm

# ./merge -z 32 bios.bin bios0.bin bios1.bin bios2.bin
./merge bios.bin bios0.bin bios1.bin bios2.bin
