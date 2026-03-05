/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * FD1771 Floppy Controller                                                     *
 *                                                                              *
 * This module implements a subset of the Western Digital FD1771 interface,     *
 * providing only the signals and commands used by the 380Z ROM routines.       *
 *                                                                              *
 * The data bus (DAL) is inverted and bidirectional as per the original         *
 * datasheet.  The WE (write enable) and RE (read enable) signals are active    *
 * low.                                                                         *
 *                                                                              *
 * When SD_CARD_SUPPORT is defined a connected SD card PMOD is used for         *
 * storage.  Otherwise an 80K BRAM is used, which is preloaded with raw data    *
 * from the first side of an SD boot disk.  The disk image cannot be changed    *
 * after synthesis, but sectors may be overwritten.                             *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module fd1771(
  input CLK,
`ifdef SD_CARD_SUPPORT
  input i_miso,
  input i_cd,
  output o_mosi,
  output o_cs,
  output o_sck,
  output [15:0] o_led,
`endif
  input WE,
  input RE,
  input [1:0] A,
  inout [7:0] DAL
);

`ifdef SD_CARD_SUPPORT

wire w_sd_read;
wire w_sd_write;
wire w_sd_data_req;
wire w_sd_data_ack;
wire w_sd_op_complete;
wire [7:0] w_sd_dout;
wire [7:0] w_sd_din;
wire [31:0] w_sd_address;

sd_card sd_card_inst (
  .i_clk(CLK),
  .i_miso(i_miso),
  .i_cd(i_cd),
  .i_read(w_sd_read),
  .i_write(w_sd_write),
  .i_data_ack(w_sd_data_ack),
  .i_address(w_sd_address),
  .i_din(w_sd_din),
  .o_data_req(w_sd_data_req),
  .o_op_complete(w_sd_op_complete),
  .o_mosi(o_mosi),
  .o_cs(o_cs),
  .o_sck(o_sck),
  .o_dout(w_sd_dout),
  .o_led(o_led)
);

`else

wire [16:0] w_floppy_addr;
wire [7:0] w_floppy_din;
wire [7:0] w_floppy_dout;
wire w_floppy_we;

single_port_ram #(.DEPTH(81920), .INIT_FILE("380ZDS6A.mem")) fake_floppy_inst (
  .clka(CLK),
  .wea(w_floppy_we),
  .addra(w_floppy_addr),
  .dina(w_floppy_din),
  .douta(w_floppy_dout)
);

`endif

// register addresses (A)
localparam STATUS_REGISTER  = 2'b00;
localparam COMMAND_REGISTER = 2'b00;
localparam TRACK_REGISTER   = 2'b01;
localparam SECTOR_REGISTER  = 2'b10;
localparam DATA_REGISTER    = 2'b11;

// commands
localparam RESTORE          = 4'b0000;
localparam SEEK             = 4'b0001;
localparam STEP_IN          = 4'b0101;
localparam READ_SECTOR      = 4'b1000;
localparam WRITE_SECTOR     = 4'b1010;
localparam FORCE_INTERRUPT  = 4'b1101;

// status bit indexes
localparam NOT_READY    = 7;
localparam DATA_REQUEST = 1;
localparam BUSY         = 0;

reg [7:0] r_data = 0;
reg [7:0] r_track = 0;
reg [7:0] r_sector = 0;
reg [3:0] r_command = 0;
reg [7:0] r_status = 1'b1 << NOT_READY;

reg r_RE = 1'b1;
reg r_WE = 1'b1;
reg [7:0] r_DALout;

`ifdef SD_CARD_SUPPORT
reg r_sd_read = 1'b0;
reg r_sd_write = 1'b0;
reg r_sd_data_ack = 1'b0;
`else
reg [7:0] r_offset = 0;
reg r_floppy_we = 1'b0;
`endif

