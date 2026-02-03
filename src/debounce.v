/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Debounce signal                                                              *
 *                                                                              *
 * Wait until input signal is stable for a given period before updating output  *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module debounce#(
  parameter DEBOUNCE_LIMIT = 10
)(
  input i_clk,
  input i_in,
  output o_out
);

  reg [$clog2(DEBOUNCE_LIMIT)-1:0] r_count = 0;
  reg r_state = 1'b0;

  always @(posedge i_clk) begin
    if (i_in != r_state && r_count < DEBOUNCE_LIMIT) begin
      r_count <= r_count + 1;
    end else if (r_count == DEBOUNCE_LIMIT) begin
      r_state <= i_in;
      r_count <= 0;
    end else begin
      r_count <= 0;
    end
  end

  assign o_out = r_state;
endmodule
