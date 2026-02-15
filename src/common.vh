/********************************************************************************
 *                                                                              *
 * Copyright (C) 2026 Robin Sergeant                                            *
 *                                                                              *
 * Common functionality shared between modules                                  *
 *                                                                              *
 ********************************************************************************/

function automatic [10:0] vram_address;
  input [4:0] row;
  input [6:0] col;
  input [4:0] counter;
  begin
    vram_address = (((row + counter) % 24) * 80) + col;
  end
endfunction