/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Intel 8251A USART                                                            *
 *                                                                              *
 * This module implements a subset of the Intel 8251A interface, providing only *
 * the signals and commands used by the 380Z ROM routines.                      *
 *                                                                              *
 * The mode is always set to 8N1 async (8 bits, no parity, 1 stop bit) by the   *
 * firmware and communication software such as Kermit.                          *
 *                                                                              *
 * The baud rate is fixed at 9600 baud as the Z80 CTC (normally used as the     *
 * clock generator) is not included.  This was the maximum baud rate supported  *
 * by the firmware.                                                             *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module intel_8251a(
  input CLK,
  input WR,
  input RD,
  input CD,
  input RxD,
  output TxD,
  inout [7:0] D
);

localparam BAUD_RATE = 9600;
localparam CYCLES_PER_BIT = (`CPU_SPEED_HZ + (BAUD_RATE / 2)) / BAUD_RATE;

localparam STATE_IDLE     = 4'b00;
localparam STATE_READY    = 4'b01;
localparam STATE_START    = 4'b10;
localparam STATE_RECEIVE  = 4'b11;

reg r_RD = 1'b1;
reg r_WR = 1'b1;

reg [1:0] r_State = STATE_READY;
reg [$clog2(CYCLES_PER_BIT)-1:0] r_TransmitCounter = 0;
reg [$clog2(CYCLES_PER_BIT)-1:0] r_ReceiveCounter = 0;
reg [8:0] r_OutFrame = {9{1'b1}};
reg [8:0] r_InFrame;
reg [3:0] r_BitsToSend = 0;
reg [3:0] r_BitsToReceive = 0;
reg [7:0] r_Dout;
reg [7:0] r_Status;
reg [7:0] r_ReceivedData;
reg [7:0] r_OutputData;
reg r_DataReceived = 1'b0;
reg r_DataToSend = 1'b0;

always @(posedge CLK) begin
  r_RD <= RD;
  r_WR <= WR;

  if ((WR == 1'b0) && (r_WR == 1'b1)) begin
    if (CD == 1'b1) begin
      case (r_State)
        STATE_IDLE: begin
          // mode not checked as should always be 8N1
          r_State <= STATE_READY;
        end

        STATE_READY: begin
          if (D[6]) begin
            // internal reset
            r_State <= STATE_IDLE;
          end
          // Tx and Rx enable bits not checked (as always set)
        end
      endcase
    end else begin
      r_OutputData <= D;
      r_DataToSend <= 1'b1;
    end
  end

  if ((RD == 1'b0) && (r_RD == 1'b1) && (CD == 1'b0)) begin
    // received data read by CPU
    r_DataReceived <= 1'b0;
  end

  // transmit logic
  if (r_BitsToSend > 0) begin
    if (r_TransmitCounter < CYCLES_PER_BIT-1) begin
      r_TransmitCounter <= r_TransmitCounter + 1;
    end else begin
      r_TransmitCounter <= 0;
      r_BitsToSend <= r_BitsToSend - 1;
      r_OutFrame <= {1'b1, r_OutFrame[8:1]};
    end
  end else if (r_DataToSend) begin
    r_DataToSend <= 1'b0;
    r_BitsToSend <= 10;
    r_OutFrame <= {r_OutputData, 1'b0};
  end

  // receive logic
  case (r_State)
    STATE_READY: begin
      if (RxD == 1'b0) begin
        // possilbe start bit detected
        r_State <= STATE_START;
      end
    end

    STATE_START: begin
      if (r_ReceiveCounter < (CYCLES_PER_BIT / 2)-1) begin
         r_ReceiveCounter <= r_ReceiveCounter + 1;
      end else begin
        r_ReceiveCounter <= 0;
        if (RxD == 1'b0) begin
          // in middle of start bit
          r_BitsToReceive <= 9;
          r_State <= STATE_RECEIVE;
        end else begin
          // false alarm
          r_State <= STATE_READY;
        end
      end
    end

    STATE_RECEIVE: begin
      if (r_BitsToReceive > 0) begin
        if (r_ReceiveCounter < CYCLES_PER_BIT-1) begin
          r_ReceiveCounter <= r_ReceiveCounter + 1;
        end else begin
          r_ReceiveCounter <= 0;
          r_BitsToReceive <= r_BitsToReceive - 1;
          r_InFrame <= {RxD, r_InFrame[8:1]};
        end
      end else begin
          if (r_InFrame[8] == 1'b1) begin
            // stop bit present
            r_ReceivedData <= r_InFrame[7:0];
            r_DataReceived <= 1'b1;
          end
          // NB framing error status bit not set as never checked/cleared by firmware
          r_State <= STATE_READY;
      end
    end
  endcase
end

always @(*) begin
  r_Status = {1'b1, 4'b0000, ~r_DataToSend, r_DataReceived, ~r_DataToSend};
  r_Dout = (CD) ? r_Status : r_ReceivedData;
end

assign TxD = r_OutFrame[0];
assign D = (RD == 1'b0) ? r_Dout : {8{1'bz}};

endmodule
