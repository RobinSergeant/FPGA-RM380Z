/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Display module                                                               *
 *                                                                              *
 * This module output a 640x480 60Hz VGA signal and includes both the VDU-80    *
 * character and HRG (High Resolution Graphics) displays.                       *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module display(
  input i_clk,
  input i_mode80,
  input i_counter_valid,
  input i_hrg_port0_valid,
  input i_hrg_port1_valid,
  input [4:0] i_counter,
  input [7:0] i_hrg_port0,
  input [7:0] i_hrg_port1,
  input [7:0] i_char_code,
  input [7:0] i_attr_data,
  input [7:0] i_char_data,
  input [7:0] i_hrg_data,
  output [10:0] o_vram_addr,
  output reg [11:0] o_chargen_addr,
  output reg [13:0] o_hrg_addr,
  output [3:0] o_red,
  output [3:0] o_green,
  output [3:0] o_blue,
  output o_hsync,
  output o_vsync,
  output o_hblank,
  output o_vblank
);

`include "common.vh"

/********************************************************************************
 *                                                                              *
 * VGA driver                                                                   *
 *                                                                              *
 ********************************************************************************/

localparam MAX_COL = 799;
localparam MAX_ROW = 520;
localparam VISIBLE_COLS = 640;
localparam VISIBLE_ROWS = 480;

localparam HFRONT_PORCH = 16;
localparam HBACK_PORCH = 48;
localparam HSYNC_START = VISIBLE_COLS + HFRONT_PORCH;
localparam HSYNC_END = MAX_COL - HBACK_PORCH;

localparam VFRONT_PORCH = 10;
localparam VBACK_PORCH = 29;
localparam VSYNC_START = VISIBLE_ROWS + VFRONT_PORCH;
localparam VSYNC_END = MAX_ROW - VBACK_PORCH;

reg [9:0] r_col_counter = 0;
reg [9:0] r_row_counter = VISIBLE_ROWS;

wire w_visible;

always @(posedge i_clk) begin
  if (r_col_counter < MAX_COL) begin
    r_col_counter <= r_col_counter + 1;
  end else begin
    r_col_counter <= 0;
    if (r_row_counter < MAX_ROW) begin
      r_row_counter <= r_row_counter + 1;
    end else begin
      r_row_counter <= 0;
    end
  end
end

assign w_visible = (r_col_counter < VISIBLE_COLS) && (r_row_counter < VISIBLE_ROWS);

/********************************************************************************
 *                                                                              *
 * VDU-80 character display                                                     *
 *                                                                              *
 * Both 40 and 80 column display modes are supported, each with 24 rows.        *
 * Characters are 8 pixels wide and 10 pixels deep in both modes.               *
 *                                                                              *
 * Pixels are stretched verticaly by a factor of two (each row of pixels is     *
 * is repeated so that 240 pixels occupy the full 480 vga pixel height).        *
 * In 40 column mode pixels are also stretched horizontally (each column of     *
 * pixels is repeated so that 320 pixels occupy the full 640 vga pixel width).  *
 *                                                                              *
 * Each display characters has an associated attribute byte to control it's     *
 * appearance.  Supported attributes include underline, dim, and inverse.  The  *
 * underline attribute changes the character generator address for the the last *
 * two rows (selecting rows and 11 and 12 to replace row 9 and 10).             *
 *                                                                              *
 ********************************************************************************/

// 12 bit colours
localparam BLACK = {12{1'b0}};
localparam WHITE = {12{1'b1}};
localparam GREY = {3{4'b1000}};

// attribute bit indexes
localparam UNDERLINE  = 1;
localparam DIM        = 2;
localparam INVERSE    = 3;

wire [11:0] w_vdu_out;
reg [7:0] r_char_data = 0;
reg [7:0] r_attr_val = 0;
reg [6:0] r_cc_counter = 0;    // 80 columns
reg [4:0] r_cr_counter = 0;    // 24 rows
reg [4:0] r_scroll_counter = 0;
reg [2:0] r_px = 7;            // 8 pixel wide chars
reg [4:0] r_py = 0;            // 20 (10*2) pixels high
reg r_pixel_tog = 1'b0;        // use same data for 2 pixels in 40 col mode
reg r_mode80 = 1'b0;           // don't repeat pixel data in 80 col mode

always @(posedge i_clk) begin
  if (w_visible) begin
    r_pixel_tog <= ~r_pixel_tog;
    if (r_mode80 || r_pixel_tog) begin
      if (r_px > 0) begin
        if (r_px == 7) begin
          // read ahead and fetch data for next character row
          if (r_cc_counter < (r_mode80 ? 79 : 39)) begin
            r_cc_counter <= r_cc_counter + 1;
          end else begin
            r_cc_counter <= 0;
            if (r_py < 19) begin
              r_py <= r_py + 1;
            end else begin
              r_py <= 0;
              if (r_cr_counter < 23) begin
                r_cr_counter <= r_cr_counter + 1;
              end else begin
                r_cr_counter <= 0;
              end
            end
          end
        end
        r_px <= r_px - 1;
      end else begin
        // get ready to draw the next character row
        r_px <= 7;
        r_attr_val <= i_attr_data;
        r_char_data <= i_char_data;
      end
    end
  end else begin
    r_attr_val <= i_attr_data;
    r_char_data <= i_char_data;
    r_mode80 <= i_mode80;
  end

  if (i_counter_valid) begin
    r_scroll_counter <= i_counter;
  end
end

always @(*) begin
  if (i_attr_data[UNDERLINE] && (r_py >= 16)) begin
    // underline attribute, use alternative data for last two rows
    o_chargen_addr = (i_char_code << 4) | (r_py >> 1) + 2;
  end else begin
    o_chargen_addr = (i_char_code << 4) | (r_py >> 1);
  end   
end

assign o_vram_addr = vram_address(r_cr_counter, r_cc_counter, r_scroll_counter);
assign w_vdu_out = (r_char_data[r_px] ^ r_attr_val[INVERSE]) ? (r_attr_val[DIM] ? GREY : WHITE) : BLACK;

/********************************************************************************
 *                                                                              *
 * HRG (High Resolution Graphics) display                                       *
 *                                                                              *
 * Two graphics modes are provided by the HRG card:                             *
 *   1) High res (4 colours, 320x192)                                           *
 *   2) Medium res (16 colours, 160x96 with two pages)                          *
 *                                                                              *
 * Both are stretched to a VGA resolution of 640x384 and shown at the top of    *
 * the screen (the lower 96 pixels are black / not used for HRG).               *
 *                                                                              *
 ********************************************************************************/

localparam MODE_NONE = 4'b00;
localparam MODE_HIGH = 4'b01;
localparam MODE_MED0 = 4'b10;
localparam MODE_MED1 = 4'b11;

reg [1:0] r_mode = MODE_NONE;
reg [7:0] r_hrg_port0 = 0;
reg [7:0] r_hrg_port1 = 0;
reg [7:0] r_scratchpad [0:15];
reg [7:0] r_colour;
reg [11:0] r_hrg_out;
reg [9:0] r_hrg_xpos = 8;
reg [8:0] r_hrg_ypos = 0;
reg [2:0] r_hrg_pixel_no = 0;
reg [7:0] r_hrg_byte;

reg [8:0] r_hrg_x;
reg [7:0] r_hrg_y;

always @(posedge i_clk) begin
  if (w_visible) begin
    if (r_hrg_pixel_no == 7) begin
      // start displaying the next byte
      r_hrg_byte <= i_hrg_data;
      r_hrg_pixel_no <= 0;
      // read ahead 8 pixels to get a new byte
      if (r_hrg_xpos == 632) begin
        r_hrg_xpos <= 0;
        if (r_hrg_ypos == 479) begin
          r_hrg_ypos <= 0;
        end else begin
          r_hrg_ypos <= r_hrg_ypos + 1;
        end
      end else begin
        r_hrg_xpos <= r_hrg_xpos + 8;
      end
    end else begin
      if (r_mode[1]) begin
        // medium res (shift every 4 pixels)
        if (r_hrg_pixel_no == 3)
          r_hrg_byte <= r_hrg_byte >> 2;
      end else begin
        // high res (shift every 2 pixels)
        if (r_hrg_pixel_no[0])
          r_hrg_byte <= r_hrg_byte >> 2;
      end
      r_hrg_pixel_no <= r_hrg_pixel_no + 1;
    end
  end

  if (i_hrg_port0_valid) begin
    case (i_hrg_port0)
      8'h00: r_mode <= MODE_NONE;
      8'h03: r_mode <= MODE_HIGH;
      8'hA3: r_mode <= MODE_MED0;
      8'hC3: r_mode <= MODE_MED1;
    endcase

    // update scrachdpad (colour palette)
    if (!r_hrg_port0[0] && i_hrg_port0[0]) begin
      // bit 0 toggled, update low nibble 
      r_scratchpad[r_hrg_port1[7:4]][3:0] <= r_hrg_port1[3:0];
    end
    if (!r_hrg_port0[1] && i_hrg_port0[1]) begin
      // bit 1 toggled, update high nibble
      r_scratchpad[r_hrg_port1[7:4]][7:4] <= r_hrg_port1[3:0];
    end

    r_hrg_port0 <= i_hrg_port0;
  end

  if (i_hrg_port1_valid) begin
    r_hrg_port1 <= i_hrg_port1;
  end
end

always @(*) begin
  if (r_mode[1]) begin
    // medium res, 4 real pixels for every hrg pixel
    r_hrg_x = r_hrg_xpos >> 2;
    r_hrg_y = r_hrg_ypos >> 2;
    o_hrg_addr = (r_hrg_y[6:3] * 1280) + {r_hrg_x[7:1], r_hrg_y[2:0], r_mode[0]};
  end else begin
    // high res, 2 real pixels for every hrg pixel
    r_hrg_x = r_hrg_xpos >> 1;
    r_hrg_y = r_hrg_ypos >> 1;
    o_hrg_addr = (r_hrg_y[7:4] * 1280) + {r_hrg_x[8:2], r_hrg_y[3:0]};
  end

  // NB the scratch pad stores 8-bit colour in the following format:
  // GRGBRGBR   (3 bits for red and green, only 2 bits for blue)
  // 22111000   (bits 7, 5, and 2 form green etc.)
  r_colour = r_mode[1] ? r_scratchpad[{r_hrg_byte[5:4], r_hrg_byte[1:0]}] : r_scratchpad[r_hrg_byte[1:0]];
  if ((r_hrg_ypos < 384) && r_mode) begin
    r_hrg_out = {r_colour[6], r_colour[3], r_colour[0], r_colour[6], r_colour[7], r_colour[5], r_colour[2], r_colour[7], r_colour[4], r_colour[1], r_colour[4], r_colour[1]};
  end else begin
    r_hrg_out = BLACK;
  end
end

assign o_red = (w_visible) ? w_vdu_out[11:8] | r_hrg_out[11:8] : 4'b0000;
assign o_green = (w_visible) ? w_vdu_out[7:4] | r_hrg_out[7:4] : 4'b0000;
assign o_blue = (w_visible) ? w_vdu_out[3:0] | r_hrg_out[3:0] : 4'b0000;

assign o_hsync = ((r_col_counter >= HSYNC_START) && (r_col_counter <= HSYNC_END)) ? 1'b0 : 1'b1;
assign o_vsync = ((r_row_counter >= VSYNC_START) && (r_row_counter <= VSYNC_END)) ? 1'b0 : 1'b1;

assign o_hblank = (r_col_counter >= VISIBLE_COLS);
assign o_vblank = (r_row_counter >= VISIBLE_ROWS);

endmodule
