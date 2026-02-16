/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * PS2 to ASCII keyboard                                                        *
 *                                                                              *
 * Converts PS2 keyboard scan codes to ASCII (taking Ctrl, Shift and CapsLock   *
 * states into account).  CapsLock LED toggled to reflect state (hence inout    *
 * PS2 signals in interface).                                                   *
 *                                                                              *
 * NB I could not set the CapsLock LED reliably without resorting to a retry    *
 *    mechanism.  The KBD occasionally fails to process a command without       *
 *    sending any response.  If this happens after the ED byte is acknowledged  *
 *    the keyboard locks up because ED disables scanning until the followup     *
 *    byte is received.  Retrying if a response is not received within 10ms     *
 *    prevents this from happening.                                             *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module keyboard(
  input i_clk,
  inout io_ps2_clk,
  inout io_ps2_data,
  output reg [7:0] o_ascii_code,
  output reg o_key_press,
  output reg o_key_release
);

wire i_ps2_clk;
wire w_ps2_clk;
debounce #(.DEBOUNCE_LIMIT(20)) debounce_clk_inst (
.i_clk(i_clk),
.i_in(i_ps2_clk),
.o_out(w_ps2_clk)
);

wire i_ps2_data;
wire w_ps2_data;
debounce #(.DEBOUNCE_LIMIT(20)) debounce_data_inst (
.i_clk(i_clk),
.i_in(i_ps2_data),
.o_out(w_ps2_data)
);

// states
localparam IDLE         = 4'b0000;
localparam READ_CODE    = 4'b0001;
localparam PARITY_BIT   = 4'b0010;
localparam STOP_BIT     = 4'b0011;
localparam REQ_TO_SEND  = 4'b0100;
localparam SEND_DATA    = 4'b0101;
localparam SEND_PARITY  = 4'b0110;
localparam RELEASE_DATA = 4'b0111;
localparam WAIT_ACK     = 4'b1000;
localparam SYNC_ERROR   = 4'b1001;

// kbd scan codes / commands
localparam LEFT_SHIFT   = 8'h12;
localparam RIGHT_SHIFT  = 8'h59;
localparam CTRL         = 8'h14;
localparam CAPS_LOCK    = 8'h58;
localparam KEY_RELEASE  = 8'hF0;
localparam OK_RESPONSE  = 8'hFA;
localparam SET_LEDS     = 8'hED;

// delay and timeout constants (adjust if not using a 10 MHz clock)
localparam RESPONSE_TIMEOUT  = 100000;  // wait 10ms for command response before retrying
localparam SYNC_CLOCK_PERIOD = 1200;    // pull clock low for 120us to re-sync with device
localparam RTS_CLOCK_PERIOD  = 1200;    // pull clock low for 120us during RTS handshake
localparam RTS_DATA_PERIOD   = 200;     // pull data low 20us before the clock is released

reg [3:0] r_State = IDLE;
reg [7:0] r_ScanCode = 0;
reg [7:0] r_LastCode = 0;
reg [7:0] r_Command = 0;
reg [2:0] r_BitIndex = 0;
reg [$clog2(RESPONSE_TIMEOUT)-1:0] r_CommandCounter = 0;
reg [$clog2(SYNC_CLOCK_PERIOD)-1:0] r_SyncCounter = 0;
reg r_DataLine = 0;
reg r_EnDataLine = 0;
reg r_Shift = 0;
reg r_CapsLock = 0;
reg r_Ctrl = 0;
reg r_ps2_clk = 0;
reg r_ResponsePending = 0;

assign io_ps2_clk = ((r_State == REQ_TO_SEND) || (r_State == SYNC_ERROR)) ? 1'b0 : 1'bz;
assign i_ps2_clk = ((r_State == REQ_TO_SEND) || (r_State == SYNC_ERROR)) ? 1'b0 : io_ps2_clk;

assign io_ps2_data = (r_EnDataLine) ? r_DataLine : 1'bz;
assign i_ps2_data = (r_EnDataLine) ? r_DataLine : io_ps2_data;

