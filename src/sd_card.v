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
  input [31:0] i_address,
  output reg o_data_ready,
  output reg o_read_complete,
  output reg o_mosi,
  output reg o_cs,
  output o_sck,
  output reg [7:0] o_data,
  output [15:0] o_led
);

localparam CMD0   = {2'b01, 6'd00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h95};  // GO_IDLE_STATE
localparam CMD8   = {2'b01, 6'd08, 8'h00, 8'h00, 8'h01, 8'hAA, 8'h87};  // SEND_IF_COND
localparam CMD16  = {2'b01, 6'd16, 8'h00, 8'h00, 8'h00, 8'h80, 8'h01};  // SET_BLOCKLEN
localparam CMD17  = {2'b01, 6'd17, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // READ_SINGLE_BLOCK
localparam CMD55  = {2'b01, 6'd55, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // APP_CMD
localparam ACMD41 = {2'b01, 6'd41, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // SD_SEND_OP_COND

localparam STATE_INIT   = 4'b0000;
localparam STATE_CMD0   = 4'b0001;
localparam STATE_CMD8   = 4'b0010;  
localparam STATE_CMD55  = 4'b0011;
localparam STATE_ACMD41 = 4'b0100;
localparam STATE_CMD16  = 4'b0101;
localparam STATE_CMD17  = 4'b0110;
localparam STATE_RBDATA = 4'b0111;
localparam STATE_RBCRC  = 4'b1000;
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
reg [7:0] t_ReceivedByte;
reg [7:0] r_BytesExpected = 10; // stay in INIT state for 80 clocks

always @(posedge i_clk) begin
  o_data_ready <= 1'b0;
  o_read_complete <= 1'b0;

  if (w_FallingEdge) begin
    o_cs <= (r_State == STATE_INIT);
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
              r_ReadyToSend <= 1'b1;
            end
          end

          STATE_CMD17: begin
            if (t_ReceivedByte == 8'hFF) begin
              // keep waiting if card is busy
              r_BytesExpected <= 1;
            end else if (t_ReceivedByte == 8'hFE) begin
              r_State <= STATE_RBDATA;
              r_BytesExpected <= 128;
            end
          end

          STATE_RBDATA: begin
            o_data <= t_ReceivedByte;
            o_data_ready <= 1'b1;
            if (r_BytesExpected == 1) begin
              r_State <= STATE_RBCRC;
              r_BytesExpected <= 2;
            end
          end

          STATE_RBCRC: begin
            if (r_BytesExpected == 1) begin
              o_read_complete <= 1'b1;
              r_State <= STATE_IDLE;
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
              // card ready so set block size
              r_Command <= CMD16;
              r_State <= STATE_CMD16;
            end
          end

          STATE_CMD16: begin
            if (t_ReceivedByte == 8'h00) begin
              r_State <= STATE_IDLE;
            end
          end

          STATE_CMD17: begin
            if (t_ReceivedByte == 8'h00) begin
              r_BytesExpected <= 1;
            end
          end
        endcase
      end else if ((t_ReceivedByte == 8'hFF) && !r_Command[47]) begin
        r_ReadyToSend <= 1'b1;
      end
    end else begin
      r_ReceivedByte <= t_ReceivedByte;
    end
  end

  if (i_read) begin
    r_Command <= {CMD17[47:40], i_address, CMD17[7:0]};
    r_State <= STATE_CMD17;
  end
end

assign o_sck = w_ClkBit;

assign o_led[15] = ~i_cd;
assign o_led[14:11] = r_State;
assign o_led[10:8] = 1'b0;
assign o_led[7:0] = r_ResponseByte;

initial begin
  o_mosi = 1'b1;
  o_cs = 1'b1;
  o_data = 8'h00;
  o_data_ready = 1'b0;
  o_read_complete = 1'b0;
end

endmodule

