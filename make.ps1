sjasmplus --lst --raw=bios.bin `
  bios.asm maths.asm serial.asm stdio.asm cpm.asm `
  rtc.asm ctc.asm pio.asm spi.asm sd.asm

$f = Get-Item ./bios.bin
$l = $f.Length
$s = 16384-$l
Write-Host "Image size:" $l "bytes  space:" $s (' 0x{0:X}' -f $s)