function automatic [7:0] to_ascii;
  input [7:0] scan_code;
  input ctrl;
  input shift;
  input caps;

  begin
    case (scan_code)
      // Letter keys (A to Z)
      8'h1C:   to_ascii = (ctrl) ? 8'd01 : (shift ^ caps) ? 8'h41 : 8'h61;
      8'h32:   to_ascii = (ctrl) ? 8'd02 : (shift ^ caps) ? 8'h42 : 8'h62;
      8'h21:   to_ascii = (ctrl) ? 8'd03 : (shift ^ caps) ? 8'h43 : 8'h63;
      8'h23:   to_ascii = (ctrl) ? 8'd04 : (shift ^ caps) ? 8'h44 : 8'h64;
      8'h24:   to_ascii = (ctrl) ? 8'd05 : (shift ^ caps) ? 8'h45 : 8'h65;
      8'h2B:   to_ascii = (ctrl) ? 8'd06 : (shift ^ caps) ? 8'h46 : 8'h66;
      8'h34:   to_ascii = (ctrl) ? 8'd07 : (shift ^ caps) ? 8'h47 : 8'h67;
      8'h33:   to_ascii = (ctrl) ? 8'd08 : (shift ^ caps) ? 8'h48 : 8'h68;
      8'h43:   to_ascii = (ctrl) ? 8'd09 : (shift ^ caps) ? 8'h49 : 8'h69;
      8'h3B:   to_ascii = (ctrl) ? 8'd10 : (shift ^ caps) ? 8'h4A : 8'h6a;
      8'h42:   to_ascii = (ctrl) ? 8'd11 : (shift ^ caps) ? 8'h4B : 8'h6b;
      8'h4B:   to_ascii = (ctrl) ? 8'd12 : (shift ^ caps) ? 8'h4C : 8'h6c;
      8'h3A:   to_ascii = (ctrl) ? 8'd13 : (shift ^ caps) ? 8'h4D : 8'h6d;
      8'h31:   to_ascii = (ctrl) ? 8'd14 : (shift ^ caps) ? 8'h4E : 8'h6e;
      8'h44:   to_ascii = (ctrl) ? 8'd15 : (shift ^ caps) ? 8'h4F : 8'h6f;
      8'h4D:   to_ascii = (ctrl) ? 8'd16 : (shift ^ caps) ? 8'h50 : 8'h70;
      8'h15:   to_ascii = (ctrl) ? 8'd17 : (shift ^ caps) ? 8'h51 : 8'h71;
      8'h2D:   to_ascii = (ctrl) ? 8'd18 : (shift ^ caps) ? 8'h52 : 8'h72;
      8'h1B:   to_ascii = (ctrl) ? 8'd19 : (shift ^ caps) ? 8'h53 : 8'h73;
      8'h2C:   to_ascii = (ctrl) ? 8'd20 : (shift ^ caps) ? 8'h54 : 8'h74;
      8'h3C:   to_ascii = (ctrl) ? 8'd21 : (shift ^ caps) ? 8'h55 : 8'h75;
      8'h2A:   to_ascii = (ctrl) ? 8'd22 : (shift ^ caps) ? 8'h56 : 8'h76;
      8'h1D:   to_ascii = (ctrl) ? 8'd23 : (shift ^ caps) ? 8'h57 : 8'h77;
      8'h22:   to_ascii = (ctrl) ? 8'd24 : (shift ^ caps) ? 8'h58 : 8'h78;
      8'h35:   to_ascii = (ctrl) ? 8'd25 : (shift ^ caps) ? 8'h59 : 8'h79;
      8'h1A:   to_ascii = (ctrl) ? 8'd26 : (shift ^ caps) ? 8'h5A : 8'h7a;

      // Number keys (0-9)
      8'h16:   to_ascii = (shift) ? 8'h21 : 8'h31;
      8'h1E:   to_ascii = (shift) ? 8'h22 : 8'h32;
      8'h26:   to_ascii = (shift) ? 8'h23 : 8'h33;
      8'h25:   to_ascii = (shift) ? 8'h24 : 8'h34;
      8'h2E:   to_ascii = (shift) ? 8'h25 : 8'h35;
      8'h36:   to_ascii = (shift) ? 8'h5E : 8'h36;
      8'h3D:   to_ascii = (shift) ? 8'h26 : 8'h37;
      8'h3E:   to_ascii = (shift) ? 8'h2A : 8'h38;
      8'h46:   to_ascii = (shift) ? 8'h28 : 8'h39;
      8'h45:   to_ascii = (shift) ? 8'h29 : 8'h30;

      // Punctuation and other keys
      8'h4E:   to_ascii = (shift) ? 8'h5F : 8'h2D;
      8'h55:   to_ascii = (shift) ? 8'h2B : 8'h3D;
      8'h54:   to_ascii = (shift) ? 8'h7B : 8'h5B;
      8'h5B:   to_ascii = (shift) ? 8'h7D : 8'h5D;
      8'h5D:   to_ascii = (shift) ? 8'h7C : 8'h23;
      8'h4C:   to_ascii = (shift) ? 8'h3A : 8'h3B;
      8'h52:   to_ascii = (shift) ? 8'h40 : 8'h27;
      8'h41:   to_ascii = (shift) ? 8'h3C : 8'h2C;
      8'h49:   to_ascii = (shift) ? 8'h3E : 8'h2E;
      8'h4A:   to_ascii = (shift) ? 8'h3F : 8'h2F;
      8'h29:   to_ascii = 8'h20; // Spacebar

      // Special keys (Return, Backspace)
      8'h5A:   to_ascii = 8'h0D; // Return (CR+LF)
      8'h66:   to_ascii = 8'h08; // Backspace (BS)
      8'h76:   to_ascii = 8'h1B; // ESC
      default: to_ascii = 8'h00; // unknown key (ignore)
    endcase
  end  
