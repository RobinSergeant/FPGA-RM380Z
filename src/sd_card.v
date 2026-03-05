/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * SD card host controller                                                      *
 *                                                                              *
 * This module provides the SD card host controller.  It is responsible for     *
 * initializing the card, and provides an interface for reading from and        *
 * writing to it.                                                               *
 *                                                                              *
 * Only older SDSC cards are currently supported as later cards have a fixed    *
 * 512K block size, which does not map nicely to the 380Z's 128K sector size.   *
 *                                                                              *
 * Hence, for simplicity SET_BLOCKLEN is used to reduce the block size to 128K. *
 * By doing this we don't have the to read and write 4 sectors at a time!       *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module sd_card(
  input i_clk,
  input i_miso,
  input i_cd,
  input i_read,
  input i_write,
  input i_data_ack,
  input [31:0] i_address,
  input [7:0] i_din,
  output reg o_data_req,
  output reg o_op_complete,
  output reg o_mosi,
  output reg o_cs,
  output o_sck,
  output [7:0] o_dout,
  output [15:0] o_led
);

wire w_ram_we;
reg r_ram_we = 1'b0;
wire [7:0] w_ram_din;
wire [7:0] w_ram_dout;
wire [8:0] w_ram_addr;
reg [8:0] r_ram_addr;

single_port_ram #(.DEPTH(512)) block_cache (
  .clka(i_clk),
  .wea(w_ram_we),
  .addra(w_ram_addr),
  .dina(w_ram_din),
  .douta(w_ram_dout)
);

