// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifdef RISCV_FORMAL
  `define RVFI
`endif

/**
 * Instruction Decode Stage
 *
 * Decode stage of the core. It decodes the instructions and hosts the register
 * file.
 */

`include "prim_assert.sv"
`include "dv_fcov_macros.svh"

module cve2_id_stage #(
  parameter bit               RV32E           = 0,
  parameter cve2_pkg::rv32m_e RV32M           = cve2_pkg::RV32MFast,
  parameter cve2_pkg::rv32b_e RV32B           = cve2_pkg::RV32BNone,
  parameter bit               XInterface      = 1'b0
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  input  logic                      fetch_enable_i,
  output logic                      ctrl_busy_o,
  output logic                      illegal_insn_o,

  // Interface to IF stage
  input  logic                      instr_valid_i,
  input  logic [31:0]               instr_rdata_i,
  input  logic [31:0]               instr_rdata_alu_i,
  input  logic [15:0]               instr_rdata_c_i,
  input  logic                      instr_is_compressed_i,
  output logic                      instr_req_o,
  output logic                      instr_first_cycle_id_o,
  output logic                      instr_valid_clear_o,
  output logic                      id_in_ready_o,

  // Jumps and branches
  input  logic                      branch_decision_i,
  input  logic                      alu_is_equal_result_i,

  // IF and ID stage signals
  output logic                      pc_set_o,
  output cve2_pkg::pc_sel_e         pc_mux_o,
  output cve2_pkg::exc_pc_sel_e     exc_pc_mux_o,
  output cve2_pkg::exc_cause_e      exc_cause_o,

  input  logic                      illegal_c_insn_i,
  input  logic                      instr_fetch_err_i,
  input  logic                      instr_fetch_err_plus2_i,

  input  logic [31:0]               pc_id_i,
  input  logic [31:0]               pc_id_upper_i,

  // Stalls
  input  logic                      ex_valid_i,
  input  logic                      lsu_resp_valid_i,
  // ALU
  output cve2_pkg::alu_op_e         alu_operator_ex_o,
  output logic [31:0]               alu_operand_a_ex_o,
  output logic [31:0]               alu_operand_b_ex_o,

  // Multicycle Operation Stage Register
  input  logic [1:0]                imd_val_we_ex_i,
  input  logic [33:0]               imd_val_d_ex_i[2],
  output logic [33:0]               imd_val_q_ex_o[2],

  input  logic                      carry_out_i,
  output logic                      carry_in_o,

  // MUL, DIV
  output logic                      mult_en_ex_o,
  output logic                      div_en_ex_o,
  output logic                      mult_sel_ex_o,
  output logic                      div_sel_ex_o,
  output cve2_pkg::md_op_e          multdiv_operator_ex_o,
  output logic  [1:0]               multdiv_signed_mode_ex_o,
  output logic [31:0]               multdiv_operand_a_ex_o,
  output logic [31:0]               multdiv_operand_b_ex_o,

  // CSR
  output logic                      csr_access_o,
  output cve2_pkg::csr_op_e         csr_op_o,
  output logic                      csr_op_en_o,
  output logic                      csr_save_if_o,
  output logic                      csr_save_id_o,
  output logic                      csr_restore_mret_id_o,
  output logic                      csr_restore_dret_id_o,
  output logic                      csr_save_cause_o,
  output logic [63:0]               csr_mtval_o,
  output logic [31:0]               csr_wdata_o,
  output logic                      csr_wdata_upper_o,
  output logic                      csr_wdata_capture_o,
  output logic                      csr_rdata_upper_o,
  output logic                      csr_rdata_capture_o,
  input  cve2_pkg::priv_lvl_e       priv_mode_i,
  input  logic                      csr_mstatus_tw_i,
  input  logic                      illegal_csr_insn_i,

  // Interface to load store unit
  output logic                      lsu_req_o,
  output logic                      lsu_we_o,
  output logic [1:0]                lsu_type_o,
  output logic                      lsu_sign_ext_o,
  output logic [31:0]               lsu_wdata_o,

  input  logic                      lsu_addr_incr_req_i,
  input  logic [63:0]               lsu_addr_last_i,

  //  Core-V eXtension Interface (CV-X-IF)
  input  logic [31:0]               hart_id_i,
  //  Issue Interface
  output logic                      x_issue_valid_o,
  input  logic                      x_issue_ready_i,
  output cve2_pkg::x_issue_req_t    x_issue_req_o,
  input  cve2_pkg::x_issue_resp_t   x_issue_resp_i,

  // Register Interface
  output  cve2_pkg::x_register_t    x_register_o,
  output  logic                     r_a_upper_o,
  output  logic                     r_b_upper_o,

  // Commit Interface
  output logic                      x_commit_valid_o,
  output cve2_pkg::x_commit_t       x_commit_o,

  // Result Interface
  input  logic                      x_result_valid_i,
  output logic                      x_result_ready_o,
  input   cve2_pkg::x_result_t      x_result_i,

  // Interrupt signals
  input  logic                      csr_mstatus_mie_i,
  input  logic                      irq_pending_i,
  input  cve2_pkg::irqs_t           irqs_i,
  input  logic                      irq_nm_i,
  output logic                      nmi_mode_o,

  input  logic                      lsu_load_err_i,
  input  logic                      lsu_store_err_i,

  // Debug Signal
  output logic                      debug_mode_o,
  output cve2_pkg::dbg_cause_e      debug_cause_o,
  output logic                      debug_csr_save_o,
  input  logic                      debug_req_i,
  input  logic                      debug_single_step_i,
  input  logic                      debug_ebreakm_i,
  input  logic                      debug_ebreaku_i,
  input  logic                      trigger_match_i,

  // Write back signal
  input  logic [31:0]               result_ex_i,
  input  logic [31:0]               csr_rdata_i,

  // Register file read
  output logic [4:0]                rf_raddr_a_o,
  input  logic [31:0]               rf_rdata_a_i,
  output logic [4:0]                rf_raddr_b_o,
  input  logic [31:0]               rf_rdata_b_i,
  output logic                      rf_ren_a_o,
  output logic                      rf_ren_b_o,

  // Register file write (via writeback)
  output logic [4:0]                rf_waddr_id_o,
  output logic [31:0]               rf_wdata_id_o,
  output logic                      rf_we_id_o,
  output logic                      rf_w_upper_id_o,
  output logic [63:0]               lsu_addr_ex_o,
  output logic [63:0]               pc_target_ex_o,

  output  logic                     en_wb_o,
  output  logic                     instr_perf_count_id_o,

  // Performance Counters
  output logic                      perf_jump_o,
  output logic                      perf_branch_o,
  output logic                      perf_tbranch_o,
  output logic                      perf_dside_wait_o,
  output logic                      perf_wfi_wait_o,
  output logic                      perf_div_wait_o,
  output logic                      instr_id_done_o
);

  import cve2_pkg::*;

  // Decoder/Controller, ID stage internal signals
  logic        illegal_insn_dec;
  logic        ebrk_insn;
  logic        mret_insn_dec;
  logic        dret_insn_dec;
  logic        ecall_insn_dec;
  logic        wfi_insn_dec;

  logic        branch_in_dec;
  logic        branch_set, branch_set_raw, branch_set_raw_d;
  logic        branch_jump_set_done_q, branch_jump_set_done_d;
  logic        jump_in_dec;
  logic        jump_set_dec;
  logic        jump_set, jump_set_raw;

  logic        instr_first_cycle;
  logic        instr_executing_spec;
  logic        instr_executing;
  logic        instr_done;
  logic        controller_run;
  logic        stall_mem;
  logic        stall_multdiv;
  logic        stall_branch;
  logic        stall_jump;
  logic        stall_id;
  logic        flush_id;
  logic        multicycle_done;

  // Immediate decoding and sign extension
  logic [31:0] imm_i_type;
  logic [31:0] imm_s_type;
  logic [31:0] imm_b_type;
  logic [31:0] imm_u_type;
  logic [31:0] imm_j_type;
  logic [31:0] zimm_rs1_type;

  logic [31:0] imm_a;
  logic [31:0] imm_b;

  // Register file interface

  logic [XInterface:0] rf_wdata_sel;
  logic                rf_we_dec, rf_we_raw;
  logic                rf_ren_a, rf_ren_b;
  logic                rf_ren_a_dec, rf_ren_b_dec;

  assign rf_ren_a = instr_valid_i & ~instr_fetch_err_i & ~illegal_insn_o & rf_ren_a_dec;
  assign rf_ren_b = instr_valid_i & ~instr_fetch_err_i & ~illegal_insn_o & rf_ren_b_dec;

  assign rf_ren_a_o = rf_ren_a;
  assign rf_ren_b_o = rf_ren_b;

  logic [31:0] rf_rdata_a_fwd;
  logic [31:0] rf_rdata_b_fwd;

  // ALU Control
  alu_op_e     alu_operator;
  op_a_sel_e   alu_op_a_mux_sel, alu_op_a_mux_sel_dec;
  op_b_sel_e   alu_op_b_mux_sel, alu_op_b_mux_sel_dec;
  logic        alu_multicycle_dec;
  logic        stall_alu;
  alu_op_e     alu_operator_eff;

  logic [33:0] imd_val_q[2];

  imm_a_sel_e  imm_a_mux_sel;
  imm_b_sel_e  imm_b_mux_sel, imm_b_mux_sel_dec;

  // ==== 64-bit execution control ====
  op_class_e   op_class;
  logic        op_uses_64_path;
  logic        is_op_or_op_imm;
  logic        is_word_op;
  logic        needs_upper_cycle;
  logic [31:0] imm_b_eff;
  logic        use_upper_half_operand_a;
  logic        use_upper_half_operand_b;
  logic        cmp_is_compare;
  logic        cmp_is_lower_cycle;
  logic        cmp_write_upper_cycle;
  logic        cmp_use_upper_first;
  logic        cmp_need_lower_after_upper;
  logic        shift_is_64;
  logic        shift_is_left;
  logic        shift_is_right;
  logic        shift_is_arith;
  logic [5:0]  shift_amt_now;
  logic [5:0]  shift_amt_q;
  logic [5:0]  shift_amt;
  logic [5:0]  shift_amt_compl;
  logic        shift_amt_zero;
  logic        shift_amt_ge32;
  logic        shift_amt_lt32_nonzero;
  logic        shift_first_save;
  logic        shift_capture;
  logic        shift_imd_we;
  logic        shift_use_upper_a;
  logic [5:0]  shift_amt_to_alu;
  logic [31:0] alu_operand_b_base;
  logic [31:0] rf_wdata_shift;
  logic        is_lui_op;
  logic        is_auipc_op;
  logic        is_jump_op;
  logic        pcadd_active;
  logic        pcadd_upper_cycle;
  logic        pcadd_lower_cycle;
  logic [31:0] pc_id_upper_eff;
  logic [31:0] pc_id_operand;
  logic        is_jalr_op;
  logic        addr_upper_cycle;
  logic        addr_needs_upper_cycle;
  logic        addr_capture_lower;
  logic        addr_use_upper_a;
  logic [31:0] addr_lower_q;
  logic        addr_carry_q;
  logic [31:0] addr_src_upper;
  logic [31:0] addr_imm_upper;
  logic [31:0] addr_upper_comb;
  logic [31:0] addr_lower_result;
  logic [31:0] addr_upper_result;
  logic [63:0] addr_result_ex;
  logic        signext_upper_cycle;
  logic [31:0] signext_upper_fill_q;
  logic [31:0] signext_upper_fill_now;
  logic        csr_upper_cycle;
  logic        csr_is_imm_op;
  logic        csr_src_needs_upper;
  logic        csr_read_needs_upper;
  logic        csr_need_upper_cycle;
  logic        csr_src_needs_upper_q;
  logic        csr_read_needs_upper_q;
  logic [31:0] csr_src_lower_q;
  logic [31:0] csr_src_lower_now;

  // Multiplier Control
  logic        mult_en_id, mult_en_dec;
  logic        div_en_id, div_en_dec;
  logic        multdiv_en_dec;
  md_op_e      multdiv_operator;
  logic [1:0]  multdiv_signed_mode;

  // Data Memory Control
  logic        lsu_we;
  logic [1:0]  lsu_type;
  logic        lsu_sign_ext;
  logic        lsu_req, lsu_req_dec;
  logic        lsu_store_upper_half;
  logic [31:0] lsu_wdata_upper;
  logic        data_req_allowed;

  // CSR control
  logic        csr_pipe_flush;

  logic [31:0] alu_operand_a;
  logic [31:0] alu_operand_b;

  // CV-X-IF
  logic stall_coproc;
  logic scoreboard_busy;

  ///////////////
  // ID-EX FSM //
  ///////////////

  typedef enum logic [3:0] {
    FIRST_CYCLE,
    MULTI_CYCLE,
    CMP_LOWER_CYCLE,
    CMP_UPPER_WRITE_CYCLE,
    SHIFT_LOW_CYCLE,
    SHIFT_UPPER_CYCLE,
    PC_UPPER_CYCLE,
    ADDR_UPPER_CYCLE,
    SIGNEXT_UPPER_CYCLE,
    CSR_UPPER_CYCLE
  } id_fsm_e;
  id_fsm_e id_fsm_q, id_fsm_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin : id_pipeline_reg
    if (!rst_ni) begin
      id_fsm_q <= FIRST_CYCLE;
    end else if (instr_executing) begin
      id_fsm_q <= id_fsm_d;
    end
  end

  // CV-X-IF
  if (XInterface) begin: gen_xif

    logic coproc_done;
    logic [X_INSTR_INFLIGHT-1:0] scoreboard_d, scoreboard_q;
    id_t x_instr_id_d, x_instr_id_q;

    logic scoreboard_free;

    assign scoreboard_free = ~scoreboard_q[x_instr_id_q];
    assign scoreboard_busy = (scoreboard_q != '0);

    always_comb begin
      scoreboard_d = scoreboard_q;
      x_instr_id_d = x_instr_id_q;
      if (x_issue_valid_o && x_issue_ready_i && x_issue_resp_i.accept) begin
        scoreboard_d[x_instr_id_q] = 1'b1;
        x_instr_id_d = x_instr_id_q + 1'b1;
      end
      if (x_result_valid_i) begin
        scoreboard_d[x_result_i.id] = 1'b0;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : x_scoreboard
      if (!rst_ni) begin
        scoreboard_q <= '0;
        x_instr_id_q <= '0;
      end else begin
        scoreboard_q <= scoreboard_d;
        x_instr_id_q <= x_instr_id_d;
      end
    end

    assign multicycle_done = lsu_req_dec ? lsu_resp_valid_i : (illegal_insn_dec ? coproc_done : ex_valid_i);
    assign coproc_done = (x_issue_valid_o & x_issue_ready_i & ~x_issue_resp_i.writeback) | (x_result_valid_i & x_result_i.we);

    assign x_issue_valid_o      = instr_executing & illegal_insn_dec & (id_fsm_q == FIRST_CYCLE) & scoreboard_free;
    assign x_issue_req_o.instr  = instr_rdata_i;
    assign x_issue_req_o.id     = x_instr_id_q;
    assign x_issue_req_o.hartid = hart_id_i;

    assign x_register_o.rs[0]    = rf_rdata_a_fwd;
    assign x_register_o.rs[1]    = rf_rdata_b_fwd;
    assign x_register_o.rs_valid = '1;
    assign x_register_o.id       = x_instr_id_q;
    assign x_register_o.hartid   = hart_id_i;
    assign x_commit_valid_o       = x_issue_valid_o & x_issue_ready_i;
    assign x_commit_o.commit_kill = 1'b0;
    assign x_commit_o.id          = x_instr_id_q;
    assign x_commit_o.hartid      = hart_id_i;

    assign x_result_ready_o = 1'b1;

    assign illegal_insn_o = instr_valid_i & (illegal_csr_insn_i | (x_issue_valid_o & x_issue_ready_i & ~x_issue_resp_i.accept));
  end

  else begin: no_gen_xif
    logic          unused_x_issue_ready;
    x_issue_resp_t unused_x_issue_resp;
    logic          unused_x_result_valid;
    x_result_t     unused_x_result;

    assign multicycle_done = lsu_req_dec ? lsu_resp_valid_i : ex_valid_i;
    assign scoreboard_busy = 1'b0;

    assign x_issue_valid_o      = 1'b0;
    assign unused_x_issue_ready = x_issue_ready_i;
    assign x_issue_req_o        = '0;
    assign unused_x_issue_resp  = x_issue_resp_i;

    assign x_register_o = '0;

    assign x_commit_valid_o = 1'b0;
    assign x_commit_o       = '0;

    assign x_result_ready_o      = 1'b0;
    assign unused_x_result_valid = x_result_valid_i;
    assign unused_x_result       = x_result_i;

    assign illegal_insn_o = instr_valid_i & (illegal_csr_insn_i | illegal_insn_dec);
  end

  /////////////
  // LSU Mux //
  /////////////

  assign alu_op_a_mux_sel = lsu_addr_incr_req_i ? OP_A_FWD        : alu_op_a_mux_sel_dec;
  assign alu_op_b_mux_sel = lsu_addr_incr_req_i ? OP_B_IMM        : alu_op_b_mux_sel_dec;
  assign imm_b_mux_sel    = lsu_addr_incr_req_i ? IMM_B_INCR_ADDR : imm_b_mux_sel_dec;

  ///////////////////
  // Operand MUXES //
  ///////////////////

  assign imm_a = (imm_a_mux_sel == IMM_A_Z) ? zimm_rs1_type : '0;

  assign pc_id_upper_eff = pc_id_upper_i;

  assign pc_id_operand = pcadd_upper_cycle ? pc_id_upper_eff : pc_id_i;

  always_comb begin : alu_operand_a_mux
    unique case (alu_op_a_mux_sel)
      OP_A_REG_A:  alu_operand_a = rf_rdata_a_fwd;
      OP_A_FWD:    alu_operand_a = lsu_addr_last_i[31:0];
      OP_A_CURRPC: alu_operand_a = pc_id_operand;
      OP_A_IMM:    alu_operand_a = imm_a;
      default:     alu_operand_a = pc_id_operand;
    endcase
  end

  op_a_sel_e  unused_a_mux_sel;
  imm_b_sel_e unused_b_mux_sel;

  always_comb begin : immediate_b_mux
    unique case (imm_b_mux_sel)
      IMM_B_I:         imm_b = imm_i_type;
      IMM_B_S:         imm_b = imm_s_type;
      IMM_B_B:         imm_b = imm_b_type;
      IMM_B_U:         imm_b = imm_u_type;
      IMM_B_J:         imm_b = imm_j_type;
      IMM_B_INCR_PC:   imm_b = instr_is_compressed_i ? 32'h2 : 32'h4;
      IMM_B_INCR_ADDR: imm_b = 32'h4;
      default:         imm_b = 32'h4;
    endcase
  end
  `ASSERT(CVE2ImmBMuxSelValid, instr_valid_i |-> imm_b_mux_sel inside {
      IMM_B_I,
      IMM_B_S,
      IMM_B_B,
      IMM_B_U,
      IMM_B_J,
      IMM_B_INCR_PC,
      IMM_B_INCR_ADDR})

  // For upper-half cycles, immediate's upper value is its sign-extension.
  assign imm_b_eff = use_upper_half_operand_b
                   ? {32{imm_b[31]}}
                   : imm_b;
  assign alu_operand_b_base = (alu_op_b_mux_sel == OP_B_IMM) ? imm_b_eff : rf_rdata_b_fwd;
  assign alu_operand_b      = shift_is_64 ? {26'h0, shift_amt_to_alu} : alu_operand_b_base;

  /////////////////////////////////////////
  // Multicycle Operation Stage Register //
  /////////////////////////////////////////

  for (genvar i = 0; i < 2; i++) begin : gen_intermediate_val_reg
    always_ff @(posedge clk_i or negedge rst_ni) begin : intermediate_val_reg
      if (!rst_ni) begin
        imd_val_q[i] <= '0;
      end else if (imd_val_we_ex_i[i]) begin
        imd_val_q[i] <= imd_val_d_ex_i[i];
      end else if ((i == 0) && shift_imd_we) begin
        imd_val_q[i] <= {2'b00, result_ex_i};
      end
    end
  end

  assign imd_val_q_ex_o = imd_val_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : shift_state_reg
    if (!rst_ni) begin
      shift_amt_q     <= 6'h00;
    end else if (shift_capture) begin
      shift_amt_q     <= shift_amt_now;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : addr_state_reg
    if (!rst_ni) begin
      addr_lower_q <= 32'h0000_0000;
      addr_carry_q <= 1'b0;
    end else if (addr_capture_lower) begin
      addr_lower_q <= result_ex_i;
      addr_carry_q <= carry_out_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : signext_upper_reg
    if (!rst_ni) begin
      signext_upper_fill_q <= 32'h0000_0000;
    end else if (instr_executing_spec && (id_fsm_q == FIRST_CYCLE) &&
                 (is_word_op || is_lui_op)) begin
      signext_upper_fill_q <= signext_upper_fill_now;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : csr_state_reg
    if (!rst_ni) begin
      csr_src_needs_upper_q  <= 1'b0;
      csr_read_needs_upper_q <= 1'b0;
      csr_src_lower_q        <= 32'h0000_0000;
    end else if (instr_executing_spec && csr_need_upper_cycle) begin
      csr_src_needs_upper_q  <= csr_src_needs_upper;
      csr_read_needs_upper_q <= csr_read_needs_upper;
      csr_src_lower_q        <= csr_src_lower_now;
    end else if (instr_done && csr_upper_cycle) begin
      csr_src_needs_upper_q  <= 1'b0;
      csr_read_needs_upper_q <= 1'b0;
      csr_src_lower_q        <= 32'h0000_0000;
    end
  end

  // Carry register: captures lower-cycle carry for adder-class 2-cycle ops.
  // Cleared otherwise so stale carries can't leak into a subsequent op.
  always_ff @(posedge clk_i or negedge rst_ni) begin : carry_reg
    if (!rst_ni) begin
      carry_in_o <= 1'b0;
    end else if (((((op_class == OP_CLASS_ADDER) && (id_fsm_q == FIRST_CYCLE)) ||
                   pcadd_lower_cycle) &&
                  !is_word_op &&
                  instr_executing_spec) ||
                 addr_capture_lower) begin
      carry_in_o <= carry_out_i;
    end else begin
      carry_in_o <= 1'b0;
    end
  end

  ///////////////////////
  // Register File MUX //
  ///////////////////////

  assign rf_we_id_o = rf_we_raw & instr_executing & ~illegal_csr_insn_i;

  always_comb begin : rf_wdata_id_mux
    unique case ($bits(rf_wd_sel_e)'({rf_wdata_sel}))
      RF_WD_EX:     rf_wdata_id_o   = signext_upper_cycle ? signext_upper_fill_q :
                                      (cmp_write_upper_cycle ? 32'h0000_0000 :
                                      (shift_is_64 ? rf_wdata_shift : result_ex_i));
      RF_WD_CSR:    rf_wdata_id_o   = csr_rdata_i;
      RF_WD_COPROC: rf_wdata_id_o   = XInterface? x_result_i.data : result_ex_i;
      default:      rf_wdata_id_o   = signext_upper_cycle ? signext_upper_fill_q :
                                      (cmp_write_upper_cycle ? 32'h0000_0000 :
                                      (shift_is_64 ? rf_wdata_shift : result_ex_i));
    endcase
  end

  /////////////
  // Decoder //
  /////////////

  cve2_decoder #(
    .RV32E          (RV32E),
    .RV32M          (RV32M),
    .RV32B          (RV32B),
    .XInterface     (XInterface)
  ) decoder_i (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .illegal_insn_o(illegal_insn_dec),
    .ebrk_insn_o   (ebrk_insn),
    .mret_insn_o   (mret_insn_dec),
    .dret_insn_o   (dret_insn_dec),
    .ecall_insn_o  (ecall_insn_dec),
    .wfi_insn_o    (wfi_insn_dec),
    .jump_set_o    (jump_set_dec),
    .instr_first_cycle_i(instr_first_cycle),
    .instr_rdata_i      (instr_rdata_i),
    .instr_rdata_alu_i  (instr_rdata_alu_i),
    .illegal_c_insn_i   (illegal_c_insn_i),
    .imm_a_mux_sel_o(imm_a_mux_sel),
    .imm_b_mux_sel_o(imm_b_mux_sel_dec),
    .imm_i_type_o   (imm_i_type),
    .imm_s_type_o   (imm_s_type),
    .imm_b_type_o   (imm_b_type),
    .imm_u_type_o   (imm_u_type),
    .imm_j_type_o   (imm_j_type),
    .zimm_rs1_type_o(zimm_rs1_type),
    .rf_wdata_sel_o(rf_wdata_sel),
    .rf_we_o       (rf_we_dec),
    .rf_raddr_a_o(rf_raddr_a_o),
    .rf_raddr_b_o(rf_raddr_b_o),
    .rf_waddr_o  (rf_waddr_id_o),
    .rf_ren_a_o  (rf_ren_a_dec),
    .rf_ren_b_o  (rf_ren_b_dec),
    .alu_operator_o    (alu_operator),
    .alu_op_a_mux_sel_o(alu_op_a_mux_sel_dec),
    .alu_op_b_mux_sel_o(alu_op_b_mux_sel_dec),
    .alu_multicycle_o  (alu_multicycle_dec),
    .mult_en_o            (mult_en_dec),
    .div_en_o             (div_en_dec),
    .mult_sel_o           (mult_sel_ex_o),
    .div_sel_o            (div_sel_ex_o),
    .multdiv_operator_o   (multdiv_operator),
    .multdiv_signed_mode_o(multdiv_signed_mode),
    .csr_access_o(csr_access_o),
    .csr_op_o    (csr_op_o),
    .data_req_o           (lsu_req_dec),
    .data_we_o            (lsu_we),
    .data_type_o          (lsu_type),
    .data_sign_extension_o(lsu_sign_ext),
    .x_issue_resp_register_read_i(x_issue_resp_i.register_read),
    .x_issue_resp_writeback_i(x_issue_resp_i.writeback),
    .jump_in_dec_o  (jump_in_dec),
    .branch_in_dec_o(branch_in_dec)
  );

  /////////////////////////////////
  // CSR-related pipeline flushes //
  /////////////////////////////////
  always_comb begin : csr_pipeline_flushes
    csr_pipe_flush = 1'b0;
    if (csr_op_en_o == 1'b1 && (csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET)) begin
      if (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSTATUS ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MIE     ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MSECCFG ||
          instr_rdata_i[31:25] == 7'h1D) begin
        csr_pipe_flush = 1'b1;
      end
    end else if (csr_op_en_o == 1'b1 && csr_op_o != CSR_OP_READ) begin
      if (csr_num_e'(instr_rdata_i[31:20]) == CSR_DCSR      ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DPC       ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH0 ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH1) begin
        csr_pipe_flush = 1'b1;
      end
    end
  end

  ////////////////
  // Controller //
  ////////////////

  cve2_controller #(
  ) controller_i (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .fetch_enable_i(fetch_enable_i),
    .ctrl_busy_o(ctrl_busy_o),
    .illegal_insn_i  (illegal_insn_o),
    .ecall_insn_i    (ecall_insn_dec),
    .mret_insn_i     (mret_insn_dec),
    .dret_insn_i     (dret_insn_dec),
    .wfi_insn_i      (wfi_insn_dec),
    .ebrk_insn_i     (ebrk_insn),
    .csr_pipe_flush_i(csr_pipe_flush),
    .xif_scoreboard_busy_i(scoreboard_busy),
    .instr_valid_i          (instr_valid_i),
    .instr_i                (instr_rdata_i),
    .instr_compressed_i     (instr_rdata_c_i),
    .instr_is_compressed_i  (instr_is_compressed_i),
    .instr_fetch_err_i      (instr_fetch_err_i),
    .instr_fetch_err_plus2_i(instr_fetch_err_plus2_i),
    .pc_id_i                ({pc_id_upper_i, pc_id_i}),
    .instr_valid_clear_o(instr_valid_clear_o),
    .id_in_ready_o      (id_in_ready_o),
    .controller_run_o   (controller_run),
    .instr_req_o           (instr_req_o),
    .pc_set_o              (pc_set_o),
    .pc_mux_o              (pc_mux_o),
    .exc_pc_mux_o          (exc_pc_mux_o),
    .exc_cause_o           (exc_cause_o),
    .lsu_addr_last_i(lsu_addr_last_i),
    .load_err_i     (lsu_load_err_i),
    .store_err_i    (lsu_store_err_i),
    .branch_set_i     (branch_set),
    .jump_set_i       (jump_set),
    .csr_mstatus_mie_i(csr_mstatus_mie_i),
    .irq_pending_i    (irq_pending_i),
    .irqs_i           (irqs_i),
    .irq_nm_i         (irq_nm_i),
    .nmi_mode_o       (nmi_mode_o),
    .csr_save_if_o        (csr_save_if_o),
    .csr_save_id_o        (csr_save_id_o),
    .csr_restore_mret_id_o(csr_restore_mret_id_o),
    .csr_restore_dret_id_o(csr_restore_dret_id_o),
    .csr_save_cause_o     (csr_save_cause_o),
    .csr_mtval_o          (csr_mtval_o),
    .priv_mode_i          (priv_mode_i),
    .csr_mstatus_tw_i     (csr_mstatus_tw_i),
    .debug_mode_o       (debug_mode_o),
    .debug_cause_o      (debug_cause_o),
    .debug_csr_save_o   (debug_csr_save_o),
    .debug_req_i        (debug_req_i),
    .debug_single_step_i(debug_single_step_i),
    .debug_ebreakm_i    (debug_ebreakm_i),
    .debug_ebreaku_i    (debug_ebreaku_i),
    .trigger_match_i    (trigger_match_i),
    .stall_id_i(stall_id),
    .flush_id_o(flush_id),
    .perf_jump_o   (perf_jump_o),
    .perf_tbranch_o(perf_tbranch_o)
  );

  assign multdiv_en_dec   = mult_en_dec | div_en_dec;

  assign lsu_req         = instr_executing ? data_req_allowed & lsu_req_dec &
                                             !addr_needs_upper_cycle         : 1'b0;
  assign mult_en_id      = instr_executing ? mult_en_dec                     : 1'b0;
  assign div_en_id       = instr_executing ? div_en_dec                      : 1'b0;

  // =========================================================================
  // Op classification: drives FSM and 64-bit operand sequencing.
  // =========================================================================
  // OP/OP_IMM and RV64 word ALU opcodes enter the RV64 ALU path. Branches enter only for their
  // comparison cycle; their target-address ADD remains outside that path.
  assign is_lui_op       = (instr_rdata_alu_i[6:0] == OPCODE_LUI);
  assign is_auipc_op     = (instr_rdata_alu_i[6:0] == OPCODE_AUIPC);
  assign is_jump_op      = (instr_rdata_alu_i[6:0] == OPCODE_JAL) ||
                           (instr_rdata_alu_i[6:0] == OPCODE_JALR);
  assign is_jalr_op      = (instr_rdata_alu_i[6:0] == OPCODE_JALR);
  assign addr_upper_cycle = (id_fsm_q == ADDR_UPPER_CYCLE);
  assign pcadd_active    = is_auipc_op ||
                           (is_jump_op && ((id_fsm_q == MULTI_CYCLE) ||
                                           (id_fsm_q == PC_UPPER_CYCLE)));
  assign pcadd_upper_cycle = pcadd_active && (id_fsm_q == PC_UPPER_CYCLE);
  assign pcadd_lower_cycle = pcadd_active && !pcadd_upper_cycle;
  assign addr_needs_upper_cycle = (id_fsm_q == FIRST_CYCLE) &&
                                  (lsu_req_dec ||
                                   (jump_in_dec && is_jalr_op));
  assign addr_capture_lower = instr_executing_spec && addr_needs_upper_cycle;
  assign addr_use_upper_a = addr_upper_cycle &&
                            (lsu_req_dec || (jump_in_dec && is_jalr_op));

  assign is_word_op = (instr_rdata_alu_i[6:0] == OPCODE_OP_32) ||
                      (instr_rdata_alu_i[6:0] == OPCODE_OP_IMM_32);

  assign is_op_or_op_imm = (instr_rdata_alu_i[6:0] == OPCODE_OP) ||
                           (instr_rdata_alu_i[6:0] == OPCODE_OP_IMM) ||
                           is_word_op;

  always_comb begin
    op_class = OP_CLASS_NONE;
    if (pcadd_active) begin
      op_class = OP_CLASS_PCADD;
    end else if (is_op_or_op_imm || (instr_rdata_alu_i[6:0] == 7'b1100011)) begin // OPCODE_BRANCH
      unique case (alu_operator)
        ALU_ADD, ALU_SUB: begin
          op_class = is_op_or_op_imm ? OP_CLASS_ADDER : OP_CLASS_NONE;
        end
        ALU_AND, ALU_OR, ALU_XOR: begin
          op_class = is_op_or_op_imm ? OP_CLASS_BITWISE : OP_CLASS_NONE;
        end
        ALU_EQ,  ALU_NE,
        ALU_LT,  ALU_LTU,
        ALU_GE,  ALU_GEU,
        ALU_SLT, ALU_SLTU: begin
          op_class = OP_CLASS_COMPARE;
        end
        ALU_SLL, ALU_SRL, ALU_SRA: begin
          op_class = is_op_or_op_imm ? OP_CLASS_SHIFT : OP_CLASS_NONE;
        end
        default: op_class = OP_CLASS_NONE;
      endcase
    end
  end

  assign op_uses_64_path = (op_class != OP_CLASS_NONE);

  // =========================================================================
  // RV64 shift sequencing control
  // =========================================================================
  assign shift_is_64            = (op_class == OP_CLASS_SHIFT) && !is_word_op;
  assign shift_is_left          = shift_is_64 && (alu_operator == ALU_SLL);
  assign shift_is_right         = shift_is_64 && ((alu_operator == ALU_SRL) ||
                                                  (alu_operator == ALU_SRA));
  assign shift_is_arith         = shift_is_64 && (alu_operator == ALU_SRA);
  assign shift_amt_now          = (alu_op_b_mux_sel == OP_B_IMM) ?
                                  instr_rdata_alu_i[25:20] : rf_rdata_b_i[5:0];
  assign shift_amt              = (id_fsm_q == FIRST_CYCLE) ? shift_amt_now : shift_amt_q;
  assign shift_amt_compl        = 6'd32 - shift_amt;
  assign shift_amt_zero         = (shift_amt == 6'h00);
  assign shift_amt_ge32         = shift_amt[5];
  assign shift_amt_lt32_nonzero = !shift_amt_zero && !shift_amt_ge32;
  assign shift_first_save       = shift_is_64 &&
                                  (id_fsm_q == FIRST_CYCLE) &&
                                  !shift_amt_zero &&
                                  !(shift_is_right && shift_amt_ge32);
  assign shift_capture          = instr_executing_spec &&
                                  (id_fsm_q == FIRST_CYCLE) &&
                                  shift_is_64;
  assign shift_imd_we           = instr_executing_spec && shift_first_save;

  always_comb begin
    shift_use_upper_a = 1'b0;
    if (shift_is_64) begin
      unique case (id_fsm_q)
        FIRST_CYCLE: begin
          shift_use_upper_a = shift_is_right && shift_amt_ge32;
        end
        SHIFT_LOW_CYCLE: begin
          shift_use_upper_a = shift_is_right && shift_amt_lt32_nonzero;
        end
        SHIFT_UPPER_CYCLE: begin
          shift_use_upper_a = shift_amt_zero ||
                              shift_amt_lt32_nonzero ||
                              (shift_is_right && shift_amt_ge32);
        end
        default: shift_use_upper_a = 1'b0;
      endcase
    end
  end

  always_comb begin
    shift_amt_to_alu = shift_amt;
    if (shift_is_64) begin
      unique case (id_fsm_q)
        FIRST_CYCLE: begin
          if (shift_is_left && shift_amt_lt32_nonzero) begin
            shift_amt_to_alu = shift_amt_compl;
          end else begin
            shift_amt_to_alu = shift_amt;
          end
        end
        SHIFT_LOW_CYCLE: begin
          // The ALU internally complements shift amounts after the first cycle.
          if (shift_is_right) begin
            shift_amt_to_alu = shift_amt;
          end else if (shift_amt_lt32_nonzero) begin
            shift_amt_to_alu = shift_amt_compl;
          end else begin
            shift_amt_to_alu = shift_amt;
          end
        end
        SHIFT_UPPER_CYCLE: begin
          // The ALU internally complements shift amounts after the first cycle.
          if (shift_amt_lt32_nonzero) begin
            shift_amt_to_alu = shift_amt_compl;
          end else begin
            shift_amt_to_alu = shift_amt;
          end
        end
        default: shift_amt_to_alu = shift_amt;
      endcase
    end
  end

  always_comb begin
    rf_wdata_shift = result_ex_i;
    if (shift_is_64) begin
      unique case (id_fsm_q)
        SHIFT_LOW_CYCLE: begin
          if (shift_is_left && shift_amt_ge32) begin
            rf_wdata_shift = 32'h0000_0000;
          end else if (shift_is_right) begin
            rf_wdata_shift = imd_val_q[0][31:0] | result_ex_i;
          end else begin
            rf_wdata_shift = result_ex_i;
          end
        end
        SHIFT_UPPER_CYCLE: begin
          if (shift_is_right && shift_amt_ge32) begin
            rf_wdata_shift = (shift_is_arith && rf_rdata_a_fwd[31]) ?
                             32'hffff_ffff : 32'h0000_0000;
          end else if (shift_is_left && shift_amt_ge32) begin
            rf_wdata_shift = imd_val_q[0][31:0];
          end else if (shift_is_left) begin
            rf_wdata_shift = imd_val_q[0][31:0] | result_ex_i;
          end else begin
            rf_wdata_shift = result_ex_i;
          end
        end
        default: rf_wdata_shift = result_ex_i;
      endcase
    end
  end

  // =========================================================================
  // Compare control
  // =========================================================================
  assign cmp_is_compare       = (op_class == OP_CLASS_COMPARE);
  assign cmp_use_upper_first = cmp_is_compare &&
                               (id_fsm_q == FIRST_CYCLE);
  assign cmp_is_lower_cycle  = cmp_is_compare &&
                               (id_fsm_q == CMP_LOWER_CYCLE);
  assign cmp_write_upper_cycle = cmp_is_compare &&
                                 (id_fsm_q == CMP_UPPER_WRITE_CYCLE);
  assign cmp_need_lower_after_upper = cmp_use_upper_first && alu_is_equal_result_i;

  assign use_upper_half_operand_a = ((id_fsm_q == MULTI_CYCLE) &&
                                     op_uses_64_path &&
                                     (op_class != OP_CLASS_COMPARE) &&
                                     (op_class != OP_CLASS_PCADD)) ||
                                    cmp_use_upper_first ||
                                    shift_use_upper_a ||
                                    addr_use_upper_a;
  assign use_upper_half_operand_b = ((id_fsm_q == MULTI_CYCLE) &&
                                     op_uses_64_path &&
                                     (op_class != OP_CLASS_COMPARE) &&
                                     (op_class != OP_CLASS_PCADD)) ||
                                    cmp_use_upper_first ||
                                    pcadd_upper_cycle ||
                                    addr_upper_cycle;
  // =========================================================================
  // needs_upper_cycle: 1 = explicit upper-half execution required.
  // =========================================================================
  always_comb begin
    needs_upper_cycle = 1'b0;
    unique case (op_class)
      OP_CLASS_ADDER: begin
        needs_upper_cycle = !is_word_op;
      end
      OP_CLASS_BITWISE: begin
        needs_upper_cycle = 1'b1;
      end
      OP_CLASS_COMPARE: begin
        needs_upper_cycle = cmp_need_lower_after_upper && !branch_in_dec;
      end
      OP_CLASS_SHIFT: begin
        needs_upper_cycle = 1'b0;
      end
      OP_CLASS_PCADD: begin
        needs_upper_cycle = rf_we_dec && (rf_waddr_id_o != 5'd0);
      end
      default: needs_upper_cycle = 1'b0;
    endcase
  end

  always_comb begin
    alu_operator_eff = alu_operator;
    if (cmp_is_lower_cycle) begin
      unique case (alu_operator)
        ALU_LT:  alu_operator_eff = ALU_LTU;
        ALU_GE:  alu_operator_eff = ALU_GEU;
        ALU_SLT: alu_operator_eff = ALU_SLTU;
        default: alu_operator_eff = alu_operator;
      endcase
    end else if (shift_is_64) begin
      unique case (id_fsm_q)
        FIRST_CYCLE: begin
          if ((shift_is_left && shift_amt_lt32_nonzero) ||
              (shift_is_right && !shift_amt_ge32)) begin
            alu_operator_eff = ALU_SRL;
          end else begin
            alu_operator_eff = alu_operator;
          end
        end
        SHIFT_LOW_CYCLE: begin
          alu_operator_eff = ALU_SLL;
        end
        SHIFT_UPPER_CYCLE: begin
          alu_operator_eff = shift_is_left ? ALU_SLL : alu_operator;
        end
        default: alu_operator_eff = alu_operator;
      endcase
    end
  end

  always_comb begin
    unique case (alu_op_a_mux_sel)
      OP_A_REG_A:  addr_src_upper = rf_rdata_a_i;
      OP_A_FWD:    addr_src_upper = lsu_addr_last_i[63:32];
      OP_A_CURRPC: addr_src_upper = pc_id_upper_eff;
      default:     addr_src_upper = 32'h0000_0000;
    endcase
  end

  assign addr_imm_upper    = {32{imm_b[31]}};
  assign addr_upper_comb   = addr_src_upper + addr_imm_upper +
                             {31'h0, (addr_upper_cycle ? addr_carry_q : carry_out_i)};
  assign addr_lower_result = addr_upper_cycle ? addr_lower_q : result_ex_i;
  assign addr_upper_result = addr_upper_cycle ? result_ex_i : addr_upper_comb;
  assign addr_result_ex    = {addr_upper_result, addr_lower_result};

  assign signext_upper_cycle    = (id_fsm_q == SIGNEXT_UPPER_CYCLE);
  assign signext_upper_fill_now = {32{result_ex_i[31]}};

  assign csr_upper_cycle      = (id_fsm_q == CSR_UPPER_CYCLE);
  assign csr_is_imm_op        = (alu_op_a_mux_sel == OP_A_IMM);
  assign csr_src_lower_now    = csr_is_imm_op ? imm_a : rf_rdata_a_i;
  assign csr_src_needs_upper  = csr_access_o &&
                                (csr_op_o != CSR_OP_READ) &&
                                !csr_is_imm_op;

  assign csr_read_needs_upper = csr_access_o &&
                                rf_we_dec &&
                                (rf_waddr_id_o != 5'd0);
  assign csr_need_upper_cycle = (id_fsm_q == FIRST_CYCLE) &&
                                csr_access_o &&
                                (csr_src_needs_upper || csr_read_needs_upper);

  assign lsu_req_o               = lsu_req;
  assign lsu_we_o                = lsu_we;
  assign lsu_type_o              = lsu_type;
  assign lsu_sign_ext_o          = lsu_sign_ext;
  assign lsu_store_upper_half    = lsu_addr_incr_req_i & lsu_we & (lsu_type == 2'b11);
  assign lsu_wdata_o             = lsu_store_upper_half ? lsu_wdata_upper : rf_rdata_b_i;
  assign csr_op_en_o             = csr_access_o & instr_executing & instr_id_done_o;
  assign csr_wdata_o             = (csr_upper_cycle && csr_src_needs_upper_q) ?
                                    rf_rdata_a_i :
                                    (csr_upper_cycle ? csr_src_lower_q : csr_src_lower_now);
  assign csr_wdata_upper_o       = csr_upper_cycle && csr_src_needs_upper_q;
  assign csr_wdata_capture_o     = instr_executing_spec &&
                                    csr_need_upper_cycle &&
                                    csr_src_needs_upper;
  assign csr_rdata_upper_o       = csr_upper_cycle && csr_read_needs_upper_q;
  assign csr_rdata_capture_o     = instr_executing_spec &&
                                    csr_need_upper_cycle &&
                                    csr_read_needs_upper;

  assign alu_operator_ex_o           = alu_operator_eff;
  assign alu_operand_a_ex_o          = alu_operand_a;
  assign alu_operand_b_ex_o          = alu_operand_b;
  assign lsu_addr_ex_o               = addr_result_ex;
  assign pc_target_ex_o              = addr_result_ex;

  assign mult_en_ex_o                = mult_en_id;
  assign div_en_ex_o                 = div_en_id;

  assign multdiv_operator_ex_o       = multdiv_operator;
  assign multdiv_signed_mode_ex_o    = multdiv_signed_mode;
  assign multdiv_operand_a_ex_o      = rf_rdata_a_fwd;
  assign multdiv_operand_b_ex_o      = rf_rdata_b_fwd;

  ////////////////////////
  // Branch set control //
  ////////////////////////

  logic branch_set_raw_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      branch_set_raw_q <= 1'b0;
    end else begin
      branch_set_raw_q <= branch_set_raw_d;
    end
  end

  assign branch_set_raw      = branch_set_raw_q;

  assign branch_jump_set_done_d = (branch_set_raw | jump_set_raw | branch_jump_set_done_q) &
    ~instr_valid_clear_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      branch_jump_set_done_q <= 1'b0;
    end else begin
      branch_jump_set_done_q <= branch_jump_set_done_d;
    end
  end

  assign jump_set        = jump_set_raw        & ~branch_jump_set_done_q;
  assign branch_set      = branch_set_raw      & ~branch_jump_set_done_q;

  always_comb begin
    id_fsm_d                = id_fsm_q;
    rf_we_raw               = rf_we_dec;
    stall_multdiv           = 1'b0;
    stall_jump              = 1'b0;
    stall_branch            = 1'b0;
    stall_alu               = 1'b0;
    stall_coproc            = 1'b0;
    branch_set_raw_d        = 1'b0;
    jump_set_raw            = 1'b0;
    perf_branch_o           = 1'b0;
    r_a_upper_o             = 1'b0;
    r_b_upper_o             = 1'b0;
    rf_w_upper_id_o         = 1'b0;

    if (instr_executing_spec) begin
      unique case (id_fsm_q)
        FIRST_CYCLE: begin
          priority case (1'b1)
            lsu_req_dec: begin
              if (addr_needs_upper_cycle) begin
                id_fsm_d  = ADDR_UPPER_CYCLE;
                stall_alu = 1'b1;
              end else begin
                id_fsm_d  = MULTI_CYCLE;
              end
            end
            multdiv_en_dec: begin
              if (~ex_valid_i) begin
                id_fsm_d      = MULTI_CYCLE;
                rf_we_raw     = 1'b0;
                stall_multdiv = 1'b1;
              end
            end
            branch_in_dec: begin
              if (cmp_need_lower_after_upper) begin
                id_fsm_d     = CMP_LOWER_CYCLE;
                stall_branch = 1'b1;
              end else begin
                id_fsm_d         = branch_decision_i ? MULTI_CYCLE : FIRST_CYCLE;
                stall_branch     = branch_decision_i;
                branch_set_raw_d = branch_decision_i;
                perf_branch_o    = 1'b1;
              end
            end
            jump_in_dec: begin
              if (addr_needs_upper_cycle) begin
                id_fsm_d     = ADDR_UPPER_CYCLE;
                stall_jump   = 1'b1;
                jump_set_raw = 1'b0;
              end else begin
                id_fsm_d     = MULTI_CYCLE;
                stall_jump   = 1'b1;
                jump_set_raw = jump_set_dec;
              end
            end
            ((is_lui_op || is_word_op) && rf_we_dec && (rf_waddr_id_o != 5'd0)): begin
              id_fsm_d  = SIGNEXT_UPPER_CYCLE;
              stall_alu = 1'b1;
            end
            (op_uses_64_path && !branch_in_dec): begin
              if (shift_is_64) begin
                if (shift_first_save) begin
                  id_fsm_d  = SHIFT_LOW_CYCLE;
                  stall_alu = 1'b1;
                  rf_we_raw = 1'b0;
                end else if (shift_amt_zero || (shift_is_right && shift_amt_ge32)) begin
                  id_fsm_d  = SHIFT_UPPER_CYCLE;
                  stall_alu = 1'b1;
                end
              end else if (op_class == OP_CLASS_COMPARE) begin
                if (cmp_need_lower_after_upper) begin
                  id_fsm_d  = CMP_LOWER_CYCLE;
                  stall_alu = 1'b1;
                  rf_we_raw = 1'b0;
                end else begin
                  id_fsm_d  = CMP_UPPER_WRITE_CYCLE;
                  stall_alu = 1'b1;
                end
              end else if (op_class == OP_CLASS_PCADD) begin
                if (needs_upper_cycle) begin
                  id_fsm_d  = PC_UPPER_CYCLE;
                  stall_alu = 1'b1;
                end
              end else begin
                if (needs_upper_cycle) begin
                  id_fsm_d  = MULTI_CYCLE;
                  stall_alu = 1'b1;
                end
              end
              // else: 1-cycle, stays in FIRST_CYCLE
            end
            csr_access_o: begin
              if (csr_need_upper_cycle) begin
                id_fsm_d  = CSR_UPPER_CYCLE;
                stall_alu = 1'b1;
              end
            end
            alu_multicycle_dec: begin
              stall_alu     = 1'b1;
              id_fsm_d      = MULTI_CYCLE;
              rf_we_raw     = 1'b0;
            end
            illegal_insn_dec: begin
              if(XInterface) begin
                if(x_issue_valid_o && x_issue_ready_i) begin
                  if(x_issue_resp_i.accept && x_issue_resp_i.writeback) begin
                      id_fsm_d = MULTI_CYCLE;
                      stall_coproc = 1'b1;
                  end
                  else begin
                    id_fsm_d = FIRST_CYCLE;
                  end
                end
                else begin
                  stall_coproc = 1'b1;
                  id_fsm_d = FIRST_CYCLE;
                end
              end
              else begin
                id_fsm_d = FIRST_CYCLE;
              end
            end
            default: begin
              id_fsm_d      = FIRST_CYCLE;
            end
          endcase
        end

        MULTI_CYCLE: begin
            if (op_uses_64_path && (op_class != OP_CLASS_COMPARE)) begin
              if (op_class == OP_CLASS_PCADD) begin
                if (needs_upper_cycle) begin
                  id_fsm_d   = PC_UPPER_CYCLE;
                  stall_jump = jump_in_dec;
                  stall_alu  = !jump_in_dec;
                end else begin
                  id_fsm_d = FIRST_CYCLE;
                end
              end else begin
                id_fsm_d        = FIRST_CYCLE;
                r_a_upper_o     = 1'b1;
                r_b_upper_o     = (alu_op_b_mux_sel != OP_B_IMM); // I-type: B is imm, no RF read
                rf_w_upper_id_o = 1'b1;
              end
            end else begin
              if (multdiv_en_dec) begin
              rf_we_raw = rf_we_dec & ex_valid_i;
            end

            if (multicycle_done) begin
              id_fsm_d = FIRST_CYCLE;
            end else begin
              stall_multdiv = multdiv_en_dec;
              stall_branch  = branch_in_dec;
              stall_jump    = jump_in_dec;
              stall_coproc  = XInterface & illegal_insn_dec;
            end
          end
        end

        CMP_LOWER_CYCLE: begin
          if (branch_in_dec) begin
            if (branch_decision_i) begin
              id_fsm_d         = MULTI_CYCLE;
              stall_branch     = 1'b1;
              branch_set_raw_d = 1'b1;
            end else begin
              id_fsm_d = FIRST_CYCLE;
            end
            perf_branch_o = 1'b1;
          end else begin
            id_fsm_d  = CMP_UPPER_WRITE_CYCLE;
            stall_alu = 1'b1;
          end
        end

        CMP_UPPER_WRITE_CYCLE: begin
          id_fsm_d        = FIRST_CYCLE;
          rf_w_upper_id_o = 1'b1;
        end

        SHIFT_LOW_CYCLE: begin
          id_fsm_d  = SHIFT_UPPER_CYCLE;
          stall_alu = 1'b1;
        end

        SHIFT_UPPER_CYCLE: begin
          id_fsm_d        = FIRST_CYCLE;
          rf_w_upper_id_o = 1'b1;
        end

        PC_UPPER_CYCLE: begin
          id_fsm_d        = FIRST_CYCLE;
          rf_w_upper_id_o = 1'b1;
        end

        ADDR_UPPER_CYCLE: begin
          if (lsu_req_dec) begin
            id_fsm_d = MULTI_CYCLE;
          end else if (jump_in_dec) begin
            id_fsm_d     = MULTI_CYCLE;
            stall_jump   = 1'b1;
            jump_set_raw = jump_set_dec;
          end else begin
            id_fsm_d = FIRST_CYCLE;
          end
        end

        SIGNEXT_UPPER_CYCLE: begin
          id_fsm_d        = FIRST_CYCLE;
          rf_w_upper_id_o = 1'b1;
        end

        CSR_UPPER_CYCLE: begin
          id_fsm_d        = FIRST_CYCLE;
          rf_we_raw       = csr_read_needs_upper_q ? rf_we_dec : 1'b0;
          rf_w_upper_id_o = csr_read_needs_upper_q;
          r_a_upper_o     = csr_src_needs_upper_q;
        end

        default: begin
          id_fsm_d          = FIRST_CYCLE;
        end
      endcase
    end

    if (use_upper_half_operand_a) begin
      r_a_upper_o = 1'b1;
    end

    if (use_upper_half_operand_b && (alu_op_b_mux_sel != OP_B_IMM)) begin
      r_b_upper_o = 1'b1;
    end

    if (lsu_store_upper_half) begin
      r_b_upper_o = 1'b1;
    end
  end

  `ASSERT(StallIDIfMulticycle, (id_fsm_q == FIRST_CYCLE) & (id_fsm_d == MULTI_CYCLE) |-> stall_id)

  assign stall_id = stall_mem | stall_multdiv | stall_jump | stall_branch |
                      stall_alu | (XInterface & stall_coproc);

  `ASSERT(IllegalInsnStallMustBeMemStall, illegal_insn_o & stall_id |-> stall_mem &
    ~(stall_multdiv | stall_jump | stall_branch | stall_alu))

  assign instr_done = ~stall_id & ~flush_id & instr_executing;

  assign instr_first_cycle      = instr_valid_i &
                                  ((id_fsm_q == FIRST_CYCLE) ||
                                   (id_fsm_q == CMP_LOWER_CYCLE) ||
                                   (id_fsm_q == ADDR_UPPER_CYCLE));
  assign instr_first_cycle_id_o = instr_first_cycle;

  assign data_req_allowed = instr_first_cycle;

  assign stall_mem = instr_valid_i & (lsu_req_dec & (~lsu_resp_valid_i | instr_first_cycle));

  assign instr_executing_spec = instr_valid_i & ~instr_fetch_err_i & controller_run;
  assign instr_executing = instr_executing_spec;

  `ASSERT(IbexStallIfValidInstrNotExecuting,
    instr_valid_i & ~instr_fetch_err_i & ~instr_executing & controller_run |-> stall_id)

  // =========================================================================
  // Forwarding mux
  // =========================================================================
  always_comb begin
    rf_rdata_a_fwd = rf_rdata_a_i;
    rf_rdata_b_fwd = rf_rdata_b_i;
  end

  assign lsu_wdata_upper = rf_rdata_b_i;

  logic unused_data_req_done_ex;

  assign perf_dside_wait_o = instr_executing & lsu_req_dec & ~lsu_resp_valid_i;

  assign instr_id_done_o = instr_done;

  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~(dret_insn_dec & ~debug_mode_o) &
      ~illegal_csr_insn_i & ~instr_fetch_err_i;

  assign en_wb_o = instr_done;

  assign perf_wfi_wait_o = wfi_insn_dec;
  assign perf_div_wait_o = stall_multdiv & div_en_dec;

  //////////
  // FCOV //
  //////////

  `DV_FCOV_SIGNAL(logic, branch_taken,
    instr_executing & (id_fsm_q == FIRST_CYCLE) & branch_decision_i)
  `DV_FCOV_SIGNAL(logic, branch_not_taken,
    instr_executing & (id_fsm_q == FIRST_CYCLE) & ~branch_decision_i)

  ////////////////
  // Assertions //
  ////////////////

  `ASSERT_KNOWN_IF(CVE2AluOpMuxSelKnown, alu_op_a_mux_sel, instr_valid_i)
  `ASSERT(CVE2AluAOpMuxSelValid, instr_valid_i |-> alu_op_a_mux_sel inside {
      OP_A_REG_A,
      OP_A_FWD,
      OP_A_CURRPC,
      OP_A_IMM})
  if (XInterface) begin: gen_asserts_xif
    `ASSERT(IbexRegfileWdataSelValid, instr_valid_i |-> rf_wdata_sel inside {
        RF_WD_EX,
        RF_WD_CSR,
        RF_WD_COPROC})
  end
  else begin : no_gen_asserts_xif
    `ASSERT(IbexRegfileWdataSelValid, instr_valid_i |-> rf_wdata_sel inside {
        RF_WD_EX,
        RF_WD_CSR})
  end
  `ASSERT_KNOWN(IbexWbStateKnown, id_fsm_q)

  `ASSERT_KNOWN_IF(CVE2BranchDecisionValid, branch_decision_i,
      instr_valid_i && !(illegal_csr_insn_i || instr_fetch_err_i))

  `ASSERT_KNOWN_IF(CVE2IdInstrKnown, instr_rdata_i,
      instr_valid_i && !(illegal_c_insn_i || instr_fetch_err_i))

  `ASSERT_KNOWN_IF(CVE2IdInstrALUKnown, instr_rdata_alu_i,
      instr_valid_i && !(illegal_c_insn_i || instr_fetch_err_i))

  `ASSERT(IbexMulticycleEnableUnique,
      $onehot0({lsu_req_dec, multdiv_en_dec, branch_in_dec, jump_in_dec, illegal_insn_dec,
                (op_uses_64_path && !branch_in_dec && needs_upper_cycle)}))

  `ASSERT(CVE2DuplicateInstrMatch, instr_valid_i |-> instr_rdata_i === instr_rdata_alu_i)

  `ifdef CHECK_MISALIGNED
  `ASSERT(CVE2MisalignedMemoryAccess, !lsu_addr_incr_req_i)
  `endif

endmodule
