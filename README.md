# FPGA-RM380Z
## Introduction
This project creates an FPGA clone of the Research Machines 380Z in Verilog using the Digilent Basys 3 development board.  
The Basys 3 includes an AMD (Xilinx) Artix 7 FPGA chip (XC7A35T-1CPG236C), 12-bit VGA output and a USB HID with PS/2 compatible keyboard interface.
The Artix 7 itelf provides just enough BRAM for 64K of RAM, the necessary ROM files and one 80K floppy image.

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
  - This disk images maps to the A: drive in CP/M as RM used A: for the first side of a floppy, and C: for the second.
  - Disk image can only be changed by rebuilding the project and must be bootable.
- 64K RAM.
- Single step debugging via the 380Z Front Panel (accessed with Ctrl+F) supported.
  - Requires special hardware to count M1 CPU cycles and trigger Non Maskable Interrupts when enabled.

Here are a couple of photos showing it in action running some SMILE educational games from the early 80s:

<img width="378" height="504" alt="smile" src="https://github.com/user-attachments/assets/e44f1e15-35a2-4cf3-a352-55f69562572b" />
<img width="378" height="504" alt="race" src="https://github.com/user-attachments/assets/645021dd-23a7-4808-9e57-443ce05d9131" />

## Build and setup instructions
### Memory 
