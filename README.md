# Z80 hardware debugging bios for the Zeta V2 board

The whole game with building an old Z80 board again is to rewrite the bios.
My first home computer, way back in about 1980, was hand crafted in wrap wire
on veroboard and the bios was all my own work. I was an assembler programmer on
mini-computers so it was home territory.
Then the GB2SR ham radio repeater logic that I built was was another Z80, more
veroboard.
This is just the commercial Zeta2 board which I bought as a blank having
inspected his circuit diagram and liked it.
So this is my bios...

It goes in the ROM and boots when things start as normal.
It prompts with its signon including version and compile date and time.
The prompt is
>
and it expects a full duplex terminal that obeys ANSI control codes so it can
clear the screen and do simple colours.
The commands are pretty low level being single letters followed by some arguments.

I've been using putty as I have it for SSH. Set it up with
	Keys: Control-H Standard ESC[n~ Normal Normal
	Translation: Latin-1
	Colours: Allow terminal to specify ANSI colours
	Serial: COM7 19200 8 1 N N
It doesn't like me power cycling the board without unplugging it first. There
may be a simple fix but I haven't searched that yet.

**E echo stuff**. Whatever you type is echoed back. As it is for argument testing
  it removes the \e[stuff

**H hex echo**. You type a hex number and it echoes it back also with the decimal
  version. This also loads and saves the 'default address' so just entering
  H will read that back to you. Mostly we work in hex but if you want decimal
  prefix it with a . and if decimal is expected and you really want to enter
  the time in hex prefix it with $. Use 'A for the ascii value of A. Don't even
  try the extended 8 bit characters. Also when multiple values are required and
  you want the default one enter # and it takes the default and moves on to the
  next argument.

**R Read a byte of memory**. This takes a full 24 bit address. The 32x16K pages of
  ROM and RAM are all accessible. RAM is from $0000000 to $7fffff so for most
  cases you are worried about $0 to $ffff and get what you expect. If you want
  to access higher pages you can. If you want to read the ROM that goes from
  $800000 to $ffffff

**W Write memory**. This takes a 24 bit address again followed by as many 8 bit
  values as you can get on an 80 character line. Each value is actioned as it
  is read so if you make a mistake on value seven you have already changed the
  first six you typed but will have to redo seven onwards.

**F Fill memory**. This takes a 24 bit address, a 16 bit count and an 8 bit value.
  Try not to overwrite the first $69 bytes. If you overwrite the stack the SP
  gets reset before it shows the prompt so it should survive.

**I Input from a port**. This takes an eight bit port address and gives you
  back hex

**O Output to a port**. This takes an eight bit port address and an eight bit data
  value

**X Execute from this address**. This takes a 16 bit address in the Z80 address map.
  The default is the ROM start up address

**D Dump memory**. This takes a 24 bit address and a 16 bit count that defaults
  to $100 aka 256. This writes up the usual panel of hex and character values
  for the bytes in memory. It does not display ascii <$20 or >$7e as terminals
  can act silly.

**B** Watch this space.

**T Set/read the Real Time Clock**. Use HH:MM:SS and DD/MM/YY or YYYY and it will
  adjust things. It also appends the current tick count for the CTC

**Z** This is just a place I put my current test routine in

**K Kill**. DI HALT. Don't ask why I wanted that...

**C Clear screen** Using an ANSI sequence

**L Leds**. I soldered two LEDs to the spare pins on the RTC port to indicate states.
  This is the manual control L 11 puts them both on. L 00 puts them both off
  Lx1 leaves the first in whatever state it was and changes the second.

**P 7-segment display** I also wired a 7 segment display to the PIO PORT A.
  This just puts up a number letter or anything else I could do in 7 segments.
  0123456789AbCcdEFHhiJLoPtUu[]_=-. It makes a handy journal when bug hunting.

**S Read/write RTC memory**. S address16 R|W. A 16 bit address as
  it needs to be in Z80 reachable memory and use R and W for read or write.

Most of the rest of anything you might need to know is in the code.
I've gone for the ELI5 comment style because at 73 I forget stuff.
Start from bios.asm and go from there.
The RTC clock and the FDC systems are based on reading code from other GitHub
denizens. Credits are in the files.