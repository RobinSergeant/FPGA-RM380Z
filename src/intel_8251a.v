/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Intel 8251A USART                                                            *
 *                                                                              *
 * This module implements a subset of the Intel 8251A interface, providing only *
 * the signals and commands used by the 380Z ROM routines.                      *
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

localparam CYCLES_PER_BIT = 1042; // 9600 baud

reg r_RD = 1'b1;
reg r_WR = 1'b1;

reg [10:0] r_TransmitCounter = 0;
reg [9:0] r_DataFrame = {10{1'b1}};
reg [3:0] r_BitsToSend = 0;
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
    if (CD == 1'b0) begin
      r_OutputData <= D;
      r_DataToSend <= 1'b1;
    end
  end

  if (r_BitsToSend > 0) begin
    if (r_TransmitCounter < CYCLES_PER_BIT-1) begin
      r_TransmitCounter <= r_TransmitCounter + 1;
    end else begin
      r_TransmitCounter <= 0;
      r_BitsToSend <= r_BitsToSend - 1;
      r_DataFrame <= {1'b1, r_DataFrame[8:1]};
    end
  end else if (r_DataToSend) begin
    r_DataToSend <= 1'b0;
    r_BitsToSend <= 10;
    r_DataFrame <= {1'b1, r_OutputData, 1'b0};
  end
end

always @(*) begin
  r_Status = {1'b1, 4'b000000, ~r_DataToSend, r_DataReceived, ~r_DataToSend};
  r_Dout = (CD) ? r_Status : r_ReceivedData;
end

assign TxD = r_DataFrame[0];
assign D = (RD == 1'b0) ? r_Dout : {8{1'bz}};

endmodule
