`timescale 1ns/1ps

module testbench;

  import cve2_pkg::*;

  // --------------------
  // clk / reset
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
  // Core enable
  // --------------------
  logic fetch_enable_i;
  initial fetch_enable_i = 1'b1;

  // --------------------
  // IF->ID instruction interface
  // --------------------
  logic        instr_valid_i;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_alu_i;
  logic [15:0] instr_rdata_c_i;
  logic        instr_is_compressed_i;

  initial begin
    instr_valid_i         = 1'b0;
    instr_rdata_i         = 32'h0000_0013; // NOP (ADDI x0,x0,0)
    instr_rdata_alu_i     = 32'h0000_0013;
    instr_rdata_c_i       = 16'h0001;
    instr_is_compressed_i = 1'b0;
  end

  logic instr_req_o;
  logic instr_first_cycle_id_o;
  logic instr_valid_clear_o;
  logic id_in_ready_o;

  // --------------------
  // IF/ID PC
  // --------------------
  logic [31:0] pc_id_i;
  initial pc_id_i = 32'h0000_0000;

  // --------------------
  // Branch decision feedback (EX->ID)
  // --------------------
  logic branch_decision_i;
  assign branch_decision_i = 1'b0;

  // --------------------
  // ID control outputs
  // --------------------
  logic              pc_set_o;
  pc_sel_e           pc_mux_o;
  exc_pc_sel_e       exc_pc_mux_o;
  exc_cause_e        exc_cause_o;

  // --------------------
  // Error/illegal inputs
  // --------------------
  logic illegal_c_insn_i;
  logic instr_fetch_err_i;
  logic instr_fetch_err_plus2_i;
  logic illegal_csr_insn_i;

  initial begin
    illegal_c_insn_i          = 1'b0;
    instr_fetch_err_i         = 1'b0;
    instr_fetch_err_plus2_i   = 1'b0;
    illegal_csr_insn_i        = 1'b0;
  end

  // --------------------
  // Stall inputs to ID
  // --------------------
  logic ex_valid_i;
  logic lsu_resp_valid_i;

  // --------------------
  // ALU signals ID->EX
  // --------------------
  alu_op_e     alu_operator_ex_o;
  logic [31:0] alu_operand_a_ex_o;
  logic [31:0] alu_operand_b_ex_o;

  // --------------------
  // Multicycle intermediate reg between EX and ID
  // --------------------
  logic [1:0]  imd_val_we_ex;
  logic [33:0] imd_val_d_ex[2];
  logic [33:0] imd_val_q_ex[2];

  // --------------------
  // Carry plumbing between EX and ID
  // --------------------
  logic carry_in;
  logic carry_out;

  // --------------------
  // Mult/Div signals ID->EX
  // --------------------
  logic         mult_en_ex_o, div_en_ex_o;
  logic         mult_sel_ex_o, div_sel_ex_o;
  md_op_e       multdiv_operator_ex_o;
  logic [1:0]   multdiv_signed_mode_ex_o;
  logic [31:0]  multdiv_operand_a_ex_o, multdiv_operand_b_ex_o;

  // --------------------
  // CSR signals
  // --------------------
  logic          csr_access_o;
  csr_op_e       csr_op_o;
  logic          csr_op_en_o;
  logic          csr_save_if_o, csr_save_id_o;
  logic          csr_restore_mret_id_o, csr_restore_dret_id_o;
  logic          csr_save_cause_o;
  logic [31:0]   csr_mtval_o;
  priv_lvl_e     priv_mode_i;
  logic          csr_mstatus_tw_i;
  logic [31:0]   csr_rdata_i;

  initial begin
    priv_mode_i       = PRIV_LVL_M;
    csr_mstatus_tw_i  = 1'b0;
    csr_rdata_i       = 32'h0;
  end

  // --------------------
  // LSU interface
  // --------------------
  logic        lsu_req_o;
  logic        lsu_we_o;
  logic [1:0]  lsu_type_o;
  logic        lsu_sign_ext_o;
  logic [31:0] lsu_wdata_o;

  logic        lsu_addr_incr_req_i;
  logic [31:0] lsu_addr_last_i;
  logic        lsu_load_err_i, lsu_store_err_i;

  logic        data_req_o;
  logic        data_gnt_i;
  logic        data_rvalid_i;
  logic        data_err_i;
  logic        data_pmp_err_i;
  logic [31:0] data_addr_o;
  logic        data_we_o;
  logic [3:0]  data_be_o;
  logic [31:0] data_wdata_o;
  logic [31:0] data_rdata_i;

  initial begin
    data_rvalid_i  = 1'b0;
    data_err_i     = 1'b0;
    data_pmp_err_i = 1'b0;
    data_rdata_i   = 32'h0;
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
  logic        r_a_upper_o, r_b_upper_o;
  logic [1:0]  r_a_tag_i, r_b_tag_i;

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
    // r_a_tag_i and r_b_tag_i are driven by the RF port — do NOT drive here
  end

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
  // ID writeback interface
  // --------------------
  logic [31:0] result_ex_i;
  logic [4:0]  rf_raddr_a_o, rf_raddr_b_o;
  logic [31:0] rf_rdata_a_i, rf_rdata_b_i;
  logic        rf_ren_a_o, rf_ren_b_o;

  logic [4:0]  rf_waddr_id_o;
  logic [31:0] rf_wdata_id_o;
  logic        rf_we_id_o;
  logic        rf_w_upper_id_o;

  logic en_wb_o;
  logic instr_perf_count_id_o;

  // Perf outputs
  logic perf_jump_o, perf_branch_o, perf_tbranch_o;
  logic perf_dside_wait_o, perf_wfi_wait_o, perf_div_wait_o;
  logic instr_id_done_o;

  // --------------------
  // WB outputs to RF
  // --------------------
  logic [4:0]  rf_waddr_wb_o;
  logic [31:0] rf_wdata_wb_o;
  logic        rf_we_wb_o;
  logic [1:0]  w_tag_o;
  logic [1:0]  w_tag_id;
  logic        rf_w_upper_wb_o;

  // LSU writeback path
  logic [31:0] rf_wdata_lsu_i;
  logic [1:0]  rf_wdata_lsu_tag_i;
  logic        rf_we_lsu_i;

  // --------------------
  // Instantiate ID
  // --------------------
  cve2_id_stage #(
    .RV32E      (1'b0),
    .RV32M      (RV32MFast),
    .RV32B      (RV32BNone),
    .XInterface (1'b0)
  ) dut_id (
    .clk_i,
    .rst_ni,

    .fetch_enable_i,
    .ctrl_busy_o(),
    .illegal_insn_o(),

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
    .r_a_upper_o,
    .r_b_upper_o,
    .r_a_tag_i,
    .r_b_tag_i,

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

    .result_ex_i(result_ex_i),
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
    .rf_w_upper_id_o,
    .w_tag_id_o(w_tag_id),

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
  logic [31:0] alu_adder_result_ex_o;
  logic [31:0] branch_target_o;
  logic        branch_decision_o;

  cve2_ex_block #(
    .RV32M(RV32MFast),
    .RV32B(RV32BNone)
  ) dut_ex (
    .clk_i,
    .rst_ni,

    .alu_operator_i         (alu_operator_ex_o),
    .alu_operand_a_i        (alu_operand_a_ex_o),
    .alu_operand_b_i        (alu_operand_b_ex_o),
    .alu_instr_first_cycle_i(instr_first_cycle_id_o),

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
    .lsu_rdata_tag_o  (rf_wdata_lsu_tag_i),
    .lsu_rdata_valid_o(rf_we_lsu_i),
    .lsu_req_i        (lsu_req_o),

    .adder_result_ex_i(alu_adder_result_ex_o),

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
    .rf_wdata_lsu_tag_i(rf_wdata_lsu_tag_i),

    .rf_waddr_wb_o(rf_waddr_wb_o),
    .rf_wdata_wb_o(rf_wdata_wb_o),
    .rf_we_wb_o   (rf_we_wb_o),

    .lsu_resp_valid_i(lsu_resp_valid_i),
    .lsu_resp_err_i  (1'b0),

    .w_tag_o   (w_tag_o),
    .w_tag_id_i(w_tag_id),
    .w_upper_i (rf_w_upper_id_o),
    .w_upper_o (rf_w_upper_wb_o)
  );

  // --------------------
  // Preload mux: allows testbench to write RF directly
  // --------------------
  logic        preload_mode;
  logic [4:0]  preload_waddr;
  logic [31:0] preload_wdata;
  logic        preload_we;
  logic        preload_w_upper;
  logic [1:0]  preload_w_tag;

  initial begin
    preload_mode    = 1'b0;
    preload_waddr   = 5'd0;
    preload_wdata   = 32'h0;
    preload_we      = 1'b0;
    preload_w_upper = 1'b0;
    preload_w_tag   = 2'b01;
  end

  logic [4:0]  rf_waddr_mux;
  logic [31:0] rf_wdata_mux;
  logic        rf_we_mux;
  logic        rf_w_upper_mux;
  logic [1:0]  rf_w_tag_mux;

  assign rf_waddr_mux   = preload_mode ? preload_waddr   : rf_waddr_wb_o;
  assign rf_wdata_mux   = preload_mode ? preload_wdata   : rf_wdata_wb_o;
  assign rf_we_mux      = preload_mode ? preload_we      : rf_we_wb_o;
  assign rf_w_upper_mux = preload_mode ? preload_w_upper  : rf_w_upper_wb_o;
  assign rf_w_tag_mux   = preload_mode ? preload_w_tag    : w_tag_o;

  // --------------------
  // Readback mux: allows testbench to read RF directly
  // --------------------
  logic        readback_mode;
  logic [4:0]  readback_raddr;
  logic        readback_r_upper;

  initial begin
    readback_mode    = 1'b0;
    readback_raddr   = 5'd0;
    readback_r_upper = 1'b0;
  end

  logic [4:0]  rf_raddr_a_mux;
  logic        rf_r_upper_a_mux;

  assign rf_raddr_a_mux   = readback_mode ? readback_raddr   : rf_raddr_a_o;
  assign rf_r_upper_a_mux = readback_mode ? readback_r_upper  : r_a_upper_o;

  // --------------------
  // Instantiate RF
  // --------------------
  cve2_register_file_ff #(
    .RV32E      (1'b0),
    .DataWidth  (32),
    .WordZeroVal(32'h0)
  ) dut_rf (
    .clk_i,
    .rst_ni,
    .test_en_i(1'b0),

    .raddr_a_i(rf_raddr_a_mux),
    .rdata_a_o(rf_rdata_a_i),
    .r_a_upper_i(rf_r_upper_a_mux),
    .r_a_tag_o(r_a_tag_i),

    .raddr_b_i(rf_raddr_b_o),
    .rdata_b_o(rf_rdata_b_i),
    .r_b_upper_i(r_b_upper_o),
    .r_b_tag_o(r_b_tag_i),

    .waddr_a_i(rf_waddr_mux),
    .wdata_a_i(rf_wdata_mux),
    .we_a_i   (rf_we_mux),
    .w_tag_i  (rf_w_tag_mux),

    .w_upper_i(rf_w_upper_mux)
  );

  // --------------------
  // Helper task: write one half of a register via preload mux
  // --------------------
  task automatic write_rf_half(input logic [4:0] addr,
                               input logic [31:0] data,
                               input logic        upper,
                               input logic [1:0]  tag);
    @(posedge clk_i);
    #1;
    preload_mode    = 1'b1;
    preload_waddr   = addr;
    preload_wdata   = data;
    preload_we      = 1'b1;
    preload_w_upper = upper;
    preload_w_tag   = tag;
    @(posedge clk_i);  // write happens on this edge
    #1;
    preload_we      = 1'b0;
    preload_mode    = 1'b0;
  endtask

  // --------------------
  // Write a full 64-bit register (lower then upper). Final tag applied on upper write.
  // --------------------
  task automatic write_rf_64(input logic [4:0]  addr,
                             input logic [31:0] upper_val,
                             input logic [31:0] lower_val,
                             input logic [1:0]  tag);
    write_rf_half(addr, lower_val, 1'b0, 2'b01);  // temp tag, gets overwritten
    write_rf_half(addr, upper_val, 1'b1, tag);     // final tag
  endtask

  // --------------------
  // Write a 32-bit register (lower only, tag 00)
  // --------------------
  task automatic write_rf_32(input logic [4:0]  addr,
                             input logic [31:0] data);
    write_rf_half(addr, data, 1'b0, 2'b00);
  endtask


  localparam logic [31:0] ADD_X3_X1_X2 = 32'h002081b3;
  localparam logic [31:0] SUB_X3_X1_X2 = 32'h402081b3;
  localparam logic [31:0] AND_X3_X1_X2  = 32'h0020f1b3;
  localparam logic [31:0] OR_X3_X1_X2   = 32'h0020e1b3;
  localparam logic [31:0] XOR_X3_X1_X2  = 32'h0020c1b3;
  localparam logic [31:0] ADDI_X3_X1_POS = 32'h00508193;  // ADDI x3, x1, +5
  localparam logic [31:0] ADDI_X3_X1_NEG = 32'hfff08193;  // ADDI x3, x1, -1
  localparam logic [31:0] ANDI_X3_X1_POS = 32'h0050f193;  // ANDI x3, x1, +5
  localparam logic [31:0] ANDI_X3_X1_NEG = 32'hfff0f193;  // ANDI x3, x1, -1
  localparam logic [31:0] ORI_X3_X1_POS  = 32'h0050e193;  // ORI  x3, x1, +5
  localparam logic [31:0] ORI_X3_X1_NEG  = 32'hfff0e193;  // ORI  x3, x1, -1
  localparam logic [31:0] XORI_X3_X1_POS = 32'h0050c193;  // XORI x3, x1, +5
  localparam logic [31:0] XORI_X3_X1_NEG = 32'hfff0c193;  // XORI x3, x1, -1
  localparam logic [31:0] LB_X3_0_X1     = 32'h00008183;  // LB  x3, 0(x1)
  localparam logic [31:0] LH_X3_0_X1     = 32'h00009183;  // LH  x3, 0(x1)
  localparam logic [31:0] LW_X3_0_X1     = 32'h0000a183;  // LW  x3, 0(x1)
  localparam logic [31:0] LBU_X3_0_X1    = 32'h0000c183;  // LBU x3, 0(x1)
  localparam logic [31:0] LHU_X3_0_X1    = 32'h0000d183;  // LHU x3, 0(x1)
  localparam logic [31:0] LWU_X3_0_X1    = 32'h0000e183;  // LWU x3, 0(x1)

  task automatic inject_instr(input  logic [31:0]  encoding,
                            output int unsigned  cycles_taken);
    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;

    // Wait one posedge: FIRST_CYCLE executes
    @(posedge clk_i);
    #1;

    if (dut_id.id_fsm_q == 1'b1) begin  // MULTI_CYCLE
      cycles_taken = 2;
      @(posedge clk_i);
      #1;
    end else begin
      cycles_taken = 1;
    end

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;

    repeat (3) @(posedge clk_i);
  endtask

  task automatic inject_load(input  logic [31:0]  encoding,
                             input  logic [31:0]  mem_word,
                             output int unsigned  cycles_taken);
    @(posedge clk_i);
    #1;
    instr_valid_i     = 1'b1;
    instr_rdata_i     = encoding;
    instr_rdata_alu_i = encoding;
    data_rvalid_i     = 1'b0;
    data_rdata_i      = 32'h0000_0000;

    // First cycle issues the load request. The testbench grants immediately.
    @(posedge clk_i);
    #1;
    data_rdata_i  = mem_word;
    data_rvalid_i = 1'b1;

    // Second cycle returns the memory response and lets WB write the RF.
    @(posedge clk_i);
    #1;
    cycles_taken  = 2;
    data_rvalid_i = 1'b0;

    instr_valid_i     = 1'b0;
    instr_rdata_i     = 32'h0000_0013;
    instr_rdata_alu_i = 32'h0000_0013;
    data_rdata_i      = 32'h0000_0000;

    repeat (3) @(posedge clk_i);
  endtask

  // --------------------
  // Read back lower, upper, and tag of a register via the readback mux
  // --------------------
  logic [31:0] readback_lower, readback_upper;
  logic [1:0]  readback_tag;

  task automatic check_result(input string       test_name,
                              input logic [4:0]   regnum,
                              input logic [31:0]  exp_lower,
                              input logic [1:0]   exp_tag,
                              input int unsigned  exp_cycles,
                              input int unsigned  actual_cycles,
                              // upper check: -1 = skip, else check
                              input logic [31:0]  exp_upper,
                              input logic         do_check_upper);
    logic pass;
    pass = 1'b1;

    // Read lower half via readback mux
    readback_mode    = 1'b1;
    readback_raddr   = regnum;
    readback_r_upper = 1'b0;
    #1;
    readback_lower = rf_rdata_a_i;
    readback_tag   = r_a_tag_i;    // tag is combinational from RF

    // Read upper half
    readback_r_upper = 1'b1;
    #1;
    readback_upper = rf_rdata_a_i;

    // Release read port
    readback_mode = 1'b0;

    // Check lower
    if (readback_lower !== exp_lower) begin
      $error("%s FAIL: x%0d lower = %08h, expected %08h", test_name, regnum, readback_lower, exp_lower);
      pass = 1'b0;
    end else
      $display("%s PASS: x%0d lower = %08h", test_name, regnum, readback_lower);

    // Check upper (only for 2-cycle adds where upper was written)
    if (do_check_upper) begin
      if (readback_upper !== exp_upper) begin
        $error("%s FAIL: x%0d upper = %08h, expected %08h", test_name, regnum, readback_upper, exp_upper);
        pass = 1'b0;
      end else
        $display("%s PASS: x%0d upper = %08h", test_name, regnum, readback_upper);
    end else
      $display("%s SKIP: x%0d upper check (1-cycle, upper not written)", test_name, regnum);

    // Check tag
    if (readback_tag !== exp_tag) begin
      $error("%s FAIL: x%0d tag = %02b, expected %02b", test_name, regnum, readback_tag, exp_tag);
      pass = 1'b0;
    end else
      $display("%s PASS: x%0d tag = %02b", test_name, regnum, readback_tag);

    // Check cycle count
    if (actual_cycles !== exp_cycles) begin
      $error("%s FAIL: cycles = %0d, expected %0d", test_name, actual_cycles, exp_cycles);
      pass = 1'b0;
    end else
      $display("%s PASS: cycles = %0d", test_name, actual_cycles);

    if (pass)
      $display("%s: ALL CHECKS PASSED", test_name);
    else
      $display("%s: SOME CHECKS FAILED", test_name);
  endtask

  // --------------------
  // Main test stimulus
  // --------------------
  int unsigned cycles;

  initial begin
    // Wait for reset release
    @(posedge rst_ni);
    #1;

    // Wait for controller to reach DECODE state
    repeat (15) @(posedge clk_i);

    // ==========================================================
    // Test 1: tag 00 + tag 00, no carry
    // Pure 32-bit add. Always 1 cycle. Carry ignored.
    // x1=5 (tag 00), x2=3 (tag 00) → x3=8 (tag 00)
    // ==========================================================
    $display("\n---- Test 1: tag00+tag00, no carry ----");
    write_rf_32(5'd1, 32'h0000_0005);
    write_rf_32(5'd2, 32'h0000_0003);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T01", 5'd3, 32'h0000_0008, 2'b00, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 2: tag 00 + tag 00, with carry (overflow ignored)
    // x1=FFFFFFFF (tag 00), x2=1 (tag 00) → x3=0 (tag 00), 1 cycle
    // ==========================================================
    $display("\n---- Test 2: tag00+tag00, carry ignored ----");
    write_rf_32(5'd1, 32'hFFFF_FFFF);
    write_rf_32(5'd2, 32'h0000_0001);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T02", 5'd3, 32'h0000_0000, 2'b00, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 3: tag 10 + tag 10, no carry → 1 cycle, tag 10
    // x1={upper=0, lower=5} tag 10
    // x2={upper=0, lower=3} tag 10
    // upper = 0+0+0 = 0, inferable → tag 10
    // ==========================================================
    $display("\n---- Test 3: tag10+tag10, no carry ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0005, 2'b10);
    write_rf_64(5'd2, 32'h0, 32'h0000_0003, 2'b10);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T03", 5'd3, 32'h0000_0008, 2'b10, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 4: tag 10 + tag 10, with carry → 2 cycles, tag from WB
    // x1={upper=0, lower=FFFFFFFF} tag 10
    // x2={upper=0, lower=1} tag 10
    // lower=0, carry=1, upper=0+0+1=1, not inferable → 2 cycles, tag 01
    // ==========================================================
    $display("\n---- Test 4: tag10+tag10, carry → 2 cycles ----");
    write_rf_64(5'd1, 32'h0, 32'hFFFF_FFFF, 2'b10);
    write_rf_64(5'd2, 32'h0, 32'h0000_0001, 2'b10);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T04", 5'd3, 32'h0000_0000, 2'b01, 2, cycles,
                 32'h0000_0001, 1'b1);

    // ==========================================================
    // Test 5: tag 10 + tag 11, no carry → 1 cycle, tag 11
    // x1={upper=0, lower=5} tag 10
    // x2={upper=FF, lower=3} tag 11
    // upper = 0+FF+0 = FF, inferable → tag 11
    // ==========================================================
    $display("\n---- Test 5: tag10+tag11, no carry ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0005, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0003, 2'b11);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T05", 5'd3, 32'h0000_0008, 2'b11, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 6: tag 10 + tag 11, with carry → 1 cycle, tag 10
    // x1={upper=0, lower=FFFFFFFF} tag 10
    // x2={upper=FF, lower=1} tag 11
    // lower=0, carry=1, upper = 0+FF+1 = 00, inferable → tag 10
    // ==========================================================
    $display("\n---- Test 6: tag10+tag11, carry ----");
    write_rf_64(5'd1, 32'h0, 32'hFFFF_FFFF, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0001, 2'b11);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T06", 5'd3, 32'h0000_0000, 2'b10, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 7: tag 11 + tag 10, no carry → 1 cycle, tag 11 (symmetric of T05)
    // x1={upper=FF, lower=5} tag 11
    // x2={upper=0, lower=3} tag 10
    // upper = FF+0+0 = FF, inferable → tag 11
    // ==========================================================
    $display("\n---- Test 7: tag11+tag10, no carry ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0005, 2'b11);
    write_rf_64(5'd2, 32'h0, 32'h0000_0003, 2'b10);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T07", 5'd3, 32'h0000_0008, 2'b11, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 8: tag 11 + tag 10, with carry → 1 cycle, tag 10 (symmetric of T06)
    // x1={upper=FF, lower=FFFFFFFF} tag 11
    // x2={upper=0, lower=1} tag 10
    // lower=0, carry=1, upper = FF+0+1 = 00, inferable → tag 10
    // ==========================================================
    $display("\n---- Test 8: tag11+tag10, carry ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 2'b11);
    write_rf_64(5'd2, 32'h0, 32'h0000_0001, 2'b10);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T08", 5'd3, 32'h0000_0000, 2'b10, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 9: tag 11 + tag 11, no carry → 2 cycles
    // x1={upper=FF, lower=5} tag 11
    // x2={upper=FF, lower=3} tag 11
    // lower=8, carry=0, upper=FF+FF+0=FE, not inferable → 2 cycles
    // ==========================================================
    $display("\n---- Test 9: tag11+tag11, no carry → 2 cycles ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0005, 2'b11);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0003, 2'b11);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T09", 5'd3, 32'h0000_0008, 2'b01, 2, cycles,
                 32'hFFFF_FFFE, 1'b1);

    // ==========================================================
    // Test 10: tag 11 + tag 11, with carry → 1 cycle, tag 11
    // x1={upper=FF, lower=FFFFFFFF} tag 11
    // x2={upper=FF, lower=1} tag 11
    // lower=0, carry=1, upper=FF+FF+1=FF, inferable → tag 11
    // ==========================================================
    $display("\n---- Test 10: tag11+tag11, carry ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 2'b11);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0001, 2'b11);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T10", 5'd3, 32'h0000_0000, 2'b11, 1, cycles,
                 32'h0, 1'b0);

    // ==========================================================
    // Test 11: tag 01 + tag 01, no carry → always 2 cycles
    // x1={upper=3, lower=5} tag 01
    // x2={upper=1, lower=2} tag 01
    // Must read uppers from RF → 2 cycles
    // ==========================================================
    $display("\n---- Test 11: tag01+tag01, no carry ----");
    write_rf_64(5'd1, 32'h0000_0003, 32'h0000_0005, 2'b01);
    write_rf_64(5'd2, 32'h0000_0001, 32'h0000_0002, 2'b01);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T11", 5'd3, 32'h0000_0007, 2'b01, 2, cycles,
                 32'h0000_0004, 1'b1);

    // ==========================================================
    // Test 12: tag 01 + tag 01, with carry → 2 cycles
    // x1={upper=1, lower=FFFFFFFF} tag 01
    // x2={upper=0, lower=1} tag 01
    // lower=0, carry=1, upper=1+0+1=2
    // ==========================================================
    $display("\n---- Test 12: tag01+tag01, carry ----");
    write_rf_64(5'd1, 32'h0000_0001, 32'hFFFF_FFFF, 2'b01);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0001, 2'b01);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T12", 5'd3, 32'h0000_0000, 2'b01, 2, cycles,
                 32'h0000_0002, 1'b1);

    // ==========================================================
    // Test 13: tag 01 + tag 10 → 2 cycles (one explicit forces 2-cycle)
    // x1={upper=ABCD0000, lower=5} tag 01
    // x2={upper=0, lower=3} tag 10
    // ==========================================================
    $display("\n---- Test 13: tag01+tag10 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_0000, 32'h0000_0005, 2'b01);
    write_rf_64(5'd2, 32'h0, 32'h0000_0003, 2'b10);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T13", 5'd3, 32'h0000_0008, 2'b01, 2, cycles,
                 32'hABCD_0000, 1'b1);

    // ==========================================================
    // Test 14: tag 01 + tag 01, upper result is all zeros → tag 10
    // x1={upper=FFFFFFFF, lower=5} tag 01
    // x2={upper=00000001, lower=3} tag 01
    // upper = FFFFFFFF+1+0 = 00000000 → WB sets tag 10
    // ==========================================================
    $display("\n---- Test 14: tag01+tag01, upper=0 → tag 10 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0005, 2'b01);
    write_rf_64(5'd2, 32'h0000_0001, 32'h0000_0003, 2'b01);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T14", 5'd3, 32'h0000_0008, 2'b10, 2, cycles,
                 32'h0000_0000, 1'b1);

    // ==========================================================
    // Test 15: tag 01 + tag 01, upper result is all ones → tag 11
    // x1={upper=FFFFFFFE, lower=5} tag 01
    // x2={upper=00000001, lower=3} tag 01
    // upper = FFFFFFFE+1+0 = FFFFFFFF → WB sets tag 11
    // ==========================================================
    $display("\n---- Test 15: tag01+tag01, upper=FF → tag 11 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFE, 32'h0000_0005, 2'b01);
    write_rf_64(5'd2, 32'h0000_0001, 32'h0000_0003, 2'b01);
    inject_instr(ADD_X3_X1_X2, cycles);
    check_result("T15", 5'd3, 32'h0000_0008, 2'b11, 2, cycles,
                 32'hFFFF_FFFF, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d add tests complete", 15);
    $display("==============================");


    // ==========================================================
    // SUB tests
    // ==========================================================
    $display("\n========== SUB tests ==========");

    // SUB-1: tag00-tag00, no borrow. Pure 32-bit subtract, tag 00.
    $display("\n---- SUB-1: tag00-tag00, no borrow ----");
    write_rf_32(5'd1, 32'h0000_0005);
    write_rf_32(5'd2, 32'h0000_0003);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S01", 5'd3, 32'h0000_0002, 2'b00, 1, cycles, 32'h0, 1'b0);

    // SUB-2: tag00-tag00, borrow ignored for word-sized result.
    $display("\n---- SUB-2: tag00-tag00, borrow ignored ----");
    write_rf_32(5'd1, 32'h0000_0003);
    write_rf_32(5'd2, 32'h0000_0005);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S02", 5'd3, 32'hFFFF_FFFE, 2'b00, 1, cycles, 32'h0, 1'b0);

    // SUB-3: tag10-tag10, no borrow -> inferred zero upper, 1 cycle.
    $display("\n---- SUB-3: tag10-tag10, no borrow ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0005, 2'b10);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0003, 2'b10);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S03", 5'd3, 32'h0000_0002, 2'b10, 1, cycles, 32'h0, 1'b0);

    // SUB-4: tag10-tag10, borrow -> inferred all-ones upper, 1 cycle.
    $display("\n---- SUB-4: tag10-tag10, borrow ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0003, 2'b10);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0005, 2'b10);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S04", 5'd3, 32'hFFFF_FFFE, 2'b11, 1, cycles, 32'h0, 1'b0);

    // SUB-5: tag10-tag11, no borrow -> upper becomes 1, so 2 cycles.
    $display("\n---- SUB-5: tag10-tag11, no borrow -> 2 cycles ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0005, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0003, 2'b11);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S05", 5'd3, 32'h0000_0002, 2'b01, 2, cycles, 32'h0000_0001, 1'b1);

    // SUB-6: tag10-tag11, borrow -> upper remains zero, 1 cycle.
    $display("\n---- SUB-6: tag10-tag11, borrow ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0003, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0005, 2'b11);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S06", 5'd3, 32'hFFFF_FFFE, 2'b10, 1, cycles, 32'h0, 1'b0);

    // SUB-7: tag11-tag10, no borrow -> inferred all-ones upper, 1 cycle.
    $display("\n---- SUB-7: tag11-tag10, no borrow ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0005, 2'b11);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0003, 2'b10);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S07", 5'd3, 32'h0000_0002, 2'b11, 1, cycles, 32'h0, 1'b0);

    // SUB-8: tag11-tag10, borrow -> upper becomes FFFFFFFE, so 2 cycles.
    $display("\n---- SUB-8: tag11-tag10, borrow -> 2 cycles ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0003, 2'b11);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0005, 2'b10);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S08", 5'd3, 32'hFFFF_FFFE, 2'b01, 2, cycles, 32'hFFFF_FFFE, 1'b1);

    // SUB-9: explicit upper source -> 2 cycles, WB derives tag from actual upper zero.
    $display("\n---- SUB-9: tag01-tag01, upper=0 -> tag 10 ----");
    write_rf_64(5'd1, 32'h0000_0001, 32'h0000_0005, 2'b01);
    write_rf_64(5'd2, 32'h0000_0001, 32'h0000_0003, 2'b01);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S09", 5'd3, 32'h0000_0002, 2'b10, 2, cycles, 32'h0000_0000, 1'b1);

    // SUB-10: explicit upper source with borrow -> WB derives tag from actual upper all-ones.
    $display("\n---- SUB-10: tag01-tag01, borrow upper=FF -> tag 11 ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0003, 2'b01);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0005, 2'b01);
    inject_instr(SUB_X3_X1_X2, cycles);
    check_result("S10", 5'd3, 32'hFFFF_FFFE, 2'b11, 2, cycles, 32'hFFFF_FFFF, 1'b1);

    $display("\n==============================");
    $display("All %0d SUB tests complete", 10);
    $display("==============================");




    // ==========================================================
    // AND tests — bitwise, halves independent
    // ==========================================================
    $display("\n========== AND tests ==========");

    // AND-1: tag00+tag00 → tag 00, 1 cycle (pure RV32)
    $display("\n---- AND-1: tag00+tag00 ----");
    write_rf_32(5'd1, 32'hF0F0_F0F0);
    write_rf_32(5'd2, 32'h0FF0_0FF0);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A01", 5'd3, 32'h00F0_00F0, 2'b00, 1, cycles, 32'h0, 1'b0);

    // AND-2: tag10+tag10 → tag 10 (0 AND 0 = 0)
    $display("\n---- AND-2: tag10+tag10 ----");
    write_rf_64(5'd1, 32'h0, 32'hF0F0_F0F0, 2'b10);
    write_rf_64(5'd2, 32'h0, 32'h0FF0_0FF0, 2'b10);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A02", 5'd3, 32'h00F0_00F0, 2'b10, 1, cycles, 32'h0, 1'b0);

    // AND-3: tag10+tag11 → tag 10 (0 AND FF = 0)
    $display("\n---- AND-3: tag10+tag11 ----");
    write_rf_64(5'd1, 32'h0,         32'hF0F0_F0F0, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0FF0_0FF0, 2'b11);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A03", 5'd3, 32'h00F0_00F0, 2'b10, 1, cycles, 32'h0, 1'b0);

    // AND-4: tag11+tag11 → tag 11 (FF AND FF = FF)
    $display("\n---- AND-4: tag11+tag11 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hF0F0_F0F0, 2'b11);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0FF0_0FF0, 2'b11);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A04", 5'd3, 32'h00F0_00F0, 2'b11, 1, cycles, 32'h0, 1'b0);

    // AND-5: tag01+tag10 → tag 10, 1 cycle (explicit AND 0 = 0; upper read skipped)
    $display("\n---- AND-5: tag01+tag10 ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_F0F0, 2'b01);
    write_rf_64(5'd2, 32'h0,         32'h0FF0_0FF0, 2'b10);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A05", 5'd3, 32'h00F0_00F0, 2'b10, 1, cycles, 32'h0, 1'b0);

    // AND-6: tag01+tag11 → tag 01, 2 cycles (FF AND explicit = explicit)
    $display("\n---- AND-6: tag01+tag11 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_F0F0, 2'b01);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0FF0_0FF0, 2'b11);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A06", 5'd3, 32'h00F0_00F0, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // AND-7: tag01+tag01 → tag 01, 2 cycles
    $display("\n---- AND-7: tag01+tag01 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_F0F0, 2'b01);
    write_rf_64(5'd2, 32'hFF00_FF00, 32'h0FF0_0FF0, 2'b01);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A07", 5'd3, 32'h00F0_00F0, 2'b01, 2, cycles, 32'hAB00_1200, 1'b1);

    // AND-8: tag01+tag01 producing all-ones upper → tag 11
    $display("\n---- AND-8: tag01+tag01, upper=FF → tag 11 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hF0F0_F0F0, 2'b01);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0FF0_0FF0, 2'b01);
    inject_instr(AND_X3_X1_X2, cycles);
    check_result("A08", 5'd3, 32'h00F0_00F0, 2'b11, 2, cycles, 32'hFFFF_FFFF, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d AND tests complete", 8);
    $display("==============================");



    // ==========================================================
    // OR tests — bitwise, halves independent
    // ==========================================================
    $display("\n========== OR tests ==========");

    // OR-1: tag00+tag00 → tag 00, 1 cycle (pure RV32)
    $display("\n---- OR-1: tag00+tag00 ----");
    write_rf_32(5'd1, 32'hF0F0_0000);
    write_rf_32(5'd2, 32'h0000_0F0F);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O01", 5'd3, 32'hF0F0_0F0F, 2'b00, 1, cycles, 32'h0, 1'b0);

    // OR-2: tag10+tag10 → tag 10 (0 OR 0 = 0)
    $display("\n---- OR-2: tag10+tag10 ----");
    write_rf_64(5'd1, 32'h0, 32'hF0F0_0000, 2'b10);
    write_rf_64(5'd2, 32'h0, 32'h0000_0F0F, 2'b10);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O02", 5'd3, 32'hF0F0_0F0F, 2'b10, 1, cycles, 32'h0, 1'b0);

    // OR-3: tag11+tag10 → tag 11 (FF OR 0 = FF)
    $display("\n---- OR-3: tag11+tag10 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hF0F0_0000, 2'b11);
    write_rf_64(5'd2, 32'h0,         32'h0000_0F0F, 2'b10);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O03", 5'd3, 32'hF0F0_0F0F, 2'b11, 1, cycles, 32'h0, 1'b0);

    // OR-4: tag11+tag11 → tag 11 (FF OR FF = FF)
    $display("\n---- OR-4: tag11+tag11 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hF0F0_0000, 2'b11);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0F0F, 2'b11);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O04", 5'd3, 32'hF0F0_0F0F, 2'b11, 1, cycles, 32'h0, 1'b0);

    // OR-5: tag01+tag11 → tag 11, 1 cycle (FF forces upper, no explicit read)
    $display("\n---- OR-5: tag01+tag11 ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0F0F, 2'b11);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O05", 5'd3, 32'hF0F0_0F0F, 2'b11, 1, cycles, 32'h0, 1'b0);

    // OR-6: tag01+tag10 → tag 01, 2 cycles (explicit OR 0 = explicit)
    $display("\n---- OR-6: tag01+tag10 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'h0,         32'h0000_0F0F, 2'b10);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O06", 5'd3, 32'hF0F0_0F0F, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // OR-7: tag01+tag01 → tag 01, 2 cycles (general)
    $display("\n---- OR-7: tag01+tag01 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'h1234_5678, 32'h0000_0F0F, 2'b01);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O07", 5'd3, 32'hF0F0_0F0F, 2'b01, 2, cycles, 32'hBBFD_567C, 1'b1);

    // OR-8: tag01+tag01 producing all-zero upper → tag 10
    $display("\n---- OR-8: tag01+tag01, upper=0 → tag 10 ----");
    write_rf_64(5'd1, 32'h0000_0000, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'h0000_0000, 32'h0000_0F0F, 2'b01);
    inject_instr(OR_X3_X1_X2, cycles);
    check_result("O08", 5'd3, 32'hF0F0_0F0F, 2'b10, 2, cycles, 32'h0000_0000, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d OR tests complete", 8);
    $display("==============================");



    // ==========================================================
    // XOR tests — bitwise, halves independent; explicit always 2-cycle
    // ==========================================================
    $display("\n========== XOR tests ==========");

    // XOR-1: tag00+tag00 → tag 00, 1 cycle (pure RV32)
    $display("\n---- XOR-1: tag00+tag00 ----");
    write_rf_32(5'd1, 32'hF0F0_0000);
    write_rf_32(5'd2, 32'h0000_0F0F);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X01", 5'd3, 32'hF0F0_0F0F, 2'b00, 1, cycles, 32'h0, 1'b0);

    // XOR-2: tag10+tag10 → tag 10 (0 XOR 0 = 0)
    $display("\n---- XOR-2: tag10+tag10 ----");
    write_rf_64(5'd1, 32'h0, 32'hF0F0_0000, 2'b10);
    write_rf_64(5'd2, 32'h0, 32'h0000_0F0F, 2'b10);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X02", 5'd3, 32'hF0F0_0F0F, 2'b10, 1, cycles, 32'h0, 1'b0);

    // XOR-3: tag11+tag11 → tag 10 (FF XOR FF = 0)
    $display("\n---- XOR-3: tag11+tag11 → tag 10 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'hF0F0_0000, 2'b11);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0F0F, 2'b11);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X03", 5'd3, 32'hF0F0_0F0F, 2'b10, 1, cycles, 32'h0, 1'b0);

    // XOR-4: tag10+tag11 → tag 11 (0 XOR FF = FF)
    $display("\n---- XOR-4: tag10+tag11 ----");
    write_rf_64(5'd1, 32'h0,         32'hF0F0_0000, 2'b10);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0F0F, 2'b11);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X04", 5'd3, 32'hF0F0_0F0F, 2'b11, 1, cycles, 32'h0, 1'b0);

    // XOR-5: tag01+tag10 → tag 01, 2 cycles (any explicit forces 2-cycle XOR)
    $display("\n---- XOR-5: tag01+tag10 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'h0,         32'h0000_0F0F, 2'b10);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X05", 5'd3, 32'hF0F0_0F0F, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // XOR-6: tag01+tag11 → tag 01, 2 cycles
    $display("\n---- XOR-6: tag01+tag11 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'hFFFF_FFFF, 32'h0000_0F0F, 2'b11);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X06", 5'd3, 32'hF0F0_0F0F, 2'b01, 2, cycles, 32'h5432_EDCB, 1'b1);

    // XOR-7: tag01+tag01 → tag 01, 2 cycles (general)
    $display("\n---- XOR-7: tag01+tag01 → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'hF0F0_0000, 2'b01);
    write_rf_64(5'd2, 32'h1234_5678, 32'h0000_0F0F, 2'b01);
    inject_instr(XOR_X3_X1_X2, cycles);
    check_result("X07", 5'd3, 32'hF0F0_0F0F, 2'b01, 2, cycles, 32'hB9F9_444C, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d XOR tests complete", 7);
    $display("==============================");




    // ==========================================================
    // ADDI tests — I-type adder, immediate's tag derived from imm[31]
    // ==========================================================
    $display("\n========== ADDI tests ==========");

    // ADDI-1: rs1 tag10 + pos_imm (virtual tag 10), no carry → tag 10
    $display("\n---- ADDI-1: tag10+pos_imm ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0010, 2'b10);
    inject_instr(ADDI_X3_X1_POS, cycles);    // imm = +5
    check_result("AI1", 5'd3, 32'h0000_0015, 2'b10, 1, cycles, 32'h0, 1'b0);

    // ADDI-2: rs1 tag11 + pos_imm (10), no carry → tag 11 (FF+0+0=FF)
    $display("\n---- ADDI-2: tag11+pos_imm ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0010, 2'b11);
    inject_instr(ADDI_X3_X1_POS, cycles);    // imm = +5
    check_result("AI2", 5'd3, 32'h0000_0015, 2'b11, 1, cycles, 32'h0, 1'b0);

    // ADDI-3: rs1 tag10 + neg_imm (11), carry → tag 10 (0+FF+1=00)
    $display("\n---- ADDI-3: tag10+neg_imm, carry ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0010, 2'b10);
    inject_instr(ADDI_X3_X1_NEG, cycles);    // imm = -1
    check_result("AI3", 5'd3, 32'h0000_000F, 2'b10, 1, cycles, 32'h0, 1'b0);

    // ADDI-4: rs1 tag10 + neg_imm (11), no carry → tag 11 (0+FF+0=FF)
    $display("\n---- ADDI-4: tag10+neg_imm, no carry ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0000, 2'b10);
    inject_instr(ADDI_X3_X1_NEG, cycles);    // imm = -1
    check_result("AI4", 5'd3, 32'hFFFF_FFFF, 2'b11, 1, cycles, 32'h0, 1'b0);

    // ADDI-5: rs1 tag11 + neg_imm (11), no carry → 2 cycles (FF+FF+0=FE, not inferable)
    $display("\n---- ADDI-5: tag11+neg_imm, no carry → 2 cycles ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0000, 2'b11);
    inject_instr(ADDI_X3_X1_NEG, cycles);    // imm = -1
    check_result("AI5", 5'd3, 32'hFFFF_FFFF, 2'b01, 2, cycles, 32'hFFFF_FFFE, 1'b1);

    // ADDI-6: rs1 tag01 + pos_imm (10) → 2 cycles (a explicit forces upper read)
    $display("\n---- ADDI-6: tag01+pos_imm → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_0000, 32'h0000_0010, 2'b01);
    inject_instr(ADDI_X3_X1_POS, cycles);    // imm = +5
    check_result("AI6", 5'd3, 32'h0000_0015, 2'b01, 2, cycles, 32'hABCD_0000, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d ADDI tests complete", 6);
    $display("==============================");



    // ==========================================================
    // ANDI tests — I-type bitwise AND
    // ==========================================================
    $display("\n========== ANDI tests ==========");

    // ANDI-1: rs1 tag10 + pos_imm (10) → tag 10
    $display("\n---- ANDI-1: tag10+pos_imm ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_001F, 2'b10);
    inject_instr(ANDI_X3_X1_POS, cycles);    // imm = +5
    check_result("NI1", 5'd3, 32'h0000_0005, 2'b10, 1, cycles, 32'h0, 1'b0);

    // ANDI-2: rs1 tag11 + neg_imm (11) → tag 11 (FF AND FF = FF)
    $display("\n---- ANDI-2: tag11+neg_imm ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_001F, 2'b11);
    inject_instr(ANDI_X3_X1_NEG, cycles);    // imm = -1
    check_result("NI2", 5'd3, 32'h0000_001F, 2'b11, 1, cycles, 32'h0, 1'b0);

    // ANDI-3: rs1 tag01 + pos_imm (10) → tag 10, 1 cycle (zero side forces result)
    $display("\n---- ANDI-3: tag01+pos_imm → 1 cycle ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'h0000_001F, 2'b01);
    inject_instr(ANDI_X3_X1_POS, cycles);    // imm = +5
    check_result("NI3", 5'd3, 32'h0000_0005, 2'b10, 1, cycles, 32'h0, 1'b0);

    // ANDI-4: rs1 tag01 + neg_imm (11) → tag 01, 2 cycles (need explicit upper)
    $display("\n---- ANDI-4: tag01+neg_imm → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'h0000_001F, 2'b01);
    inject_instr(ANDI_X3_X1_NEG, cycles);    // imm = -1
    check_result("NI4", 5'd3, 32'h0000_001F, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d ANDI tests complete", 4);
    $display("==============================");



    // ==========================================================
    // ORI tests — I-type bitwise OR
    // ==========================================================
    $display("\n========== ORI tests ==========");

    // ORI-1: rs1 tag10 + pos_imm (10) → tag 10 (0 OR 0 = 0)
    $display("\n---- ORI-1: tag10+pos_imm ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0012, 2'b10);
    inject_instr(ORI_X3_X1_POS, cycles);     // imm = +5
    check_result("RI1", 5'd3, 32'h0000_0017, 2'b10, 1, cycles, 32'h0, 1'b0);

    // ORI-2: rs1 tag10 + neg_imm (11) → tag 11 (0 OR FF = FF)
    $display("\n---- ORI-2: tag10+neg_imm ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0012, 2'b10);
    inject_instr(ORI_X3_X1_NEG, cycles);     // imm = -1
    check_result("RI2", 5'd3, 32'hFFFF_FFFF, 2'b11, 1, cycles, 32'h0, 1'b0);

    // ORI-3: rs1 tag01 + neg_imm (11) → tag 11, 1 cycle (FF forces result)
    $display("\n---- ORI-3: tag01+neg_imm → 1 cycle ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'h0000_0012, 2'b01);
    inject_instr(ORI_X3_X1_NEG, cycles);     // imm = -1
    check_result("RI3", 5'd3, 32'hFFFF_FFFF, 2'b11, 1, cycles, 32'h0, 1'b0);

    // ORI-4: rs1 tag01 + pos_imm (10) → tag 01, 2 cycles
    $display("\n---- ORI-4: tag01+pos_imm → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'h0000_0012, 2'b01);
    inject_instr(ORI_X3_X1_POS, cycles);     // imm = +5
    check_result("RI4", 5'd3, 32'h0000_0017, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d ORI tests complete", 4);
    $display("==============================");




    // ==========================================================
    // XORI tests — I-type bitwise XOR
    // ==========================================================
    $display("\n========== XORI tests ==========");

    // XORI-1: rs1 tag10 + pos_imm (10) → tag 10 (0 XOR 0 = 0)
    $display("\n---- XORI-1: tag10+pos_imm ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0012, 2'b10);
    inject_instr(XORI_X3_X1_POS, cycles);    // imm = +5
    check_result("XI1", 5'd3, 32'h0000_0017, 2'b10, 1, cycles, 32'h0, 1'b0);

    // XORI-2: rs1 tag11 + neg_imm (11) → tag 10 (FF XOR FF = 0)
    $display("\n---- XORI-2: tag11+neg_imm → tag 10 ----");
    write_rf_64(5'd1, 32'hFFFF_FFFF, 32'h0000_0012, 2'b11);
    inject_instr(XORI_X3_X1_NEG, cycles);    // imm = -1
    check_result("XI2", 5'd3, 32'hFFFF_FFED, 2'b10, 1, cycles, 32'h0, 1'b0);

    // XORI-3: rs1 tag10 + neg_imm (11) → tag 11 (0 XOR FF = FF)
    $display("\n---- XORI-3: tag10+neg_imm → tag 11 ----");
    write_rf_64(5'd1, 32'h0, 32'h0000_0012, 2'b10);
    inject_instr(XORI_X3_X1_NEG, cycles);    // imm = -1
    check_result("XI3", 5'd3, 32'hFFFF_FFED, 2'b11, 1, cycles, 32'h0, 1'b0);

    // XORI-4: rs1 tag01 + pos_imm (10) → tag 01, 2 cycles (any explicit forces 2-cycle)
    $display("\n---- XORI-4: tag01+pos_imm → 2 cycles ----");
    write_rf_64(5'd1, 32'hABCD_1234, 32'h0000_0012, 2'b01);
    inject_instr(XORI_X3_X1_POS, cycles);    // imm = +5
    check_result("XI4", 5'd3, 32'h0000_0017, 2'b01, 2, cycles, 32'hABCD_1234, 1'b1);

    // ==========================================================
    // Done
    // ==========================================================
    $display("\n==============================");
    $display("All %0d XORI tests complete", 4);
    $display("==============================");


    // ==========================================================
    // LOAD tag tests
    // ==========================================================
    $display("\n========== LOAD tag tests ==========");
    write_rf_64(5'd1, 32'h0000_0000, 32'h0000_0000, 2'b10);

    // Signed byte with positive sign bit -> zero-inferred upper.
    $display("\n---- LOAD-1: LB positive ----");
    inject_load(LB_X3_0_X1, 32'h0000_007f, cycles);
    check_result("L01", 5'd3, 32'h0000_007f, 2'b10, 2, cycles, 32'h0, 1'b0);

    // Signed byte with negative sign bit -> ones-inferred upper.
    $display("\n---- LOAD-2: LB negative ----");
    inject_load(LB_X3_0_X1, 32'h0000_0080, cycles);
    check_result("L02", 5'd3, 32'hffff_ff80, 2'b11, 2, cycles, 32'h0, 1'b0);

    // Unsigned byte always zero-extends, even when bit 7 is set.
    $display("\n---- LOAD-3: LBU high bit set ----");
    inject_load(LBU_X3_0_X1, 32'h0000_0080, cycles);
    check_result("L03", 5'd3, 32'h0000_0080, 2'b10, 2, cycles, 32'h0, 1'b0);

    // Signed halfword with positive sign bit -> zero-inferred upper.
    $display("\n---- LOAD-4: LH positive ----");
    inject_load(LH_X3_0_X1, 32'h0000_7fff, cycles);
    check_result("L04", 5'd3, 32'h0000_7fff, 2'b10, 2, cycles, 32'h0, 1'b0);

    // Signed halfword with negative sign bit -> ones-inferred upper.
    $display("\n---- LOAD-5: LH negative ----");
    inject_load(LH_X3_0_X1, 32'h0000_8001, cycles);
    check_result("L05", 5'd3, 32'hffff_8001, 2'b11, 2, cycles, 32'h0, 1'b0);

    // Unsigned halfword always zero-extends, even when bit 15 is set.
    $display("\n---- LOAD-6: LHU high bit set ----");
    inject_load(LHU_X3_0_X1, 32'h0000_8001, cycles);
    check_result("L06", 5'd3, 32'h0000_8001, 2'b10, 2, cycles, 32'h0, 1'b0);

    // Signed word with positive sign bit -> zero-inferred upper.
    $display("\n---- LOAD-7: LW positive ----");
    inject_load(LW_X3_0_X1, 32'h7fff_ffff, cycles);
    check_result("L07", 5'd3, 32'h7fff_ffff, 2'b10, 2, cycles, 32'h0, 1'b0);

    // Signed word with negative sign bit -> ones-inferred upper.
    $display("\n---- LOAD-8: LW negative ----");
    inject_load(LW_X3_0_X1, 32'h8000_0000, cycles);
    check_result("L08", 5'd3, 32'h8000_0000, 2'b11, 2, cycles, 32'h0, 1'b0);

    // LWU zero-extends, so tag stays zero-inferred even when bit 31 is set.
    $display("\n---- LOAD-9: LWU high bit set ----");
    inject_load(LWU_X3_0_X1, 32'h8000_0000, cycles);
    check_result("L09", 5'd3, 32'h8000_0000, 2'b10, 2, cycles, 32'h0, 1'b0);

    $display("\n==============================");
    $display("All %0d LOAD tag tests complete", 9);
    $display("==============================");


    repeat (10) @(posedge clk_i);
    $stop;
  end

  // --------------------
  // Optional: waveform dump for debugging
  // --------------------
  initial begin
    $dumpfile("testbench.vcd");
    $dumpvars(0, testbench);
  end

endmodule
