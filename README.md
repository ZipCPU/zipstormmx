## Zip-Storm, mx

This is a development project for the BlackICE-mx boards

Until the project is known to work, files will be kept in the dev branch.

## Build instructions

To build, you need to first install the ZipCPU toolchain.  The design also
uses AutoFPGA, but you should be able to use it without AutoFPGA

To build:

1. If you are building with AutoFPGA, the first step is to run "make autodata"
   from the main directory.

2. Type "make" in the main directory.  This *should* build everything.  If not,
   you can run "make" in waves

   -- You can either run "make" from with "rt/", or run "make rtl" to lint and Verilate the source code, as well as to build a binary file that can be loaded on the device.

   -- Make in the "sim" directory, or "make sim", should build a simulation program called "main_tb".

   -- Make "sw-host" or in "sw/host" will build a series of programs that can be used to interactt with the design

   -- Make "sw-zlib" or in sw/zlib will build the addendum to the C-library
      necessary for this board

   -- Make "sw-board", or make in sw/board, will build one of two ZipCPU test
      programs: cputest (and cputestcis), as well as the more traditional hello
      world test.  Hello World requires the C-library, whereas the cputest
      can be run stand-alone.

## Running the Simulation

To run the simulation, cd into the "sim" directory and run `main_tb`.  The
simulation can be ended at any time by typing control C.

To run a ZipCPU program in simulation type `main_tb zipcpu_executable`.  The
design comes with two programs, `cputest` and `hello`, that will build in
`sw/board`.  Once built, they can be referenced from the command line of
`main_tb` to run them in simulation.  (The multiply test takes a while to
complete.)  Both programs, upon completion, will end the simulation.

To capture a complete trace of the simulation, use the `-d` flag.  The trace
will be placed into the current directory, and called `trace.vcd`.

You can also interact with the simulation using the software in the `sw/host`
directory as though interacting with the actual hardware.  For example,
`wbregs version` will read the version word from the design.  This word contains
the Year-Month-Day the last time make build the date stamp using `mkdatev.pl`.
You can also use `wbregs buildtime` to find the time associated with the
date stamp as well.

`wbregs spio 0x0c0c` Should turn on the top two LEDs, `wbregs spio 0x0c00` will
turn them off.  `wbregs spio 0x0404` will turn one of them on, and
`wbregs spio 0x808` will turn the other on.  `wbregs spio` will return the value
from the `SPIO` driver (special purpose I/O: buttons, switches, and LEDs).
The low order 8-bits will contain the state of the LEDs.

`wbregs pwrcount` will return an up-counter started at load time.  The top bit,
however, saturates: once set it doesn't clear, so you can at least tell  you've
been around once.

`wbregs bustimer` provides access to set/clear a ZipTimer found on the bus.


`wbregs ram` will read from the block RAM, and `wbregs ram value` will write
`value` to the first address of block RAM.

You can also read from the flash using `wbregs flash`.

The named address in these examples can also be given numerically, using any
format that `strtoul` will accept.

## In Hardware

All of the above `wbregs` tests should work in hardware as well.

The design will depend upon interacting with a debugging channel--currently
using the serial port for that purpose.  To run, run the program `netuart` from
the `sw/host` directory.  You may need to provide the name of the USB/UART
device, as in `netuart /dev/ttyUSB3`.  Once `netuart` is running,
`wbregs` should be able to speak to the device--assuming that the serial port is
working.

If you aren't certain whether or not the serial port is working, then you can
connect to the device via minicom.  If it is working, you should get an
occasional `Z` through the channel from the device every couple of seconds
or so.  If you do not get a `Z` return, check the serial port parameters.
²There should be a `BAUDRATE` defined in [regdefs.h](sw/host/regdefs.h).
After that, the protocol is 8-data bits, 1 stop bit, and no parity.

To run a ZipCPU program, use `zipload`.  `zipload program` will load `program`
into memory, but not start it.  `zipload -r program` will start the program
once loaded.

