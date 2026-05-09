`timescale 1ns/1ps

module testbench;

  import cve2_pkg::*;

  localparam int unsigned ImemWords = 256;
  localparam int unsigned DmemWords = 256;

  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
  localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
  localparam logic [6:0] OPCODE_OP     = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
  localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
  localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

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

  function automatic logic [31:0] enc_i(input logic [11:0] imm,
                                        input logic [4:0]  rs1,
                                        input logic [2:0]  funct3,
                                        input logic [4:0]  rd,
                                        input logic [6:0]  opcode);
    enc_i = {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm,
                                        input logic [4:0]  rs2,
                                        input logic [4:0]  rs1,
                                        input logic [2:0]  funct3);
    enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], OPCODE_STORE};
  endfunction

  function automatic logic [31:0] enc_b(input logic [12:0] imm,
                                        input logic [4:0]  rs2,
                                        input logic [4:0]  rs1,
                                        input logic [2:0]  funct3);
    enc_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], OPCODE_BRANCH};
  endfunction

  function automatic logic [31:0] enc_r(input logic [6:0] funct7,
                                        input logic [4:0] rs2,
                                        input logic [4:0] rs1,
                                        input logic [2:0] funct3,
                                        input logic [4:0] rd);
    enc_r = {funct7, rs2, rs1, funct3, rd, OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_u(input logic [19:0] imm20,
                                        input logic [4:0]  rd,
                                        input logic [6:0]  opcode);
    enc_u = {imm20, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_j(input logic [20:0] imm,
                                        input logic [4:0]  rd);
    enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, OPCODE_JAL};
  endfunction

  function automatic logic [31:0] enc_csr(input logic [11:0] csr,
                                          input logic [4:0]  rs1,
                                          input logic [2:0]  funct3,
                                          input logic [4:0]  rd);
    enc_csr = {csr, rs1, funct3, rd, OPCODE_SYSTEM};
  endfunction

  logic [31:0] imem [0:ImemWords-1];
  logic [31:0] dmem [0:DmemWords-1];

  initial begin : init_memories
    for (int unsigned i = 0; i < ImemWords; i++) begin
      imem[i] = enc_i(12'h000, 5'd0, 3'b000, 5'd0, OPCODE_OP_IMM); // NOP
    end
    for (int unsigned i = 0; i < DmemWords; i++) begin
      dmem[i] = 32'h0;
    end

    imem[0]  = enc_i(12'd5,  5'd0, 3'b000, 5'd1,  OPCODE_OP_IMM); // addi x1,x0,5
    imem[1]  = enc_i(12'd7,  5'd0, 3'b000, 5'd2,  OPCODE_OP_IMM); // addi x2,x0,7
    imem[2]  = enc_r(7'b0000000, 5'd2,  5'd1, 3'b000, 5'd3);      // add x3,x1,x2
    imem[3]  = enc_r(7'b0100000, 5'd1,  5'd3, 3'b000, 5'd4);      // sub x4,x3,x1
    imem[4]  = enc_i(12'd10, 5'd3, 3'b111, 5'd5,  OPCODE_OP_IMM); // andi x5,x3,10
    imem[5]  = enc_i(12'd1,  5'd5, 3'b110, 5'd6,  OPCODE_OP_IMM); // ori x6,x5,1
    imem[6]  = enc_r(7'b0000000, 5'd2,  5'd6, 3'b100, 5'd7);      // xor x7,x6,x2
    imem[7]  = enc_i({7'b0000000, 5'd2}, 5'd2, 3'b001, 5'd8,
                     OPCODE_OP_IMM);                              // slli x8,x2,2
    imem[8]  = enc_i({7'b0000000, 5'd1}, 5'd8, 3'b101, 5'd9,
                     OPCODE_OP_IMM);                              // srli x9,x8,1
    imem[9]  = enc_u(20'h80000, 5'd11, OPCODE_LUI);               // lui x11,0x80000
    imem[10] = enc_i({7'b0100000, 5'd31}, 5'd11, 3'b101, 5'd12,
                     OPCODE_OP_IMM);                              // srai x12,x11,31
    imem[11] = enc_s(12'd0, 5'd3, 5'd0, 3'b010);                  // sw x3,0(x0)
    imem[12] = enc_i(12'd0, 5'd0, 3'b010, 5'd13, OPCODE_LOAD);    // lw x13,0(x0)
    imem[13] = enc_b(13'd8, 5'd3, 5'd13, 3'b000);                 // beq x13,x3,+8
    imem[14] = enc_i(12'd1, 5'd0, 3'b000, 5'd14, OPCODE_OP_IMM);  // skipped if branch works
    imem[15] = enc_i(12'd2, 5'd0, 3'b000, 5'd14, OPCODE_OP_IMM);  // addi x14,x0,2
    imem[16] = enc_j(21'd0, 5'd0);                                // loop: jal x0,0
  end

  logic                         test_en_i;
  prim_ram_1p_pkg::ram_1p_cfg_t ram_cfg_i;
  logic [31:0]                  hart_id_i;
  logic [31:0]                  boot_addr_i;
  logic                         fetch_enable_i;
  logic                         core_sleep_o;

  logic                         instr_req_o;
  logic                         instr_gnt_i;
  logic                         instr_rvalid_i;
  logic [31:0]                  instr_addr_o;
  logic [31:0]                  instr_rdata_i;
  logic                         instr_err_i;

  logic                         data_req_o;
  logic                         data_gnt_i;
  logic                         data_rvalid_i;
  logic                         data_we_o;
  logic [3:0]                   data_be_o;
  logic [31:0]                  data_addr_o;
  logic [31:0]                  data_wdata_o;
  logic [31:0]                  data_rdata_i;
  logic                         data_err_i;

  logic                         x_issue_valid_o;
  logic                         x_issue_ready_i;
  x_issue_req_t                 x_issue_req_o;
  x_issue_resp_t                x_issue_resp_i;
  x_register_t                  x_register_o;
  logic                         x_commit_valid_o;
  x_commit_t                    x_commit_o;
  logic                         x_result_valid_i;
  logic                         x_result_ready_o;
  x_result_t                    x_result_i;

  logic                         irq_software_i;
  logic                         irq_timer_i;
  logic                         irq_external_i;
  logic [15:0]                  irq_fast_i;
  logic                         irq_nm_i;
  logic                         debug_req_i;
  logic                         debug_halted_o;
  logic [31:0]                  dm_halt_addr_i;
  logic [31:0]                  dm_exception_addr_i;
  crash_dump_t                  crash_dump_o;

  initial begin
    test_en_i           = 1'b1;
    ram_cfg_i           = '0;
    hart_id_i           = 32'h0;
    boot_addr_i         = 32'h0;
    fetch_enable_i      = 1'b1;
    instr_err_i         = 1'b0;
    data_err_i          = 1'b0;
    x_issue_ready_i     = 1'b0;
    x_issue_resp_i      = '0;
    x_result_valid_i    = 1'b0;
    x_result_i          = '0;
    irq_software_i      = 1'b0;
    irq_timer_i         = 1'b0;
    irq_external_i      = 1'b0;
    irq_fast_i          = 16'h0;
    irq_nm_i            = 1'b0;
    debug_req_i         = 1'b0;
    dm_halt_addr_i      = 32'h1a11_0800;
    dm_exception_addr_i = 32'h1a11_0808;
  end

  assign instr_gnt_i = instr_req_o;
  assign data_gnt_i  = data_req_o;

  always @(posedge clk_i or negedge rst_ni) begin : instr_mem_model
    if (!rst_ni) begin
      instr_rvalid_i <= 1'b0;
      instr_rdata_i  <= 32'h0000_0013;
    end else begin
      instr_rvalid_i <= instr_req_o;
      if (instr_req_o) begin
        instr_rdata_i <= imem[instr_addr_o[9:2]];
      end
    end
  end

  always @(posedge clk_i or negedge rst_ni) begin : data_mem_model
    if (!rst_ni) begin
      data_rvalid_i <= 1'b0;
      data_rdata_i  <= 32'h0;
    end else begin
      data_rvalid_i <= data_req_o;
      if (data_req_o) begin
        data_rdata_i <= dmem[data_addr_o[9:2]];
        if (data_we_o) begin
          if (data_be_o[0]) dmem[data_addr_o[9:2]][7:0]   <= data_wdata_o[7:0];
          if (data_be_o[1]) dmem[data_addr_o[9:2]][15:8]  <= data_wdata_o[15:8];
          if (data_be_o[2]) dmem[data_addr_o[9:2]][23:16] <= data_wdata_o[23:16];
          if (data_be_o[3]) dmem[data_addr_o[9:2]][31:24] <= data_wdata_o[31:24];
        end
      end
    end
  end

  cve2_top #(
    .RV32M      (RV32MNone),
    .XInterface (1'b0),
    .EnableCSRs (1'b0)
  ) dut (
    .clk_i,
    .rst_ni,
    .test_en_i,
    .ram_cfg_i,
    .hart_id_i,
    .boot_addr_i,
    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_rdata_i,
    .instr_err_i,
    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_we_o,
    .data_be_o,
    .data_addr_o,
    .data_wdata_o,
    .data_rdata_i,
    .data_err_i,
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
    .irq_software_i,
    .irq_timer_i,
    .irq_external_i,
    .irq_fast_i,
    .irq_nm_i,
    .debug_req_i,
    .debug_halted_o,
    .dm_halt_addr_i,
    .dm_exception_addr_i,
    .crash_dump_o,
    .fetch_enable_i,
    .core_sleep_o
  );

  logic        dec_illegal;
  logic        dec_csr_access;
  logic [31:0] dec_instr;

  cve2_decoder #(
    .RV32M      (RV32MNone),
    .RV32B      (RV32BNone),
    .XInterface (1'b0),
    .EnableCSRs (1'b0)
  ) dut_decoder_nocsr (
    .clk_i,
    .rst_ni,
    .illegal_insn_o(dec_illegal),
    .ebrk_insn_o(),
    .mret_insn_o(),
    .dret_insn_o(),
    .ecall_insn_o(),
    .wfi_insn_o(),
    .jump_set_o(),
    .instr_first_cycle_i(1'b1),
    .instr_rdata_i(dec_instr),
    .instr_rdata_alu_i(dec_instr),
    .illegal_c_insn_i(1'b0),
    .imm_a_mux_sel_o(),
    .imm_b_mux_sel_o(),
    .imm_i_type_o(),
    .imm_s_type_o(),
    .imm_b_type_o(),
    .imm_u_type_o(),
    .imm_j_type_o(),
    .zimm_rs1_type_o(),
    .rf_wdata_sel_o(),
    .rf_we_o(),
    .rf_raddr_a_o(),
    .rf_raddr_b_o(),
    .rf_waddr_o(),
    .rf_ren_a_o(),
    .rf_ren_b_o(),
    .alu_operator_o(),
    .alu_op_a_mux_sel_o(),
    .alu_op_b_mux_sel_o(),
    .alu_multicycle_o(),
    .mult_en_o(),
    .div_en_o(),
    .mult_sel_o(),
    .div_sel_o(),
    .multdiv_operator_o(),
    .multdiv_signed_mode_o(),
    .csr_access_o(dec_csr_access),
    .csr_op_o(),
    .data_req_o(),
    .data_we_o(),
    .data_type_o(),
    .data_sign_extension_o(),
    .x_issue_resp_register_read_i('0),
    .x_issue_resp_writeback_i('0),
    .jump_in_dec_o(),
    .branch_in_dec_o()
  );

  int unsigned errors;

  function automatic logic [31:0] rf_value(input int unsigned idx);
    if (idx == 0) begin
      rf_value = 32'h0;
    end else begin
      rf_value = dut.u_cve2_core.register_file_i.rf_reg_q[idx[4:0]];
    end
  endfunction

  task automatic check_value(input string name,
                             input logic [31:0] actual,
                             input logic [31:0] expected);
    if (actual !== expected) begin
      $display("FAIL %-24s expected=%08h actual=%08h", name, expected, actual);
      errors++;
    end else begin
      $display("PASS %-24s %08h", name, actual);
    end
  endtask

  task automatic check_reg(input string name,
                           input int unsigned idx,
                           input logic [31:0] expected);
    check_value(name, rf_value(idx), expected);
  endtask

  task automatic check_decode_illegal(input string name,
                                      input logic [31:0] instr,
                                      input logic expected_illegal);
    dec_instr = instr;
    #1;
    if (dec_illegal !== expected_illegal) begin
      $display("FAIL %-24s expected_illegal=%0b actual=%0b",
               name, expected_illegal, dec_illegal);
      errors++;
    end else begin
      $display("PASS %-24s illegal=%0b", name, dec_illegal);
    end
  endtask

  initial begin : run_tests
    errors = 0;
    dec_instr = enc_i(12'h000, 5'd0, 3'b000, 5'd0, OPCODE_OP_IMM);

    wait (rst_ni);
    repeat (160) @(posedge clk_i);

    $display("\n========== RV32I top-level smoke test ==========");
    check_reg("x0 hardwired zero", 0, 32'h0000_0000);
    check_reg("ADDI x1",          1, 32'h0000_0005);
    check_reg("ADDI x2",          2, 32'h0000_0007);
    check_reg("ADD x3",           3, 32'h0000_000c);
    check_reg("SUB x4",           4, 32'h0000_0007);
    check_reg("ANDI x5",          5, 32'h0000_0008);
    check_reg("ORI x6",           6, 32'h0000_0009);
    check_reg("XOR x7",           7, 32'h0000_000e);
    check_reg("SLLI x8",          8, 32'h0000_001c);
    check_reg("SRLI x9",          9, 32'h0000_000e);
    check_reg("LUI x11",         11, 32'h8000_0000);
    check_reg("SRAI x12",        12, 32'hffff_ffff);
    check_reg("LW x13",          13, 32'h0000_000c);
    check_reg("BEQ skip x14",    14, 32'h0000_0002);
    check_value("SW memory word", dmem[0], 32'h0000_000c);

    $display("\n========== No-CSR decode checks ==========");
    check_decode_illegal("ADDI remains legal",
                         enc_i(12'h001, 5'd0, 3'b000, 5'd1, OPCODE_OP_IMM),
                         1'b0);
    check_decode_illegal("CSRRS is illegal",
                         enc_csr(12'hb00, 5'd0, 3'b010, 5'd15),
                         1'b1);
    check_decode_illegal("MRET is illegal", 32'h3020_0073, 1'b1);

    if (errors == 0) begin
      $display("\nALL BASE TESTS PASSED");
      $finish;
    end else begin
      $display("\nBASE TESTS FAILED: %0d error(s)", errors);
      $fatal(1);
    end
  end

  initial begin : timeout
    repeat (500) @(posedge clk_i);
    $display("TIMEOUT waiting for base test completion");
    $fatal(1);
  end

  initial begin
    $dumpfile("testbench.vcd");
    $dumpvars(0, testbench);
  end

endmodule
