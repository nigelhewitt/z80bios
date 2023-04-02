# Z80 hardware debugging bios for the Zeta V2 board

The whole game with building an old Z80 board again is to rewrite the bios.
My first home computer, way back in about 1980, before home computers were a
thing, was a 2MHz Z80 hand crafted in wrap wire on veroboard and the bios was
all my own work hand compiled into hex. I was an assembler programmer on
mini-computers by day so it was home territory. Then the GB2SR ham radio
repeater logic that I built was another Z80, more veroboard.

This is just the commercial Zeta2 board which I bought as a blank having
inspected his circuit diagram and rather liked it, However this is my bios
because that is what I want to do...

I use the SjASMPlus Z80 Cross-Assembler v1.20.2  
&nbsp;&nbsp;&nbsp;&nbsp;https://github.com/z00m128/sjasmplus  
and compile with the Powershell script  
&nbsp;&nbsp;&nbsp;&nbsp;make.ps1

This generates **bios.bin** which I put into the Flash chip with a cheap blower.
It goes in the ROM socket (I fitted a ZIF) and boots as normal.
It prompts with its sign on text including version and compile date and time.
The prompt is  
&nbsp;&nbsp;&nbsp;&nbsp;**\>**  
and it likes a full duplex terminal that obeys ANSI control codes so it can
clear the screen and do simple colours. However that can be switched off in
**zeta2.inc**

The commands are low level being up to four character letters followed by some
arguments.

I've been using **putty** as a terminal as I have it for SSH. Set it up with  
&nbsp;&nbsp;&nbsp;&nbsp;Keys: Control-H Standard ESC[n~ Normal Normal  
&nbsp;&nbsp;&nbsp;&nbsp;Translation: Latin-1  
&nbsp;&nbsp;&nbsp;&nbsp;Colours: Allow terminal to specify ANSI colours  
&nbsp;&nbsp;&nbsp;&nbsp;Serial: COM7 115600 8 1 N N  
It didn't seem to like me power cycling the board without unplugging it first
but that was down to the serial to USB converter and a three wire only cable
extension (TX/RX/GND) fixed that.

If there is no JP1 fitted the memory is arranges with the first three 16K RAM
blocks in the first three Z80 blocks and the first ROM block in the third page.
If there is a jumper the ROM copies itself into the fourth RAM page and swaps
that in and since the ROM code is only about 6K you get an extra 10K of RAM to
play in.

Then I added some lights and switches and a micro SD card slot wired into the
PIO. (see **Z80 addons.pdf**)It's the software to read the SD in FAT32 and the
FDC in FAT12 that I'm growing at the moment.

## Commands

**FLAG** set bits in the options table This is really a testing convenience.
They are saved in the first three bytes of the RTC RAM so they are retained as
you reboot of power down/up.

**CLS** Clear screen Using an ANSI sequence. A mere convenience.

**DUMP** Dump memory. This takes a 24 bit hex address and a 16 bit hex count
that defaults to $100 aka .256. This writes up the usual panel of hex and
character values for the bytes in memory. It does not display ASCII for
values<$20 or >$7e as many terminals can act silly.

**ERR** Decode the last_error. Checks the last_error data and returns a
hopefully more useful message.

**FILL** Fill memory. This takes a 24 bit hex address, a 16 bit hex count and
an 8 bit hex value. Try not to overwrite the first 0x69 bytes. If you overwrite
the stack the SP gets reset before it shows the prompt so it should survive.

**HEX** hex echo. You type a hex number up to 24 bits (123456) and echoes it
back in hex and with the decimal equivalent. This also loads and saves the
'default address' so just entering H will read that back to you. Mostly I work
in hex but if you want decimal prefix it with a . and if decimal is expected
and you really want to enter the time in hex prefix it with $. Use 'A for the
ASCII value of A. Don't even try the extended 8 bit characters on putty. Also
when multiple values are required and you want the use the default one enter #
and it takes the default and moves on to the next argument.

**IN** Input from a port. This takes an eight bit hex port address and gives
you back the 8 bit hex it reads from the port.

**KILL** That means **DI HALT**. Mostly so I could test the HALT light...

**LED** Set/reset the Leds. I soldered two LEDs from the spare pins on the RTC
port with 2N7000 fets and 240 ohm resistors to 5V. I use it testing states. The
pins are U10 pins 7 and 10. This is the manual control L 11 puts them both on.
L 00 puts them both off Lx1 leaves the first in whatever state it was and
changes the second.

**ROM** program the flash memory. ROM rom_n I|P|E|P Details later once I have
the SD card system sorted and it might be useful.

**OUT** Output to a port. This takes an eight bit hex port address and an eight
bit hex data value.

**READ** Read a byte of memory. This takes a full 24 bit hex address. The
32x16K pages of ROM and RAM are all accessible. RAM is from $0000000 to $7fffff
so for most cases you are worried about $0 to $ffff and get what you expect. If
you want to access higher pages you can. If you want to read the ROM that goes
from $800000 to $ffffff

**SAVE** Read/write RTC memory. SAVE address16 R|W|T|S. A 16 bit hex address as
it needs to be in Z80 reachable memory and use R and W for read or write the
RTC RAM and T and S to read and write the RTC clock data.

**TIME** Set/read the Real Time Clock. Use **HH:MM:SS** and **DD/MM/YY** or
**YYYY** (in decimal) and it will adjust things. It also appends the current
tick count for the CTC as seconds.

**W** Write memory. This takes a 24 bit hex address again followed by as many
8 bit hex values as you can get on an 80 character line. Each value is actioned
as it is read so if you make a mistake on value seven you have already changed
the first six that you typed but will have to redo from seven onwards.

**EXEC** Execute from this address. This takes a 16 bit hex address in the Z80
address map. The default is the ROM start up address so just X restarts with a
full reload.

**CORE** zero all the user ram and refresh the restart vectors. I do not do
this on a reset as it destroys all the forensic debug evidence.

**Y Z** This is just the places I put my current test code

**?** Show a quick cheat sheet for the commands

Most of the rest that you might need to know is in the code.  
I've gone for the ELI5 comment style because at 73 I forget stuff.  
Start from **bios.asm** and go from there.  
The **make.ps1** compiles the separate biosN.bin and merge.exe glues them
together. The separate bios blocks have their own copies of the stdio et al as
they have lots of space while bios0 tries to squeeze down to leave lots of free
address map for RAM.  
The RTC clock and the FDC systems are based on reading code from other GitHub
denizens. Credits are in the files.

I even built it a box...

![Box](/box.jpg)
