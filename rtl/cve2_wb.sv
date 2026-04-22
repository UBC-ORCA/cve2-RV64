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
  input  logic [31:0]              rf_wdata_id_i,
  input  logic                     rf_we_id_i,                  

  input  logic [31:0]              rf_wdata_lsu_i,
  input  logic                     rf_we_lsu_i,

  output logic [4:0]               rf_waddr_wb_o,
  output logic [31:0]              rf_wdata_wb_o,
  output logic                     rf_we_wb_o,

  input logic                      lsu_resp_valid_i,
  input logic                      lsu_resp_err_i,

  output logic [1:0]               w_tag_o,
  input  logic [1:0]               w_tag_id_i,
  input  logic                     w_upper_i,
  output logic                     w_upper_o
);

  import cve2_pkg::*;

  // 0 == RF write from ID
  // 1 == RF write from LSU
  logic [31:0] rf_wdata_wb_mux    [2];
  logic [1:0]  rf_wdata_wb_mux_we;

    // without writeback stage just pass through register write signals
    assign rf_waddr_wb_o         = rf_waddr_id_i;
    assign rf_wdata_wb_mux[0]    = rf_wdata_id_i;
    assign rf_wdata_wb_mux_we[0] = rf_we_id_i;

    // Increment instruction retire counters for valid instructions which are not lsu errors.
    assign perf_instr_ret_wb_o                 = instr_perf_count_id_i & en_wb_i &
                                                 ~(lsu_resp_valid_i & lsu_resp_err_i);
    assign perf_instr_ret_compressed_wb_o      = perf_instr_ret_wb_o & instr_is_compressed_id_i;

  assign rf_wdata_wb_mux[1]    = rf_wdata_lsu_i;
  assign rf_wdata_wb_mux_we[1] = rf_we_lsu_i;

  // RF write data can come from ID results (all RF writes that aren't because of loads will come
  // from here) or the LSU (RF writes for load data)
  assign rf_wdata_wb_o = ({32{rf_wdata_wb_mux_we[0]}} & rf_wdata_wb_mux[0]) |
                         ({32{rf_wdata_wb_mux_we[1]}} & rf_wdata_wb_mux[1]);
  assign rf_we_wb_o    = |rf_wdata_wb_mux_we;

  assign w_upper_o = w_upper_i;

  // Tag computation:
  //   Upper-half write (2nd cycle): derive tag from actual upper result data
  //   Lower-half write (1st or only cycle): use tag computed by ID stage
  always_comb begin
    if (w_upper_i) begin
      // 2nd cycle of 2-cycle add: finalize tag from upper result
      if (rf_wdata_id_i == 32'h0000_0000)
        w_tag_o = 2'b10;
      else if (rf_wdata_id_i == 32'hFFFF_FFFF)
        w_tag_o = 2'b11;
      else
        w_tag_o = 2'b01;
    end else begin
      // Lower-half write: tag from ID stage
      // For 1-cycle adds: this is the final tag
      // For 2-cycle adds: gets overwritten by the upper write next cycle
      w_tag_o = w_tag_id_i;
    end
  end

  `ASSERT(RFWriteFromOneSourceOnly, $onehot0(rf_wdata_wb_mux_we))
endmodule