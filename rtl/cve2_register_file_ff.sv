// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * RISC-V register file
 *
 * Register file with 31 or 15 architectural registers split into lower/upper
 * 32-bit physical entries. Register 0 is fixed to 0.
 *
 * The physical data storage is organized as 2 * NUM_WORDS 32-bit entries, using
 * {upper_half, architectural_register} as the memory address. Two mirrored data
 * memories provide the two architectural read ports while writes update both
 * copies. This keeps the datapath 32 bits wide and makes the RF structure closer
 * to FPGA RAM inference than the original lower/upper FF-bank implementation.
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

  localparam int unsigned ADDR_WIDTH     = RV32E ? 4 : 5;
  localparam int unsigned NUM_WORDS      = 2**ADDR_WIDTH;
  localparam int unsigned NUM_PHYS_WORDS = 2 * NUM_WORDS;

  logic [ADDR_WIDTH-1:0] raddr_a;
  logic [ADDR_WIDTH-1:0] raddr_b;
  logic [ADDR_WIDTH-1:0] waddr_a;
  logic [ADDR_WIDTH:0]   raddr_a_phys;
  logic [ADDR_WIDTH:0]   raddr_b_phys;
  logic [ADDR_WIDTH:0]   waddr_a_phys;
  logic                  we_a_nonzero;

  (* ram_style = "block" *)
  logic [DataWidth-1:0] rf_mem_a [0:NUM_PHYS_WORDS-1];

  (* ram_style = "block" *)
  logic [DataWidth-1:0] rf_mem_b [0:NUM_PHYS_WORDS-1];

  logic [NUM_WORDS-1:1][1:0] tag_q;

  assign raddr_a       = raddr_a_i[ADDR_WIDTH-1:0];
  assign raddr_b       = raddr_b_i[ADDR_WIDTH-1:0];
  assign waddr_a       = waddr_a_i[ADDR_WIDTH-1:0];
  assign raddr_a_phys  = {r_a_upper_i, raddr_a};
  assign raddr_b_phys  = {r_b_upper_i, raddr_b};
  assign waddr_a_phys  = {w_upper_i, waddr_a};
  assign we_a_nonzero  = we_a_i && (waddr_a_i != 5'd0);

  initial begin : rf_mem_init
    for (int unsigned i = 0; i < NUM_PHYS_WORDS; i++) begin
      rf_mem_a[i] = WordZeroVal;
      rf_mem_b[i] = WordZeroVal;
    end
  end

  always @(posedge clk_i) begin : rf_mem_write
    if (we_a_nonzero) begin
      rf_mem_a[waddr_a_phys] <= wdata_a_i;
      rf_mem_b[waddr_a_phys] <= wdata_a_i;
    end
  end

  for (genvar i = 1; i < NUM_WORDS; i++) begin : g_tag_flops
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tag_q[i] <= 2'b10;
      end else if (we_a_nonzero && (waddr_a == ADDR_WIDTH'(i))) begin
        tag_q[i] <= w_tag_i;
      end
    end
  end

  // Simulation-only aliases for older ModelSim wave scripts and debugging.
  // synthesis translate_off
  logic [NUM_WORDS-1:0][DataWidth-1:0] rf_reg_lower;
  logic [NUM_WORDS-1:0][DataWidth-1:0] rf_reg_upper;
  logic [NUM_WORDS-1:1][DataWidth-1:0] rf_reg_q_lower;
  logic [NUM_WORDS-1:1][DataWidth-1:0] rf_reg_q_upper;

  assign rf_reg_lower[0] = WordZeroVal;
  assign rf_reg_upper[0] = WordZeroVal;

//  always_ff @(posedge clk_i) begin
//    if (rst_ni && we_a_nonzero) begin
//      $display("[RFDBG] wr x%0d upper=%0b data=%08h tag=%b",
//              waddr_a_i, w_upper_i, wdata_a_i, w_tag_i);
//    end
//  end

  for (genvar i = 1; i < NUM_WORDS; i++) begin : g_rf_wave_aliases
    assign rf_reg_lower[i]   = rf_mem_a[{1'b0, ADDR_WIDTH'(i)}];
    assign rf_reg_upper[i]   = rf_mem_a[{1'b1, ADDR_WIDTH'(i)}];
    assign rf_reg_q_lower[i] = rf_reg_lower[i];
    assign rf_reg_q_upper[i] = rf_reg_upper[i];
  end
  // synthesis translate_on

  assign rdata_a_o = (raddr_a_i == 5'd0) ? WordZeroVal : rf_mem_a[raddr_a_phys];
  assign rdata_b_o = (raddr_b_i == 5'd0) ? WordZeroVal : rf_mem_b[raddr_b_phys];

  assign r_a_tag_o = (raddr_a_i == 5'd0) ? 2'b10 : tag_q[raddr_a];
  assign r_b_tag_o = (raddr_b_i == 5'd0) ? 2'b10 : tag_q[raddr_b];

  // Signal not used in FF register file
  logic unused_test_en;
  assign unused_test_en = test_en_i;

endmodule
