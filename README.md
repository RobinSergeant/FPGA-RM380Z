# Introduction
This project creates an FPGA clone of the Research Machines 380Z in Verilog using the Digilent Basys 3 development board.  
The Basys 3 includes an AMD (Xilinx) Artix 7 FPGA chip (XC7A35T-1CPG236C), 12-bit VGA output and a USB HID with PS/2 compatible keyboard interface.
The Artix 7 itself provides just enough BRAM for 64K of RAM, the necessary ROM files and one 80K floppy image.

[A-Z80](https://github.com/gdevic/A-Z80) created by Goran Devic is used as the Z80 CPU core.

Features:
- Runs original ROM and software (CP/M, RM Basic, Infocom text adventures etc.).
- VDU-80 text based display:
  - Both 40 and 80 column modes, each with 24 rows of text.
  - User defined characters.
  - Character attributes (inverse, dim and underline).
  - Hardware scrolling.
- HRG (High Resolution Graphis):
  - High res mode (4 colours, 320x192).
  - Medium res mode (16 colours, 160x96 with two pages).
  - Upscaled to 640x384 for display (lower 96 pixels are/were only used by the VDU-80).
- Outputs a 60Hz 640x480 VGA signal.
- Uses a standard USB keyboard for input (simulating the ASCII keyboard of the 380Z).
- Caps Lock toggles LED on keyboard (which caused me more grief than anything else on this project!).
- Floppy controller providing a FD1771 compatible interface to a preloaded single sided, single density, 80K BRAM disk image.
  - Both sector reads and writes are implemented, allowing data to be overwritten if desired.
  - This disk image maps to the A: drive in CP/M as RM used A: for the first side of a floppy, and C: for the second.
  - Disk image can only be changed by rebuilding the project and must be bootable.
- 64K RAM.
- Single step debugging via the 380Z Front Panel (accessed with \<Ctrl\>+F) supported.
  - Requires special hardware to count M1 CPU cycles and trigger Non Maskable Interrupts when enabled.

Here are a couple of photos showing it in action running some SMILE educational games from the early 80s:

<img width="378" height="504" alt="smile" src="https://github.com/user-attachments/assets/e44f1e15-35a2-4cf3-a352-55f69562572b" />
<img width="378" height="504" alt="race" src="https://github.com/user-attachments/assets/645021dd-23a7-4808-9e57-443ce05d9131" />

# Build and setup instructions
## Memory initialization files
For copyright reasons I have not included ROM files in the repository, but they are easy to find online and the same files are used by MAME.  
Obtain the ROM set for COS 4.0/M which should include the following files:
- c-gen-22.bin
- cos40b-m_1c00-1dff.bin
- cos40b-m.bin
- cos40b-m_f600-f9ff.bin
### combined_roms.mem
Use the included `bin_to_mem.py` tool to combine the 3 cos40 BIN files into a single MEM file with the following command:
```
bin_to_mem.py -o combined_roms.mem cos40b-m.bin cos40b-m_f600-f9ff.bin cos40b-m_1c00-1dff.bin
```
### c-gen-22.mem
Likewise convert the character generator rom with the following command:
```
bin_to_mem.py c-gen-22.bin
```
### 380ZDS6A.mem
I've chosen one of the Smile educational disks for the floppy drive image, but any suitable boot disk in IMD format can be used.  Just
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

Then use the Vivado Clocking Wizard to generate the clock_generator IP which should output the following clocks:
- clk_vga (requested: 25.175, actual: 25.17483)
- clk_cpu (requested: 10, actual 10.00000)
# TODO
The project is still very much in development and at least the following work remains:
- To improve the floppy controller so that it uses an SD card or SPI flash memory to remove the fixed floppy disk image restriction.
- To improve timing accuracy.  I am currently running the CPU at 10Mhz without wait states, whereas the original machine ran at only 4Mhz with wait states!
- To implement some of the missing port control flags, e.g. to inhibit VDU output while displaying HRG.
- To investigate Vivado warnings.
  
