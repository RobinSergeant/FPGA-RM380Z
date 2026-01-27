/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Single Port ROM module (simple wrapper for xpm_memory_sprom)                 *
 *                                                                              *
 ********************************************************************************/

`timescale 1ns / 1ps

module single_port_rom #(
  parameter DEPTH = 1024,
  parameter INIT_FILE = "none"
)(
  input clka,
  input [$clog2(DEPTH)-1:0] addra,
  output [7:0] douta
);

xpm_memory_sprom #(
  .ADDR_WIDTH_A($clog2(DEPTH)),  // DECIMAL
  .AUTO_SLEEP_TIME(0),           // DECIMAL
  .CASCADE_HEIGHT(0),            // DECIMAL
  .ECC_BIT_RANGE("7:0"),         // String
  .ECC_MODE("no_ecc"),           // String
  .ECC_TYPE("none"),             // String
  .IGNORE_INIT_SYNTH(0),         // DECIMAL
  .MEMORY_INIT_FILE(INIT_FILE),  // String
  .MEMORY_INIT_PARAM(""),        // String
  .MEMORY_OPTIMIZATION("true"),  // String
  .MEMORY_PRIMITIVE("auto"),     // String
  .MEMORY_SIZE(DEPTH * 8),       // DECIMAL
  .MESSAGE_CONTROL(0),           // DECIMAL
  .RAM_DECOMP("auto"),           // String
  .READ_DATA_WIDTH_A(8),         // DECIMAL
  .READ_LATENCY_A(1),            // DECIMAL
  .READ_RESET_VALUE_A("0"),      // String
  .RST_MODE_A("SYNC"),           // String
  .SIM_ASSERT_CHK(0),            // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
  .USE_MEM_INIT(0),              // DECIMAL
  .USE_MEM_INIT_MMI(0),          // DECIMAL
  .WAKEUP_TIME("disable_sleep")  // String
)
xpm_memory_sprom_inst (
  .dbiterra(),                     // 1-bit output: Leave open.
  .douta(douta),                   // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
  .sbiterra(),                     // 1-bit output: Leave open.
  .addra(addra),                   // ADDR_WIDTH_A-bit input: Address for port A read operations.
  .clka(clka),                     // 1-bit input: Clock signal for port A.
  .ena(1'b1),                      // 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read operations are
                                   // initiated. Pipelined internally.

  .injectdbiterra(1'b0),           // 1-bit input: Do not change from the provided value.
  .injectsbiterra(1'b0),           // 1-bit input: Do not change from the provided value.
  .regcea(1'b1),                   // 1-bit input: Do not change from the provided value.
  .rsta(1'b0),                     // 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                   // douta to the value specified by parameter READ_RESET_VALUE_A.

  .sleep(1'b0)                     // 1-bit input: sleep signal to enable the dynamic power saving feature.
);

endmodule
