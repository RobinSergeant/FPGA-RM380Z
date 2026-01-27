/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Dual Port RAM module (simple wrapper for xpm_memory_tdpram)                  *
 *                                                                              *
 * Port A can read and write (used by CPU)                                      *
 * Port B can only read (used by the display)                                   *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module dual_port_ram #(
  parameter DEPTH = 1024,
  parameter INIT_FILE = "none"
)(
  input clka,
  input clkb,
  input [7:0] dina,
  input [$clog2(DEPTH)-1:0] addra,
  input [$clog2(DEPTH)-1:0] addrb,
  input wea,
  output [7:0] douta,
  output [7:0] doutb
);

xpm_memory_tdpram #(
  .ADDR_WIDTH_A($clog2(DEPTH)),   // DECIMAL
  .ADDR_WIDTH_B($clog2(DEPTH)),   // DECIMAL
  .AUTO_SLEEP_TIME(0),            // DECIMAL
  .BYTE_WRITE_WIDTH_A(8),         // DECIMAL
  .BYTE_WRITE_WIDTH_B(8),         // DECIMAL
  .CASCADE_HEIGHT(0),             // DECIMAL
  .CLOCKING_MODE("independent_clock"), // String
  .ECC_BIT_RANGE("7:0"),          // String
  .ECC_MODE("no_ecc"),            // String
  .ECC_TYPE("none"),              // String
  .IGNORE_INIT_SYNTH(0),          // DECIMAL
  .MEMORY_INIT_FILE(INIT_FILE),   // String
  .MEMORY_INIT_PARAM(""),         // String
  .MEMORY_OPTIMIZATION("true"),   // String
  .MEMORY_PRIMITIVE("auto"),      // String
  .MEMORY_SIZE(DEPTH * 8),        // DECIMAL
  .MESSAGE_CONTROL(0),            // DECIMAL
  .RAM_DECOMP("auto"),            // String
  .READ_DATA_WIDTH_A(8),          // DECIMAL
  .READ_DATA_WIDTH_B(8),          // DECIMAL
  .READ_LATENCY_A(1),             // DECIMAL
  .READ_LATENCY_B(1),             // DECIMAL
  .READ_RESET_VALUE_A("0"),       // String
  .READ_RESET_VALUE_B("0"),       // String
  .RST_MODE_A("SYNC"),            // String
  .RST_MODE_B("SYNC"),            // String
  .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
  .USE_MEM_INIT(0),               // DECIMAL
  .USE_MEM_INIT_MMI(0),           // DECIMAL
  .WAKEUP_TIME("disable_sleep"),  // String
  .WRITE_DATA_WIDTH_A(8),         // DECIMAL
  .WRITE_DATA_WIDTH_B(8),         // DECIMAL
  .WRITE_MODE_A("no_change"),     // String
  .WRITE_MODE_B("no_change"),     // String
  .WRITE_PROTECT(1)               // DECIMAL
)
xpm_memory_tdpram_inst (
  .dbiterra(),                     // 1-bit output: Status signal to indicate double bit error occurrence on the data output of port A.
  .dbiterrb(),                     // 1-bit output: Status signal to indicate double bit error occurrence on the data output of port A.
  .douta(douta),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
  .doutb(doutb),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
  .sbiterra(),                     // 1-bit output: Status signal to indicate single bit error occurrence on the data output of port A.
  .sbiterrb(),                     // 1-bit output: Status signal to indicate single bit error occurrence on the data output of port B.
  .addra(addra),                   // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
  .addrb(addrb),                   // ADDR_WIDTH_B-bit input: Address for port B write and read operations.
  .clka(clka),                     // 1-bit input: Clock signal for port A. Also clocks port B when parameter CLOCKING_MODE is "common_clock".
  .clkb(clkb),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is "independent_clock". Unused when
                                   // parameter CLOCKING_MODE is "common_clock".

  .dina(dina),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
  .dinb(0),                        // WRITE_DATA_WIDTH_B-bit input: Data input for port B write operations.
  .ena(1'b1),                      // 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                   // are initiated. Pipelined internally.

  .enb(1'b1),                      // 1-bit input: Memory enable signal for port B. Must be high on clock cycles when read or write operations
                                   // are initiated. Pipelined internally.

  .injectdbiterra(1'b0),           // 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection capability
                                   // is not available in "decode_only" mode).

  .injectdbiterrb(1'b0),           // 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection capability
                                   // is not available in "decode_only" mode).

  .injectsbiterra(1'b0),           // 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection capability
                                   // is not available in "decode_only" mode).

  .injectsbiterrb(1'b0),           // 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection capability
                                   // is not available in "decode_only" mode).

  .regcea(1'b1),                   // 1-bit input: Clock Enable for the last register stage on the output data path.
  .regceb(1'b1),                   // 1-bit input: Clock Enable for the last register stage on the output data path.
  .rsta(1'b0),                     // 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                   // douta to the value specified by parameter READ_RESET_VALUE_A.

  .rstb(1'b0),                     // 1-bit input: Reset signal for the final port B output register stage. Synchronously resets output port
                                   // doutb to the value specified by parameter READ_RESET_VALUE_B.

  .sleep(1'b0),                    // 1-bit input: sleep signal to enable the dynamic power saving feature.
  .wea(wea),                       // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1 bit
                                   // wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing one
                                   // byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                   // WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.

  .web(1'b0)                       // WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-bit input: Write enable vector for port B input data port dinb. 1 bit
                                   // wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing one
                                   // byte of dinb to address addrb. For example, to synchronously write only bits [15-8] of dinb when
                                   // WRITE_DATA_WIDTH_B is 32, web would be 4'b0010.
);

endmodule
