# Z80 hardware debugging bios for the Zeta V2 board

The whole fun in the game with building an old Z80 computer again was to
rewrite the bios. My first home computer, way back in about 1980 well before
home computers were a thing, was a 2MHz Z80 hand crafted in wrap wire on
Veroboard and the bios was all my own work hand compiled into hex. However I
was an assembler programmer on big super-mini computers by day so it was my
home turf. When we needed a ham radio repeater logic for the GB2SR Brighton
repeater I built it using another Z80 and more Veroboard but now I had an
assembler.

This is just the commercial Zeta2 SBC PCB which I bought as a blank having
inspected the circuit diagram and rather liked it, However this is my bios
because that was what I wanted to do...

I use the SjASMPlus Z80 Cross-Assembler v1.20.2  
&nbsp;&nbsp;&nbsp;&nbsp;https://github.com/z00m128/sjasmplus  
and compile it with the PowerShell script  
&nbsp;&nbsp;&nbsp;&nbsp;make.ps1

This generates **bios.bin** which I put into the Flash chip with a cheap
blower (XGecu Pro - TL866PlusII). It goes in the ROM socket (I fitted a ZIF)
and boots as normal. It prompts with its sign on text including version and
compile date and time. The prompt is just   
&nbsp;&nbsp;&nbsp;&nbsp;**\>**   
until you add media to the equation. It is coded for a full duplex terminal
that obeys ANSI control codes so it can clear the screen and do simple colours.
However the ANSI stuff can be switched off in **zeta2.inc**

The commands are low level being up to four character letters followed by some
arguments.

I've been using **putty** as a terminal as I have it anyway for SSH. Set it up
with  
&nbsp;&nbsp;&nbsp;&nbsp;Keys: Control-H Standard ESC[n~ Normal Normal  
&nbsp;&nbsp;&nbsp;&nbsp;Translation: UTF-8  
&nbsp;&nbsp;&nbsp;&nbsp;Colours: Allow terminal to specify ANSI colours  
&nbsp;&nbsp;&nbsp;&nbsp;Serial: COM7 115600 8 1 N N  
It didn't seem to like me power cycling the board without unplugging it first
but I think that was down to the serial to USB converter and adding a three 
wire only cable extension (TX/RX/GND) fixed that.

If there is no JP1 fitted the memory is arranged with the first three 16K RAM
blocks in the first three Z80 blocks and the first ROM block in the third page.
If there is a jumper fitted the ROM copies itself into the fourth RAM page and
swaps that in and since the ROM code is only about 6K you get an extra 10K of
RAM to play in.

Then I added some lights and switches and a micro SD card slot wired into the
PIO (see **Z80 addons.pdf**). It's the software to read the SD in FAT32 and the
FDC in FAT12 that I'm growing at the moment.

I have documented things as if somebody was actually going to use it but if you
do you are rather missing the point. This is just my safety backup as I work
and to others I just expect it to be a pile of source code to loot to write
their own systems. That's what real open source is for isn't it?

Have fun.

## Commands

**BOOT** Jump to the Z80 restart address.

**CLS** Clear screen Using an ANSI sequence. A mere convenience.

**x:** Set the default media. Currently A: is the Floppy (stubbed out), C is
the first partition of the SD card and D: is the second.

**CD** change the current directory. Each 'drive' has it's own current directory
and the current drive:directory is added to the prompt.

**CORE** zero all the user ram and refresh the restart vectors. I do not do
this on a reset as it destroys all the forensic evidence for debugging.

**DIR** list the files and subfolders in the current drive:folder

**DUMP** Dump memory. This takes a 24 bit hex address and a 16 bit hex count
that defaults to $100 aka .256. This writes up the usual panel of hex and
character values for the bytes in memory. It does not display ASCII for
values<$20 or >$7e as many terminals can act silly. This uses my modified
addressing strategy where $00000 to $7ffff access the 512K of RAM and $80000 to
$fffff address the 512K of ROM and if you use $ff0000 to 0xffffff it is the
unmapped Z80 range however you have that mapped.

**ERR** Decode the last_error. Checks the last_error data and returns a
hopefully more useful message.

**EXEC** Execute from this address. This takes an address16 in the Z80 map. The
default 0x100 which is the default LOAD.

**FILL** Fill memory. This takes a 24 bit hex address, a 16 bit hex count and
an 8 bit hex value. Try not to overwrite the first 0x69 bytes. If you overwrite
the stack the SP gets reset before it shows the prompt so it should survive.

**FLAG** set bits in the options table This is really a testing convenience.
They are saved in the first three bytes of the RTC RAM so they are retained as
you reboot of power down/up.

**HEX** hex echo. You type a hex number up to 32 bits and echoes it back in hex
and with the decimal equivalent. This also loads and saves the 'default
address' so just entering HEX will read that back to you. Mostly I work in hex
but if you want decimal prefix it with a . and if decimal is expected and you
really want to enter the time in hex prefix it with $. Use 'A for the ASCII
value of A. Don't even try the extended 8 bit characters on putty. Also when
multiple values are required and you want the use the default one enter # and
it takes the default and moves on to the next argument.  
eg: W 100 'H'E'L'L'O'  1 2 3 ff .123 sets 10 bytes from $100 onwards.

**IN** Input from a port. This takes a hex port address8 and gives
you back the 8 bit hex it reads from the port.

**KILL** That means **DI HALT**. Mostly so I could test the HALT light...

**LED** Set/reset the Leds. I soldered two LEDs from the spare pins on the RTC
port with 2N3904 transisore and 220 ohm resistors in 'emitter follower'
configuration so the signals didn't get inverted. I used it testing states.
The pins are U10 pins 7 and 10. This is the manual control LED 11 puts them both
on. L 00 puts them both off Lx1 leaves the first in whatever state it was and
changes the second.

**LOAD** <filename> [address24=0x100]

**OUT** Output to a port. This takes an eight bit hex port address and an eight
bit hex data value.

**READ** Read a byte of memory. This takes a full 24 bit hex address. See DUMP
for a discussion of the addressing mode.

**ROM** program the flash memory. ROM rom_n I|P|E|P Details later once I have
the SD card system sorted and it might be useful.

**SAVE** Read/write RTC memory. SAVE address16 R|W|T|S. A 16 bit hex address as
it needs to be in Z80 reachable memory and use R and W for read or write the
RTC RAM and T and S to read and write the RTC clock data.

**TIME** Set/read the Real Time Clock. Use **HH:MM:SS** and **DD/MM/YY** or
**YYYY** (in decimal) and it will adjust things. It also appends the current
tick count from the CTC as seconds.

**W** Write memory. This takes a 24 bit hex address again followed by as many
8 bit hex values as you can get on an 80 character line. Each value is actioned
as it is read so if you make a mistake on value seven you have already changed
the first six that you typed but will have to redo from seven onwards.

**?** Show a quick cheat sheet for the commands

Most of the rest that you might need to know is in the code.  
I've gone for the ELI5 comment style because at 73 I forget stuff.  
Start from **bios.asm** and go from there.  
The **make.ps1** compiles the separate biosN.bin and merge.exe glues them
together. The separate bios blocks have their own copies of the stdio et al as
they have lots of space while bios0 tries to squeeze down to leave lots of free
address map for RAM.  
The RTC clock, SD and the FDC low level systems are based on reading code from
other GitHub denizens. Credits are in the files.

I even built it a box...

![Box](/box.jpg)