localparam CMD0   = {2'b01, 6'd00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h95};  // GO_IDLE_STATE
localparam CMD8   = {2'b01, 6'd08, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h87};  // SEND_IF_COND
localparam CMD17  = {2'b01, 6'd17, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // READ_SINGLE_BLOCK
localparam CMD24  = {2'b01, 6'd24, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // WRITE_BLOCK
localparam CMD55  = {2'b01, 6'd55, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // APP_CMD
localparam ACMD41 = {2'b01, 6'd41, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // SD_SEND_OP_COND

localparam STATE_INIT   = 4'b0000;  // init states
localparam STATE_CMD0   = 4'b0001;
localparam STATE_CMD8   = 4'b0010;  
localparam STATE_CMD55  = 4'b0011;
localparam STATE_ACMD41 = 4'b0100;

localparam STATE_CMD17  = 4'b0110;  // block read states
localparam STATE_RBDATA = 4'b0111;
localparam STATE_RBCRC  = 4'b1000;
localparam STATE_CMD24  = 4'b1001;  // block write states
localparam STATE_WBDATA = 4'b1010;
localparam STATE_WBDRT  = 4'b1011;
localparam STATE_WBBUSY = 4'b1100;
localparam STATE_IDLE   = 4'b1111;

reg [4:0] r_ClkCounter = 0;
reg r_PrevClkBit = 0;

wire w_ClkBit;
wire w_RisingEdge;
wire w_FallingEdge;

always @(posedge i_clk) begin
  r_PrevClkBit <= w_ClkBit;
  r_ClkCounter <= r_ClkCounter + 1;
end

// At 10MHz: 10,000,000 / 2^5 (32) = 312.5 kHz
assign w_ClkBit = r_ClkCounter[4];
assign w_RisingEdge = (~r_PrevClkBit & w_ClkBit);
assign w_FallingEdge = (r_PrevClkBit & ~w_ClkBit);

reg r_ReadyToSend = 1'b0;

reg [3:0] r_State = STATE_INIT;
reg [47:0] r_Command = {48{1'b1}};
reg [7:0] r_ResponseByte = 8'h00;
reg [7:0] r_ReceivedByte = 8'h01;
reg [7:0] r_DataByte = 8'h00;
reg [7:0] t_ReceivedByte;
reg [9:0] r_BytesExpected = 10; // stay in INIT state for 80 clocks
reg [22:0] r_BlockNumber;
reg r_BlockValid = 1'b0;
reg r_WriteOp = 1'b0;
reg r_cs = 1'b1;

always @(posedge i_clk) begin
  o_op_complete <= 1'b0;

  if (w_FallingEdge) begin
    o_cs <= r_cs;
    if (r_ReadyToSend) begin
      o_mosi <= r_Command[47];
      r_Command <= {r_Command[46:0], 1'b1};
    end
  end

  if (w_RisingEdge) begin
    t_ReceivedByte = {r_ReceivedByte[6:0], i_miso};
    if (r_ReceivedByte[7]) begin
      // complete byte received from device
      r_ReceivedByte <= 8'h01;

      if (r_BytesExpected > 0) begin
        // consume payload bytes (following R1)
        r_BytesExpected <= r_BytesExpected - 1;

        case (r_State)
          STATE_INIT: begin
            if (r_BytesExpected == 1) begin
              r_Command <= CMD0;
              r_State <= STATE_CMD0;
            end
          end

          STATE_CMD17: begin
            if (t_ReceivedByte == 8'hFF) begin
              // keep waiting if card is busy
              r_BytesExpected <= 1;
            end else if (t_ReceivedByte == 8'hFE) begin
              r_State <= STATE_RBDATA;
              r_BytesExpected <= 512;
              r_ram_addr <= 511;
            end
          end

          STATE_RBDATA: begin
            r_ram_addr <= r_ram_addr + 1;
            r_DataByte <= t_ReceivedByte;
            r_ram_we <= 1'b1;
            if (r_BytesExpected == 1) begin
              r_State <= STATE_RBCRC;
              r_BytesExpected <= 2;
            end
          end

          STATE_RBCRC: begin
            r_ram_we <= 1'b0;
            if (r_BytesExpected == 1) begin
              r_BlockValid <= ~r_WriteOp;
              r_BlockNumber <= i_address[31:9];
              r_ram_addr <= i_address[8:0];
              r_ram_we <= r_WriteOp;
              o_data_req <= 1'b1;
              r_State <= STATE_IDLE;
            end
          end

          STATE_CMD24: begin
            if (r_BytesExpected == 1) begin
              r_State <= STATE_WBDATA;
              r_BytesExpected <= 512;
              r_Command[47:40] <= w_ram_dout;
              r_ram_addr <= r_ram_addr + 1;
            end
          end

          STATE_WBDATA: begin
            if (r_BytesExpected > 1) begin
              r_Command[47:40] <= w_ram_dout;
              r_ram_addr <= r_ram_addr + 1;
            end else begin
              r_State <= STATE_WBDRT;
              r_BytesExpected <= 1;
            end
          end

          STATE_WBDRT: begin
            if (t_ReceivedByte[4:0] == 5'b00101) begin
              // data response token received
              r_State <= STATE_WBBUSY;
              r_ReadyToSend <= 1'b0;
            end
            r_BytesExpected <= 1;
          end

          STATE_WBBUSY: begin
            if (t_ReceivedByte == 8'h00) begin
              // flash programming started
              r_State <= STATE_IDLE;
            end
            r_BytesExpected <= 1;
          end

          STATE_IDLE: begin
            if (t_ReceivedByte == 8'hFF) begin
              // flash programming complete
              o_op_complete <= 1'b1;
            end else begin
              r_BytesExpected <= 1;
            end
          end
        endcase
      end else if (t_ReceivedByte[7] == 1'b0) begin
        // process R1 command response
        r_ReadyToSend <= 1'b0;
        r_ResponseByte <= t_ReceivedByte;

        case (r_State)
          STATE_CMD0: begin
            if (t_ReceivedByte == 8'h01) begin
              r_Command <= CMD8;
              r_State <= STATE_CMD8;
            end 
          end

          STATE_CMD8: begin
            if (t_ReceivedByte == 8'h01) begin
              r_BytesExpected <= 4;
              r_Command <= CMD55;
              r_State <= STATE_CMD55;
            end
          end

          STATE_CMD55: begin
            if (t_ReceivedByte == 8'h01) begin
              r_Command <= ACMD41;
              r_State <= STATE_ACMD41;
            end
          end

          STATE_ACMD41: begin
            if (t_ReceivedByte == 8'h01) begin
              // repeat command until card is idle
              r_Command <= CMD55;
              r_State <= STATE_CMD55;
            end else if (t_ReceivedByte == 8'h00) begin
              // card ready
              r_State <= STATE_IDLE;
            end
          end

          STATE_CMD17: begin
            if (t_ReceivedByte == 8'h00) begin
              r_BytesExpected <= 1;
            end
          end

          STATE_CMD24: begin
            if (t_ReceivedByte == 8'h00) begin
              // send dummy byte followed by start block token
              r_Command[47:32] <= {8'hFF, 8'hFE};
              r_BytesExpected <= 2;
              r_ReadyToSend <= 1'b1;
            end
          end
        endcase
      end else if (t_ReceivedByte == 8'hFF) begin
        if (!r_Command[47]) begin
          r_ReadyToSend <= 1'b1;
          r_cs <= 1'b0;
        end
        if (r_State == STATE_IDLE)
          r_cs <= 1'b1;
      end
    end else begin
      r_ReceivedByte <= t_ReceivedByte;
    end
  end

  if (i_read || i_write) begin
    r_WriteOp <= i_write;
    if (r_BlockValid && (r_BlockNumber == i_address[31:9])) begin
      // block already in cache
      r_BlockValid <= i_read;
      r_ram_addr <= i_address[8:0];
      r_ram_we <= i_write;
      o_data_req <= 1'b1;
    end else begin
      // read block
      r_Command <= {CMD17[47:40], i_address[31:9], {9{1'b0}}, CMD17[7:0]};
      r_State <= STATE_CMD17;
    end
  end

  if (i_data_ack) begin
    r_ram_addr <= r_ram_addr + 1;
    if (&r_ram_addr[6:0]) begin
      o_data_req <= 1'b0;
      if (r_WriteOp) begin
        r_ram_addr <= 0;
        r_ram_we <= 1'b0;
        r_Command <= {CMD24[47:40], i_address[31:9], {9{1'b0}}, CMD24[7:0]};
        r_State <= STATE_CMD24;
      end else begin
        o_op_complete <= 1'b1;
      end
    end
  end
end

assign w_ram_we = r_ram_we;
assign w_ram_addr = r_ram_addr;
assign w_ram_din = o_data_req ? i_din : r_DataByte;

assign o_sck = w_ClkBit;

assign o_dout = w_ram_dout;

assign o_led[15] = ~i_cd;
assign o_led[14:11] = r_State;
assign o_led[10:8] = 1'b0;
assign o_led[7:0] = r_ResponseByte;

initial begin
  o_mosi = 1'b1;
  o_cs = 1'b1;
  o_data_req = 1'b0;
  o_op_complete = 1'b0;
end

endmodule

