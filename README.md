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

I started by using **putty** as a terminal as I have it anyway for SSH. Set it
up with  
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
and to others I just expect it to be a pile of source code to be mined to write
their own systems. That's what real open source is for isn't it?

Have fun.

Most of what you might need to know is in the code comments.  
I've gone for the ELI5 comment style because at 73 I forget stuff.  
Start from **bios.asm** and go from there.  
The **make.ps1** compiles the separate biosN.bin and merge.exe glues them
together. The separate bios blocks have their own copies of the stdio et al as
they have lots of space while bios0 tries to squeeze down to leave lots of free
address map for RAM.  
The RTC clock, SD and the FDC low level systems are based on reading code from
other GitHub denizens. Credits are in the files.

If you try to use any of it and run into problems drop me an email. I'm hardly
hard to find on the web.

I even built it a box as wires sprawling all over my desk got irritating...

![Box](/box.jpg)

Darn it I built it a debugger with a built in terminal using good old C++ and
the classic WIN32 interface. The Visual Studio VS2023 source is naturally
included....  
I have designed myself a NMI triggering single-step execution adapter but that
needs the debugger to work usefully atm. I got a PCB made and I have a bunch of
spares if somebody want to avoid the hassle of making similar. Email to check
then pay the postage and you can have them for free. There is one track to cut
and run a wire to replace but I needed one and the PCB house put six on the
board and sent me an extra board so I have a lot spare...  

![Debugger screen shot](/debugger.jpg)
