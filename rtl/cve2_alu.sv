// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Native RV64I arithmetic logic unit.
 *
 * This branch uses a conventional 64-bit datapath. The RV32B and mult/div
 * compatibility ports are kept so the surrounding CVE2 module interfaces stay
 * close to the existing code, but RV64I synthesis should set RV32B=RV32BNone
 * and RV32M=RV32MNone.
 */
module cve2_alu #(
  parameter cve2_pkg::rv32b_e RV32B = cve2_pkg::RV32BNone
) (
  input  cve2_pkg::alu_op_e operator_i,
  input  logic [63:0]       operand_a_i,
  input  logic [63:0]       operand_b_i,

  input  logic              instr_first_cycle_i,
  input  logic              word_op_i,

  input  logic [32:0]       multdiv_operand_a_i,
  input  logic [32:0]       multdiv_operand_b_i,

  input  logic              multdiv_sel_i,

  input  logic [31:0]       imd_val_q_i[2],
  output logic [31:0]       imd_val_d_o[2],
  output logic [1:0]        imd_val_we_o,

  input  logic              carry_in_i,
  output logic              carry_out_o,

  output logic [63:0]       adder_result_o,
  output logic [33:0]       adder_result_ext_o,

  output logic [63:0]       result_o,
  output logic              comparison_result_o,
  output logic              is_equal_result_o
);
  import cve2_pkg::*;

  logic        adder_sub;
  logic [64:0] adder_ext;
  logic [63:0] adder_b;
  logic        cmp_lt_signed;
  logic        cmp_lt_unsigned;
  logic        cmp_result;
  logic [5:0]  shift_amt;
  logic [31:0] word_addsub_result;
  logic [63:0] shift_operand;
  logic [63:0] shift_result;
  logic [63:0] word_result_sext;

  always_comb begin
    unique case (operator_i)
      ALU_SUB,
      ALU_EQ,  ALU_NE,
      ALU_GE,  ALU_GEU,
      ALU_LT,  ALU_LTU,
      ALU_SLT, ALU_SLTU: adder_sub = 1'b1;
      default:           adder_sub = 1'b0;
    endcase
  end

  assign adder_b   = adder_sub ? ~operand_b_i : operand_b_i;
  assign adder_ext = {1'b0, operand_a_i} + {1'b0, adder_b} + {64'h0, adder_sub};

  assign adder_result_o     = adder_ext[63:0];
  assign carry_out_o        = adder_ext[64];
  assign adder_result_ext_o = {1'b0, adder_ext[32:0]};

  assign is_equal_result_o = (adder_result_o == 64'h0);

  assign cmp_lt_signed   = (operand_a_i[63] != operand_b_i[63]) ?
                           operand_a_i[63] : adder_result_o[63];
  assign cmp_lt_unsigned = ~adder_ext[64];

  always_comb begin
    unique case (operator_i)
      ALU_EQ:   cmp_result =  is_equal_result_o;
      ALU_NE:   cmp_result = ~is_equal_result_o;
      ALU_LT,
      ALU_SLT:  cmp_result =  cmp_lt_signed;
      ALU_LTU,
      ALU_SLTU: cmp_result =  cmp_lt_unsigned;
      ALU_GE:   cmp_result = ~cmp_lt_signed;
      ALU_GEU:  cmp_result = ~cmp_lt_unsigned;
      default:  cmp_result =  is_equal_result_o;
    endcase
  end

  assign comparison_result_o = cmp_result;

  assign shift_amt = word_op_i ? {1'b0, operand_b_i[4:0]} : operand_b_i[5:0];

  // RV64 W-shifts operate on rs1[31:0] and sign-extend the 32-bit result.
  // Feed those operations through the same 64-bit shifter used by full-width
  // shifts instead of building a second 32-bit shifter in parallel.
  always_comb begin
    shift_operand = operand_a_i;
    if (word_op_i) begin
      shift_operand = (operator_i == ALU_SRA) ?
          {{32{operand_a_i[31]}}, operand_a_i[31:0]} :
          {32'h0000_0000, operand_a_i[31:0]};
    end
  end

  always_comb begin
    unique case (operator_i)
      ALU_SLL:  shift_result = shift_operand << shift_amt;
      ALU_SRL:  shift_result = shift_operand >> shift_amt;
      ALU_SRA:  shift_result = $unsigned($signed(shift_operand) >>> shift_amt);
      default:  shift_result = shift_operand;
    endcase
  end

  assign word_addsub_result = adder_result_o[31:0];
  assign word_result_sext = {{32{shift_result[31]}}, shift_result[31:0]};

  always_comb begin
    unique case (operator_i)
      ALU_ADD,
      ALU_SUB: begin
        result_o = word_op_i ? {{32{word_addsub_result[31]}}, word_addsub_result}
                             : adder_result_o;
      end

      ALU_AND: result_o = operand_a_i & operand_b_i;
      ALU_OR:  result_o = operand_a_i | operand_b_i;
      ALU_XOR: result_o = operand_a_i ^ operand_b_i;

      ALU_SLL,
      ALU_SRL,
      ALU_SRA: result_o = word_op_i ? word_result_sext : shift_result;

      ALU_SLT,
      ALU_SLTU: result_o = {63'h0, cmp_result};

      default: result_o = adder_result_o;
    endcase
  end

  assign imd_val_d_o  = '{default: '0};
  assign imd_val_we_o = '0;

  logic unused_inputs;
  assign unused_inputs = instr_first_cycle_i ^ carry_in_i ^ multdiv_sel_i ^
                         ^multdiv_operand_a_i ^ ^multdiv_operand_b_i ^
                         ^imd_val_q_i[0] ^ ^imd_val_q_i[1] ^
                         (RV32B != RV32BNone);

endmodule
