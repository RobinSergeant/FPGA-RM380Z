# Introduction
This project creates an FPGA clone of the Research Machines 380Z in Verilog using the Digilent Basys 3 development board.  
The Basys 3 includes an AMD (Xilinx) Artix 7 FPGA chip (XC7A35T-1CPG236C), 12-bit VGA output and a USB HID with PS/2 compatible keyboard interface.
The Artix 7 itself provides just enough BRAM for 64K of RAM, the necessary ROM files and one 80K floppy image.

For persistent storage I have used this [SD card PMOD](https://digilent.com/reference/pmod/pmodsd/start) from Digilent.  Their smaller [Micro SD card PMOD](https://digilent.com/reference/pmod/pmodmicrosd/start)
should also work, but I've not tested it.  Alternively, a smaller BRAM ram disk can be configured to boot without an SD card.

[A-Z80](https://github.com/gdevic/A-Z80) created by Goran Devic is used as the Z80 CPU core.

Features:
- Runs original ROM and software (CP/M, RM Basic, Infocom text adventures etc.).
- VDU-80 text based display:
  - Both 40 and 80 column modes, each with 24 rows of text.
  - User defined characters.
  - Character attributes (inverse, dim and underline).
  - Hardware scrolling.
- HRG (High Resolution Graphics):
  - High res mode (4 colours, 320x192).
  - Medium res mode (16 colours, 160x96 with two pages).
  - Upscaled to 640x384 for display (lower 96 pixels are/were only used by the VDU-80).
- Outputs a 60Hz 640x480 VGA signal.
- SIO4 serial port implemented using the on board USB FTDI UART.
  - Intel 8251A compatible SIO module, supporting 8N1 at 9600 baud.
  - Send and receive files using communication software such as Kermit.
- Uses a standard USB keyboard for input (simulating the ASCII keyboard of the 380Z).
- Caps Lock toggles LED on keyboard (which caused me more grief than anything else on this project!).
- Floppy controller providing a FD1771 compatible interface to external SD card or a preloaded 80K BRAM disk image.
  - Both sector reads and writes are implemented.
  - With an SD card all 4 logical drives are available (A:, B:, C: and D:).
  - Without an SD card only drive A: is avaiable.
  - BRAM disk image can only be changed by rebuilding the project and must be bootable.
  - Both SDSC and SDHC card types supported by the SD host controller.
  - Seperate disk activity and disk write LEDs.
- Can be built as a MDS (5.25" floppy) or FDS (8" inch floppy) system.
  - FDS requires an SD card due to the lack of free BRAM.
  - FDS provides nearly 1 megabyte of storage (~250K per logical drive).
- 64K RAM.
- Single step debugging via the 380Z Front Panel (accessed with \<Ctrl\>+F) supported.
  - Requires special hardware to count M1 CPU cycles and trigger Non Maskable Interrupts when enabled.

Here are a couple of photos showing it in action running some SMILE educational games from the early 80s:

<img width="378" height="504" alt="smile" src="https://github.com/user-attachments/assets/e44f1e15-35a2-4cf3-a352-55f69562572b" />
<img width="378" height="504" alt="race" src="https://github.com/user-attachments/assets/645021dd-23a7-4808-9e57-443ce05d9131" />

# Build and setup instructions
## Memory initialization files
For copyright reasons I have not included ROM files in the repository, but they are easy to find online and the same files are used by MAME.  
Obtain the ROM set for COS 4.0/M (to build an MDS system) or COS 4.0/F (for FDS) which should include the following files:
- c-gen-22.bin
- cos40b-m_1c00-1dff.bin (or cos40b-f_1c00-1dff.bin for FDS)
- cos40b-m.bin (or cos40b-f.bin for FDS)
- cos40b-m_f600-f9ff.bin (or cos40b-f_f600-f9ff.bin for FDS)
### combined_roms.mem
Use the included `bin_to_mem.py` tool to combine the 3 cos40 BIN files into a single MEM file with one of the following commands:
```
bin_to_mem.py -o combined_mds.mem cos40b-m.bin cos40b-m_f600-f9ff.bin cos40b-m_1c00-1dff.bin
bin_to_mem.py -o combined_fds.mem cos40b-f.bin cos40b-f_f600-f9ff.bin cos40b-f_1c00-1dff.bin
```
### c-gen-22.mem
Likewise convert the character generator rom with the following command:
```
bin_to_mem.py c-gen-22.bin
```
### 380ZDS6A.mem
This step is not required if using an SD card PMOD and can be skipped in that case.

I've chosen one of the Smile educational disks for the BRAM floppy drive image, but any suitable boot disk in IMD format can be used.  Just
remember to update the .INIT_FILE reference in fd1771.v to match the name of the MEM file created here.
This is a two stage process, with `imdcat` required to create a BIN file from the IMD file, and `bin_to_mem.py` used to produce the final MEM file:
```
imdcat -h 0 -o 380ZDS6A.bin 380ZDS6A.IMD
bin_to_mem.py -m 81920 380ZDS6A.bin
```
NB `imdcat` can be built from source available at the [dumpfloppy repository](https://github.com/johnkw/dumpfloppy).
## Building with Vivavdo
I am using Vivavdo 2025.1, but other editions should also work.  Simply create a new project for the board and import the following:
- All Verilog files from the `src` folder.
- The constraints files from the `constraints` folder.
- The MEM files created in the previous section.
- Necessary files from [A-Z80](https://github.com/gdevic/A-Z80).  See README in repository for further details.

Under project settings define the following optional configuration flags:
- FDS_SUPPORT to build the FDS variant (requires SD_CARD_SUPPORT)
- SD_CARD_SUPPORT to use an external SD card PMOD for persistent storage instead of BRAM.

Then use the Vivado Clocking Wizard to generate the clock_generator IP which should output the following clocks:
- clk_vga (requested: 25.175, actual: 25.17483)
- clk_cpu (requested: 10, actual 10.00000)
## SD card use and preperation
As no FAT filesystem is used care must be taken when writing disk images to the SD card, as specifying the wrong device could **DESTROY** your hard drive!

Firstly use `imdcat` to create raw binary disk images from imd files, e.g.
```
imdcat -c 0:39 -s 1:16 -o zork_demo.bin zork_demo.imd
```
for a 5.25" floppy image (MDS) or:
```
imdcat -c 0:76 -s 1:26 -o zork1.bin zork1.imd
```
for an 8" floppy image.  If the floppy images are single sided, two must be combined to create a double sided disk.  This can be done using the included
`ss_to_ds.py` tool, e.g.
```
ss_to_ds.py -o disk1.bin zork1.bin zork2.bin
```
Once two double sided floppy bin images have been created these can be written to the SD card using the DD tool.  The first image should be written to sector 0,
which overwrites the MBR.  The second should be written at a 512K seek offset (address 524288 in bytes).
```
sudo dd if=disk1.bin of=/dev/{sdcard} bs=512K conv=notrunc,fsync status=progress
sudo dd if=disk2.bin of=/dev/{sdcard} bs=512K seek=1 conv=notrunc,fsync status=progress
```
Use the following command to identify your {sdcard} device string.  In my case it was sdb, but **DO NOT** use this without verifying.
```
lsblk -f
```
All being well you should then be able to boot from drive A: using the 'B' command, or drive B: using 'X'.  The following logical drive mapping applies:
- Disk 1, side 1 -> A:
- Disk 1, side 2 -> C:
- Disk 2, side 1 -> B:
- Disk 2, side 2 -> D:

A solid green LED indicates an SD card initialisation problem (try a different card).  Under normal operation the LED should only illuminate during disk access.
I have tested the SD controller with a variety of SDSC and SDHC cards so please let me know if you encounter a card that does not work.

# TODO
The project is still very much in development and at least the following work remains:
- To improve timing accuracy.  I am currently running the CPU at 10Mhz without wait states, whereas the original machine ran at only 4Mhz with wait states!
- To implement some of the missing port control flags, e.g. to inhibit VDU output while displaying HRG.
- To investigate Vivado warnings.
  
