module rv32i_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter bit SYNC_IMEM = 1'b0
) (
  input logic clk,
  input logic reset,
  output logic [31:0] imem_addr,
  input logic [31:0] imem_rdata,
  output logic req_valid,
  input logic req_ready,
  output logic req_write,
  output logic [31:0] req_addr,
  output logic [31:0] req_wdata,
  output logic [3:0] req_wstrb,
  input logic rsp_valid,
  input logic [31:0] rsp_rdata,
  input logic rsp_err,
  output logic trap,
  output logic core_sleep,
  output logic [31:0] perf_cycles,
  output logic [31:0] perf_instructions,
  output logic [31:0] perf_loads,
  output logic [31:0] perf_stores,
  output logic [31:0] perf_branches,
  output logic [31:0] perf_bus_requests,
  output logic [31:0] perf_wait_cycles,
  input logic irq_external,
  input logic irq_timer
);
  localparam logic [6:0] OP_CUSTOM0  = 7'b0001011;
  localparam logic [6:0] OP_LUI      = 7'b0110111;
  localparam logic [6:0] OP_AUIPC    = 7'b0010111;
  localparam logic [6:0] OP_JAL      = 7'b1101111;
  localparam logic [6:0] OP_JALR     = 7'b1100111;
  localparam logic [6:0] OP_BRANCH   = 7'b1100011;
  localparam logic [6:0] OP_LOAD     = 7'b0000011;
  localparam logic [6:0] OP_STORE    = 7'b0100011;
  localparam logic [6:0] OP_OPIMM    = 7'b0010011;
  localparam logic [6:0] OP_OP       = 7'b0110011;
  localparam logic [6:0] OP_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM   = 7'b1110011;

  typedef enum logic [2:0] {RUN, MEM_WAIT, WFI_WAIT, DIV_WAIT, TRAP} state_t;
  state_t state;

  logic [31:0] fetch_pc;
  logic [31:0] if_pc;
  logic [31:0] if_insn;
  logic if_valid;
  logic if_pred_taken;
  logic [31:0] if_pred_target;
  logic [31:0] cur_pc;
  logic [31:0] cur_insn;
  logic cur_valid;
  logic hold_valid;
  logic [31:0] hold_insn;
  logic _unused_core;

  logic [7:0] btb_valid;
  logic [26:0] btb_tag [0:7];
  logic [31:0] btb_target [0:7];
  logic [2:0] btb_idx_f;
  logic btb_hit_f;
  logic [31:0] btb_tgt_f;
  logic [31:0] next_seq_fetch_pc;

  logic [31:0] regs [0:31];
  logic wait_pending;
  logic [31:0] mem_addr_q;
  logic [31:0] mem_wdata_q;
  logic [3:0] mem_wstrb_q;
  logic mem_write_q;
  logic [2:0] mem_funct3_q;
  logic [4:0] mem_rd_q;
  logic mem_is_load_q;
  logic [31:0] mem_pc_q;
  logic store_posted_stall;
  logic lsu_busy;
  logic lsu_completing;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rd;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_b;
  logic [31:0] imm_u;
  logic [31:0] imm_j;
  logic [31:0] effective_addr;
  logic [31:0] jal_target;
  logic [31:0] jalr_target;
  logic [31:0] branch_target;
  logic branch_taken;
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic mem_misaligned;
  integer index;

  logic [31:0] csr_mstatus;
  logic [31:0] csr_mie;
  logic [31:0] csr_mtvec;
  logic [31:0] csr_mepc;
  logic [31:0] csr_mcause;
  logic [63:0] cycle64;
  logic [63:0] instret64;
  logic [11:0] csr_addr;
  logic [31:0] csr_rdata;
  logic [31:0] csr_wdata;
  logic csr_write_en;
  logic irq_ext_en;
  logic irq_tim_en;
  logic irq_pending_active;

  logic mul_sign_a;
  logic mul_sign_b;
  logic signed [32:0] mul_a;
  logic signed [32:0] mul_b;
  logic signed [65:0] mul_prod;
  logic _unused_mul_hi;

  logic signed [15:0] dot_p0, dot_p1, dot_p2, dot_p3;
  logic signed [31:0] dot4_sum;
  logic signed [31:0] clip_sh;
  logic signed [31:0] clip_rel;
  logic [31:0] clip8_res;
  logic [31:0] pack4_res;

  logic [4:0] div_cnt;
  logic [31:0] div_quotient;
  logic [31:0] div_rem;
  logic [31:0] div_divisor;
  logic div_neg_res;
  logic div_is_rem;
  logic [4:0] div_rd;
  logic div_signed_op;
  logic [31:0] div_abs_rs1;
  logic [31:0] div_abs_rs2;
  logic [33:0] div_trial;
  logic [33:0] div_d1, div_d2, div_d3;
  logic [1:0] div_q_bits;
  logic [31:0] div_next_rem;
  logic [31:0] div_next_quot;
  logic [31:0] div_raw_res;
  logic [31:0] div_final_res;

  logic sync_exc_valid;
  logic [31:0] sync_exc_cause;
  logic lsu_err_trap;

  assign lsu_err_trap = lsu_completing && rsp_err;

  assign imem_addr = fetch_pc;
  assign btb_idx_f = fetch_pc[4:2];
  assign btb_hit_f = btb_valid[btb_idx_f] && (btb_tag[btb_idx_f] == fetch_pc[31:5]);
  assign btb_tgt_f = btb_target[btb_idx_f];
  assign next_seq_fetch_pc = btb_hit_f ? btb_tgt_f : (fetch_pc + 32'd4);

  assign cur_pc = if_pc;
  assign cur_insn = SYNC_IMEM ? (hold_valid ? hold_insn : imem_rdata) : if_insn;
  assign cur_valid = if_valid;
  assign _unused_core = &{1'b0, cur_valid, SYNC_IMEM};

  assign opcode = cur_insn[6:0];
  assign rd = cur_insn[11:7];
  assign funct3 = cur_insn[14:12];
  assign rs1 = cur_insn[19:15];
  assign rs2 = cur_insn[24:20];
  assign funct7 = cur_insn[31:25];
  assign csr_addr = cur_insn[31:20];
  assign rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  assign rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];
  assign imm_i = {{20{cur_insn[31]}}, cur_insn[31:20]};
  assign imm_s = {{20{cur_insn[31]}}, cur_insn[31:25], cur_insn[11:7]};
  assign imm_b = {{19{cur_insn[31]}}, cur_insn[31], cur_insn[7], cur_insn[30:25], cur_insn[11:8], 1'b0};
  assign imm_u = {cur_insn[31:12], 12'd0};
  assign imm_j = {{11{cur_insn[31]}}, cur_insn[31], cur_insn[19:12], cur_insn[20], cur_insn[30:21], 1'b0};
  assign effective_addr = rs1_value + ((opcode == OP_LOAD) ? imm_i : imm_s);
  assign jal_target = cur_pc + imm_j;
  assign jalr_target = (rs1_value + imm_i) & 32'hffff_fffe;
  assign branch_target = cur_pc + imm_b;
  assign mem_misaligned = ((funct3 == 3'b001 || funct3 == 3'b101) && effective_addr[0]) ||
                          ((funct3 == 3'b010) && (effective_addr[1:0] != 2'b00));

  always_comb begin
    case (funct3)
      3'b000: branch_taken = (rs1_value == rs2_value);
      3'b001: branch_taken = (rs1_value != rs2_value);
      3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value));
      3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));
      3'b110: branch_taken = (rs1_value < rs2_value);
      3'b111: branch_taken = (rs1_value >= rs2_value);
      default: branch_taken = 1'b0;
    endcase
  end

  assign lsu_busy = req_valid || wait_pending;
  assign lsu_completing = (req_valid && req_ready && rsp_valid) || (wait_pending && rsp_valid);
  assign store_posted_stall = lsu_busy && !lsu_completing;

  assign req_write = mem_write_q;
  assign req_addr = mem_addr_q;
  assign req_wdata = mem_wdata_q;
  assign req_wstrb = mem_wstrb_q;
  assign trap = (state == TRAP);
  assign core_sleep = (state == WFI_WAIT);

  assign irq_ext_en = irq_external && csr_mie[11];
  assign irq_tim_en = irq_timer && csr_mie[7];
  assign irq_pending_active = csr_mstatus[3] && (irq_ext_en || irq_tim_en);
  assign csr_write_en = (funct3[1:0] == 2'b01) || (rs1 != 5'd0);

  assign mul_sign_a = (funct3 != 3'b011);
  assign mul_sign_b = (funct3 == 3'b000) || (funct3 == 3'b001);
  assign mul_a = $signed({mul_sign_a & rs1_value[31], rs1_value});
  assign mul_b = $signed({mul_sign_b & rs2_value[31], rs2_value});
  assign mul_prod = mul_a * mul_b;
  assign _unused_mul_hi = &{1'b0, mul_prod[65:64]};

  assign dot_p0 = $signed(rs1_value[7:0])   * $signed(rs2_value[7:0]);
  assign dot_p1 = $signed(rs1_value[15:8])  * $signed(rs2_value[15:8]);
  assign dot_p2 = $signed(rs1_value[23:16]) * $signed(rs2_value[23:16]);
  assign dot_p3 = $signed(rs1_value[31:24]) * $signed(rs2_value[31:24]);
  assign dot4_sum = $signed({{16{dot_p0[15]}}, dot_p0}) +
                    $signed({{16{dot_p1[15]}}, dot_p1}) +
                    $signed({{16{dot_p2[15]}}, dot_p2}) +
                    $signed({{16{dot_p3[15]}}, dot_p3});

  assign clip_sh = $signed(rs1_value) >>> rs2_value[4:0];
  assign clip_rel = (rs2_value[5] && (clip_sh < 32'sd0)) ? 32'sd0 : clip_sh;
  assign clip8_res = (clip_rel > 32'sd127) ? 32'h0000_007f :
                     ((clip_rel < -32'sd128) ? 32'hffff_ff80 : clip_rel);
  assign pack4_res = {rs2_value[7:0], rs1_value[31:8]};

  assign div_signed_op = !funct3[0];
  assign div_abs_rs1 = (div_signed_op && rs1_value[31]) ? (~rs1_value + 32'd1) : rs1_value;
  assign div_abs_rs2 = (div_signed_op && rs2_value[31]) ? (~rs2_value + 32'd1) : rs2_value;
  assign div_trial = {div_rem, div_quotient[31:30]};
  assign div_d1 = {2'b00, div_divisor};
  assign div_d2 = {1'b0, div_divisor, 1'b0};
  assign div_d3 = div_d2 + div_d1;

  always_comb begin
    if (div_trial >= div_d3) begin
      div_q_bits = 2'b11;
      div_next_rem = div_trial[31:0] - div_d3[31:0];
    end else if (div_trial >= div_d2) begin
      div_q_bits = 2'b10;
      div_next_rem = div_trial[31:0] - div_d2[31:0];
    end else if (div_trial >= div_d1) begin
      div_q_bits = 2'b01;
      div_next_rem = div_trial[31:0] - div_d1[31:0];
    end else begin
      div_q_bits = 2'b00;
      div_next_rem = div_trial[31:0];
    end
  end

  assign div_next_quot = {div_quotient[29:0], div_q_bits};
  assign div_raw_res = div_is_rem ? div_next_rem : div_next_quot;
  assign div_final_res = div_neg_res ? (~div_raw_res + 32'd1) : div_raw_res;

  assign perf_cycles = cycle64[31:0];
  assign perf_instructions = instret64[31:0];

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      12'h300: csr_rdata = csr_mstatus;
      12'h301: csr_rdata = 32'h4000_1100;
      12'h304: csr_rdata = csr_mie;
      12'h305: csr_rdata = csr_mtvec;
      12'h341: csr_rdata = csr_mepc;
      12'h342: csr_rdata = csr_mcause;
      12'h344: csr_rdata = {20'd0, irq_external, 3'd0, irq_timer, 7'd0};
      12'hb00,
      12'hc00: csr_rdata = cycle64[31:0];
      12'hb02,
      12'hc02: csr_rdata = instret64[31:0];
      12'hb80,
      12'hc80: csr_rdata = cycle64[63:32];
      12'hb82,
      12'hc82: csr_rdata = instret64[63:32];
      12'hf14: csr_rdata = 32'd0;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_comb begin
    case (funct3[1:0])
      2'b01: csr_wdata = (funct3[2]) ? {27'd0, rs1} : rs1_value;
      2'b10: csr_wdata = csr_rdata | ((funct3[2]) ? {27'd0, rs1} : rs1_value);
      2'b11: csr_wdata = csr_rdata & ~((funct3[2]) ? {27'd0, rs1} : rs1_value);
      default: csr_wdata = csr_rdata;
    endcase
  end

  function automatic logic [31:0] load_extend(input logic [31:0] value, input logic [2:0] load_funct3, input logic [1:0] byte_offset);
    logic [31:0] shifted;
    shifted = value >> (8 * byte_offset);
    case (load_funct3)
      3'b000: load_extend = {{24{shifted[7]}}, shifted[7:0]};
      3'b001: load_extend = {{16{shifted[15]}}, shifted[15:0]};
      3'b010: load_extend = shifted;
      3'b100: load_extend = {24'd0, shifted[7:0]};
      3'b101: load_extend = {16'd0, shifted[15:0]};
      default: load_extend = 32'd0;
    endcase
  endfunction

  always_comb begin
    sync_exc_valid = 1'b0;
    sync_exc_cause = 32'd2;
    case (opcode)
      OP_LUI,
      OP_AUIPC: begin end
      OP_CUSTOM0: begin
        if (funct7 != 7'b0000000 || (funct3 != 3'b000 && funct3 != 3'b001 && funct3 != 3'b010)) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      OP_JAL: begin
        if (jal_target[1] != 1'b0) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd0;
        end
      end
      OP_JALR: begin
        if (funct3 != 3'b000) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end else if (jalr_target[1] != 1'b0) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd0;
        end
      end
      OP_BRANCH: begin
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      OP_LOAD: begin
        if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end else if (mem_misaligned) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd4;
        end
      end
      OP_STORE: begin
        if (funct3 > 3'b010) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end else if (mem_misaligned) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd6;
        end
      end
      OP_OPIMM: begin
        if ((funct3 == 3'b001 && funct7 != 7'b0000000) ||
            (funct3 == 3'b101 && funct7 != 7'b0000000 && funct7 != 7'b0100000)) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      OP_OP: begin
        if (!(funct7 == 7'b0000000 ||
              funct7 == 7'b0000001 ||
              (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)))) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      OP_MISC_MEM: begin
        if (funct3 != 3'b000 && funct3 != 3'b001) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      OP_SYSTEM: begin
        if (funct3 == 3'b000) begin
          if (cur_insn == 32'h0000_0073) begin
            sync_exc_valid = 1'b1;
            sync_exc_cause = 32'd11;
          end else if (cur_insn == 32'h0010_0073) begin
            sync_exc_valid = 1'b1;
            sync_exc_cause = 32'd3;
          end else if (cur_insn != 32'h1050_0073 && cur_insn != 32'h3020_0073) begin
            sync_exc_valid = 1'b1;
            sync_exc_cause = 32'd2;
          end
        end else if (funct3 == 3'b100 || (csr_write_en && csr_addr[11:10] == 2'b11)) begin
          sync_exc_valid = 1'b1;
          sync_exc_cause = 32'd2;
        end
      end
      default: begin
        sync_exc_valid = 1'b1;
        sync_exc_cause = 32'd2;
      end
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= RUN;
      fetch_pc <= RESET_PC;
      if_pc <= RESET_PC;
      if_insn <= 32'h0000_0013;
      if_valid <= 1'b0;
      if_pred_taken <= 1'b0;
      if_pred_target <= 32'd0;
      hold_valid <= 1'b0;
      hold_insn <= 32'h0000_0013;
      btb_valid <= 8'd0;
      for (index = 0; index < 8; index = index + 1) begin
        btb_tag[index] <= 27'd0;
        btb_target[index] <= 32'd0;
      end
      req_valid <= 1'b0;
      wait_pending <= 1'b0;
      mem_addr_q <= 32'd0;
      mem_wdata_q <= 32'd0;
      mem_wstrb_q <= 4'd0;
      mem_write_q <= 1'b0;
      mem_funct3_q <= 3'd0;
      mem_rd_q <= 5'd0;
      mem_is_load_q <= 1'b0;
      mem_pc_q <= RESET_PC;
      cycle64 <= 64'd0;
      instret64 <= 64'd0;
      perf_loads <= 32'd0;
      perf_stores <= 32'd0;
      perf_branches <= 32'd0;
      perf_bus_requests <= 32'd0;
      perf_wait_cycles <= 32'd0;
      csr_mstatus <= 32'd0;
      csr_mie <= 32'd0;
      csr_mtvec <= 32'd0;
      csr_mepc <= 32'd0;
      csr_mcause <= 32'd0;
      div_cnt <= 5'd0;
      div_quotient <= 32'd0;
      div_rem <= 32'd0;
      div_divisor <= 32'd0;
      div_neg_res <= 1'b0;
      div_is_rem <= 1'b0;
      div_rd <= 5'd0;
      for (index = 0; index < 32; index = index + 1) regs[index] <= 32'd0;
    end else begin
      cycle64 <= cycle64 + 64'd1;
      regs[0] <= 32'd0;

      if (wait_pending) begin
        perf_wait_cycles <= perf_wait_cycles + 32'd1;
      end

      if (req_valid && req_ready) begin
        perf_bus_requests <= perf_bus_requests + 32'd1;
        if (rsp_valid) begin
          req_valid <= 1'b0;
          wait_pending <= 1'b0;
          if (!rsp_err) begin
            if (mem_is_load_q) perf_loads <= perf_loads + 32'd1;
            else perf_stores <= perf_stores + 32'd1;
            if (mem_is_load_q && mem_rd_q != 5'd0) begin
              regs[mem_rd_q] <= load_extend(rsp_rdata, mem_funct3_q, mem_addr_q[1:0]);
            end
          end
        end else begin
          req_valid <= 1'b0;
          wait_pending <= 1'b1;
        end
      end else if (wait_pending && rsp_valid) begin
        wait_pending <= 1'b0;
        if (!rsp_err) begin
          if (mem_is_load_q) perf_loads <= perf_loads + 32'd1;
          else perf_stores <= perf_stores + 32'd1;
          if (mem_is_load_q && mem_rd_q != 5'd0) begin
            regs[mem_rd_q] <= load_extend(rsp_rdata, mem_funct3_q, mem_addr_q[1:0]);
          end
        end
      end

      if (lsu_err_trap && state != TRAP) begin
        if (csr_mtvec != 32'd0) begin
          csr_mepc <= mem_pc_q;
          csr_mcause <= mem_is_load_q ? 32'd5 : 32'd7;
          csr_mstatus[7] <= csr_mstatus[3];
          csr_mstatus[3] <= 1'b0;
          fetch_pc <= csr_mtvec;
          if_valid <= 1'b0;
          if_pred_taken <= 1'b0;
          hold_valid <= 1'b0;
          state <= RUN;
        end else begin
          if_valid <= 1'b0;
          hold_valid <= 1'b0;
          state <= TRAP;
        end
      end else begin
        case (state)
          RUN: begin
            if (!cur_valid) begin
              if (irq_pending_active && !store_posted_stall) begin
                csr_mepc <= fetch_pc;
                csr_mcause <= irq_ext_en ? 32'h8000_000b : 32'h8000_0007;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                fetch_pc <= csr_mtvec;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
                hold_valid <= 1'b0;
              end else begin
                if_valid <= 1'b1;
                hold_valid <= 1'b0;
                if_pc <= fetch_pc;
                if (!SYNC_IMEM) if_insn <= imem_rdata;
                fetch_pc <= next_seq_fetch_pc;
                if_pred_taken <= btb_hit_f;
                if_pred_target <= btb_tgt_f;
              end
            end else if (irq_pending_active) begin
              if (store_posted_stall) begin
                if (SYNC_IMEM && !hold_valid) begin
                  hold_valid <= 1'b1;
                  hold_insn <= imem_rdata;
                end
              end else begin
                csr_mepc <= cur_pc;
                csr_mcause <= irq_ext_en ? 32'h8000_000b : 32'h8000_0007;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                fetch_pc <= csr_mtvec;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
                hold_valid <= 1'b0;
              end
            end else if (sync_exc_valid) begin
              if (store_posted_stall) begin
                if (SYNC_IMEM && !hold_valid) begin
                  hold_valid <= 1'b1;
                  hold_insn <= imem_rdata;
                end
              end else if (csr_mtvec != 32'd0) begin
                hold_valid <= 1'b0;
                csr_mepc <= cur_pc;
                csr_mcause <= sync_exc_cause;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                fetch_pc <= csr_mtvec;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
              end else begin
                if_valid <= 1'b0;
                hold_valid <= 1'b0;
                state <= TRAP;
              end
            end else if (opcode == OP_LOAD) begin
              if (store_posted_stall) begin
                if (SYNC_IMEM && !hold_valid) begin
                  hold_valid <= 1'b1;
                  hold_insn <= imem_rdata;
                end
              end else begin
                hold_valid <= 1'b0;
                req_valid <= 1'b1;
                mem_addr_q <= effective_addr;
                mem_wdata_q <= 32'd0;
                mem_wstrb_q <= 4'b0000;
                mem_write_q <= 1'b0;
                mem_is_load_q <= 1'b1;
                mem_funct3_q <= funct3;
                mem_rd_q <= rd;
                mem_pc_q <= cur_pc;
                state <= MEM_WAIT;
              end
            end else if (opcode == OP_STORE) begin
              if (store_posted_stall) begin
                if (SYNC_IMEM && !hold_valid) begin
                  hold_valid <= 1'b1;
                  hold_insn <= imem_rdata;
                end
              end else begin
                hold_valid <= 1'b0;
                req_valid <= 1'b1;
                mem_addr_q <= effective_addr;
                mem_wdata_q <= rs2_value << (8 * effective_addr[1:0]);
                mem_write_q <= 1'b1;
                mem_is_load_q <= 1'b0;
                mem_funct3_q <= funct3;
                mem_rd_q <= 5'd0;
                mem_pc_q <= cur_pc;
                case (funct3)
                  3'b000: mem_wstrb_q <= 4'b0001 << effective_addr[1:0];
                  3'b001: mem_wstrb_q <= 4'b0011 << effective_addr[1:0];
                  default: mem_wstrb_q <= 4'b1111;
                endcase
                instret64 <= instret64 + 64'd1;
                if (if_pred_taken) begin
                  fetch_pc <= cur_pc + 32'd4;
                  if_valid <= 1'b0;
                  if_pred_taken <= 1'b0;
                end else begin
                  if_valid <= 1'b1;
                  if_pc <= fetch_pc;
                  if (!SYNC_IMEM) if_insn <= imem_rdata;
                  fetch_pc <= next_seq_fetch_pc;
                  if_pred_taken <= btb_hit_f;
                  if_pred_target <= btb_tgt_f;
                end
              end
            end else if (opcode == OP_OP && funct7 == 7'b0000001 && funct3[2] == 1'b1) begin
              if (rs2_value == 32'd0) begin
                if (rd != 5'd0) regs[rd] <= funct3[1] ? rs1_value : 32'hffff_ffff;
                instret64 <= instret64 + 64'd1;
                if (if_pred_taken) begin
                  fetch_pc <= cur_pc + 32'd4;
                  if_valid <= 1'b0;
                  if_pred_taken <= 1'b0;
                end else begin
                  if_valid <= 1'b1;
                  if_pc <= fetch_pc;
                  if (!SYNC_IMEM) if_insn <= imem_rdata;
                  fetch_pc <= next_seq_fetch_pc;
                  if_pred_taken <= btb_hit_f;
                  if_pred_target <= btb_tgt_f;
                end
              end else if (!funct3[0] && rs1_value == 32'h8000_0000 && rs2_value == 32'hffff_ffff) begin
                if (rd != 5'd0) regs[rd] <= funct3[1] ? 32'd0 : 32'h8000_0000;
                instret64 <= instret64 + 64'd1;
                if (if_pred_taken) begin
                  fetch_pc <= cur_pc + 32'd4;
                  if_valid <= 1'b0;
                  if_pred_taken <= 1'b0;
                end else begin
                  if_valid <= 1'b1;
                  if_pc <= fetch_pc;
                  if (!SYNC_IMEM) if_insn <= imem_rdata;
                  fetch_pc <= next_seq_fetch_pc;
                  if_pred_taken <= btb_hit_f;
                  if_pred_target <= btb_tgt_f;
                end
              end else begin
                if (div_abs_rs1[31:8] == 24'd0) begin
                  div_quotient <= {div_abs_rs1[7:0], 24'd0};
                  div_cnt <= 5'd3;
                end else if (div_abs_rs1[31:16] == 16'd0) begin
                  div_quotient <= {div_abs_rs1[15:0], 16'd0};
                  div_cnt <= 5'd7;
                end else if (div_abs_rs1[31:24] == 8'd0) begin
                  div_quotient <= {div_abs_rs1[23:0], 8'd0};
                  div_cnt <= 5'd11;
                end else begin
                  div_quotient <= div_abs_rs1;
                  div_cnt <= 5'd15;
                end
                div_divisor <= div_abs_rs2;
                div_rem <= 32'd0;
                div_is_rem <= funct3[1];
                div_neg_res <= div_signed_op && (funct3[1] ? rs1_value[31] : (rs1_value[31] ^ rs2_value[31]));
                div_rd <= rd;
                hold_valid <= 1'b0;
                state <= DIV_WAIT;
              end
            end else if (opcode == OP_SYSTEM && funct3 == 3'b000 && store_posted_stall) begin
              if (SYNC_IMEM && !hold_valid) begin
                hold_valid <= 1'b1;
                hold_insn <= imem_rdata;
              end
            end else begin
              hold_valid <= 1'b0;
              instret64 <= instret64 + 64'd1;
              if (opcode == OP_BRANCH) perf_branches <= perf_branches + 32'd1;
              if (opcode == OP_SYSTEM && funct3 == 3'b000 && cur_insn == 32'h1050_0073) begin
                fetch_pc <= cur_pc + 32'd4;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
                state <= WFI_WAIT;
              end else if (opcode == OP_SYSTEM && funct3 == 3'b000) begin
                fetch_pc <= csr_mepc;
                csr_mstatus[3] <= csr_mstatus[7];
                csr_mstatus[7] <= 1'b1;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
              end else if (opcode == OP_JAL) begin
                if (rd != 5'd0) regs[rd] <= cur_pc + 32'd4;
                btb_valid[cur_pc[4:2]] <= 1'b1;
                btb_tag[cur_pc[4:2]] <= cur_pc[31:5];
                btb_target[cur_pc[4:2]] <= jal_target;
                if (if_pred_taken && if_pred_target == jal_target) begin
                  if_valid <= 1'b1;
                  if_pc <= fetch_pc;
                  if (!SYNC_IMEM) if_insn <= imem_rdata;
                  fetch_pc <= next_seq_fetch_pc;
                  if_pred_taken <= btb_hit_f;
                  if_pred_target <= btb_tgt_f;
                end else begin
                  fetch_pc <= jal_target;
                  if_valid <= 1'b0;
                  if_pred_taken <= 1'b0;
                end
              end else if (opcode == OP_JALR) begin
                if (rd != 5'd0) regs[rd] <= cur_pc + 32'd4;
                fetch_pc <= jalr_target;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
              end else if (opcode == OP_BRANCH) begin
                if (branch_taken) begin
                  btb_valid[cur_pc[4:2]] <= 1'b1;
                  btb_tag[cur_pc[4:2]] <= cur_pc[31:5];
                  btb_target[cur_pc[4:2]] <= branch_target;
                  if (if_pred_taken && if_pred_target == branch_target) begin
                    if_valid <= 1'b1;
                    if_pc <= fetch_pc;
                    if (!SYNC_IMEM) if_insn <= imem_rdata;
                    fetch_pc <= next_seq_fetch_pc;
                    if_pred_taken <= btb_hit_f;
                    if_pred_target <= btb_tgt_f;
                  end else begin
                    fetch_pc <= branch_target;
                    if_valid <= 1'b0;
                    if_pred_taken <= 1'b0;
                  end
                end else begin
                  if (btb_valid[cur_pc[4:2]] && btb_tag[cur_pc[4:2]] == cur_pc[31:5]) begin
                    btb_valid[cur_pc[4:2]] <= 1'b0;
                  end
                  if (if_pred_taken) begin
                    fetch_pc <= cur_pc + 32'd4;
                    if_valid <= 1'b0;
                    if_pred_taken <= 1'b0;
                  end else begin
                    if_valid <= 1'b1;
                    if_pc <= fetch_pc;
                    if (!SYNC_IMEM) if_insn <= imem_rdata;
                    fetch_pc <= next_seq_fetch_pc;
                    if_pred_taken <= btb_hit_f;
                    if_pred_target <= btb_tgt_f;
                  end
                end
              end else begin
                case (opcode)
                  OP_LUI: begin if (rd != 5'd0) regs[rd] <= imm_u; end
                  OP_AUIPC: begin if (rd != 5'd0) regs[rd] <= cur_pc + imm_u; end
                  OP_CUSTOM0: begin
                    if (rd != 5'd0) begin
                      case (funct3)
                        3'b000: regs[rd] <= dot4_sum;
                        3'b001: regs[rd] <= clip8_res;
                        default: regs[rd] <= pack4_res;
                      endcase
                    end
                  end
                  OP_OPIMM: begin
                    case (funct3)
                      3'b000: if (rd != 5'd0) regs[rd] <= rs1_value + imm_i;
                      3'b010: if (rd != 5'd0) regs[rd] <= ($signed(rs1_value) < $signed(imm_i)) ? 32'd1 : 32'd0;
                      3'b011: if (rd != 5'd0) regs[rd] <= (rs1_value < imm_i) ? 32'd1 : 32'd0;
                      3'b100: if (rd != 5'd0) regs[rd] <= rs1_value ^ imm_i;
                      3'b110: if (rd != 5'd0) regs[rd] <= rs1_value | imm_i;
                      3'b111: if (rd != 5'd0) regs[rd] <= rs1_value & imm_i;
                      3'b001: if (rd != 5'd0) regs[rd] <= rs1_value << cur_insn[24:20];
                      default: begin
                        if (funct7 == 7'b0100000) begin
                          if (rd != 5'd0) regs[rd] <= $signed(rs1_value) >>> cur_insn[24:20];
                        end else begin
                          if (rd != 5'd0) regs[rd] <= rs1_value >> cur_insn[24:20];
                        end
                      end
                    endcase
                  end
                  OP_OP: begin
                    case ({funct7, funct3})
                      10'b0000000_000: if (rd != 5'd0) regs[rd] <= rs1_value + rs2_value;
                      10'b0100000_000: if (rd != 5'd0) regs[rd] <= rs1_value - rs2_value;
                      10'b0000000_001: if (rd != 5'd0) regs[rd] <= rs1_value << rs2_value[4:0];
                      10'b0000000_010: if (rd != 5'd0) regs[rd] <= ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0;
                      10'b0000000_011: if (rd != 5'd0) regs[rd] <= (rs1_value < rs2_value) ? 32'd1 : 32'd0;
                      10'b0000000_100: if (rd != 5'd0) regs[rd] <= rs1_value ^ rs2_value;
                      10'b0000000_101: if (rd != 5'd0) regs[rd] <= rs1_value >> rs2_value[4:0];
                      10'b0100000_101: if (rd != 5'd0) regs[rd] <= $signed(rs1_value) >>> rs2_value[4:0];
                      10'b0000000_110: if (rd != 5'd0) regs[rd] <= rs1_value | rs2_value;
                      10'b0000000_111: if (rd != 5'd0) regs[rd] <= rs1_value & rs2_value;
                      10'b0000001_000: if (rd != 5'd0) regs[rd] <= mul_prod[31:0];
                      10'b0000001_001,
                      10'b0000001_010,
                      10'b0000001_011: if (rd != 5'd0) regs[rd] <= mul_prod[63:32];
                      default: begin end
                    endcase
                  end
                  OP_MISC_MEM: begin end
                  OP_SYSTEM: begin
                    if (rd != 5'd0) regs[rd] <= csr_rdata;
                    if (csr_write_en) begin
                      case (csr_addr)
                        12'h300: csr_mstatus <= csr_wdata;
                        12'h304: csr_mie <= csr_wdata;
                        12'h305: csr_mtvec <= {csr_wdata[31:2], 2'b00};
                        12'h341: csr_mepc <= {csr_wdata[31:2], 2'b00};
                        12'h342: csr_mcause <= csr_wdata;
                        default: begin end
                      endcase
                    end
                  end
                  default: begin end
                endcase
                if (if_pred_taken) begin
                  fetch_pc <= cur_pc + 32'd4;
                  if_valid <= 1'b0;
                  if_pred_taken <= 1'b0;
                end else begin
                  if_valid <= 1'b1;
                  if_pc <= fetch_pc;
                  if (!SYNC_IMEM) if_insn <= imem_rdata;
                  fetch_pc <= next_seq_fetch_pc;
                  if_pred_taken <= btb_hit_f;
                  if_pred_target <= btb_tgt_f;
                end
              end
            end
          end
          DIV_WAIT: begin
            if (div_cnt == 5'd0) begin
              if (div_rd != 5'd0) regs[div_rd] <= div_final_res;
              instret64 <= instret64 + 64'd1;
              if (if_pred_taken) begin
                fetch_pc <= cur_pc + 32'd4;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
              end else begin
                if_valid <= 1'b1;
                if_pc <= fetch_pc;
                if (!SYNC_IMEM) if_insn <= imem_rdata;
                fetch_pc <= next_seq_fetch_pc;
                if_pred_taken <= btb_hit_f;
                if_pred_target <= btb_tgt_f;
              end
              state <= RUN;
            end else begin
              div_rem <= div_next_rem;
              div_quotient <= div_next_quot;
              div_cnt <= div_cnt - 5'd1;
            end
          end
          MEM_WAIT: begin
            if (lsu_completing) begin
              instret64 <= instret64 + 64'd1;
              if (if_pred_taken) begin
                fetch_pc <= cur_pc + 32'd4;
                if_valid <= 1'b0;
                if_pred_taken <= 1'b0;
              end else begin
                if_valid <= 1'b1;
                if_pc <= fetch_pc;
                if (!SYNC_IMEM) if_insn <= imem_rdata;
                fetch_pc <= next_seq_fetch_pc;
                if_pred_taken <= btb_hit_f;
                if_pred_target <= btb_tgt_f;
              end
              state <= RUN;
            end
          end
          WFI_WAIT: begin
            if (irq_ext_en || irq_tim_en) begin
              if (csr_mstatus[3]) begin
                csr_mepc <= fetch_pc;
                csr_mcause <= irq_ext_en ? 32'h8000_000b : 32'h8000_0007;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                fetch_pc <= csr_mtvec;
                if_valid <= 1'b0;
              end
              state <= RUN;
            end else begin
              state <= WFI_WAIT;
            end
          end
          TRAP: begin state <= TRAP; end
          default: state <= TRAP;
        endcase
      end
    end
  end

`ifdef FORMAL
  always @(posedge clk) begin
    if (!reset) begin
      assert (!(req_valid && wait_pending));
      assert ((state != MEM_WAIT) || (req_valid || wait_pending));
      assert ((state != TRAP) || (!req_valid && !wait_pending));
      assert ((state != WFI_WAIT) || (!req_valid && !wait_pending));
    end
  end
`endif
endmodule
