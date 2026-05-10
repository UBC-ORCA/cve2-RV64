// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Writeback passthrough
 *
 * The writeback stage is not present therefore this module acts as
 * a simple passthrough to write data direct to the register file.
 */

`include "prim_assert.sv"
`include "dv_fcov_macros.svh"

module cve2_wb #(
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     en_wb_i,

  input  logic                     instr_is_compressed_id_i,
  input  logic                     instr_perf_count_id_i,

  output logic                     perf_instr_ret_wb_o,
  output logic                     perf_instr_ret_compressed_wb_o,

  input  logic [4:0]               rf_waddr_id_i,
  input  logic [63:0]              rf_wdata_id_i,
  input  logic                     rf_we_id_i,                  

  input  logic [63:0]              rf_wdata_lsu_i,
  input  logic                     rf_we_lsu_i,

  output logic [4:0]               rf_waddr_wb_o,
  output logic [63:0]              rf_wdata_wb_o,
  output logic                     rf_we_wb_o,

  input logic                      lsu_resp_valid_i,
  input logic                      lsu_resp_err_i
);

  import cve2_pkg::*;

    // without writeback stage just pass through register write signals
    assign rf_waddr_wb_o         = rf_waddr_id_i;

    // Increment instruction retire counters for valid instructions which are not lsu errors.
    assign perf_instr_ret_wb_o                 = instr_perf_count_id_i & en_wb_i &
                                                 ~(lsu_resp_valid_i & lsu_resp_err_i);
    assign perf_instr_ret_compressed_wb_o      = perf_instr_ret_wb_o & instr_is_compressed_id_i;

  // RF write data can come from ID results (all RF writes that aren't because of loads will come
  // from here) or the LSU (RF writes for load data)
  assign rf_wdata_wb_o = rf_we_lsu_i ? rf_wdata_lsu_i : rf_wdata_id_i;
  assign rf_we_wb_o    = rf_we_id_i | rf_we_lsu_i;

  `ASSERT(RFWriteFromOneSourceOnly, $onehot0({rf_we_id_i, rf_we_lsu_i}))
endmodule
