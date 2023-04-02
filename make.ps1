sjasmplus --lst=bios0.lst --raw=bios0.bin `
  bios.asm map.asm router.asm maths.asm serial.asm stdio.asm cpm.asm `
  rtc.asm ctc.asm pio.asm interrupt.asm stepper.asm
$error = $LastExitCode

sjasmplus --lst=bios1.lst --raw=bios1.bin `
	bios1.asm router.asm serial.asm stdio.asm maths.asm map.asm `
	spi.asm sd.asm interrupt.asm `
	fat-struct.inc fat-drive.asm fat-clusters.asm fat-folder.asm fat-file.asm `
	stepper.asm
$error = $error -or $LastExitCode

sjasmplus --lst=bios2.lst --raw=bios2.bin `
	bios2.asm router.asm serial.asm stdio.asm maths.asm `
	interrupt.asm error.asm rom.asm map.asm stepper.asm
$error = $error -or $LastExitCode

# ./merge -z 32 bios.bin bios0.bin bios1.bin bios2.bin
./merge bios.bin bios0.bin bios1.bin bios2.bin

if($error){ [System.Console]::Beep(1000,300) }