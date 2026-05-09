`timescale 1ns/1ps

module testbench;
  import cve2_pkg::*;

  localparam logic [31:0] NOP = 32'h0000_0013;

  logic clk_i;
  logic rst_ni;

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  logic fetch_enable_i;
  assign fetch_enable_i = 1'b1;

  logic        instr_valid_i;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_alu_i;
  logic [15:0] instr_rdata_c_i;
  logic        instr_is_compressed_i;

  logic [31:0] pc_id_i;
  logic [31:0] pc_id_upper_i;

  logic        branch_decision;
  logic        alu_is_equal_result;
  logic        pc_set_o;
  pc_sel_e     pc_mux_o;
  exc_pc_sel_e exc_pc_mux_o;
  exc_cause_e  exc_cause_o;
  logic        illegal_insn_o;

  logic instr_req_o;
  logic instr_first_cycle_id_o;
  logic instr_valid_clear_o;
  logic id_in_ready_o;
  logic instr_id_done_o;

  alu_op_e     alu_operator_ex;
  logic [63:0] alu_operand_a_ex;
  logic [63:0] alu_operand_b_ex;
  logic        alu_word_op_ex;

  logic [1:0]  imd_val_we_ex;
  logic [33:0] imd_val_d_ex[2];
  logic [33:0] imd_val_q_ex[2];
  logic        carry_in;
  logic        carry_out;

  logic        mult_en_ex;
  logic        div_en_ex;
  logic        mult_sel_ex;
  logic        div_sel_ex;
  md_op_e      multdiv_operator_ex;
  logic [1:0]  multdiv_signed_mode_ex;
  logic [31:0] multdiv_operand_a_ex;
  logic [31:0] multdiv_operand_b_ex;

  logic        csr_access_o;
  csr_op_e     csr_op_o;
  logic        csr_op_en_o;
  logic        csr_save_if_o;
  logic        csr_save_id_o;
  logic        csr_restore_mret_id_o;
  logic        csr_restore_dret_id_o;
  logic        csr_save_cause_o;
  logic [63:0] csr_mtval_o;
  logic [31:0] csr_wdata_o;
  logic        csr_wdata_upper_o;
  logic        csr_wdata_capture_o;
  logic        csr_rdata_upper_o;
  logic        csr_rdata_capture_o;

  logic        lsu_req_o;
  logic        lsu_we_o;
  logic [1:0]  lsu_type_o;
  logic        lsu_sign_ext_o;
  logic [63:0] lsu_wdata_o;
  logic        lsu_addr_incr_req;
  logic [63:0] lsu_addr_last;
  logic [63:0] lsu_addr_ex;
  logic [63:0] pc_target_ex;
  logic        lsu_resp_valid;
  logic        lsu_load_err;
  logic        lsu_store_err;
  logic        lsu_busy;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic        data_err;
  logic        data_pmp_err;
  logic [63:0] data_addr;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;

  logic [63:0] result_ex;
  logic [63:0] alu_adder_result_ex;
  logic [63:0] branch_target_unused;
  logic        ex_valid;

  logic [4:0]  rf_raddr_a;
  logic [63:0] rf_rdata_a;
  logic [4:0]  rf_raddr_b;
  logic [63:0] rf_rdata_b;
  logic        rf_ren_a;
  logic        rf_ren_b;
  logic [4:0]  rf_waddr_id;
  logic [63:0] rf_wdata_id;
  logic        rf_we_id;
  logic        rf_w_upper_id;

  logic [4:0]  rf_waddr_wb;
  logic [63:0] rf_wdata_wb;
  logic        rf_we_wb;
  logic        rf_w_upper_wb;
  logic [63:0] rf_wdata_lsu;
  logic        rf_we_lsu;
  logic        rf_wdata_lsu_upper;
  logic        en_wb;

  logic        preload_we;
  logic [4:0]  preload_waddr;
  logic [63:0] preload_wdata;
  logic [4:0]  rf_waddr_mux;
  logic [63:0] rf_wdata_mux;
  logic        rf_we_mux;

  logic [31:0] data_mem [0:255];
  logic        data_rvalid_next;
  logic [31:0] data_rdata_next;
  logic        last_pc_set;
  logic [63:0] last_pc_target;

  int errors;

  assign instr_rdata_alu_i     = instr_rdata_i;
  assign instr_rdata_c_i       = instr_rdata_i[15:0];
  assign instr_is_compressed_i = 1'b0;

  assign data_gnt     = 1'b1;
  assign data_err     = 1'b0;
  assign data_pmp_err = 1'b0;

  assign rf_waddr_mux = preload_we ? preload_waddr : rf_waddr_wb;
  assign rf_wdata_mux = preload_we ? preload_wdata : rf_wdata_wb;
  assign rf_we_mux    = preload_we | rf_we_wb;

  cve2_id_stage #(
    .RV32E     (1'b0),
    .RV32M     (RV32MNone),
    .RV32B     (RV32BNone),
    .XInterface(1'b0),
    .EnableCSRs(1'b0)
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
    .branch_decision_i(branch_decision),
    .alu_is_equal_result_i(alu_is_equal_result),
    .pc_set_o,
    .pc_mux_o,
    .exc_pc_mux_o,
    .exc_cause_o,
    .illegal_c_insn_i(1'b0),
    .instr_fetch_err_i(1'b0),
    .instr_fetch_err_plus2_i(1'b0),
    .pc_id_i,
    .pc_id_upper_i,
    .ex_valid_i(ex_valid),
    .lsu_resp_valid_i(lsu_resp_valid),
    .alu_operator_ex_o(alu_operator_ex),
    .alu_operand_a_ex_o(alu_operand_a_ex),
    .alu_operand_b_ex_o(alu_operand_b_ex),
    .alu_word_op_ex_o(alu_word_op_ex),
    .imd_val_we_ex_i(imd_val_we_ex),
    .imd_val_d_ex_i(imd_val_d_ex),
    .imd_val_q_ex_o(imd_val_q_ex),
    .carry_out_i(carry_out),
    .carry_in_o(carry_in),
    .mult_en_ex_o(mult_en_ex),
    .div_en_ex_o(div_en_ex),
    .mult_sel_ex_o(mult_sel_ex),
    .div_sel_ex_o(div_sel_ex),
    .multdiv_operator_ex_o(multdiv_operator_ex),
    .multdiv_signed_mode_ex_o(multdiv_signed_mode_ex),
    .multdiv_operand_a_ex_o(multdiv_operand_a_ex),
    .multdiv_operand_b_ex_o(multdiv_operand_b_ex),
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
    .csr_wdata_upper_o,
    .csr_wdata_capture_o,
    .csr_rdata_upper_o,
    .csr_rdata_capture_o,
    .priv_mode_i(PRIV_LVL_M),
    .csr_mstatus_tw_i(1'b0),
    .illegal_csr_insn_i(1'b0),
    .lsu_req_o,
    .lsu_we_o,
    .lsu_type_o,
    .lsu_sign_ext_o,
    .lsu_wdata_o,
    .lsu_addr_incr_req_i(lsu_addr_incr_req),
    .lsu_addr_last_i(lsu_addr_last),
    .hart_id_i(32'h0),
    .x_issue_valid_o(),
    .x_issue_ready_i(1'b0),
    .x_issue_req_o(),
    .x_issue_resp_i('0),
    .x_register_o(),
    .r_a_upper_o(),
    .r_b_upper_o(),
    .x_commit_valid_o(),
    .x_commit_o(),
    .x_result_valid_i(1'b0),
    .x_result_ready_o(),
    .x_result_i('0),
    .csr_mstatus_mie_i(1'b0),
    .irq_pending_i(1'b0),
    .irqs_i('0),
    .irq_nm_i(1'b0),
    .nmi_mode_o(),
    .lsu_load_err_i(lsu_load_err),
    .lsu_store_err_i(lsu_store_err),
    .debug_mode_o(),
    .debug_cause_o(),
    .debug_csr_save_o(),
    .debug_req_i(1'b0),
    .debug_single_step_i(1'b0),
    .debug_ebreakm_i(1'b0),
    .debug_ebreaku_i(1'b0),
    .trigger_match_i(1'b0),
    .result_ex_i(result_ex),
    .csr_rdata_i(32'h0),
    .rf_raddr_a_o(rf_raddr_a),
    .rf_rdata_a_i(rf_rdata_a),
    .rf_raddr_b_o(rf_raddr_b),
    .rf_rdata_b_i(rf_rdata_b),
    .rf_ren_a_o(rf_ren_a),
    .rf_ren_b_o(rf_ren_b),
    .rf_waddr_id_o(rf_waddr_id),
    .rf_wdata_id_o(rf_wdata_id),
    .rf_we_id_o(rf_we_id),
    .rf_w_upper_id_o(rf_w_upper_id),
    .lsu_addr_ex_o(lsu_addr_ex),
    .pc_target_ex_o(pc_target_ex),
    .en_wb_o(en_wb),
    .instr_perf_count_id_o(),
    .perf_jump_o(),
    .perf_branch_o(),
    .perf_tbranch_o(),
    .perf_dside_wait_o(),
    .perf_wfi_wait_o(),
    .perf_div_wait_o(),
    .instr_id_done_o(instr_id_done_o)
  );

  cve2_ex_block #(
    .RV32M(RV32MNone),
    .RV32B(RV32BNone)
  ) dut_ex (
    .clk_i,
    .rst_ni,
    .alu_operator_i(alu_operator_ex),
    .alu_operand_a_i(alu_operand_a_ex),
    .alu_operand_b_i(alu_operand_b_ex),
    .alu_instr_first_cycle_i(instr_first_cycle_id_o),
    .alu_word_op_i(alu_word_op_ex),
    .multdiv_operator_i(multdiv_operator_ex),
    .mult_en_i(mult_en_ex),
    .div_en_i(div_en_ex),
    .mult_sel_i(mult_sel_ex),
    .div_sel_i(div_sel_ex),
    .multdiv_signed_mode_i(multdiv_signed_mode_ex),
    .multdiv_operand_a_i(multdiv_operand_a_ex),
    .multdiv_operand_b_i(multdiv_operand_b_ex),
    .imd_val_we_o(imd_val_we_ex),
    .imd_val_d_o(imd_val_d_ex),
    .imd_val_q_i(imd_val_q_ex),
    .carry_in_i(carry_in),
    .carry_out_o(carry_out),
    .alu_adder_result_ex_o(alu_adder_result_ex),
    .result_ex_o(result_ex),
    .branch_target_o(branch_target_unused),
    .branch_decision_o(branch_decision),
    .alu_is_equal_result_o(alu_is_equal_result),
    .ex_valid_o(ex_valid)
  );

  cve2_load_store_unit dut_lsu (
    .clk_i,
    .rst_ni,
    .data_req_o(data_req),
    .data_gnt_i(data_gnt),
    .data_rvalid_i(data_rvalid),
    .data_err_i(data_err),
    .data_pmp_err_i(data_pmp_err),
    .data_addr_o(data_addr),
    .data_we_o(data_we),
    .data_be_o(data_be),
    .data_wdata_o(data_wdata),
    .data_rdata_i(data_rdata),
    .lsu_we_i(lsu_we_o),
    .lsu_type_i(lsu_type_o),
    .lsu_wdata_i(lsu_wdata_o),
    .lsu_sign_ext_i(lsu_sign_ext_o),
    .lsu_rdata_o(rf_wdata_lsu),
    .lsu_rdata_upper_o(rf_wdata_lsu_upper),
    .lsu_rdata_valid_o(rf_we_lsu),
    .lsu_req_i(lsu_req_o),
    .adder_result_ex_i(lsu_addr_ex),
    .addr_incr_req_o(lsu_addr_incr_req),
    .addr_last_o(lsu_addr_last),
    .lsu_resp_valid_o(lsu_resp_valid),
    .load_err_o(lsu_load_err),
    .store_err_o(lsu_store_err),
    .busy_o(lsu_busy),
    .perf_load_o(),
    .perf_store_o()
  );

  cve2_wb dut_wb (
    .clk_i,
    .rst_ni,
    .en_wb_i(en_wb),
    .instr_is_compressed_id_i(instr_is_compressed_i),
    .instr_perf_count_id_i(1'b1),
    .perf_instr_ret_wb_o(),
    .perf_instr_ret_compressed_wb_o(),
    .rf_waddr_id_i(rf_waddr_id),
    .rf_wdata_id_i(rf_wdata_id),
    .rf_we_id_i(rf_we_id),
    .rf_wdata_lsu_i(rf_wdata_lsu),
    .rf_we_lsu_i(rf_we_lsu),
    .rf_wdata_lsu_upper_i(rf_wdata_lsu_upper),
    .rf_waddr_wb_o(rf_waddr_wb),
    .rf_wdata_wb_o(rf_wdata_wb),
    .rf_we_wb_o(rf_we_wb),
    .lsu_resp_valid_i(lsu_resp_valid),
    .lsu_resp_err_i(lsu_load_err | lsu_store_err),
    .w_upper_i(rf_w_upper_id),
    .w_upper_o(rf_w_upper_wb)
  );

  cve2_register_file_ff #(
    .RV32E(1'b0),
    .DataWidth(64),
    .WordZeroVal(64'h0)
  ) dut_rf (
    .clk_i,
    .rst_ni,
    .test_en_i(1'b0),
    .raddr_a_i(rf_raddr_a),
    .rdata_a_o(rf_rdata_a),
    .r_a_upper_i(1'b0),
    .raddr_b_i(rf_raddr_b),
    .rdata_b_o(rf_rdata_b),
    .r_b_upper_i(1'b0),
    .waddr_a_i(rf_waddr_mux),
    .wdata_a_i(rf_wdata_mux),
    .we_a_i(rf_we_mux),
    .w_upper_i(1'b0)
  );

  function automatic logic [31:0] enc_r(input logic [6:0] funct7,
                                        input logic [4:0] rs2,
                                        input logic [4:0] rs1,
                                        input logic [2:0] funct3,
                                        input logic [4:0] rd,
                                        input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_i(input logic [11:0] imm,
                                        input logic [4:0] rs1,
                                        input logic [2:0] funct3,
                                        input logic [4:0] rd,
                                        input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm,
                                        input logic [4:0] rs2,
                                        input logic [4:0] rs1,
                                        input logic [2:0] funct3);
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
  endfunction

  function automatic logic [31:0] enc_u(input logic [19:0] imm,
                                        input logic [4:0] rd,
                                        input logic [6:0] opcode);
    return {imm, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_b(input logic [12:0] imm,
                                        input logic [4:0] rs2,
                                        input logic [4:0] rs1,
                                        input logic [2:0] funct3);
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011};
  endfunction

  task automatic set_pc64(input logic [63:0] pc);
    begin
      pc_id_i       = pc[31:0];
      pc_id_upper_i = pc[63:32];
    end
  endtask

  task automatic write_rf64(input logic [4:0] addr, input logic [63:0] value);
    begin
      @(negedge clk_i);
      preload_waddr = addr;
      preload_wdata = value;
      preload_we    = 1'b1;
      @(posedge clk_i);
      #1;
      preload_we    = 1'b0;
    end
  endtask

  function automatic logic [63:0] read_rf64(input logic [4:0] addr);
    if (addr == 5'd0) begin
      return 64'h0;
    end else begin
      return dut_rf.rf_mem_a[addr];
    end
  endfunction

  task automatic run_instr(input logic [31:0] encoding, output int cycles);
    logic is_mem_op;
    logic mem_resp_seen;
    begin
      @(negedge clk_i);
      instr_rdata_i = encoding;
      instr_valid_i = 1'b1;
      is_mem_op = (encoding[6:0] == 7'b0000011) || (encoding[6:0] == 7'b0100011);
      mem_resp_seen = 1'b0;
      last_pc_set = 1'b0;
      last_pc_target = 64'h0;
      cycles = 0;
      begin : wait_done
        forever begin
          @(posedge clk_i);
          #1;
          if (lsu_resp_valid) begin
            mem_resp_seen = 1'b1;
          end
          if (pc_set_o) begin
            last_pc_set = 1'b1;
            last_pc_target = pc_target_ex;
          end
          cycles++;
          if (instr_id_done_o && (!is_mem_op || mem_resp_seen)) begin
            disable wait_done;
          end
          if (cycles > 30) begin
            $display("TIMEOUT: instruction %h did not complete", encoding);
            $display("  state=%0d lsu_req_dec=%0b lsu_req=%0b data_req=%0b data_rvalid=%0b lsu_resp=%0b instr_done=%0b stall=%0b",
                     dut_id.id_fsm_q, dut_id.lsu_req_dec, lsu_req_o, data_req, data_rvalid,
                     lsu_resp_valid, instr_id_done_o, dut_id.stall_id);
            errors++;
            disable wait_done;
          end
        end
      end
      if (is_mem_op) begin
        @(posedge clk_i);
        #1;
      end
      @(negedge clk_i);
      instr_valid_i = 1'b0;
      instr_rdata_i = NOP;
      repeat (2) @(posedge clk_i);
      #1;
    end
  endtask

  task automatic check_reg(input string name, input logic [4:0] addr, input logic [63:0] exp);
    logic [63:0] got;
    begin
      got = read_rf64(addr);
      if (got !== exp) begin
        $display("ERROR %s: x%0d expected %h got %h", name, addr, exp, got);
        errors++;
      end else begin
        $display("PASS  %s: x%0d = %h", name, addr, got);
      end
    end
  endtask

  task automatic check_mem(input string name, input int index, input logic [31:0] exp);
    begin
      if (data_mem[index] !== exp) begin
        $display("ERROR %s: mem[%0d] expected %h got %h", name, index, exp, data_mem[index]);
        errors++;
      end else begin
        $display("PASS  %s: mem[%0d] = %h", name, index, exp);
      end
    end
  endtask

  task automatic clear_regs;
    begin
      for (int i = 1; i < 32; i++) begin
        write_rf64(i[4:0], 64'h0);
      end
    end
  endtask

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_rvalid      <= 1'b0;
      data_rvalid_next <= 1'b0;
      data_rdata       <= 32'h0;
      data_rdata_next  <= 32'h0;
    end else begin
      data_rvalid <= data_rvalid_next;
      data_rdata  <= data_rdata_next;

      data_rvalid_next <= data_req;
      data_rdata_next  <= data_mem[data_addr[9:2]];

      if (data_req && data_we) begin
        if (data_be[0]) data_mem[data_addr[9:2]][7:0]   <= data_wdata[7:0];
        if (data_be[1]) data_mem[data_addr[9:2]][15:8]  <= data_wdata[15:8];
        if (data_be[2]) data_mem[data_addr[9:2]][23:16] <= data_wdata[23:16];
        if (data_be[3]) data_mem[data_addr[9:2]][31:24] <= data_wdata[31:24];
      end
    end
  end

  initial begin
    int cycles;

    errors = 0;
    preload_we = 1'b0;
    preload_waddr = 5'h0;
    preload_wdata = 64'h0;
    instr_valid_i = 1'b0;
    instr_rdata_i = NOP;
    set_pc64(64'h0000_0000_0000_1000);
    for (int i = 0; i < 256; i++) data_mem[i] = 32'h0;

    @(posedge rst_ni);
    repeat (3) @(posedge clk_i);

    clear_regs();

    write_rf64(5'd1, 64'h1000_2000_0000_0003);
    write_rf64(5'd2, 64'h0000_0000_0000_0005);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011), cycles);
    check_reg("ADD64", 5'd3, 64'h1000_2000_0000_0008);

    write_rf64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf64(5'd2, 64'h0000_0000_0000_0001);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011), cycles);
    check_reg("ADD64_WRAP", 5'd3, 64'h0000_0000_0000_0000);

    write_rf64(5'd1, 64'h0000_0001_0000_0000);
    write_rf64(5'd2, 64'h0000_0000_0000_0001);
    run_instr(enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011), cycles);
    check_reg("SUB64_BORROW", 5'd3, 64'h0000_0000_ffff_ffff);

    write_rf64(5'd1, 64'hff00_ff00_1234_5678);
    write_rf64(5'd2, 64'h0f0f_0f0f_ffff_0000);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3, 7'b0110011), cycles);
    check_reg("AND64", 5'd3, 64'h0f00_0f00_1234_0000);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd3, 7'b0110011), cycles);
    check_reg("OR64", 5'd3, 64'hff0f_ff0f_ffff_5678);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd3, 7'b0110011), cycles);
    check_reg("XOR64", 5'd3, 64'hf00f_f00f_edcb_5678);

    write_rf64(5'd1, 64'h0);
    run_instr(enc_i(12'hfff, 5'd1, 3'b000, 5'd3, 7'b0010011), cycles);
    check_reg("ADDI_SIGNEXT", 5'd3, 64'hffff_ffff_ffff_ffff);

    write_rf64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf64(5'd2, 64'h0000_0000_0000_0001);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd3, 7'b0110011), cycles);
    check_reg("SLT64", 5'd3, 64'h1);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd3, 7'b0110011), cycles);
    check_reg("SLTU64", 5'd3, 64'h0);

    write_rf64(5'd1, 64'h0000_0001_0000_0000);
    write_rf64(5'd2, 64'd4);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd3, 7'b0110011), cycles);
    check_reg("SLL64", 5'd3, 64'h0000_0010_0000_0000);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd3, 3'b101, 5'd4, 7'b0110011), cycles);
    check_reg("SRL64", 5'd4, 64'h0000_0001_0000_0000);
    write_rf64(5'd1, 64'h8000_0000_0000_0000);
    write_rf64(5'd2, 64'd4);
    run_instr(enc_r(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd3, 7'b0110011), cycles);
    check_reg("SRA64", 5'd3, 64'hf800_0000_0000_0000);

    write_rf64(5'd1, 64'h0000_0000_7fff_ffff);
    run_instr(enc_i(12'h001, 5'd1, 3'b000, 5'd3, 7'b0011011), cycles);
    check_reg("ADDIW", 5'd3, 64'hffff_ffff_8000_0000);
    write_rf64(5'd1, 64'h0000_0000_ffff_ffff);
    write_rf64(5'd2, 64'h1);
    run_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0111011), cycles);
    check_reg("ADDW", 5'd3, 64'h0);
    run_instr(enc_i({7'b0100000, 5'd1}, 5'd1, 3'b101, 5'd3, 7'b0011011), cycles);
    check_reg("SRAIW", 5'd3, 64'hffff_ffff_ffff_ffff);

    run_instr(enc_u(20'h80000, 5'd3, 7'b0110111), cycles);
    check_reg("LUI64", 5'd3, 64'hffff_ffff_8000_0000);
    set_pc64(64'h0000_0001_0000_1000);
    run_instr(enc_u(20'h00001, 5'd3, 7'b0010111), cycles);
    check_reg("AUIPC64", 5'd3, 64'h0000_0001_0000_2000);

    data_mem[0] = 32'h0000_0080;
    write_rf64(5'd1, 64'h0);
    run_instr(enc_i(12'h000, 5'd1, 3'b000, 5'd3, 7'b0000011), cycles);
    check_reg("LB64", 5'd3, 64'hffff_ffff_ffff_ff80);
    run_instr(enc_i(12'h000, 5'd1, 3'b100, 5'd3, 7'b0000011), cycles);
    check_reg("LBU64", 5'd3, 64'h0000_0000_0000_0080);

    data_mem[0] = 32'h8000_0000;
    run_instr(enc_i(12'h000, 5'd1, 3'b010, 5'd3, 7'b0000011), cycles);
    check_reg("LW64", 5'd3, 64'hffff_ffff_8000_0000);
    run_instr(enc_i(12'h000, 5'd1, 3'b110, 5'd3, 7'b0000011), cycles);
    check_reg("LWU64", 5'd3, 64'h0000_0000_8000_0000);

    data_mem[0] = 32'h89ab_cdef;
    data_mem[1] = 32'h0123_4567;
    run_instr(enc_i(12'h000, 5'd1, 3'b011, 5'd3, 7'b0000011), cycles);
    check_reg("LD64", 5'd3, 64'h0123_4567_89ab_cdef);

    write_rf64(5'd2, 64'h1122_3344_5566_7788);
    run_instr(enc_s(12'h000, 5'd2, 5'd1, 3'b011), cycles);
    check_mem("SD_LOWER", 0, 32'h5566_7788);
    check_mem("SD_UPPER", 1, 32'h1122_3344);

    write_rf64(5'd1, 64'hffff_ffff_ffff_ffff);
    write_rf64(5'd2, 64'hffff_ffff_ffff_ffff);
    set_pc64(64'h0000_0000_0000_2000);
    run_instr(enc_b(13'd8, 5'd2, 5'd1, 3'b000), cycles);
    if (!last_pc_set || last_pc_target !== 64'h0000_0000_0000_2008) begin
      $display("ERROR BEQ64: pc_set=%0b target=%h", last_pc_set, last_pc_target);
      errors++;
    end else begin
      $display("PASS  BEQ64: target = %h", last_pc_target);
    end

    if (errors == 0) begin
      $display("ALL NATIVE RV64 TESTS PASSED");
    end else begin
      $display("NATIVE RV64 TESTS FAILED: %0d error(s)", errors);
    end
    $finish;
  end

endmodule