endfunction

always @(posedge i_clk) begin
  o_key_release <= 1'b0;
  o_key_press <= 1'b0;

  if ((r_ps2_clk == 1'b1) && (w_ps2_clk == 1'b0)) begin
    case (r_State)
      IDLE: begin
        r_ScanCode <= 8'b10000000;
        r_State <= (w_ps2_data == 1'b0) ? READ_CODE : SYNC_ERROR;
      end

      READ_CODE: begin
        r_ScanCode <= {w_ps2_data, r_ScanCode[7:1]};
        if (r_ScanCode[0] == 1'b1)
          r_State <= PARITY_BIT;
      end

      PARITY_BIT: begin
        if (w_ps2_data != ^r_ScanCode) begin
          if ((r_ScanCode == LEFT_SHIFT) || (r_ScanCode == RIGHT_SHIFT))
            r_Shift <= (r_LastCode != KEY_RELEASE);
          else if (r_ScanCode == CTRL)
            r_Ctrl <= (r_LastCode != KEY_RELEASE);
          else if (|to_ascii(r_ScanCode, r_Ctrl, r_Shift, r_CapsLock)) begin
            o_ascii_code <= to_ascii(r_ScanCode, r_Ctrl, r_Shift, r_CapsLock);
            if (r_LastCode == KEY_RELEASE)
              o_key_release <= 1'b1;
            else
              o_key_press <= 1'b1;
          end
          r_State <= STOP_BIT;
        end else begin
          // wrong parity
          r_State <= SYNC_ERROR;
        end
      end

      STOP_BIT: begin
        r_State <= (w_ps2_data == 1'b1) ? IDLE : SYNC_ERROR;
        r_LastCode <= r_ScanCode;

        if ((r_ScanCode == CAPS_LOCK) && (r_LastCode == KEY_RELEASE)) begin
          r_CapsLock <= ~r_CapsLock;
          r_State <= REQ_TO_SEND;
          r_Command <= SET_LEDS;
        end else if (r_ScanCode == OK_RESPONSE) begin
          if (r_Command == SET_LEDS) begin
            r_State <= REQ_TO_SEND;
            r_Command <= {5'b00000, r_CapsLock, 2'b00};
          end
          r_CommandCounter <= 0;
          r_ResponsePending <= 1'b0;
        end
      end
      
      SEND_DATA: begin
        r_DataLine <= r_Command[r_BitIndex];
        if (r_BitIndex < 7)
          r_BitIndex <= r_BitIndex + 1;
        else
          r_State <= SEND_PARITY;
      end
      
      SEND_PARITY: begin
        r_DataLine <= ~^r_Command;
        r_State <= RELEASE_DATA;
      end
      
      RELEASE_DATA: begin
        r_EnDataLine <= 1'b0;
        r_State <= WAIT_ACK;
      end
      
      WAIT_ACK: begin
        r_State <= IDLE;
      end
    endcase
  end else if (r_State == SYNC_ERROR) begin
    if (r_SyncCounter < SYNC_CLOCK_PERIOD) begin
      r_SyncCounter <= r_SyncCounter + 1;
    end else begin
      r_SyncCounter <= 0;
      r_State <= IDLE;
    end
  end else if (r_State == REQ_TO_SEND) begin
    if (r_CommandCounter < RTS_CLOCK_PERIOD) begin
      r_CommandCounter <= r_CommandCounter + 1;
      if (r_CommandCounter == (RTS_CLOCK_PERIOD - RTS_DATA_PERIOD)) begin
        r_EnDataLine <= 1'b1;
        r_DataLine <= 1'b0;
      end 
    end else begin
      r_CommandCounter <= 0;
      r_BitIndex <= 0;
      r_State <= SEND_DATA;
      r_ResponsePending <= 1'b1;
    end
  end else if (r_ResponsePending) begin
    if (r_CommandCounter < RESPONSE_TIMEOUT) begin
      r_CommandCounter <= r_CommandCounter + 1;
    end else begin
      r_CommandCounter <= 0;
      r_State <= REQ_TO_SEND;
      r_Command <= SET_LEDS;
    end
  end

  r_ps2_clk <= w_ps2_clk;
end

initial begin
  o_ascii_code = 8'h00;
  o_key_press = 1'b0;
  o_key_release = 1'b0;
end

endmodule
