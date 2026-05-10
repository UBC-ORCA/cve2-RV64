// Copyright (c) 2025 Eclipse Foundation
// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0


/**
 * Load Store Unit
 *
 * Load Store Unit, used to eliminate multiple access during processor stalls,
 * and to align bytes and halfwords.
 */

`include "prim_assert.sv"
`include "dv_fcov_macros.svh"

module cve2_load_store_unit
(
  input  logic         clk_i,
  input  logic         rst_ni,

  // data interface
  output logic         data_req_o,
  input  logic         data_gnt_i,
  input  logic         data_rvalid_i,
  input  logic         data_err_i,
  input  logic         data_pmp_err_i,

  output logic [63:0]  data_addr_o,
  output logic         data_we_o,
  output logic [7:0]   data_be_o,
  output logic [63:0]  data_wdata_o,
  input  logic [63:0]  data_rdata_i,

  // signals to/from ID/EX stage
  input  logic         lsu_we_i,             // write enable                     -> from ID/EX
  input  logic [1:0]   lsu_type_i,           // data type: word, half word, byte -> from ID/EX
  input  logic [63:0]  lsu_wdata_i,          // data to write to memory          -> from ID/EX
  input  logic         lsu_sign_ext_i,       // sign extension                   -> from ID/EX

  output logic [63:0]  lsu_rdata_o,          // requested data                   -> to ID/EX
  output logic         lsu_rdata_upper_o,
  output logic         lsu_rdata_valid_o,
  input  logic         lsu_req_i,            // data request                     -> from ID/EX

  input  logic [63:0]  adder_result_ex_i,    // address computed in ALU          -> from ID/EX

  output logic         addr_incr_req_o,      // request address increment for
                                              // misaligned accesses              -> to ID/EX
  output logic [63:0]  addr_last_o,          // address of last transaction      -> to controller
                                              // -> mtval
                                              // -> AGU for misaligned accesses

  output logic         lsu_resp_valid_o,     // LSU has response from transaction -> to ID/EX

  // exception signals
  output logic         load_err_o,
  output logic         store_err_o,

  output logic         busy_o,

  output logic         perf_load_o,
  output logic         perf_store_o
);

  logic [63:0]  data_addr;
  logic [63:0]  data_addr_w_aligned;
  logic [63:0]  addr_last_q, addr_last_d;

  logic         addr_update;
  logic         ctrl_update;
  logic         rdata_update;
  logic [63:8]  rdata_q;
  logic [2:0]   rdata_offset_q;
  logic [1:0]   data_type_q;
  logic         data_sign_ext_q;
  logic         data_we_q;

  logic [2:0]   data_offset;   // mux control for data to be written to memory

  logic [7:0]   data_be;
  logic [63:0]  data_wdata;

  logic [63:0]  data_rdata_ext;
  logic [63:0]  data_rdata_full;

  logic [63:0]  rdata_d_ext; // dword realignment for misaligned loads
  logic [63:0]  rdata_w_ext; // word sign extension
  logic [63:0]  rdata_h_ext; // sign extension for half words
  logic [63:0]  rdata_b_ext; // sign extension for bytes

  logic         split_misaligned_access;
  logic         dword_access;
  logic         dword_misaligned;
  logic         handle_misaligned_q, handle_misaligned_d; // high after receiving grant for first
                                                          // part of a misaligned access
  logic         pmp_err_q, pmp_err_d;
  logic         lsu_err_q, lsu_err_d;
  logic         misaligned_err_q, misaligned_err_d;
  logic         data_or_pmp_err;

  typedef enum logic [2:0]  {
    IDLE, WAIT_GNT_MIS, WAIT_RVALID_MIS, WAIT_GNT,
    WAIT_RVALID_MIS_GNTS_DONE
  } ls_fsm_e;

  ls_fsm_e ls_fsm_cs, ls_fsm_ns;

  assign data_addr   = adder_result_ex_i;
  assign data_offset = data_addr[2:0];

  ///////////////////
  // BE generation //
  ///////////////////

  always_comb begin
    unique case (lsu_type_i) // Data type 00 Word, 01 Half word, 10 byte, 11 doubleword
      2'b00: begin // Writing a word
        if (!handle_misaligned_q) begin // first part of potentially misaligned transaction
          unique case (data_offset)
            3'b000:  data_be = 8'b0000_1111;
            3'b001:  data_be = 8'b0001_1110;
            3'b010:  data_be = 8'b0011_1100;
            3'b011:  data_be = 8'b0111_1000;
            3'b100:  data_be = 8'b1111_0000;
            3'b101:  data_be = 8'b1110_0000;
            3'b110:  data_be = 8'b1100_0000;
            3'b111:  data_be = 8'b1000_0000;
            default: data_be = 8'b1111_1111;
          endcase
        end else begin // second part of misaligned transaction (only when crossing 8-byte boundary)
          unique case (data_offset)
            3'b101:  data_be = 8'b0000_0001;
            3'b110:  data_be = 8'b0000_0011;
            3'b111:  data_be = 8'b0000_0111;
            default: data_be = 8'b0000_0000;
          endcase
        end
      end

      2'b01: begin // Writing a half word
        if (!handle_misaligned_q) begin // first part of potentially misaligned transaction
          unique case (data_offset)
            3'b000:  data_be = 8'b0000_0011;
            3'b001:  data_be = 8'b0000_0110;
            3'b010:  data_be = 8'b0000_1100;
            3'b011:  data_be = 8'b0001_1000;
            3'b100:  data_be = 8'b0011_0000;
            3'b101:  data_be = 8'b0110_0000;
            3'b110:  data_be = 8'b1100_0000;
            3'b111:  data_be = 8'b1000_0000;
            default: data_be = 8'b0000_0011;
          endcase
        end else begin // second part of misaligned transaction (offset 7 only)
          data_be = 8'b0000_0001;
        end
      end

      2'b10: begin // Writing a byte
        unique case (data_offset)
          3'b000:  data_be = 8'b0000_0001;
          3'b001:  data_be = 8'b0000_0010;
          3'b010:  data_be = 8'b0000_0100;
          3'b011:  data_be = 8'b0000_1000;
          3'b100:  data_be = 8'b0001_0000;
          3'b101:  data_be = 8'b0010_0000;
          3'b110:  data_be = 8'b0100_0000;
          3'b111:  data_be = 8'b1000_0000;
          default: data_be = 8'b0000_0001;
        endcase
      end

      2'b11: begin // Writing a doubleword (must be 8-byte aligned)
        data_be = 8'b1111_1111;
      end

      default:     data_be = 8'b1111_1111;
    endcase
  end

  /////////////////////
  // WData alignment //
  /////////////////////

  // prepare data to be written to the memory.
  // For misaligned accesses that cross the 8-byte boundary the second beat
  // wraps the upper bytes back into the low byte lanes.
  always_comb begin
    unique case (data_offset)
      3'b000:  data_wdata =  lsu_wdata_i;
      3'b001:  data_wdata = {lsu_wdata_i[55:0], lsu_wdata_i[63:56]};
      3'b010:  data_wdata = {lsu_wdata_i[47:0], lsu_wdata_i[63:48]};
      3'b011:  data_wdata = {lsu_wdata_i[39:0], lsu_wdata_i[63:40]};
      3'b100:  data_wdata = {lsu_wdata_i[31:0], lsu_wdata_i[63:32]};
      3'b101:  data_wdata = {lsu_wdata_i[23:0], lsu_wdata_i[63:24]};
      3'b110:  data_wdata = {lsu_wdata_i[15:0], lsu_wdata_i[63:16]};
      3'b111:  data_wdata = {lsu_wdata_i[ 7:0], lsu_wdata_i[63: 8]};
      default: data_wdata =  lsu_wdata_i;
    endcase
  end

  /////////////////////
  // RData alignment //
  /////////////////////

  // register for unaligned rdata: stores upper bytes from the first beat of
  // a misaligned access so we can stitch them with the second beat.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_q <= '0;
    end else if (rdata_update) begin
      rdata_q <= data_rdata_i[63:8];
    end
  end

  // registers for transaction control
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_offset_q  <= 3'h0;
      data_type_q     <= 2'h0;
      data_sign_ext_q <= 1'b0;
      data_we_q       <= 1'b0;
    end else if (ctrl_update) begin
      rdata_offset_q  <= data_offset;
      data_type_q     <= lsu_type_i;
      data_sign_ext_q <= lsu_sign_ext_i;
      data_we_q       <= lsu_we_i;
    end
  end

  // Store last address for mtval + AGU for misaligned transactions.  Do not update in case of
  // errors, mtval needs the (first) failing address.  Where an aligned access or the first half of
  // a misaligned access sees an error provide the calculated access address. For the second half of
  // a misaligned access provide the word aligned address of the second half.
  assign addr_last_d = addr_incr_req_o ? data_addr_w_aligned : data_addr;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_last_q <= '0;
    end else if (addr_update) begin
      addr_last_q <= addr_last_d;
    end
  end

  // ----------------------------------------------------------------
  // Extract requested datum from the 64-bit memory word, handling
  // misaligned accesses that span an 8-byte boundary by stitching the
  // first beat (rdata_q) with the second beat (data_rdata_i).
  // ----------------------------------------------------------------

  logic [7:0]  rdata_b_raw;
  logic [15:0] rdata_h_raw;
  logic [31:0] rdata_w_raw;
  logic [63:0] rdata_d_raw;

  // Byte extraction: pick byte at rdata_offset_q within the 8-byte word.
  always_comb begin
    unique case (rdata_offset_q)
      3'b000:  rdata_b_raw = data_rdata_i[ 7: 0];
      3'b001:  rdata_b_raw = data_rdata_i[15: 8];
      3'b010:  rdata_b_raw = data_rdata_i[23:16];
      3'b011:  rdata_b_raw = data_rdata_i[31:24];
      3'b100:  rdata_b_raw = data_rdata_i[39:32];
      3'b101:  rdata_b_raw = data_rdata_i[47:40];
      3'b110:  rdata_b_raw = data_rdata_i[55:48];
      3'b111:  rdata_b_raw = data_rdata_i[63:56];
      default: rdata_b_raw = data_rdata_i[ 7: 0];
    endcase
  end

  // Half-word extraction: 16 bits at rdata_offset_q. Offset 7 wraps using rdata_q.
  always_comb begin
    unique case (rdata_offset_q)
      3'b000:  rdata_h_raw = data_rdata_i[15: 0];
      3'b001:  rdata_h_raw = data_rdata_i[23: 8];
      3'b010:  rdata_h_raw = data_rdata_i[31:16];
      3'b011:  rdata_h_raw = data_rdata_i[39:24];
      3'b100:  rdata_h_raw = data_rdata_i[47:32];
      3'b101:  rdata_h_raw = data_rdata_i[55:40];
      3'b110:  rdata_h_raw = data_rdata_i[63:48];
      3'b111:  rdata_h_raw = {data_rdata_i[7:0], rdata_q[63:56]};
      default: rdata_h_raw = data_rdata_i[15: 0];
    endcase
  end

  // Word extraction: 32 bits at rdata_offset_q. Offsets 5-7 wrap using rdata_q.
  always_comb begin
    unique case (rdata_offset_q)
      3'b000:  rdata_w_raw = data_rdata_i[31: 0];
      3'b001:  rdata_w_raw = data_rdata_i[39: 8];
      3'b010:  rdata_w_raw = data_rdata_i[47:16];
      3'b011:  rdata_w_raw = data_rdata_i[55:24];
      3'b100:  rdata_w_raw = data_rdata_i[63:32];
      3'b101:  rdata_w_raw = {data_rdata_i[ 7:0], rdata_q[63:40]};
      3'b110:  rdata_w_raw = {data_rdata_i[15:0], rdata_q[63:48]};
      3'b111:  rdata_w_raw = {data_rdata_i[23:0], rdata_q[63:56]};
      default: rdata_w_raw = data_rdata_i[31: 0];
    endcase
  end

  // Doubleword extraction: must be 8-byte aligned (offset 0). Misaligned dword
  // accesses are reported via misaligned_err_d.
  assign rdata_d_raw = data_rdata_i;

  // Sign / zero extension to 64 bits.
  assign rdata_b_ext = data_sign_ext_q ? {{56{rdata_b_raw[7]}},  rdata_b_raw}
                                       : { 56'b0,               rdata_b_raw};
  assign rdata_h_ext = data_sign_ext_q ? {{48{rdata_h_raw[15]}}, rdata_h_raw}
                                       : { 48'b0,               rdata_h_raw};
  assign rdata_w_ext = data_sign_ext_q ? {{32{rdata_w_raw[31]}}, rdata_w_raw}
                                       : { 32'b0,               rdata_w_raw};
  assign rdata_d_ext = rdata_d_raw;

  // Final 64-bit load result
  always_comb begin
    unique case (data_type_q)
      2'b00:   data_rdata_ext = rdata_w_ext;
      2'b01:   data_rdata_ext = rdata_h_ext;
      2'b10:   data_rdata_ext = rdata_b_ext;
      2'b11:   data_rdata_ext = rdata_d_ext;
      default: data_rdata_ext = rdata_w_ext;
    endcase
  end

  assign data_rdata_full = data_rdata_ext;

  /////////////
  // LSU FSM //
  /////////////

  // Doubleword accesses must be 8-byte aligned on the native 64-bit bus; any
  // misalignment is reported as a fault so we never have to split a dword into
  // two transactions.
  assign dword_access     = (lsu_type_i == 2'b11);
  assign dword_misaligned = dword_access && (data_offset != 3'b000);

  // Word and half-word accesses can still straddle the 8-byte boundary; those
  // cases get split into two transactions just like the original LSU did
  // for 32-bit-bus 4-byte boundaries.
  assign split_misaligned_access =
      ((lsu_type_i == 2'b00) && data_offset[2] && (data_offset[1:0] != 2'b00)) ||
      ((lsu_type_i == 2'b01) && (data_offset == 3'b111));

  // FSM
  always_comb begin
    ls_fsm_ns       = ls_fsm_cs;

    data_req_o          = 1'b0;
    addr_incr_req_o     = 1'b0;
    handle_misaligned_d = handle_misaligned_q;
    pmp_err_d           = pmp_err_q;
    lsu_err_d           = lsu_err_q;
    misaligned_err_d    = 1'b0;

    addr_update         = 1'b0;
    ctrl_update         = 1'b0;
    rdata_update        = 1'b0;

    perf_load_o         = 1'b0;
    perf_store_o        = 1'b0;

    unique case (ls_fsm_cs)

      IDLE: begin
        pmp_err_d = 1'b0;
        if (lsu_req_i) begin
          pmp_err_d    = data_pmp_err_i;
          lsu_err_d    = 1'b0;
          perf_load_o  = ~lsu_we_i;
          perf_store_o = lsu_we_i;

          if (dword_misaligned) begin
            ctrl_update      = 1'b1;
            addr_update      = 1'b1;
            pmp_err_d        = 1'b0;
            misaligned_err_d = 1'b1;
            ls_fsm_ns        = IDLE;
          end else begin
            data_req_o = 1'b1;
          end

          if (!dword_misaligned && data_gnt_i) begin
            ctrl_update         = 1'b1;
            addr_update         = 1'b1;
            handle_misaligned_d = split_misaligned_access;
            ls_fsm_ns           = split_misaligned_access ? WAIT_RVALID_MIS : IDLE;
          end else if (!dword_misaligned) begin
            ls_fsm_ns           = split_misaligned_access ? WAIT_GNT_MIS    : WAIT_GNT;
          end
        end
      end

      WAIT_GNT_MIS: begin
        data_req_o = 1'b1;
        // data_pmp_err_i is valid during the address phase of a request. An error will block the
        // external request and so a data_gnt_i might never be signalled. The registered version
        // pmp_err_q is only updated for new address phases and so can be used in WAIT_GNT* and
        // WAIT_RVALID* states
        if (data_gnt_i || pmp_err_q) begin
          addr_update         = 1'b1;
          ctrl_update         = 1'b1;
          handle_misaligned_d = 1'b1;
          ls_fsm_ns           = WAIT_RVALID_MIS;
        end
      end

      WAIT_RVALID_MIS: begin
        // push out second request
        data_req_o = 1'b1;
        // tell ID/EX stage to update the address
        addr_incr_req_o = 1'b1;

        // first part rvalid is received, or gets a PMP error
        if (data_rvalid_i || pmp_err_q) begin
          // Update the PMP error for the second part
          pmp_err_d = data_pmp_err_i;
          // Record the error status of the first part
          lsu_err_d = data_err_i | pmp_err_q;
          // Capture the first rdata for loads
          rdata_update = ~data_we_q;
          // If already granted, wait for second rvalid
          ls_fsm_ns = data_gnt_i ? IDLE : WAIT_GNT;
          // Update the address for the second part, if no error
          addr_update = data_gnt_i & ~(data_err_i | pmp_err_q);
          // clear handle_misaligned if second request is granted
          handle_misaligned_d = ~data_gnt_i;
        end else begin
          // first part rvalid is NOT received
          if (data_gnt_i) begin
            // second grant is received
            ls_fsm_ns = WAIT_RVALID_MIS_GNTS_DONE;
            handle_misaligned_d = 1'b0;
          end
        end
      end

      WAIT_GNT: begin
        // tell ID/EX stage to update the address
        addr_incr_req_o = handle_misaligned_q;
        data_req_o      = 1'b1;
        if (data_gnt_i || pmp_err_q) begin
          ctrl_update         = 1'b1;
          // Update the address, unless there was an error
          addr_update         = ~lsu_err_q;
          ls_fsm_ns           = IDLE;
          handle_misaligned_d = 1'b0;
        end
      end

      WAIT_RVALID_MIS_GNTS_DONE: begin
        // tell ID/EX stage to update the address (to make sure the
        // second address can be captured correctly for mtval and PMP checking)
        addr_incr_req_o = 1'b1;
        // Wait for the first rvalid, second request is already granted
        if (data_rvalid_i) begin
          // Update the pmp error for the second part
          pmp_err_d = data_pmp_err_i;
          // The first part cannot see a PMP error in this state
          lsu_err_d = data_err_i;
          // Now we can update the address for the second part if no error
          addr_update = ~data_err_i;
          // Capture the first rdata for loads
          rdata_update = ~data_we_q;
          // Wait for second rvalid
          ls_fsm_ns = IDLE;
        end
      end

      default: begin
        ls_fsm_ns = IDLE;
      end
    endcase
  end

  // registers for FSM
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ls_fsm_cs           <= IDLE;
      handle_misaligned_q <= '0;
      pmp_err_q           <= '0;
      lsu_err_q           <= '0;
      misaligned_err_q    <= '0;
    end else begin
      ls_fsm_cs           <= ls_fsm_ns;
      handle_misaligned_q <= handle_misaligned_d;
      pmp_err_q           <= pmp_err_d;
      lsu_err_q           <= lsu_err_d;
      misaligned_err_q    <= misaligned_err_d;
    end
  end

  /////////////
  // Outputs //
  /////////////

  assign data_or_pmp_err    = lsu_err_q | data_err_i | pmp_err_q | misaligned_err_q;

  assign lsu_resp_valid_o = ((data_rvalid_i | pmp_err_q | misaligned_err_q) &
                             (ls_fsm_cs == IDLE));

  assign lsu_rdata_valid_o = ((ls_fsm_cs == IDLE) & data_rvalid_i &
                              ~data_or_pmp_err & ~data_we_q);

  // Legacy dword-split write back signal: with the native 64-bit bus every
  // load completes in one transaction, so the upper-half write-back is
  // never used. Tied to 0 for downstream compatibility.
  assign lsu_rdata_upper_o = 1'b0;

  // output to register file
  assign lsu_rdata_o = data_rdata_full;

  // output data address must be doubleword aligned for the 64-bit bus
  assign data_addr_w_aligned = {data_addr[63:3], 3'b000};

  // output to data interface
  assign data_addr_o   = data_addr_w_aligned;
  assign data_wdata_o  = data_wdata;
  assign data_we_o     = lsu_we_i;
  assign data_be_o     = data_be;

  // output to ID stage: mtval + AGU for misaligned transactions
  assign addr_last_o   = addr_last_q;

  // Signal a load or store error depending on the transaction type outstanding
  assign load_err_o    = data_or_pmp_err & ~data_we_q & lsu_resp_valid_o;
  assign store_err_o   = data_or_pmp_err &  data_we_q & lsu_resp_valid_o;

  assign busy_o = (ls_fsm_cs != IDLE);

  //////////
  // FCOV //
  //////////

  `DV_FCOV_SIGNAL(logic, ls_error_exception, (load_err_o | store_err_o) & ~pmp_err_q)
  `DV_FCOV_SIGNAL(logic, ls_pmp_exception, (load_err_o | store_err_o) & pmp_err_q)

  ////////////////
  // Assertions //
  ////////////////

  // Selectors must be known/valid.
  `ASSERT(CVE2DataTypeKnown, (lsu_req_i | busy_o) |-> !$isunknown(lsu_type_i))
  `ASSERT(CVE2DataOffsetKnown, (lsu_req_i | busy_o) |-> !$isunknown(data_offset))
  `ASSERT_KNOWN(CVE2RDataOffsetQKnown, rdata_offset_q)
  `ASSERT_KNOWN(CVE2DataTypeQKnown, data_type_q)
  `ASSERT(CVE2LsuStateValid, ls_fsm_cs inside {
      IDLE, WAIT_GNT_MIS, WAIT_RVALID_MIS, WAIT_GNT,
      WAIT_RVALID_MIS_GNTS_DONE})

  // Address must not contain X when request is sent.
  `ASSERT(CVE2DataAddrUnknown, data_req_o |-> !$isunknown(data_addr_o))

  // Address must be word aligned when request is sent.
  `ASSERT(CVE2DataAddrUnaligned, data_req_o |-> (data_addr_o[1:0] == 2'b00))

endmodule
