// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * RISC-V register file
 *
 * Native RV64 register file with 31 or 15 architectural registers. Register 0
 * is fixed to 0.
 */
module cve2_register_file_ff #(
  parameter bit                   RV32E             = 0,
  parameter int unsigned          DataWidth         = 64,
  parameter logic [DataWidth-1:0] WordZeroVal       = '0
) (
  // Clock and Reset
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 test_en_i,

  //Read port R1
  input  logic [4:0]           raddr_a_i,
  output logic [DataWidth-1:0] rdata_a_o,

  //Read port R2
  input  logic [4:0]           raddr_b_i,
  output logic [DataWidth-1:0] rdata_b_o,

  // Write port W1
  input  logic [4:0]           waddr_a_i,
  input  logic [DataWidth-1:0] wdata_a_i,
  input  logic                 we_a_i
);

  localparam int unsigned ADDR_WIDTH = RV32E ? 4 : 5;
  localparam int unsigned NUM_WORDS  = 2**ADDR_WIDTH;

  logic [ADDR_WIDTH-1:0] raddr_a;
  logic [ADDR_WIDTH-1:0] raddr_b;
  logic [ADDR_WIDTH-1:0] waddr_a;
  logic                  we_a_nonzero;

  (* ram_style = "distributed" *)
  logic [DataWidth-1:0] rf_mem_a [0:NUM_WORDS-1];

  (* ram_style = "distributed" *)
  logic [DataWidth-1:0] rf_mem_b [0:NUM_WORDS-1];

  assign raddr_a      = raddr_a_i[ADDR_WIDTH-1:0];
  assign raddr_b      = raddr_b_i[ADDR_WIDTH-1:0];
  assign waddr_a      = waddr_a_i[ADDR_WIDTH-1:0];
  assign we_a_nonzero = we_a_i && (waddr_a_i != 5'd0);

  initial begin : rf_mem_init
    for (int unsigned i = 0; i < NUM_WORDS; i++) begin
      rf_mem_a[i] = WordZeroVal;
      rf_mem_b[i] = WordZeroVal;
    end
  end

  always @(posedge clk_i) begin : rf_mem_write
    if (we_a_nonzero) begin
      rf_mem_a[waddr_a] <= wdata_a_i;
      rf_mem_b[waddr_a] <= wdata_a_i;
    end
  end

  // Simulation-only aliases for older ModelSim wave scripts and debugging.
  // synthesis translate_off
  logic [NUM_WORDS-1:0][31:0] rf_reg_lower;
  logic [NUM_WORDS-1:0][31:0] rf_reg_upper;
  logic [NUM_WORDS-1:1][31:0] rf_reg_q_lower;
  logic [NUM_WORDS-1:1][31:0] rf_reg_q_upper;

  assign rf_reg_lower[0] = 32'h0000_0000;
  assign rf_reg_upper[0] = 32'h0000_0000;

  for (genvar i = 1; i < NUM_WORDS; i++) begin : g_rf_wave_aliases
    assign rf_reg_lower[i]   = rf_mem_a[i][31:0];
    assign rf_reg_upper[i]   = rf_mem_a[i][63:32];
    assign rf_reg_q_lower[i] = rf_reg_lower[i];
    assign rf_reg_q_upper[i] = rf_reg_upper[i];
  end
  // synthesis translate_on

  assign rdata_a_o = (raddr_a_i == 5'd0) ? WordZeroVal : rf_mem_a[raddr_a];
  assign rdata_b_o = (raddr_b_i == 5'd0) ? WordZeroVal : rf_mem_b[raddr_b];

  // Signal not used in this register file.
  logic unused_test_en;
  assign unused_test_en = test_en_i;

endmodule
