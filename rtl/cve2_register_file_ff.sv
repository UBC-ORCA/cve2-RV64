// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * RISC-V register file
 *
 * Register file with 31 or 15x 32 bit wide registers. Register 0 is fixed to 0.
 * This register file is based on flip flops. Use this register file when
 * targeting FPGA synthesis or Verilator simulation.
 */
module cve2_register_file_ff #(
  parameter bit                   RV32E             = 0,
  parameter int unsigned          DataWidth         = 32,
  parameter logic [DataWidth-1:0] WordZeroVal       = '0
) (
  // Clock and Reset
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 test_en_i,

  //Read port R1
  input  logic [4:0]           raddr_a_i,
  output logic [DataWidth-1:0] rdata_a_o,
  input  logic                 r_a_upper_i,
  output logic [1:0]           r_a_tag_o,

  //Read port R2
  input  logic [4:0]           raddr_b_i,
  output logic [DataWidth-1:0] rdata_b_o,
  input  logic                 r_b_upper_i,
  output logic [1:0]           r_b_tag_o,

  // Write port W1
  input  logic [4:0]           waddr_a_i,
  input  logic [DataWidth-1:0] wdata_a_i,
  input  logic                 we_a_i,
  input  logic [1:0]           w_tag_i,

  input  logic                 w_upper_i
);

  localparam int unsigned ADDR_WIDTH = RV32E ? 4 : 5;
  localparam int unsigned NUM_WORDS  = 2**ADDR_WIDTH;

  logic [NUM_WORDS-1:0][DataWidth-1:0] rf_reg_lower;
  logic [NUM_WORDS-1:1][DataWidth-1:0] rf_reg_q_lower;

  logic [NUM_WORDS-1:0][DataWidth-1:0] rf_reg_upper;
  logic [NUM_WORDS-1:1][DataWidth-1:0] rf_reg_q_upper;

  logic [NUM_WORDS-1:1][1:0]           tag_q;

  logic [NUM_WORDS-1:1]                we_a_dec;


  always_comb begin : we_a_decoder
    for (int unsigned i = 1; i < NUM_WORDS; i++) begin
      we_a_dec[i] = (waddr_a_i == 5'(i)) ? we_a_i : 1'b0;
    end
  end

  // No flops for R0 as it's hard-wired to 0
  for (genvar i = 1; i < NUM_WORDS; i++) begin : g_rf_flops
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rf_reg_q_lower[i] <= WordZeroVal;
        rf_reg_q_upper[i] <= WordZeroVal;
        tag_q[i] <= 2'b0;
      end else if (we_a_dec[i]) begin
        tag_q[i] <= w_tag_i;
        if(w_upper_i) begin
          rf_reg_q_upper[i] <= wdata_a_i;
        end else begin
          rf_reg_q_lower[i] <= wdata_a_i;
        end
      end
    end
  end

  // R0 is nil
  assign rf_reg_lower[0] = WordZeroVal;
  assign rf_reg_upper[0] = WordZeroVal;

  assign rf_reg_lower[NUM_WORDS-1:1] = rf_reg_q_lower[NUM_WORDS-1:1];
  assign rf_reg_upper[NUM_WORDS-1:1] = rf_reg_q_upper[NUM_WORDS-1:1];

  assign rdata_a_o = r_a_upper_i ? rf_reg_upper[raddr_a_i] : rf_reg_lower[raddr_a_i];
  assign rdata_b_o = r_b_upper_i ? rf_reg_upper[raddr_b_i] : rf_reg_lower[raddr_b_i];

  assign r_a_tag_o = (raddr_a_i == 5'd0) ? 2'b00 : tag_q[raddr_a_i];
  assign r_b_tag_o = (raddr_b_i == 5'd0) ? 2'b00 : tag_q[raddr_b_i];

  // Signal not used in FF register file
  logic unused_test_en;
  assign unused_test_en = test_en_i;

endmodule
