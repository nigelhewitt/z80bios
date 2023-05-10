cls

sjasmplus --lst=bios0.lst --raw=bios0.bin --fullpath --sld=bios0.sdl `
  bios.asm map.asm router.asm maths.asm serial.asm stdio.asm cpm.asm `
  rtc.asm ctc.asm pio.asm debug.asm interrupt.asm stepper.asm
$error = $LastExitCode

Write-Host

sjasmplus --lst=bios1.lst --raw=bios1.bin --fullpath --sld=bios1.sdl `
	bios1.asm router.asm serial.asm stdio.asm maths.asm map.asm `
	fdc.asm spi.asm sd.asm interrupt.asm debug.asm `
	fat-struct.inc fat-drive.asm fat-clusters.asm fat-folder.asm fat-file.asm `
	files.asm stepper.asm
$error = $error -or $LastExitCode

Write-Host

sjasmplus --lst=bios2.lst --raw=bios2.bin --fullpath --sld=bios2.sdl `
	bios2.asm router.asm serial.asm stdio.asm maths.asm map.asm debug.asm `
	interrupt.asm error.asm rom.asm stepper.asm
$error = $error -or $LastExitCode

Write-Host

# ./merge -z 32 bios.bin bios0.bin bios1.bin bios2.bin
./merge bios.bin bios0.bin bios1.bin bios2.bin

if($error){ [System.Console]::Beep(1000,300) }