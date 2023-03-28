sjasmplus --lst=bios0.lst --raw=bios0.bin `
  bios.asm map.asm router.asm maths.asm serial.asm stdio.asm cpm.asm `
  rtc.asm ctc.asm pio.asm rom.asm stepper.asm
$error = $LastExitCode

sjasmplus --lst=bios1.lst --raw=bios1.bin `
	bios1.asm router.asm serial.asm stdio.asm maths.asm `
	map.asm error.asm spi.asm sd.asm fat-drive.asm fat-folder.asm stepper.asm
$error = $error -or $LastExitCode

sjasmplus --lst=bios2.lst --raw=bios2.bin `
	bios2.asm router.asm serial.asm stdio.asm maths.asm `
	map.asm stepper.asm
$error = $error -or $LastExitCode

# ./merge -z 32 bios.bin bios0.bin bios1.bin bios2.bin
./merge bios.bin bios0.bin bios1.bin bios2.bin

if($error){ [System.Console]::Beep(1000,300) }