always @(posedge CLK) begin
`ifdef SD_CARD_SUPPORT
  r_sd_read <= 1'b0;
  r_sd_write <= 1'b0;
  r_sd_data_ack <= 1'b0;
`endif

  if ((WE == 1'b0) && (r_WE == 1'b1)) begin
    case (A)
      COMMAND_REGISTER: begin
        r_command <= ~DAL[7:4];

        case (~DAL[7:4])
          RESTORE: begin
            r_status[NOT_READY] <= 1'b0;
            r_track <= 0;
          end

          SEEK: begin
            r_track <= r_data;
          end

          STEP_IN: begin
            r_track <= r_track + 1;
          end

`ifdef SD_CARD_SUPPORT
          READ_SECTOR: begin
            r_status[BUSY] <= 1'b1;
            r_sd_read <= 1'b1;
          end

          WRITE_SECTOR: begin
            r_status[BUSY] <= 1'b1;
            r_sd_write <= 1'b1;
          end
`else
          READ_SECTOR, WRITE_SECTOR: begin
            r_status[BUSY] <= 1'b1;
            r_status[DATA_REQUEST] <= 1'b1;
            r_offset <= 0;
          end
`endif

          FORCE_INTERRUPT: begin  // force interrupt (reset)
            r_status[BUSY] <= 1'b0;
          end
        endcase
      end

      TRACK_REGISTER: begin
        r_track <= ~DAL;
      end

      SECTOR_REGISTER: begin
        r_sector <= ~DAL;
      end

      DATA_REGISTER: begin
        r_data <= ~DAL;
        if ((r_command == WRITE_SECTOR) &&
            (r_status[BUSY] == 1'b1))
        begin
`ifdef SD_CARD_SUPPORT
          r_sd_data_ack <= 1'b1;
`else
          r_floppy_we = 1'b1;
`endif
        end
      end
    endcase
  end

  if ((RE == 1'b0) && 
      (r_RE == 1'b1) &&
      (A == DATA_REGISTER) &&
      (r_command == READ_SECTOR) &&
      (r_status[BUSY] == 1'b1))
  begin
`ifdef SD_CARD_SUPPORT
    r_data <= w_sd_dout;
    r_sd_data_ack <= 1'b1;
`else
    r_data <= w_floppy_dout;
 
    if (r_offset < 127) begin
      r_offset <= r_offset + 1;
    end else begin
      // last byte of sector now returned so finished
      r_status[BUSY] <= 1'b0;
      r_status[DATA_REQUEST] <= 1'b0;
    end
`endif
  end

`ifndef SD_CARD_SUPPORT
  if (r_floppy_we && (WE == 1'b1)) begin
    r_floppy_we = 1'b0;
    if (r_offset < 127) begin
      r_offset <= r_offset + 1;
    end else begin
      // last byte of sector now written so finished
      r_status[BUSY] <= 1'b0;
      r_status[DATA_REQUEST] <= 1'b0;
    end 
  end
`endif

`ifdef SD_CARD_SUPPORT
  r_status[DATA_REQUEST] <= w_sd_data_req;

  if (w_sd_op_complete) begin
    r_status[BUSY] <= 1'b0;
  end
`endif

  r_RE <= RE;
  r_WE <= WE;
end

always @(*) begin
  case (A)
    STATUS_REGISTER: r_DALout = r_status;
    TRACK_REGISTER:  r_DALout = r_track;
    SECTOR_REGISTER: r_DALout = r_sector;
    DATA_REGISTER:   r_DALout = r_data;
  endcase 
end

`ifdef SD_CARD_SUPPORT
// 2048 byte tracks (0-39), 128 byte sectors (1-16)
assign w_sd_address = (r_track << 11) + ((r_sector - 1) << 7);
assign w_sd_din = r_data;
assign w_sd_read = r_sd_read;
assign w_sd_write = r_sd_write;
assign w_sd_data_ack = r_sd_data_ack;
`else
// 2048 byte tracks (0-39), 128 byte sectors (1-16)
assign w_floppy_addr = (r_track << 11) + ((r_sector - 1) << 7) + r_offset;
assign w_floppy_we = r_floppy_we;
assign w_floppy_din = r_data;
`endif

assign DAL = (RE == 1'b0) ? ~r_DALout : {8{1'bz}};

endmodule
