`timescale 1ns/1ps

module testbench;

  import cve2_pkg::*;

  localparam bit EnableCSRs = 1'b0;

  // --------------------
  // Clock / reset
  // --------------------
  logic clk_i;
  logic rst_ni;

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i; // 100 MHz
  end

  initial begin
    rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  // --------------------
  // IF->ID instruction interface
  // --------------------
  logic        fetch_enable_i;
  logic        instr_valid_i;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_alu_i;
  logic [15:0] instr_rdata_c_i;
  logic        instr_is_compressed_i;

  logic instr_req_o;
  logic instr_first_cycle_id_o;
  logic instr_valid_clear_o;
  logic id_in_ready_o;

  initial begin
    fetch_enable_i        = 1'b1;
    instr_valid_i         = 1'b0;
    instr_rdata_i         = 32'h0000_0013; // NOP (ADDI x0,x0,0)
    instr_rdata_alu_i     = 32'h0000_0013;
    instr_rdata_c_i       = 16'h0001;
    instr_is_compressed_i = 1'b0;
  end

  // --------------------
  // IF/ID PC and branch feedback
  // --------------------
  logic [63:0] pc_id_i;
  logic        branch_decision_i;
  logic        branch_decision_o;
  logic        alu_is_equal_result_o;

  initial pc_id_i = 64'h0000_0000_0000_0000;

  assign branch_decision_i = branch_decision_o;

  // --------------------
  // ID control outputs
  // --------------------
  logic              pc_set_o;
  pc_sel_e           pc_mux_o;
  exc_pc_sel_e       exc_pc_mux_o;
  exc_cause_e        exc_cause_o;
  logic              illegal_insn_o;

  // --------------------
  // Error/illegal inputs
  // --------------------
  logic illegal_c_insn_i;
  logic instr_fetch_err_i;
  logic instr_fetch_err_plus2_i;
  logic illegal_csr_insn_i;

  initial begin
    illegal_c_insn_i        = 1'b0;
    instr_fetch_err_i       = 1'b0;
    instr_fetch_err_plus2_i = 1'b0;
    illegal_csr_insn_i      = 1'b0;
  end

  // --------------------
  // ID/EX/LSU plumbing
  // --------------------
  logic ex_valid_i;
  logic lsu_resp_valid_i;

  alu_op_e     alu_operator_ex_o;
  logic [63:0] alu_operand_a_ex_o;
  logic [63:0] alu_operand_b_ex_o;
  logic        alu_word_op_ex_o;

  logic [1:0]  imd_val_we_ex;
  logic [33:0] imd_val_d_ex[2];
  logic [33:0] imd_val_q_ex[2];

  logic carry_in;
  logic carry_out;

  logic         mult_en_ex_o, div_en_ex_o;
  logic         mult_sel_ex_o, div_sel_ex_o;
  md_op_e       multdiv_operator_ex_o;
  logic [1:0]   multdiv_signed_mode_ex_o;
  logic [31:0]  multdiv_operand_a_ex_o, multdiv_operand_b_ex_o;

  // --------------------
  // CSR signals, disabled in this area profile
  // --------------------
  logic          csr_access_o;
  csr_op_e       csr_op_o;
  logic          csr_op_en_o;
  logic          csr_save_if_o, csr_save_id_o;
  logic          csr_restore_mret_id_o, csr_restore_dret_id_o;
  logic          csr_save_cause_o;
  logic [63:0]   csr_mtval_o;
  logic [63:0]   csr_wdata_o;
  priv_lvl_e     priv_mode_i;
  logic          csr_mstatus_tw_i;
  logic [63:0]   csr_rdata_i;

  initial begin
    priv_mode_i      = PRIV_LVL_M;
    csr_mstatus_tw_i = 1'b0;
    csr_rdata_i      = 64'h0000_0000_0000_0000;
  end

  // --------------------
  // LSU interface
  // --------------------
  logic        lsu_req_o;
  logic        lsu_we_o;
  logic [1:0]  lsu_type_o;
  logic        lsu_sign_ext_o;
  logic [63:0] lsu_wdata_o;

  logic        lsu_addr_incr_req_i;
  logic [63:0] lsu_addr_last_i;
  logic        lsu_load_err_i, lsu_store_err_i;

  logic        data_req_o;
  logic        data_gnt_i;
  logic        data_rvalid_i;
  logic        data_err_i;
  logic        data_pmp_err_i;
  logic [63:0] data_addr_o;
  logic        data_we_o;
  logic [7:0]  data_be_o;
  logic [63:0] data_wdata_o;
  logic [63:0] data_rdata_i;

  initial begin
    data_rvalid_i  = 1'b0;
    data_err_i     = 1'b0;
    data_pmp_err_i = 1'b0;
    data_rdata_i   = 64'h0000_0000_0000_0000;
  end

  assign data_gnt_i = 1'b1;

  // --------------------
  // X-Interface (disabled)
  // --------------------
  logic [31:0] hart_id_i;
  logic        x_issue_valid_o;
  logic        x_issue_ready_i;
  x_issue_req_t  x_issue_req_o;
  x_issue_resp_t x_issue_resp_i;

  x_register_t x_register_o;
  logic [63:0] lsu_addr_ex_o;
  logic [63:0] pc_target_ex_o;

  logic        x_commit_valid_o;
  x_commit_t   x_commit_o;

  logic        x_result_valid_i;
  logic        x_result_ready_o;
  x_result_t   x_result_i;

  initial begin
    hart_id_i        = 32'h0;
    x_issue_ready_i  = 1'b0;
    x_issue_resp_i   = '0;
    x_result_valid_i = 1'b0;
    x_result_i       = '0;
  end

  // cve2_controller has a simulation-only illegal-instruction printf that uses
  // legacy hierarchical paths. These tiny aliases let this component-level
  // harness run without requiring the full cve2_core wrapper.
  tb_controller_hier_core cve2_core (
    .hart_id_i(hart_id_i)
  );

  tb_controller_hier_id cve2_id_stage (
    .pc_id_i       (pc_id_i),
    .instr_rdata_i (instr_rdata_i)
  );

  // --------------------
  // IRQ/debug
  // --------------------
  logic        csr_mstatus_mie_i;
  logic        irq_pending_i;
  irqs_t       irqs_i;
  logic        irq_nm_i;
  logic        nmi_mode_o;

  logic        debug_mode_o;
  dbg_cause_e  debug_cause_o;
  logic        debug_csr_save_o;
  logic        debug_req_i;
  logic        debug_single_step_i;
  logic        debug_ebreakm_i;
  logic        debug_ebreaku_i;
  logic        trigger_match_i;

  initial begin
    csr_mstatus_mie_i   = 1'b0;
    irq_pending_i       = 1'b0;
    irqs_i              = '0;
    irq_nm_i            = 1'b0;
    debug_req_i         = 1'b0;
    debug_single_step_i = 1'b0;
    debug_ebreakm_i     = 1'b0;
    debug_ebreaku_i     = 1'b0;
    trigger_match_i     = 1'b0;
  end

  // --------------------
  // Register file / writeback interface
  // --------------------
  logic [63:0] result_ex_i;
  logic [4:0]  rf_raddr_a_o, rf_raddr_b_o;
  logic [63:0] rf_rdata_a_i, rf_rdata_b_i;
  logic        rf_ren_a_o, rf_ren_b_o;

  logic [4:0]  rf_waddr_id_o;
  logic [63:0] rf_wdata_id_o;
  logic        rf_we_id_o;

  logic        en_wb_o;
  logic        instr_perf_count_id_o;

  logic perf_jump_o, perf_branch_o, perf_tbranch_o;
  logic perf_dside_wait_o, perf_wfi_wait_o, perf_div_wait_o;
  logic instr_id_done_o;

  logic [4:0]  rf_waddr_wb_o;
  logic [63:0] rf_wdata_wb_o;
  logic        rf_we_wb_o;

  logic [63:0] rf_wdata_lsu_i;
  logic        rf_we_lsu_i;

  // --------------------
  // Instantiate ID
  // --------------------
  cve2_id_stage #(
    .RV32E      (1'b0),
    .RV32M      (RV32MNone),
    .RV32B      (RV32BNone),
    .XInterface (1'b0),
    .EnableCSRs (EnableCSRs)
  ) dut_id (
    .clk_i,
    .rst_ni,

    .fetch_enable_i,
    .ctrl_busy_o(),
    .illegal_insn_o,

    .instr_valid_i,
    .instr_rdata_i,
    .instr_rdata_alu_i,
    .instr_rdata_c_i,
    .instr_is_compressed_i,
    .instr_req_o,
    .instr_first_cycle_id_o,
    .instr_valid_clear_o,
    .id_in_ready_o,

    .branch_decision_i,
    .alu_is_equal_result_i(alu_is_equal_result_o),

    .pc_set_o,
    .pc_mux_o,
    .exc_pc_mux_o,
    .exc_cause_o,

    .illegal_c_insn_i,
    .instr_fetch_err_i,
    .instr_fetch_err_plus2_i,

    .pc_id_i,

    .ex_valid_i,
    .lsu_resp_valid_i,

    .alu_operator_ex_o,
    .alu_operand_a_ex_o,
    .alu_operand_b_ex_o,
    .alu_word_op_ex_o,

    .imd_val_we_ex_i(imd_val_we_ex),
    .imd_val_d_ex_i (imd_val_d_ex),
    .imd_val_q_ex_o (imd_val_q_ex),

    .carry_out_i(carry_out),
    .carry_in_o (carry_in),

    .mult_en_ex_o,
    .div_en_ex_o,
    .mult_sel_ex_o,
    .div_sel_ex_o,
    .multdiv_operator_ex_o,
    .multdiv_signed_mode_ex_o,
    .multdiv_operand_a_ex_o,
    .multdiv_operand_b_ex_o,

    .csr_access_o,
    .csr_op_o,
    .csr_op_en_o,
    .csr_save_if_o,
    .csr_save_id_o,
    .csr_restore_mret_id_o,
    .csr_restore_dret_id_o,
    .csr_save_cause_o,
    .csr_mtval_o,
    .csr_wdata_o,
    .priv_mode_i,
    .csr_mstatus_tw_i,
    .illegal_csr_insn_i,

    .lsu_req_o,
    .lsu_we_o,
    .lsu_type_o,
    .lsu_sign_ext_o,
    .lsu_wdata_o,

    .lsu_addr_incr_req_i,
    .lsu_addr_last_i,

    .hart_id_i,
    .x_issue_valid_o,
    .x_issue_ready_i,
    .x_issue_req_o,
    .x_issue_resp_i,

    .x_register_o,

    .x_commit_valid_o,
    .x_commit_o,

    .x_result_valid_i,
    .x_result_ready_o,
    .x_result_i,

    .csr_mstatus_mie_i,
    .irq_pending_i,
    .irqs_i,
    .irq_nm_i,
    .nmi_mode_o,

    .lsu_load_err_i,
    .lsu_store_err_i,

    .debug_mode_o,
    .debug_cause_o,
    .debug_csr_save_o,
    .debug_req_i,
    .debug_single_step_i,
    .debug_ebreakm_i,
    .debug_ebreaku_i,
    .trigger_match_i,

    .result_ex_i,
    .csr_rdata_i,

    .rf_raddr_a_o,
    .rf_rdata_a_i,
    .rf_raddr_b_o,
    .rf_rdata_b_i,
    .rf_ren_a_o,
    .rf_ren_b_o,

    .rf_waddr_id_o,
    .rf_wdata_id_o,
    .rf_we_id_o,
    .lsu_addr_ex_o,
    .pc_target_ex_o,

    .en_wb_o,
    .instr_perf_count_id_o,

    .perf_jump_o,
    .perf_branch_o,
    .perf_tbranch_o,
    .perf_dside_wait_o,
    .perf_wfi_wait_o,
    .perf_div_wait_o,
    .instr_id_done_o
  );

  // --------------------
  // Instantiate EX
  // --------------------
  logic [63:0] alu_adder_result_ex_o;
  logic [63:0] branch_target_o;

  cve2_ex_block #(
    .RV32M(RV32MNone),
    .RV32B(RV32BNone)
  ) dut_ex (
    .clk_i,
    .rst_ni,

    .alu_operator_i         (alu_operator_ex_o),
    .alu_operand_a_i        (alu_operand_a_ex_o),
    .alu_operand_b_i        (alu_operand_b_ex_o),
    .alu_instr_first_cycle_i(instr_first_cycle_id_o),
    .alu_word_op_i          (alu_word_op_ex_o),

    .multdiv_operator_i     (multdiv_operator_ex_o),
    .mult_en_i              (mult_en_ex_o),
    .div_en_i               (div_en_ex_o),
    .mult_sel_i             (mult_sel_ex_o),
    .div_sel_i              (div_sel_ex_o),
    .multdiv_signed_mode_i  (multdiv_signed_mode_ex_o),
    .multdiv_operand_a_i    (multdiv_operand_a_ex_o),
    .multdiv_operand_b_i    (multdiv_operand_b_ex_o),

    .imd_val_we_o (imd_val_we_ex),
    .imd_val_d_o  (imd_val_d_ex),
    .imd_val_q_i  (imd_val_q_ex),

    .carry_in_i   (carry_in),
    .carry_out_o  (carry_out),

    .alu_adder_result_ex_o(alu_adder_result_ex_o),
    .result_ex_o          (result_ex_i),
    .branch_target_o      (branch_target_o),
    .branch_decision_o    (branch_decision_o),
    .alu_is_equal_result_o(alu_is_equal_result_o),

    .ex_valid_o           (ex_valid_i)
  );

  // --------------------
  // Instantiate LSU
  // --------------------
  cve2_load_store_unit dut_lsu (
    .clk_i,
    .rst_ni,

    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_err_i,
    .data_pmp_err_i,

    .data_addr_o,
    .data_we_o,
    .data_be_o,
    .data_wdata_o,
    .data_rdata_i,

    .lsu_we_i      (lsu_we_o),
    .lsu_type_i    (lsu_type_o),
    .lsu_wdata_i   (lsu_wdata_o),
    .lsu_sign_ext_i(lsu_sign_ext_o),

    .lsu_rdata_o      (rf_wdata_lsu_i),
    .lsu_rdata_valid_o(rf_we_lsu_i),
    .lsu_req_i        (lsu_req_o),

    .adder_result_ex_i(lsu_addr_ex_o),

    .addr_incr_req_o(lsu_addr_incr_req_i),
    .addr_last_o    (lsu_addr_last_i),

    .lsu_resp_valid_o(lsu_resp_valid_i),

    .load_err_o (lsu_load_err_i),
    .store_err_o(lsu_store_err_i),

    .busy_o(),
    .perf_load_o(),
    .perf_store_o()
  );

  // --------------------
  // Instantiate WB
  // --------------------
  cve2_wb dut_wb (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .en_wb_i (en_wb_o),

    .instr_is_compressed_id_i(instr_is_compressed_i),
    .instr_perf_count_id_i   (instr_perf_count_id_o),

    .perf_instr_ret_wb_o            (),
    .perf_instr_ret_compressed_wb_o (),

    .rf_waddr_id_i(rf_waddr_id_o),
    .rf_wdata_id_i(rf_wdata_id_o),
    .rf_we_id_i   (rf_we_id_o),

    .rf_wdata_lsu_i(rf_wdata_lsu_i),
    .rf_we_lsu_i   (rf_we_lsu_i),

    .rf_waddr_wb_o(rf_waddr_wb_o),
    .rf_wdata_wb_o(rf_wdata_wb_o),
    .rf_we_wb_o   (rf_we_wb_o),

    .lsu_resp_valid_i(lsu_resp_valid_i),
    .lsu_resp_err_i  (1'b0)
  );

  // --------------------
  // RF preload/readback muxes for directed tests
  // --------------------
  logic        preload_mode;
  logic [4:0]  preload_waddr;
  logic [63:0] preload_wdata;
  logic        preload_we;

  logic [4:0]  rf_waddr_mux;
  logic [63:0] rf_wdata_mux;
  logic        rf_we_mux;

  logic        readback_mode;
  logic [4:0]  readback_raddr;
  logic [4:0]  rf_raddr_a_mux;

  initial begin
    preload_mode = 1'b0;
    preload_waddr = 5'd0;
    preload_wdata = 64'h0;
    preload_we = 1'b0;

    readback_mode = 1'b0;
    readback_raddr = 5'd0;
  end

  assign rf_waddr_mux   = preload_mode ? preload_waddr : rf_waddr_wb_o;
  assign rf_wdata_mux   = preload_mode ? preload_wdata : rf_wdata_wb_o;
  assign rf_we_mux      = preload_mode ? preload_we    : rf_we_wb_o;
  assign rf_raddr_a_mux = readback_mode ? readback_raddr : rf_raddr_a_o;

  cve2_register_file_ff #(
    .RV32E      (1'b0),
    .DataWidth  (64),
    .WordZeroVal(64'h0000_0000_0000_0000)
  ) dut_rf (
    .clk_i,
    .rst_ni,
    .test_en_i(1'b0),

    .raddr_a_i(rf_raddr_a_mux),
    .rdata_a_o(rf_rdata_a_i),

    .raddr_b_i(rf_raddr_b_o),
    .rdata_b_o(rf_rdata_b_i),

    .waddr_a_i(rf_waddr_mux),
    .wdata_a_i(rf_wdata_mux),
    .we_a_i   (rf_we_mux)
  );

  // --------------------
  // Native RV64I instruction encodings used by the directed tests
  // --------------------
  localparam logic [31:0] ADD_X3_X1_X2     = 32'h002081b3;
  localparam logic [31:0] ADD_X4_X5_X6     = 32'h00628233;
  localparam logic [31:0] SUB_X3_X1_X2     = 32'h402081b3;
  localparam logic [31:0] AND_X3_X1_X2     = 32'h0020f1b3;
  localparam logic [31:0] OR_X3_X1_X2      = 32'h0020e1b3;
  localparam logic [31:0] XOR_X3_X1_X2     = 32'h0020c1b3;
  localparam logic [31:0] ADDI_X3_X1_POS   = 32'h00508193;
  localparam logic [31:0] ADDI_X3_X1_NEG   = 32'hfff08193;
  localparam logic [31:0] ANDI_X3_X1_POS   = 32'h0050f193;
  localparam logic [31:0] ANDI_X3_X1_NEG   = 32'hfff0f193;
  localparam logic [31:0] ORI_X3_X1_POS    = 32'h0050e193;
  localparam logic [31:0] ORI_X3_X1_NEG    = 32'hfff0e193;
  localparam logic [31:0] XORI_X3_X1_POS   = 32'h0050c193;
  localparam logic [31:0] XORI_X3_X1_NEG   = 32'hfff0c193;
  localparam logic [31:0] SLT_X3_X1_X2     = 32'h0020a1b3;
  localparam logic [31:0] SLTU_X3_X1_X2    = 32'h0020b1b3;
  localparam logic [31:0] SLTI_X3_X1_NEG   = 32'hfff0a193;
  localparam logic [31:0] SLTIU_X3_X1_NEG  = 32'hfff0b193;

  localparam logic [31:0] ADDIW_X3_X1_NEG  = 32'hfff0819b;
  localparam logic [31:0] SLLIW_X3_X1_1    = 32'h0010919b;
  localparam logic [31:0] SRLIW_X3_X1_1    = 32'h0010d19b;
  localparam logic [31:0] SRAIW_X3_X1_1    = 32'h4010d19b;
  localparam logic [31:0] ADDW_X3_X1_X2    = 32'h002081bb;
  localparam logic [31:0] SUBW_X3_X1_X2    = 32'h402081bb;
  localparam logic [31:0] SLLW_X3_X1_X2    = 32'h002091bb;
  localparam logic [31:0] SRLW_X3_X1_X2    = 32'h0020d1bb;
  localparam logic [31:0] SRAW_X3_X1_X2    = 32'h4020d1bb;

  localparam logic [31:0] SLL_X3_X1_X2     = 32'h002091b3;
  localparam logic [31:0] SRL_X3_X1_X2     = 32'h0020d1b3;
  localparam logic [31:0] SRA_X3_X1_X2     = 32'h4020d1b3;
  localparam logic [31:0] SLL_X1_X1_X2     = 32'h002090b3;
  localparam logic [31:0] SRL_X2_X1_X2     = 32'h0020d133;
  localparam logic [31:0] SLLI_X3_X1_0     = 32'h00009193;
  localparam logic [31:0] SLLI_X3_X1_36    = 32'h02409193;
  localparam logic [31:0] SRLI_X3_X1_36    = 32'h0240d193;
  localparam logic [31:0] SRAI_X3_X1_36    = 32'h4240d193;

  localparam logic [31:0] LB_X3_0_X1       = 32'h00008183;
  localparam logic [31:0] LH_X3_0_X1       = 32'h00009183;
  localparam logic [31:0] LW_X3_0_X1       = 32'h0000a183;
  localparam logic [31:0] LBU_X3_0_X1      = 32'h0000c183;
  localparam logic [31:0] LHU_X3_0_X1      = 32'h0000d183;
  localparam logic [31:0] LWU_X3_0_X1      = 32'h0000e183;
  localparam logic [31:0] LD_X3_0_X1       = 32'h0000b183;
  localparam logic [31:0] SD_X2_0_X1       = 32'h0020b023;
  localparam logic [31:0] SW_X2_4_X1       = 32'h0020a223;
  localparam logic [31:0] SB_X2_7_X1       = 32'h002083a3;

  localparam logic [31:0] BEQ_X1_X2        = 32'h00208463;
  localparam logic [31:0] BNE_X1_X2        = 32'h00209463;
  localparam logic [31:0] BLT_X1_X2        = 32'h0020c463;
  localparam logic [31:0] BGE_X1_X2        = 32'h0020d463;
  localparam logic [31:0] BLTU_X1_X2       = 32'h0020e463;
  localparam logic [31:0] BGEU_X1_X2       = 32'h0020f463;

  localparam logic [31:0] LUI_X3_POS       = 32'h7ffff1b7;
  localparam logic [31:0] LUI_X3_NEG       = 32'h800001b7;
  localparam logic [31:0] AUIPC_X3_1       = 32'h00001197;
  localparam logic [31:0] AUIPC_X3_NEG     = 32'hfffff197;
  localparam logic [31:0] JAL_X3_0         = 32'h000001ef;
  localparam logic [31:0] JALR_X3_X1_0     = 32'h000081e7;

  localparam logic [31:0] CSRRS_X3_MEPC_X0 = 32'h341021f3;
  localparam logic [31:0] MRET_INSN        = 32'h30200073;

  // --------------------
  // Helpers
  // --------------------
  int unsigned error_count;

  task automatic note_cycle(input string test_name,
                            input int unsigned expected_cycles,
                            input int unsigned actual_cycles);
    if (actual_cycles !== expected_cycles) begin
      $display("%s NOTE: cycles = %0d, expected previous count %0d",
               test_name, actual_cycles, expected_cycles);
    end else begin
      $display("%s PASS: cycles = %0d", test_name, actual_cycles);
    end
  endtask

  task automatic check_value64(input string test_name,
                               input logic [63:0] actual_value,
                               input logic [63:0] expected_value);
    if (actual_value !== expected_value) begin
      error_count++;
      $error("%s FAIL: value = %016h, expected %016h",
             test_name, actual_value, expected_value);
    end else begin
      $display("%s PASS: value = %016h", test_name, actual_value);
    end
  endtask

  task automatic check_addr64(input string test_name,
                              input logic [63:0] actual_addr,
                              input logic [63:0] expected_addr);
    if (actual_addr !== expected_addr) begin
      error_count++;
      $error("%s FAIL: addr = %016h, expected %016h",
             test_name, actual_addr, expected_addr);
    end else begin
      $display("%s PASS: addr = %016h", test_name, actual_addr);
    end
  endtask

  task automatic check_be8(input string test_name,
                           input logic [7:0] actual_be,
                           input logic [7:0] expected_be);
    if (actual_be !== expected_be) begin
      error_count++;
      $error("%s FAIL: byte enable = %02h, expected %02h",
             test_name, actual_be, expected_be);
    end else begin
      $display("%s PASS: byte enable = %02h", test_name, actual_be);
    end
  endtask

  task automatic write_rf_64(input logic [4:0] addr,
                             input logic [63:0] data);
    @(posedge clk_i);
    #1;
    preload_mode  = 1'b1;
    preload_waddr = addr;
    preload_wdata = data;
    preload_we    = 1'b1;
    @(posedge clk_i);
    #1;
    preload_we    = 1'b0;
    preload_mode  = 1'b0;
  endtask

  task automatic read_rf_64(input logic [4:0] addr,
                            output logic [63:0] data);
    readback_mode  = 1'b1;
    readback_raddr = addr;
    #1;
    data = rf_rdata_a_i;
    readback_mode = 1'b0;
  endtask

  task automatic check_reg(input string test_name,
                           input logic [4:0] regnum,
                           input logic [63:0] expected_value,
                           input int unsigned expected_cycles,
                           input int unsigned actual_cycles);
    logic [63:0] actual_value;

    read_rf_64(regnum, actual_value);
    check_value64(test_name, actual_value, expected_value);
    note_cycle(test_name, expected_cycles, actual_cycles);
  endtask

  task automatic set_pc64(input logic [63:0] pc_value);
    pc_id_i = pc_value;
    #1;
  endtask

  task automatic wait_for_native_idle(input string idle_context,
                                      inout int unsigned cycles_taken);
    int unsigned guard;

    guard = 0;
    while (dut_id.id_fsm_q != 1'b0) begin
      cycles_taken++;
      guard++;
      if (guard > 50) begin
        error_count++;
        $error("%s FAIL: ID stage did not return to FIRST_CYCLE", idle_context);
        disable wait_for_native_idle;
      end
      @(posedge clk_i);
      #1;
    end
  endtask

  task automatic inject_instr(input logic [31:0] encoding,
                              output int unsigned cycles_taken);
    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;

    @(posedge clk_i);
    #1;
    cycles_taken = 1;
    wait_for_native_idle("inject_instr", cycles_taken);

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_two_instrs_no_gap(input logic [31:0] first_encoding,
                                          input logic [31:0] second_encoding,
                                          output int unsigned first_cycles,
                                          output int unsigned second_cycles);
    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = first_encoding;
    instr_rdata_alu_i = first_encoding;

    @(posedge clk_i);
    #1;
    first_cycles = 1;
    wait_for_native_idle("inject_two first", first_cycles);

    instr_rdata_i     = second_encoding;
    instr_rdata_alu_i = second_encoding;

    @(posedge clk_i);
    #1;
    second_cycles = 1;
    wait_for_native_idle("inject_two second", second_cycles);

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_instr_capture_pc(input logic [31:0] encoding,
                                         output int unsigned cycles_taken,
                                         output logic saw_pc_set,
                                         output logic [63:0] pc_target);
    int unsigned guard;

    saw_pc_set = 1'b0;
    pc_target  = 64'h0000_0000_0000_0000;
    guard      = 0;

    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;

    @(posedge clk_i);
    #1;
    cycles_taken = 1;
    if (pc_set_o) begin
      saw_pc_set = 1'b1;
      pc_target  = pc_target_ex_o;
    end

    while (dut_id.id_fsm_q != 1'b0) begin
      cycles_taken++;
      guard++;
      if (guard > 50) begin
        error_count++;
        $error("capture_pc FAIL: ID stage did not return to FIRST_CYCLE");
        disable inject_instr_capture_pc;
      end
      @(posedge clk_i);
      #1;
      if (pc_set_o) begin
        saw_pc_set = 1'b1;
        pc_target  = pc_target_ex_o;
      end
    end

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_illegal_instr_check(input string test_name,
                                            input logic [31:0] encoding);
    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;
    #1;

    if (!illegal_insn_o) begin
      error_count++;
      $error("%s FAIL: instruction %08h was not flagged illegal", test_name, encoding);
    end else begin
      $display("%s PASS: instruction %08h flagged illegal", test_name, encoding);
    end

    if (csr_access_o || csr_op_en_o || rf_we_id_o || lsu_req_o) begin
      error_count++;
      $error("%s FAIL: side effects not suppressed: csr_access=%0b csr_op_en=%0b rf_we=%0b lsu_req=%0b",
             test_name, csr_access_o, csr_op_en_o, rf_we_id_o, lsu_req_o);
    end else begin
      $display("%s PASS: CSR/RF/LSU side effects suppressed", test_name);
    end

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_load(input logic [31:0] encoding,
                             input logic [63:0] mem_word,
                             output int unsigned cycles_taken,
                             output logic [63:0] first_addr,
                             output int unsigned req_count);
    logic [63:0] resp_queue[4];
    int unsigned resp_head;
    int unsigned resp_tail;
    int unsigned resp_count;
    int unsigned guard;
    logic sampled_rvalid;

    resp_head    = 0;
    resp_tail    = 0;
    resp_count   = 0;
    first_addr   = 64'h0000_0000_0000_0000;
    req_count    = 0;
    cycles_taken = 0;
    guard        = 0;

    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;
    data_rvalid_i     = 1'b0;
    data_rdata_i      = 64'h0000_0000_0000_0000;
    #1;

    // Native LSU requests are visible in the first decode cycle before the
    // next clock edge, so capture that address phase immediately.
    if (data_req_o && !data_we_o) begin
      first_addr             = data_addr_o;
      resp_queue[resp_tail]  = mem_word;
      resp_tail              = (resp_tail + 1) % 4;
      resp_count++;
      req_count++;
    end

    do begin
      @(posedge clk_i);
      #1;
      cycles_taken++;
      guard++;
      sampled_rvalid = data_rvalid_i;

      if (resp_count != 0) begin
        data_rdata_i  = resp_queue[resp_head];
        data_rvalid_i = 1'b1;
        resp_head     = (resp_head + 1) % 4;
        resp_count--;
      end else begin
        data_rdata_i  = 64'h0000_0000_0000_0000;
        data_rvalid_i = 1'b0;
      end

      if (sampled_rvalid && (dut_id.id_fsm_q == 1'b0)) begin
        instr_valid_i     = 1'b0;
        instr_rdata_i     = 32'h0000_0013;
        instr_rdata_alu_i = 32'h0000_0013;
      end

      if (instr_valid_i && data_req_o && !data_we_o) begin
        if (req_count == 0) begin
          first_addr = data_addr_o;
        end
        resp_queue[resp_tail] = mem_word;
        resp_tail             = (resp_tail + 1) % 4;
        resp_count++;
        req_count++;
      end

      if (guard > 80) begin
        error_count++;
        $error("inject_load FAIL: timeout");
        disable inject_load;
      end
    end while ((dut_id.id_fsm_q != 1'b0) || (resp_count != 0) || data_rvalid_i);

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;
    data_rdata_i      = 64'h0000_0000_0000_0000;
    data_rvalid_i     = 1'b0;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_load_two_beats(input logic [31:0] encoding,
                                       input logic [63:0] first_word,
                                       input logic [63:0] second_word,
                                       output int unsigned cycles_taken,
                                       output logic [63:0] first_addr,
                                       output logic [63:0] second_addr,
                                       output int unsigned req_count);
    logic [63:0] resp_queue[4];
    int unsigned resp_head;
    int unsigned resp_tail;
    int unsigned resp_count;
    int unsigned guard;
    logic sampled_rvalid;

    resp_head    = 0;
    resp_tail    = 0;
    resp_count   = 0;
    first_addr   = 64'h0000_0000_0000_0000;
    second_addr  = 64'h0000_0000_0000_0000;
    req_count    = 0;
    cycles_taken = 0;
    guard        = 0;

    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;
    data_rvalid_i     = 1'b0;
    data_rdata_i      = 64'h0000_0000_0000_0000;
    #1;

    if (data_req_o && !data_we_o) begin
      first_addr            = data_addr_o;
      resp_queue[resp_tail] = first_word;
      resp_tail             = (resp_tail + 1) % 4;
      resp_count++;
      req_count++;
    end

    do begin
      @(posedge clk_i);
      #1;
      cycles_taken++;
      guard++;
      sampled_rvalid = data_rvalid_i;

      if (resp_count != 0) begin
        data_rdata_i  = resp_queue[resp_head];
        data_rvalid_i = 1'b1;
        resp_head     = (resp_head + 1) % 4;
        resp_count--;
      end else begin
        data_rdata_i  = 64'h0000_0000_0000_0000;
        data_rvalid_i = 1'b0;
      end

      if (sampled_rvalid && (dut_id.id_fsm_q == 1'b0)) begin
        instr_valid_i     = 1'b0;
        instr_rdata_i     = 32'h0000_0013;
        instr_rdata_alu_i = 32'h0000_0013;
      end

      if (instr_valid_i && data_req_o && !data_we_o) begin
        if (req_count == 0) begin
          first_addr = data_addr_o;
          resp_queue[resp_tail] = first_word;
        end else begin
          second_addr = data_addr_o;
          resp_queue[resp_tail] = second_word;
        end
        resp_tail = (resp_tail + 1) % 4;
        resp_count++;
        req_count++;
      end

      if (guard > 100) begin
        error_count++;
        $error("inject_load_two_beats FAIL: timeout");
        disable inject_load_two_beats;
      end
    end while ((dut_id.id_fsm_q != 1'b0) || (resp_count != 0) || data_rvalid_i);

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;
    data_rdata_i      = 64'h0000_0000_0000_0000;
    data_rvalid_i     = 1'b0;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_store(input logic [31:0] encoding,
                              output int unsigned cycles_taken,
                              output logic [63:0] first_addr,
                              output logic [63:0] first_wdata,
                              output logic [7:0]  first_be,
                              output logic [63:0] second_addr,
                              output logic [63:0] second_wdata,
                              output logic [7:0]  second_be,
                              output int unsigned req_count);
    int unsigned resp_count;
    int unsigned guard;
    logic sampled_rvalid;

    resp_count   = 0;
    cycles_taken = 0;
    guard        = 0;
    req_count    = 0;
    first_addr   = 64'h0;
    first_wdata  = 64'h0;
    first_be     = 8'h00;
    second_addr  = 64'h0;
    second_wdata = 64'h0;
    second_be    = 8'h00;

    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;
    data_rvalid_i     = 1'b0;
    #1;

    if (data_req_o && data_we_o) begin
      first_addr  = data_addr_o;
      first_wdata = data_wdata_o;
      first_be    = data_be_o;
      req_count++;
      resp_count++;
    end

    do begin
      @(posedge clk_i);
      #1;
      cycles_taken++;
      guard++;
      sampled_rvalid = data_rvalid_i;

      if (resp_count != 0) begin
        data_rvalid_i = 1'b1;
        resp_count--;
      end else begin
        data_rvalid_i = 1'b0;
      end

      if (sampled_rvalid && (dut_id.id_fsm_q == 1'b0)) begin
        instr_valid_i     = 1'b0;
        instr_rdata_i     = 32'h0000_0013;
        instr_rdata_alu_i = 32'h0000_0013;
      end

      if (instr_valid_i && data_req_o && data_we_o) begin
        if (req_count == 0) begin
          first_addr  = data_addr_o;
          first_wdata = data_wdata_o;
          first_be    = data_be_o;
        end else begin
          second_addr  = data_addr_o;
          second_wdata = data_wdata_o;
          second_be    = data_be_o;
        end
        req_count++;
        resp_count++;
      end

      if (guard > 100) begin
        error_count++;
        $error("inject_store FAIL: timeout");
        disable inject_store;
      end
    end while ((dut_id.id_fsm_q != 1'b0) || (resp_count != 0) || data_rvalid_i);

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;
    data_rvalid_i     = 1'b0;

    repeat (3) @(posedge clk_i);
  endtask

  // --------------------
  // Main test stimulus
  // --------------------
  int unsigned cycles;
  int unsigned cycles_second;
  int unsigned req_count;
  logic [63:0] captured_addr;
  logic [63:0] captured_addr_second;
  logic [63:0] store_addr;
  logic [63:0] store_addr_second;
  logic [63:0] store_wdata;
  logic [63:0] store_wdata_second;
  logic [7:0]  store_be;
  logic [7:0]  store_be_second;
  logic        saw_pc_set;
  logic [63:0] captured_pc_target;

  initial begin
    error_count = 0;

    @(posedge rst_ni);
    #1;
    repeat (10) @(posedge clk_i);

    $display("\n========== Native RV64 ALU tests ==========");

    $display("\n---- T01: ADD full 64-bit carry across bit 31 ----");
    write_rf_64(5'd1, 64'h0000_0000_ffff_ffff);
    write_rf_64(5'd2, 64'h0000_0000_0000_0001);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_reg("T01", 5'd3, 64'h0000_0001_0000_0000, 1, cycles);

    $display("\n---- T02: ADD with non-zero upper halves ----");
    write_rf_64(5'd1, 64'h1234_5678_0000_0005);
    write_rf_64(5'd2, 64'h1111_2222_0000_0003);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_reg("T02", 5'd3, 64'h2345_789a_0000_0008, 1, cycles);

    $display("\n---- T03: SUB underflow is full 64-bit ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0003);
    write_rf_64(5'd2, 64'h0000_0000_0000_0005);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_reg("T03", 5'd3, 64'hffff_ffff_ffff_fffe, 1, cycles);

    $display("\n---- T04: back-to-back ADD regression ----");
    write_rf_64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf_64(5'd2, 64'h0000_0000_0000_0001);
    write_rf_64(5'd5, 64'h0000_0000_0000_0010);
    write_rf_64(5'd6, 64'h0000_0000_0000_0005);
    inject_two_instrs_no_gap(ADD_X3_X1_X2, ADD_X4_X5_X6, cycles, cycles_second);
    check_reg("T04A", 5'd3, 64'h0000_0000_0000_0000, 1, cycles);
    check_reg("T04B", 5'd4, 64'h0000_0000_0000_0015, 1, cycles_second);

    $display("\n---- T05: AND/OR/XOR use full 64-bit operands ----");
    write_rf_64(5'd1, 64'hffff_0000_f0f0_0f0f);
    write_rf_64(5'd2, 64'h0f0f_ffff_00ff_00ff);
    inject_instr(AND_X3_X1_X2, cycles);
    check_reg("T05A AND", 5'd3, 64'h0f0f_0000_00f0_000f, 1, cycles);
    inject_instr(OR_X3_X1_X2, cycles);
    check_reg("T05B OR", 5'd3, 64'hffff_ffff_f0ff_0fff, 1, cycles);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_reg("T05C XOR", 5'd3, 64'hf0f0_ffff_f00f_0ff0, 1, cycles);

    $display("\n========== Native RV64 immediate tests ==========");

    $display("\n---- I01: ADDI sign-extends negative immediate to 64 bits ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0000);
    inject_instr(ADDI_X3_X1_NEG, cycles);
    check_reg("I01", 5'd3, 64'hffff_ffff_ffff_ffff, 1, cycles);

    $display("\n---- I02: ADDI with positive immediate preserves upper operand ----");
    write_rf_64(5'd1, 64'h1234_5678_0000_0010);
    inject_instr(ADDI_X3_X1_POS, cycles);
    check_reg("I02", 5'd3, 64'h1234_5678_0000_0015, 1, cycles);

    $display("\n---- I03: ANDI/ORI/XORI sign-extend immediates across XLEN ----");
    write_rf_64(5'd1, 64'h1234_5678_0000_0012);
    inject_instr(ANDI_X3_X1_NEG, cycles);
    check_reg("I03A ANDI -1", 5'd3, 64'h1234_5678_0000_0012, 1, cycles);
    inject_instr(ORI_X3_X1_NEG, cycles);
    check_reg("I03B ORI -1", 5'd3, 64'hffff_ffff_ffff_ffff, 1, cycles);
    inject_instr(XORI_X3_X1_NEG, cycles);
    check_reg("I03C XORI -1", 5'd3, 64'hedcb_a987_ffff_ffed, 1, cycles);
    inject_instr(ANDI_X3_X1_POS, cycles);
    check_reg("I03D ANDI +5", 5'd3, 64'h0000_0000_0000_0000, 1, cycles);
    inject_instr(ORI_X3_X1_POS, cycles);
    check_reg("I03E ORI +5", 5'd3, 64'h1234_5678_0000_0017, 1, cycles);
    inject_instr(XORI_X3_X1_POS, cycles);
    check_reg("I03F XORI +5", 5'd3, 64'h1234_5678_0000_0017, 1, cycles);

    $display("\n========== Compare and branch tests ==========");

    $display("\n---- C01: SLT signed compares full 64-bit sign ----");
    write_rf_64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf_64(5'd2, 64'h0000_0000_0000_0000);
    inject_instr(SLT_X3_X1_X2, cycles);
    check_reg("C01", 5'd3, 64'h0000_0000_0000_0001, 1, cycles);

    $display("\n---- C02: SLTU compares full 64-bit unsigned magnitude ----");
    inject_instr(SLTU_X3_X1_X2, cycles);
    check_reg("C02", 5'd3, 64'h0000_0000_0000_0000, 1, cycles);

    $display("\n---- C03: SLTI/SLTIU use sign-extended 64-bit immediate ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0000);
    inject_instr(SLTI_X3_X1_NEG, cycles);
    check_reg("C03A SLTI", 5'd3, 64'h0000_0000_0000_0000, 1, cycles);
    inject_instr(SLTIU_X3_X1_NEG, cycles);
    check_reg("C03B SLTIU", 5'd3, 64'h0000_0000_0000_0001, 1, cycles);

    $display("\n---- B01: BEQ full 64-bit equal, taken ----");
    set_pc64(64'h0000_0000_0000_1000);
    write_rf_64(5'd1, 64'h1234_5678_0000_0005);
    write_rf_64(5'd2, 64'h1234_5678_0000_0005);
    inject_instr_capture_pc(BEQ_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B01 pc_set", {63'h0, saw_pc_set}, 64'h1);
    check_addr64("B01 target", captured_pc_target, 64'h0000_0000_0000_1008);
    note_cycle("B01", 2, cycles);

    $display("\n---- B02: BNE full 64-bit upper mismatch, taken ----");
    write_rf_64(5'd1, 64'h1234_5678_0000_0005);
    write_rf_64(5'd2, 64'h1234_5679_0000_0005);
    inject_instr_capture_pc(BNE_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B02 pc_set", {63'h0, saw_pc_set}, 64'h1);
    check_addr64("B02 target", captured_pc_target, 64'h0000_0000_0000_1008);
    note_cycle("B02", 2, cycles);

    $display("\n---- B03: BLT signed negative < zero, taken ----");
    write_rf_64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf_64(5'd2, 64'h0000_0000_0000_0000);
    inject_instr_capture_pc(BLT_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B03 pc_set", {63'h0, saw_pc_set}, 64'h1);
    note_cycle("B03", 2, cycles);

    $display("\n---- B04: BLTU unsigned max < zero is false ----");
    inject_instr_capture_pc(BLTU_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B04 pc_set", {63'h0, saw_pc_set}, 64'h0);
    note_cycle("B04", 1, cycles);

    $display("\n---- B05: BGE/BGEU true cases ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0005);
    write_rf_64(5'd2, 64'hffff_ffff_ffff_ffff);
    inject_instr_capture_pc(BGE_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B05A BGE pc_set", {63'h0, saw_pc_set}, 64'h1);
    write_rf_64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf_64(5'd2, 64'h0000_0000_0000_0005);
    inject_instr_capture_pc(BGEU_X1_X2, cycles, saw_pc_set, captured_pc_target);
    check_value64("B05B BGEU pc_set", {63'h0, saw_pc_set}, 64'h1);

    $display("\n========== W-variant tests ==========");

    $display("\n---- W01: ADDIW wraps low word and sign-extends ----");
    write_rf_64(5'd1, 64'haaaa_5555_0000_0000);
    inject_instr(ADDIW_X3_X1_NEG, cycles);
    check_reg("W01", 5'd3, 64'hffff_ffff_ffff_ffff, 1, cycles);

    $display("\n---- W02: ADDW/SUBW ignore upper source bits and sign-extend result ----");
    write_rf_64(5'd1, 64'haaaa_5555_7fff_ffff);
    write_rf_64(5'd2, 64'h1234_5678_0000_0001);
    inject_instr(ADDW_X3_X1_X2, cycles);
    check_reg("W02A ADDW", 5'd3, 64'hffff_ffff_8000_0000, 1, cycles);
    write_rf_64(5'd1, 64'haaaa_5555_0000_0000);
    write_rf_64(5'd2, 64'h1234_5678_0000_0001);
    inject_instr(SUBW_X3_X1_X2, cycles);
    check_reg("W02B SUBW", 5'd3, 64'hffff_ffff_ffff_ffff, 1, cycles);

    $display("\n---- W03: W shifts use 5-bit shamt and sign-extend 32-bit result ----");
    write_rf_64(5'd1, 64'haaaa_5555_4000_0000);
    inject_instr(SLLIW_X3_X1_1, cycles);
    check_reg("W03A SLLIW", 5'd3, 64'hffff_ffff_8000_0000, 1, cycles);
    write_rf_64(5'd1, 64'haaaa_5555_8000_0000);
    inject_instr(SRLIW_X3_X1_1, cycles);
    check_reg("W03B SRLIW", 5'd3, 64'h0000_0000_4000_0000, 1, cycles);
    inject_instr(SRAIW_X3_X1_1, cycles);
    check_reg("W03C SRAIW", 5'd3, 64'hffff_ffff_c000_0000, 1, cycles);

    $display("\n---- W04: register W shifts use rs2[4:0] only ----");
    write_rf_64(5'd1, 64'h1111_2222_4000_0000);
    write_rf_64(5'd2, 64'hffff_ffff_0000_0001);
    inject_instr(SLLW_X3_X1_X2, cycles);
    check_reg("W04A SLLW", 5'd3, 64'hffff_ffff_8000_0000, 1, cycles);
    write_rf_64(5'd1, 64'h1111_2222_8000_0000);
    inject_instr(SRLW_X3_X1_X2, cycles);
    check_reg("W04B SRLW", 5'd3, 64'h0000_0000_4000_0000, 1, cycles);
    inject_instr(SRAW_X3_X1_X2, cycles);
    check_reg("W04C SRAW", 5'd3, 64'hffff_ffff_c000_0000, 1, cycles);

    $display("\n========== Native 64-bit shift tests ==========");

    $display("\n---- SH01: SLL/SRL/SRA cross the 32-bit boundary natively ----");
    write_rf_64(5'd1, 64'h0000_0001_8000_0000);
    write_rf_64(5'd2, 64'h0000_0000_0000_0001);
    inject_instr(SLL_X3_X1_X2, cycles);
    check_reg("SH01A SLL", 5'd3, 64'h0000_0003_0000_0000, 1, cycles);
    write_rf_64(5'd1, 64'h0000_0001_0000_0000);
    inject_instr(SRL_X3_X1_X2, cycles);
    check_reg("SH01B SRL", 5'd3, 64'h0000_0000_8000_0000, 1, cycles);
    write_rf_64(5'd1, 64'h8000_0000_0000_0000);
    inject_instr(SRA_X3_X1_X2, cycles);
    check_reg("SH01C SRA", 5'd3, 64'hc000_0000_0000_0000, 1, cycles);

    $display("\n---- SH02: immediate shifts use RV64 shamt[5:0] ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0012);
    inject_instr(SLLI_X3_X1_36, cycles);
    check_reg("SH02A SLLI36", 5'd3, 64'h0000_0120_0000_0000, 1, cycles);
    write_rf_64(5'd1, 64'h1234_5678_0000_0000);
    inject_instr(SRLI_X3_X1_36, cycles);
    check_reg("SH02B SRLI36", 5'd3, 64'h0000_0000_0123_4567, 1, cycles);
    write_rf_64(5'd1, 64'h9234_5678_0000_0000);
    inject_instr(SRAI_X3_X1_36, cycles);
    check_reg("SH02C SRAI36", 5'd3, 64'hffff_ffff_f923_4567, 1, cycles);

    $display("\n---- SH03: rd==rs hazards keep original operands ----");
    write_rf_64(5'd1, 64'h0000_0001_8000_0000);
    write_rf_64(5'd2, 64'h0000_0000_0000_0001);
    inject_instr(SLL_X1_X1_X2, cycles);
    check_reg("SH03A SLL rd==rs1", 5'd1, 64'h0000_0003_0000_0000, 1, cycles);
    write_rf_64(5'd1, 64'h0000_0001_0000_0000);
    write_rf_64(5'd2, 64'h0000_0000_0000_0001);
    inject_instr(SRL_X2_X1_X2, cycles);
    check_reg("SH03B SRL rd==rs2", 5'd2, 64'h0000_0000_8000_0000, 1, cycles);

    $display("\n========== PC-producing instruction tests ==========");

    $display("\n---- P01: LUI sign-extends U-immediate to XLEN ----");
    inject_instr(LUI_X3_POS, cycles);
    check_reg("P01A LUI positive", 5'd3, 64'h0000_0000_7fff_f000, 1, cycles);
    inject_instr(LUI_X3_NEG, cycles);
    check_reg("P01B LUI negative", 5'd3, 64'hffff_ffff_8000_0000, 1, cycles);

    $display("\n---- P02: AUIPC adds full 64-bit PC and sign-extended U-immediate ----");
    set_pc64(64'h0000_0000_ffff_f000);
    inject_instr(AUIPC_X3_1, cycles);
    check_reg("P02A AUIPC carry", 5'd3, 64'h0000_0001_0000_0000, 1, cycles);
    set_pc64(64'h0000_0000_0000_0000);
    inject_instr(AUIPC_X3_NEG, cycles);
    check_reg("P02B AUIPC negative", 5'd3, 64'hffff_ffff_ffff_f000, 1, cycles);

    $display("\n---- P03: JAL link is PC+4 ----");
    set_pc64(64'h0000_0000_ffff_fffc);
    inject_instr_capture_pc(JAL_X3_0, cycles, saw_pc_set, captured_pc_target);
    check_reg("P03 link", 5'd3, 64'h0000_0001_0000_0000, 2, cycles);
    check_value64("P03 pc_set", {63'h0, saw_pc_set}, 64'h1);
    check_addr64("P03 target", captured_pc_target, 64'h0000_0000_ffff_fffc);

    $display("\n---- P04: JALR target uses 64-bit base (IF masks bit 0) ----");
    set_pc64(64'h0000_0000_0000_1000);
    write_rf_64(5'd1, 64'h1234_5678_0000_0041);
    inject_instr_capture_pc(JALR_X3_X1_0, cycles, saw_pc_set, captured_pc_target);
    check_reg("P04 link", 5'd3, 64'h0000_0000_0000_1004, 2, cycles);
    check_value64("P04 pc_set", {63'h0, saw_pc_set}, 64'h1);
    check_addr64("P04 raw target", captured_pc_target, 64'h1234_5678_0000_0041);
    set_pc64(64'h0000_0000_0000_0000);

    $display("\n========== Native 64-bit load tests ==========");

    $display("\n---- L01: LB/LBU sign and zero extension ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0000);
    inject_load(LB_X3_0_X1, 64'h0000_0000_0000_0080, cycles, captured_addr, req_count);
    check_reg("L01A LB", 5'd3, 64'hffff_ffff_ffff_ff80, 2, cycles);
    check_addr64("L01A addr", captured_addr, 64'h0000_0000_0000_0000);
    check_value64("L01A req_count", req_count, 1);
    inject_load(LBU_X3_0_X1, 64'h0000_0000_0000_0080, cycles, captured_addr, req_count);
    check_reg("L01B LBU", 5'd3, 64'h0000_0000_0000_0080, 2, cycles);

    $display("\n---- L02: LH/LHU sign and zero extension ----");
    inject_load(LH_X3_0_X1, 64'h0000_0000_0000_8001, cycles, captured_addr, req_count);
    check_reg("L02A LH", 5'd3, 64'hffff_ffff_ffff_8001, 2, cycles);
    inject_load(LHU_X3_0_X1, 64'h0000_0000_0000_8001, cycles, captured_addr, req_count);
    check_reg("L02B LHU", 5'd3, 64'h0000_0000_0000_8001, 2, cycles);

    $display("\n---- L03: LW/LWU sign and zero extension ----");
    inject_load(LW_X3_0_X1, 64'h0000_0000_8000_0000, cycles, captured_addr, req_count);
    check_reg("L03A LW", 5'd3, 64'hffff_ffff_8000_0000, 2, cycles);
    inject_load(LWU_X3_0_X1, 64'h0000_0000_8000_0000, cycles, captured_addr, req_count);
    check_reg("L03B LWU", 5'd3, 64'h0000_0000_8000_0000, 2, cycles);

    $display("\n---- L04: LD returns the full 64-bit bus word in one request ----");
    inject_load(LD_X3_0_X1, 64'h1234_5678_9abc_def0, cycles, captured_addr, req_count);
    check_reg("L04", 5'd3, 64'h1234_5678_9abc_def0, 2, cycles);
    check_value64("L04 req_count", req_count, 1);

    $display("\n---- L05: misaligned LW crossing 8-byte boundary stitches two beats ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0006);
    inject_load_two_beats(LW_X3_0_X1,
                          64'h7766_5544_3322_1100,
                          64'hffee_ddcc_bbaa_9988,
                          cycles, captured_addr, captured_addr_second, req_count);
    check_reg("L05", 5'd3, 64'hffff_ffff_9988_7766, 3, cycles);
    check_addr64("L05 first addr", captured_addr, 64'h0000_0000_0000_0000);
    check_addr64("L05 second addr", captured_addr_second, 64'h0000_0000_0000_0008);
    check_value64("L05 req_count", req_count, 2);

    $display("\n========== Native 64-bit store tests ==========");

    $display("\n---- S01: SD stores a full 64-bit word in one request ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0000);
    write_rf_64(5'd2, 64'h1122_3344_5566_7788);
    inject_store(SD_X2_0_X1, cycles, store_addr, store_wdata, store_be,
                 store_addr_second, store_wdata_second, store_be_second, req_count);
    check_addr64("S01 addr", store_addr, 64'h0000_0000_0000_0000);
    check_value64("S01 wdata", store_wdata, 64'h1122_3344_5566_7788);
    check_be8("S01 be", store_be, 8'hff);
    check_value64("S01 req_count", req_count, 1);
    note_cycle("S01", 2, cycles);

    $display("\n---- S02: SW at offset 4 uses upper byte lanes on the 64-bit bus ----");
    write_rf_64(5'd1, 64'h0000_0000_0000_0000);
    write_rf_64(5'd2, 64'h1122_3344_aabb_ccdd);
    inject_store(SW_X2_4_X1, cycles, store_addr, store_wdata, store_be,
                 store_addr_second, store_wdata_second, store_be_second, req_count);
    check_addr64("S02 addr", store_addr, 64'h0000_0000_0000_0000);
    check_value64("S02 wdata", store_wdata, 64'haabb_ccdd_1122_3344);
    check_be8("S02 be", store_be, 8'hf0);
    check_value64("S02 req_count", req_count, 1);

    $display("\n---- S03: SB at offset 7 selects only the top byte lane ----");
    write_rf_64(5'd2, 64'h1122_3344_aabb_ccdd);
    inject_store(SB_X2_7_X1, cycles, store_addr, store_wdata, store_be,
                 store_addr_second, store_wdata_second, store_be_second, req_count);
    check_addr64("S03 addr", store_addr, 64'h0000_0000_0000_0000);
    check_value64("S03 wdata", store_wdata, 64'hdd11_2233_44aa_bbcc);
    check_be8("S03 be", store_be, 8'h80);
    check_value64("S03 req_count", req_count, 1);

    $display("\n========== No-CSR decode tests ==========");
    inject_illegal_instr_check("NOCSR01 CSRRS", CSRRS_X3_MEPC_X0);
    inject_illegal_instr_check("NOCSR02 MRET", MRET_INSN);

    repeat (10) @(posedge clk_i);

    if (error_count == 0) begin
      $display("\n==============================");
      $display("ALL NATIVE RV64 DIRECTED TESTS PASSED");
      $display("==============================");
    end else begin
      $display("\n==============================");
      $display("NATIVE RV64 DIRECTED TESTS FAILED: %0d errors", error_count);
      $display("==============================");
    end

    $finish;
  end

  initial begin
    $dumpfile("testbench.vcd");
    $dumpvars(0, testbench);
  end

endmodule

module tb_controller_hier_core (
  input logic [31:0] hart_id_i
);
endmodule

module tb_controller_hier_id (
  input logic [63:0] pc_id_i,
  input logic [31:0] instr_rdata_i
);
endmodule
