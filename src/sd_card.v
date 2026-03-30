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
  output reg o_op_failed,
  output reg o_mosi,
  output reg o_cs,
  output o_sck,
  output o_ready,
  output [7:0] o_dout
);

wire w_cd;
debounce #(.DEBOUNCE_LIMIT(20_000 * `CPU_SPEED_MHZ)) debounce_cd_inst (
.i_clk(i_clk),
.i_in(i_cd),
.o_out(w_cd)
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
localparam CMD16  = {2'b01, 6'd16, 8'h00, 8'h00, 8'h02, 8'h00, 8'h01};  // SET_BLOCKLEN
localparam CMD17  = {2'b01, 6'd17, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // READ_SINGLE_BLOCK
localparam CMD24  = {2'b01, 6'd24, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // WRITE_BLOCK
localparam CMD55  = {2'b01, 6'd55, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // APP_CMD
localparam CMD58  = {2'b01, 6'd58, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};  // READ_OCR
localparam ACMD41 = {2'b01, 6'd41, 8'h40, 8'h00, 8'h00, 8'h00, 8'h01};  // SD_SEND_OP_COND

localparam STATE_INIT   = 4'b0000;  // init states
localparam STATE_CMD0   = 4'b0001;
localparam STATE_CMD8   = 4'b0010;  
localparam STATE_CMD55  = 4'b0011;
localparam STATE_ACMD41 = 4'b0100;
localparam STATE_CMD58  = 4'b0101;
localparam STATE_CMD16  = 4'b0110;
localparam STATE_IDLE   = 4'b1000;
localparam STATE_CMD17  = 4'b1001;  // block read states
localparam STATE_RBDATA = 4'b1010;
localparam STATE_RBCRC  = 4'b1011;
localparam STATE_CMD24  = 4'b1100;  // block write states
localparam STATE_WBDATA = 4'b1101;
localparam STATE_WBDRT  = 4'b1110;
localparam STATE_WBBUSY = 4'b1111;

/* Clock rate must be below 400 kHz during initialisation
   At 10MHz: 10,000,000 / 2^5 (32) = 312.5 kHz
   At 4MHz:   4,000,000 / 2^5 (16) = 250.0 kHz */
localparam CLOCK_BIT = ((`CPU_SPEED_HZ / 16) < 400_000) ? 3 : 4;

reg [CLOCK_BIT:0] r_ClkCounter = 0;
reg r_PrevClkBit = 0;

wire w_ClkBit;
wire w_RisingEdge;
wire w_FallingEdge;

always @(posedge i_clk) begin
  r_PrevClkBit <= w_ClkBit;
  r_ClkCounter <= r_ClkCounter + 1;
end

assign w_ClkBit = o_ready ? r_ClkCounter[1] : r_ClkCounter[CLOCK_BIT];
assign w_RisingEdge = (~r_PrevClkBit & w_ClkBit);
assign w_FallingEdge = (r_PrevClkBit & ~w_ClkBit);

reg r_ReadyToSend = 1'b0;

reg [3:0] r_State = STATE_INIT;
reg [47:0] r_Command = {48{1'b1}};
reg [7:0] r_ReceivedByte = 8'h01;
reg [7:0] r_DataByte = 8'h00;
reg [9:0] r_BytesExpected = 10; // stay in INIT state for 80 clocks
reg [22:0] r_BlockNumber;
reg r_BlockValid = 1'b0;
reg r_WriteOp = 1'b0;
reg r_cs = 1'b1;
reg r_cd = 1'b0;
reg r_SDHC = 1'b0;
reg r_LegacyCard = 1'b0;

reg [31:0] t_BlockAddress;
reg [7:0] t_ReceivedByte;

always @(posedge i_clk) begin
  r_cd <= w_cd;
  o_op_complete <= 1'b0;
  o_op_failed <= 1'b0;

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

          STATE_CMD8: begin
            if (r_BytesExpected == 1) begin
              r_cs <= 1'b1;
              r_Command <= CMD55;
              r_State <= STATE_CMD55;
            end
          end

          STATE_CMD58: begin
            if (r_BytesExpected == 4) begin
              // bit 30 of OCR contains the CCS
              r_SDHC <= t_ReceivedByte[6];
            end else if (r_BytesExpected == 1) begin
              r_cs <= 1'b1;
              if (r_SDHC) begin
                // SDHC card init finished
                r_State <= STATE_IDLE;
              end else begin
                // make sure block length is 512 for SDSC
                r_Command <= CMD16;
                r_State <= STATE_CMD16;
              end
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
            end else begin
              o_op_failed <= 1'b1;
              r_cs <= 1'b1;
              r_State <= STATE_IDLE;
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
              r_cs <= 1'b1;
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
              r_BytesExpected <= 1;
            end else if (t_ReceivedByte[4:0] == 5'b01101) begin
              // write error
              o_op_failed <= 1'b1;
              r_cs <= 1'b1;
              r_State <= STATE_IDLE;
            end else begin
              r_BytesExpected <= 1;
            end
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
              r_cs <= 1'b1;
            end else begin
              r_BytesExpected <= 1;
            end
          end
        endcase
      end else if (t_ReceivedByte[7] == 1'b0) begin
        // process R1 command response
        r_ReadyToSend <= 1'b0;
        r_cs <= 1'b1;

        case (r_State)
          STATE_CMD0: begin
            if (t_ReceivedByte == 8'h01) begin
              r_Command <= CMD8;
              r_State <= STATE_CMD8;
            end 
          end

          STATE_CMD8: begin
            if (t_ReceivedByte == 8'h01) begin
              r_cs <= 1'b0;
              r_BytesExpected <= 4;
            end else if (t_ReceivedByte == 8'h05) begin
              // illegal command response expected for legacy 1.x card
              r_Command <= CMD55;
              r_State <= STATE_CMD55;
            end
            r_LegacyCard <= t_ReceivedByte[2];
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
              if (r_LegacyCard) begin
                // v1.x card ready, must be SDSC
                r_SDHC <= 1'b0;
                // make sure block length is 512
                r_Command <= CMD16;
                r_State <= STATE_CMD16;
              end else begin
                // v2.0 card ready, fetch CCS
                r_Command <= CMD58;
                r_State <= STATE_CMD58;
              end
            end
          end

          STATE_CMD16: begin
            if (t_ReceivedByte == 8'h00) begin
              // SDSC card init finished
              r_State <= STATE_IDLE;
            end
          end

          STATE_CMD58: begin
            if (t_ReceivedByte == 8'h00) begin
              r_cs <= 1'b0;
              r_BytesExpected <= 4;
            end
          end

          STATE_CMD17: begin
            if (t_ReceivedByte == 8'h00) begin
              r_cs <= 1'b0;
              r_BytesExpected <= 1;
            end else begin
              o_op_failed <= 1'b1;
              r_State <= STATE_IDLE;
            end
          end

          STATE_CMD24: begin
            if (t_ReceivedByte == 8'h00) begin
              // send dummy byte followed by start block token
              r_Command[47:32] <= {8'hFF, 8'hFE};
              r_cs <= 1'b0;
              r_BytesExpected <= 2;
              r_ReadyToSend <= 1'b1;
            end else begin
              o_op_failed <= 1'b1;
              r_State <= STATE_IDLE;
            end
          end
        endcase
      end else if (t_ReceivedByte == 8'hFF) begin
        if (!r_Command[47]) begin
          // send one FF byte with CS low before new command
          r_cs <= 1'b0;
          if (!r_cs)
            r_ReadyToSend <= 1'b1;
        end
      end
    end else begin
      r_ReceivedByte <= t_ReceivedByte;
    end
  end

  // use block based addressing for SDHC, and byte addressing for SDSC
  t_BlockAddress = (r_SDHC) ? {{9{1'b0}}, i_address[31:9]} : {i_address[31:9], {9{1'b0}}};

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
      r_Command <= {CMD17[47:40], t_BlockAddress, CMD17[7:0]};
      r_State <= STATE_CMD17;
      r_ReadyToSend <= 1'b0;
    end
  end

  if (i_data_ack) begin
    r_ram_addr <= r_ram_addr + 1;
    if (&r_ram_addr[6:0]) begin
      o_data_req <= 1'b0;
      if (r_WriteOp) begin
        r_ram_addr <= 0;
        r_ram_we <= 1'b0;
        r_Command <= {CMD24[47:40], t_BlockAddress, CMD24[7:0]};
        r_State <= STATE_CMD24;
        r_ReadyToSend <= 1'b0;
      end else begin
        o_op_complete <= 1'b1;
      end
    end
  end

  if (!w_cd && r_cd) begin
    // new card inserted
    o_mosi = 1'b1;
    o_cs <= 1'b1;
    r_cs <= 1'b1;
    r_ReadyToSend <= 1'b0;
    r_BlockValid <= 1'b0;
    r_State <= STATE_INIT;
    r_BytesExpected <= 10; // stay in INIT state for 80 clocks
  end
end

assign w_ram_we = r_ram_we;
assign w_ram_addr = r_ram_addr;
assign w_ram_din = o_data_req ? i_din : r_DataByte;

assign o_sck = w_ClkBit;
assign o_ready = (!r_cd && (r_State >= STATE_IDLE));
assign o_dout = w_ram_dout;

initial begin
  o_mosi = 1'b1;
  o_cs = 1'b1;
  o_data_req = 1'b0;
  o_op_complete = 1'b0;
  o_op_failed = 1'b0;
end

endmodule

