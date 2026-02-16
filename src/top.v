/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Top module                                                                   *
 *                                                                              *
 * This module glues all the other modules together and handles the CPU I/O.    *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module top(
  input clk,
  inout PS2Clk,
  inout PS2Data,
  input btnU,
  output [3:0] vgaRed,
  output [3:0] vgaGreen,
  output [3:0] vgaBlue,
  output Hsync,
  output Vsync
);

`include "common.vh"

/********************************************************************************
 *                                                                              *
 * Clock generator and reset                                                    *
 *                                                                              *
 * Vivado Clocking Wizard used to generate clocks:                              *
 *   clk_vga (requested: 25.175, actual: 25.17483)                              *
 *   clk_cpu (requested: 10, actual 10.00000)                                   *
 *                                                                              *
 ********************************************************************************/

wire w_reset_button;

debounce #(.DEBOUNCE_LIMIT(1000000)) debounce_btnU_inst (
.i_clk(clk),
.i_in(btnU),
.o_out(w_reset_button)
);

wire w_clk_vga;
wire w_clk_cpu;
wire w_locked;

clock_generator clock_inst (
  // Clock out ports
  .clk_vga(w_clk_vga),     // output clk_vga
  .clk_cpu(w_clk_cpu),     // output clk_cpu
  // Status and control signals
  .reset(w_reset_button),  // input reset
  .locked(w_locked),       // output locked
 // Clock in ports
  .clk_in1(clk)            // input clk_in
);

wire w_cpu_reset;

xpm_cdc_async_rst #(
  .DEST_SYNC_FF(4),    // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),    // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .RST_ACTIVE_HIGH(0)  // DECIMAL; 0=active low reset, 1=active high reset
)
xpm_cdc_async_rst_inst_cpu (
  .dest_arst(w_cpu_reset), // 1-bit output: src_arst asynchronous reset signal synchronized to destination clock domain. This output is registered.
                           // NOTE: Signal asserts asynchronously but deasserts synchronously to dest_clk. Width of the reset signal is at least
                           // (DEST_SYNC_FF*dest_clk) period.

  .dest_clk(w_clk_cpu),    // 1-bit input: Destination clock.
  .src_arst(w_locked)      // 1-bit input: Source asynchronous reset signal.
);

/********************************************************************************
 *                                                                              *
 * Display and assoicated memory                                                *
 *                                                                              *
 ********************************************************************************/

wire [10:0] w_vram_addra;
wire [11:0] w_chargen_addra;
wire [13:0] w_hrg_addra;
wire [7:0] w_vram_dina;
wire [7:0] w_aram_dina;
wire [7:0] w_chargen_dina;
wire [7:0] w_hrg_dina;
wire [7:0] w_vram_douta;
wire [7:0] w_aram_douta;
wire [7:0] w_chargen_douta;
wire [7:0] w_hrg_douta;
wire w_vram_wea;
wire w_aram_wea;
wire w_chargen_wea;
wire w_hrg_wea;
wire [10:0] w_vram_addrb;
wire [11:0] w_chargen_addrb;
wire [13:0] w_hrg_addrb;
wire [7:0] w_vram_doutb;
wire [7:0] w_aram_doutb;
wire [7:0] w_chargen_doutb;
wire [7:0] w_hrg_doutb;

dual_port_ram #(.DEPTH(1920)) vram_inst (
  .clka(w_clk_cpu),
  .wea(w_vram_wea),
  .addra(w_vram_addra),
  .dina(w_vram_dina),
  .douta(w_vram_douta),
  .clkb(w_clk_vga),
  .addrb(w_vram_addrb),
  .doutb(w_vram_doutb)
);

dual_port_ram #(.DEPTH(1920)) aram_inst (
  .clka(w_clk_cpu),
  .wea(w_aram_wea),
  .addra(w_vram_addra),
  .dina(w_aram_dina),
  .douta(w_aram_douta),
  .clkb(w_clk_vga),
  .addrb(w_vram_addrb),
  .doutb(w_aram_doutb)
);

dual_port_ram #(.DEPTH(4096), .INIT_FILE("c-gen-22.mem")) chargen_inst (
  .clka(w_clk_cpu),
  .wea(w_chargen_wea),
  .addra(w_chargen_addra),
  .dina(w_chargen_dina),
  .douta(w_chargen_douta),
  .clkb(w_clk_vga),
  .addrb(w_chargen_addrb),
  .doutb(w_chargen_doutb)
);

dual_port_ram #(.DEPTH(16384)) hrg_ram_inst (
  .clka(w_clk_cpu),
  .wea(w_hrg_wea),
  .addra(w_hrg_addra),
  .dina(w_hrg_dina),
  .douta(w_hrg_douta),
  .clkb(w_clk_vga),
  .addrb(w_hrg_addrb),
  .doutb(w_hrg_doutb)
);

wire w_mode80_src;
wire w_mode80_dst;
wire w_dst_counter_valid;
wire [4:0] w_counter_dst;
wire w_dst_hrg_port0_valid;
wire [7:0] w_hrg_port0_dst;
wire w_dst_hrg_port1_valid;
wire [7:0] w_hrg_port1_dst;
wire w_hsync;
wire w_vsync;
wire w_hblank;
wire w_vblank;

display display_inst (
  .i_clk(w_clk_vga),
  .i_mode80(w_mode80_dst),
  .i_counter_valid(w_dst_counter_valid),
  .i_hrg_port0_valid(w_dst_hrg_port0_valid),
  .i_hrg_port1_valid(w_dst_hrg_port1_valid),
  .i_counter(w_counter_dst),
  .i_hrg_port0(w_hrg_port0_dst),
  .i_hrg_port1(w_hrg_port1_dst),
  .i_char_code(w_vram_doutb),
  .i_attr_data(w_aram_doutb),
  .i_char_data(w_chargen_doutb),
  .i_hrg_data(w_hrg_doutb),
  .o_vram_addr(w_vram_addrb),
  .o_chargen_addr(w_chargen_addrb),
  .o_hrg_addr(w_hrg_addrb),
  .o_red(vgaRed),
  .o_green(vgaGreen),
  .o_blue(vgaBlue),
  .o_hsync(w_hsync),
  .o_vsync(w_vsync)
);

/********************************************************************************
 *                                                                              *
 * Keyboard and floppy controller                                               *
 *                                                                              *
 ********************************************************************************/

wire [7:0] w_kbd_code;
wire w_key_press;

keyboard keyboard_inst (
  .i_clk(w_clk_cpu),
  .io_ps2_clk(PS2Clk),
  .io_ps2_data(PS2Data),
  .o_ascii_code(w_kbd_code),
  .o_key_press(w_key_press),
  .o_key_release()
);

wire w_fdc_WE;
wire w_fdc_RE;
wire [1:0] w_fdc_A;
wire [7:0] w_fdc_DAL; 

fd1771 fd1771_inst (
  .CLK(w_clk_cpu),
  .WE(w_fdc_WE),
  .RE(w_fdc_RE),
  .A(w_fdc_A),
  .DAL(w_fdc_DAL)
);

/********************************************************************************
 *                                                                              *
 * CPU and RAM/ROM                                                              *
 *                                                                              *
 ********************************************************************************/

wire w_MREQ;
wire w_IORQ;
wire w_RD;
wire w_WR;
wire w_RESET;
wire w_WAIT;
wire w_M1;
wire w_NMI;
wire w_high;

wire [15:0] w_A;
wire [7:0] w_D;
reg [7:0] r_Dout;
reg r_M1 = 1'b1;

z80_top_direct_n z80_instance (
  .nM1(w_M1),
  .nMREQ(w_MREQ),
  .nIORQ(w_IORQ),
  .nRD(w_RD),
  .nWR(w_WR),
  .nRFSH(),
  .nHALT(),
  .nBUSACK(),

  .nWAIT(w_WAIT),
  .nINT(w_high),
  .nNMI(w_NMI),
  .nRESET(w_RESET),
  .nBUSRQ(w_high),

  .CLK(w_clk_cpu),
  .A(w_A),
  .D(w_D)
);

wire [7:0] w_rom_dout;
wire [12:0] w_rom_addr;
reg [12:0] r_rom_addr;

single_port_rom #(.DEPTH(5632), .INIT_FILE("combined_roms.mem")) rom_inst (
  .clka(w_clk_cpu),
  .addra(w_rom_addr),
  .douta(w_rom_dout)
);

wire w_ram_we;
reg r_ram_we;
wire [7:0] w_ram_din;
wire [7:0] w_ram_dout;
wire [15:0] w_ram_addr;
reg [15:0] r_ram_addr;

single_port_ram #(.DEPTH(65536)) ram_inst (
  .clka(w_clk_cpu),
  .wea(w_ram_we),
  .addra(w_ram_addr),
  .dina(w_ram_din),
  .douta(w_ram_dout)
);

/********************************************************************************
 *                                                                              *
 * Clock Domain Crossing shenanigans                                            *
 *                                                                              *
 * The following xpm_cdc macros are used to safely transfer signals and data    *
 * between the CPU and VGA clock domains.                                       *
 *                                                                              *
 ********************************************************************************/

xpm_cdc_single #(
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_INPUT_REG(0)   // DECIMAL; 0=do not register input, 1=register input
)
xpm_cdc_single_mode_inst (
  .dest_out(w_mode80_dst), // 1-bit output: src_in synchronized to the destination clock domain. This output is registered.
  .dest_clk(w_clk_vga), // 1-bit input: Clock signal for the destination clock domain.
  .src_clk(w_clk_cpu),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
  .src_in(w_mode80_src)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
);

xpm_cdc_single #(
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_INPUT_REG(0)   // DECIMAL; 0=do not register input, 1=register input
)
xpm_cdc_single_hsync_inst (
  .dest_out(w_hblank), // 1-bit output: src_in synchronized to the destination clock domain. This output is registered.
  .dest_clk(w_clk_cpu), // 1-bit input: Clock signal for the destination clock domain.
  .src_clk(w_clk_vga),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
  .src_in(w_hsync)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
);

xpm_cdc_single #(
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_INPUT_REG(0)   // DECIMAL; 0=do not register input, 1=register input
)
xpm_cdc_single_vsync_inst (
  .dest_out(w_vblank), // 1-bit output: src_in synchronized to the destination clock domain. This output is registered.
  .dest_clk(w_clk_cpu), // 1-bit input: Clock signal for the destination clock domain.
  .src_clk(w_clk_vga),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
  .src_in(w_vsync)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
);

wire w_counter_src_send;
wire w_counter_src_rcv;
wire [4:0] w_counter_src;
reg r_counter_src_send = 1'b0;

xpm_cdc_handshake #(
  .DEST_EXT_HSK(0),   // DECIMAL; 0=internal handshake, 1=external handshake
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_SYNC_FF(2),    // DECIMAL; range: 2-10
  .WIDTH(5)           // DECIMAL; range: 1-1024
)
xpm_cdc_handshake_counter_inst (
  .dest_out(w_counter_dst), // WIDTH-bit output: Input bus (src_in) synchronized to destination clock domain. This output is registered.
  .dest_req(w_dst_counter_valid), // 1-bit output: Assertion of this signal indicates that new dest_out data has been received and is ready to be used or
                       // captured by the destination logic. When DEST_EXT_HSK = 1, this signal will deassert once the source handshake
                       // acknowledges that the destination clock domain has received the transferred data. When DEST_EXT_HSK = 0, this signal
                       // asserts for one clock period when dest_out bus is valid. This output is registered.

  .src_rcv(w_counter_src_rcv),   // 1-bit output: Acknowledgement from destination logic that src_in has been received. This signal will be deasserted once
                       // destination handshake has fully completed, thus completing a full data transfer. This output is registered.

  .dest_ack(), // 1-bit input: optional; required when DEST_EXT_HSK = 1
  .dest_clk(w_clk_vga), // 1-bit input: Destination clock.
  .src_clk(w_clk_cpu),   // 1-bit input: Source clock.
  .src_in(w_counter_src),     // WIDTH-bit input: Input bus that will be synchronized to the destination clock domain.
  .src_send(w_counter_src_send)  // 1-bit input: Assertion of this signal allows the src_in bus to be synchronized to the destination clock domain. This
                       // signal should only be asserted when src_rcv is deasserted, indicating that the previous data transfer is complete. This
                       // signal should only be deasserted once src_rcv is asserted, acknowledging that the src_in has been received by the
                       // destination logic.
 );

wire w_hrg_port0_src_send;
wire w_hrg_port0_src_rcv;
wire [7:0] w_hrg_port0_src;
reg r_hrg_port0_src_send = 1'b0;

xpm_cdc_handshake #(
  .DEST_EXT_HSK(0),   // DECIMAL; 0=internal handshake, 1=external handshake
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_SYNC_FF(2),    // DECIMAL; range: 2-10
  .WIDTH(8)           // DECIMAL; range: 1-1024
)
xpm_cdc_handshake_port0_inst (
  .dest_out(w_hrg_port0_dst), // WIDTH-bit output: Input bus (src_in) synchronized to destination clock domain. This output is registered.
  .dest_req(w_dst_hrg_port0_valid), // 1-bit output: Assertion of this signal indicates that new dest_out data has been received and is ready to be used or
                       // captured by the destination logic. When DEST_EXT_HSK = 1, this signal will deassert once the source handshake
                       // acknowledges that the destination clock domain has received the transferred data. When DEST_EXT_HSK = 0, this signal
                       // asserts for one clock period when dest_out bus is valid. This output is registered.

  .src_rcv(w_hrg_port0_src_rcv),   // 1-bit output: Acknowledgement from destination logic that src_in has been received. This signal will be deasserted once
                       // destination handshake has fully completed, thus completing a full data transfer. This output is registered.

  .dest_ack(), // 1-bit input: optional; required when DEST_EXT_HSK = 1
  .dest_clk(w_clk_vga), // 1-bit input: Destination clock.
  .src_clk(w_clk_cpu),   // 1-bit input: Source clock.
  .src_in(w_hrg_port0_src),     // WIDTH-bit input: Input bus that will be synchronized to the destination clock domain.
  .src_send(w_hrg_port0_src_send)  // 1-bit input: Assertion of this signal allows the src_in bus to be synchronized to the destination clock domain. This
                       // signal should only be asserted when src_rcv is deasserted, indicating that the previous data transfer is complete. This
                       // signal should only be deasserted once src_rcv is asserted, acknowledging that the src_in has been received by the
                       // destination logic.
 );

wire w_hrg_port1_src_send;
wire w_hrg_port1_src_rcv;
wire [7:0] w_hrg_port1_src;
reg r_hrg_port1_src_send = 1'b0;

xpm_cdc_handshake #(
  .DEST_EXT_HSK(0),   // DECIMAL; 0=internal handshake, 1=external handshake
  .DEST_SYNC_FF(2),   // DECIMAL; range: 2-10
  .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .SRC_SYNC_FF(2),    // DECIMAL; range: 2-10
  .WIDTH(8)           // DECIMAL; range: 1-1024
)
xpm_cdc_handshake_port1_inst (
  .dest_out(w_hrg_port1_dst), // WIDTH-bit output: Input bus (src_in) synchronized to destination clock domain. This output is registered.
  .dest_req(w_dst_hrg_port1_valid), // 1-bit output: Assertion of this signal indicates that new dest_out data has been received and is ready to be used or
                       // captured by the destination logic. When DEST_EXT_HSK = 1, this signal will deassert once the source handshake
                       // acknowledges that the destination clock domain has received the transferred data. When DEST_EXT_HSK = 0, this signal
                       // asserts for one clock period when dest_out bus is valid. This output is registered.

  .src_rcv(w_hrg_port1_src_rcv),   // 1-bit output: Acknowledgement from destination logic that src_in has been received. This signal will be deasserted once
                       // destination handshake has fully completed, thus completing a full data transfer. This output is registered.

  .dest_ack(), // 1-bit input: optional; required when DEST_EXT_HSK = 1
  .dest_clk(w_clk_vga), // 1-bit input: Destination clock.
  .src_clk(w_clk_cpu),   // 1-bit input: Source clock.
  .src_in(w_hrg_port1_src),     // WIDTH-bit input: Input bus that will be synchronized to the destination clock domain.
  .src_send(w_hrg_port1_src_send)  // 1-bit input: Assertion of this signal allows the src_in bus to be synchronized to the destination clock domain. This
                       // signal should only be asserted when src_rcv is deasserted, indicating that the previous data transfer is complete. This
                       // signal should only be deasserted once src_rcv is asserted, acknowledging that the src_in has been received by the
                       // destination logic.
 );

/********************************************************************************
 *                                                                              *
 * Handle writes to memory mapped ports                                         *
 *                                                                              *
 ********************************************************************************/

reg [7:0] r_port0 = 0;
reg [7:0] r_hrg_port0 = 0;
reg [7:0] r_hrg_port0_out = 0;
reg [7:0] r_hrg_port1 = 0;
reg [7:0] r_hrg_port1_out = 0;
reg [4:0] r_counter = 0;
reg [4:0] r_counter_out = 0;
reg [3:0] r_nmi_counter = 0;
reg [3:0] r_row_latch = 0;
reg [7:0] r_char_latch = 0;
reg r_key_ready = 1'b0;

always @(posedge w_clk_cpu or negedge w_cpu_reset) begin
  if (w_cpu_reset == 1'b0) begin
    r_port0 <= 0;
    r_hrg_port0 <= 0;
    r_counter <= 0;
    r_nmi_counter <= 0;
    r_key_ready <= 1'b0;
  end else begin
    if ((w_MREQ == 1'b0) && (w_WR == 1'b0) && ((w_A[15:8] == 8'hFB) || ((w_A[15:8] == 8'h1B) && ! r_port0[7]))) begin
      case (w_A[7:0])
        8'h00: begin
          r_hrg_port0 <= w_D;
        end
        8'h01: begin
          r_hrg_port1 <= w_D;
        end
        8'hFC: begin
          if (!w_D[0]) begin
            r_key_ready <= 1'b0;
          end
          if (w_D[1]) begin
            r_nmi_counter <= 0;
          end
          r_port0 <= w_D;
        end
        8'hFD: begin
          if (!r_port0[4] && !r_port0[3]) begin
            r_counter <= w_D[4:0];
          end
        end
        8'hFE: begin
          if (r_port0[3])
            r_char_latch <= w_D;
          else
            r_row_latch <= w_D;
        end
      endcase
    end
  
    if (w_key_press) begin
      r_key_ready <= 1'b1;
    end
  
    if (w_counter_src_rcv) begin
      r_counter_src_send <= 1'b0;
    end else if (!r_counter_src_send && (r_counter != r_counter_out)) begin
      r_counter_out <= r_counter;
      r_counter_src_send <= 1'b1;
    end
 
    if (w_hrg_port0_src_rcv) begin
      r_hrg_port0_src_send <= 1'b0;
    end else if (!r_hrg_port0_src_send && (r_hrg_port0 != r_hrg_port0_out)) begin
      r_hrg_port0_out <= r_hrg_port0;
      r_hrg_port0_src_send <= 1'b1;
    end

    if (w_hrg_port1_src_rcv) begin
      r_hrg_port1_src_send <= 1'b0;
    end else if (!r_hrg_port1_src_send && (r_hrg_port1 != r_hrg_port1_out)) begin
      r_hrg_port1_out <= r_hrg_port1;
      r_hrg_port1_src_send <= 1'b1;
    end
  
    if (!r_port0[1] && !w_M1 && r_M1) begin
      r_nmi_counter <= r_nmi_counter + 1;
    end
  
    r_M1 <= w_M1;
  end
end

/********************************************************************************
 *                                                                              *
 * Implement memory map and port reads                                          *
 *                                                                              *
 ********************************************************************************/

always @(*) begin
  r_Dout = w_rom_dout;
  r_rom_addr = w_A;
  r_ram_addr = w_A;
  r_ram_we = 1'b0;

  if (w_IORQ == 1'b0) begin
    if ((w_A[7:0] >= 8'hC0) && (w_A[7:0] <= 8'hC3)) begin
      r_Dout = w_fdc_DAL;
    end else begin
      r_Dout = 8'hFF;
    end
  end else begin
    if ((w_A[15:8] == 8'hFB) || ((w_A[15:8] == 8'h1B) && !r_port0[7])) begin
      case (w_A[7:0])
        8'h00: r_Dout = {{6{1'b1}}, ~w_hblank, ~w_vblank};
        8'hFC: r_Dout = w_kbd_code;
        8'hFD: r_Dout = w_chargen_douta;
        8'hFE: r_Dout = {w_hblank, w_vblank, {5{1'b0}}, r_key_ready};
        default: r_Dout = 0;
      endcase
    end else if ((w_A >= 16'hF000) && (w_A <= 16'hF5FF)) begin
      r_Dout = r_hrg_port0[2] ? w_hrg_douta : r_port0[6] ? w_aram_douta : w_vram_douta;
    end else if ((w_A >= 16'hE000) && (w_A < 16'hF000)) begin
      r_rom_addr = w_A[11:0];
    end else if ((w_A >= 16'hF600) && (w_A < 16'hFA00)) begin
      r_rom_addr = {w_A[12], 2'b00, w_A[11], w_A[8:0]}; // starting offset 0x1000
    end else if (w_A >= 16'hFC00) begin
      r_ram_we = 1'b1;
      r_Dout = w_ram_dout;
    end else if (!r_port0[7]) begin
      if ((w_A >= 16'h4000) && (w_A < 16'h8000)) begin
        r_ram_addr = w_A[13:0];
        r_ram_we = 1'b1;
        r_Dout = w_ram_dout;
      end else if ((w_A >= 16'h1C00) && (w_A < 16'h1E00)) begin
        r_rom_addr = {w_A[12], 1'b0, w_A[10:0]}; // starting offset 0x1400
      end
    end else if ((w_A >= 16'h0000) && (w_A < 16'hE000)) begin
      r_ram_we = 1'b1;
      r_Dout = w_ram_dout;
    end
  end
end

wire [4:0] w_vram_row;
assign w_vram_row = r_port0[5] ? {r_row_latch, w_A[7]} : w_A[10:6];
wire [6:0] w_vram_col;
assign w_vram_col = r_port0[5] ? w_A[6:0] : w_A[5:0];
assign w_vram_addra = vram_address(w_vram_row, w_vram_col, r_counter);
assign w_vram_dina = w_D;
assign w_aram_dina = r_port0[6] ? w_D : 0;
assign w_aram_wea = (w_MREQ == 1'b0) && (w_WR == 1'b0) && (w_A >= 16'hF000) && (w_A <= 16'hF5FF) && !r_hrg_port0[2];
assign w_vram_wea = w_aram_wea && !r_port0[6];

assign w_hrg_addra = (r_hrg_port1[3:0] < 12) ? (r_hrg_port1[3:0] * 1280 + w_A[10:0]) : (r_hrg_port1[1:0] * 256 + w_A[7:0] + 15360);
assign w_hrg_dina = w_D;
assign w_hrg_wea = (w_MREQ == 1'b0) && (w_WR == 1'b0) && (w_A >= 16'hF000) && (w_A <= 16'hF5FF) && r_hrg_port0[2];

assign w_chargen_addra = (r_char_latch << 4) | r_row_latch;
assign w_chargen_dina = w_D;
assign w_chargen_wea = (w_MREQ == 1'b0) && (w_WR == 1'b0) && r_port0[3] && r_char_latch[7] && (w_A == 16'hFBFD);

assign w_mode80_src = r_port0[5];
assign w_counter_src = r_counter_out;
assign w_counter_src_send = r_counter_src_send;
assign w_hrg_port0_src = r_hrg_port0_out;
assign w_hrg_port0_src_send = r_hrg_port0_src_send;
assign w_hrg_port1_src = r_hrg_port1_out;
assign w_hrg_port1_src_send = r_hrg_port1_src_send;

assign w_rom_addr = r_rom_addr;
assign w_ram_addr = r_ram_addr;
assign w_ram_we = r_ram_we && (w_MREQ == 1'b0) && (w_WR == 1'b0);
assign w_ram_din = w_D;

assign w_high = 1'b1;
assign w_RESET = w_cpu_reset;
assign w_WAIT = 1'b1;
assign w_NMI = ~r_nmi_counter[3];
assign w_D = (w_RD == 1'b0) ? r_Dout : {8{1'bz}};

assign Hsync = w_hsync;
assign Vsync = w_vsync;

assign w_fdc_WE = ~((w_IORQ == 1'b0) && (w_WR == 1'b0) && (w_A[7:0] >= 8'hC0) && (w_A[7:0] <= 8'hC3));
assign w_fdc_RE = ~((w_IORQ == 1'b0) && (w_RD == 1'b0) && (w_A[7:0] >= 8'hC0) && (w_A[7:0] <= 8'hC3));
assign w_fdc_A = w_A[1:0];
assign w_fdc_DAL = (w_RD == 1'b1) ? w_D : {8{1'bz}}; 

endmodule
