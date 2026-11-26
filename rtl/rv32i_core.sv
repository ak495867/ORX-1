module rv32i_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
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

  typedef enum logic [2:0] {FETCH, MEM_REQUEST, MEM_WAIT, WFI_WAIT, TRAP} state_t;
  state_t state;
  logic [31:0] pc;
  logic [31:0] regs [0:31];
  logic [31:0] mem_addr_q;
  logic [31:0] mem_wdata_q;
  logic [3:0] mem_wstrb_q;
  logic mem_write_q;
  logic [2:0] mem_funct3_q;
  logic [4:0] mem_rd_q;
  logic mem_is_load_q;
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
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic mem_misaligned;
  integer index;

  logic [31:0] csr_mstatus;
  logic [31:0] csr_mie;
  logic [31:0] csr_mtvec;
  logic [31:0] csr_mepc;
  logic [31:0] csr_mcause;
  logic [11:0] csr_addr;
  logic [31:0] csr_rdata;
  logic [31:0] csr_wdata;
  logic csr_write_en;
  logic irq_ext_en;
  logic irq_tim_en;
  logic irq_pending_active;

  assign imem_addr = pc;
  assign opcode = imem_rdata[6:0];
  assign rd = imem_rdata[11:7];
  assign funct3 = imem_rdata[14:12];
  assign rs1 = imem_rdata[19:15];
  assign rs2 = imem_rdata[24:20];
  assign funct7 = imem_rdata[31:25];
  assign csr_addr = imem_rdata[31:20];
  assign rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  assign rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];
  assign imm_i = {{20{imem_rdata[31]}}, imem_rdata[31:20]};
  assign imm_s = {{20{imem_rdata[31]}}, imem_rdata[31:25], imem_rdata[11:7]};
  assign imm_b = {{19{imem_rdata[31]}}, imem_rdata[31], imem_rdata[7], imem_rdata[30:25], imem_rdata[11:8], 1'b0};
  assign imm_u = {imem_rdata[31:12], 12'd0};
  assign imm_j = {{11{imem_rdata[31]}}, imem_rdata[31], imem_rdata[19:12], imem_rdata[20], imem_rdata[30:21], 1'b0};
  assign effective_addr = rs1_value + ((opcode == OP_LOAD) ? imm_i : imm_s);
  assign jal_target = pc + imm_j;
  assign jalr_target = (rs1_value + imm_i) & 32'hffff_fffe;
  assign mem_misaligned = ((funct3 == 3'b001 || funct3 == 3'b101) && effective_addr[0]) ||
                          ((funct3 == 3'b010) && (effective_addr[1:0] != 2'b00));

  assign req_valid = (state == MEM_REQUEST);
  assign req_write = mem_write_q;
  assign req_addr = mem_addr_q;
  assign req_wdata = mem_wdata_q;
  assign req_wstrb = mem_wstrb_q;

  assign irq_ext_en = irq_external && csr_mie[11];
  assign irq_tim_en = irq_timer && csr_mie[7];
  assign irq_pending_active = csr_mstatus[3] && (irq_ext_en || irq_tim_en);
  assign csr_write_en = (funct3[1:0] == 2'b01) || (rs1 != 5'd0);

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      12'h300: csr_rdata = csr_mstatus;
      12'h304: csr_rdata = csr_mie;
      12'h305: csr_rdata = csr_mtvec;
      12'h341: csr_rdata = csr_mepc;
      12'h342: csr_rdata = csr_mcause;
      12'h344: csr_rdata = {20'd0, irq_external, 3'd0, irq_timer, 7'd0};
      12'hc00: csr_rdata = perf_cycles;
      12'hc02: csr_rdata = perf_instructions;
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

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc <= RESET_PC;
      trap <= 1'b0;
      state <= FETCH;
      mem_addr_q <= 32'd0;
      mem_wdata_q <= 32'd0;
      mem_wstrb_q <= 4'd0;
      mem_write_q <= 1'b0;
      mem_funct3_q <= 3'd0;
      mem_rd_q <= 5'd0;
      mem_is_load_q <= 1'b0;
      perf_cycles <= 32'd0;
      perf_instructions <= 32'd0;
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
      for (index = 0; index < 32; index = index + 1) regs[index] <= 32'd0;
    end else begin
      perf_cycles <= perf_cycles + 32'd1;
      regs[0] <= 32'd0;
      case (state)
        FETCH: begin
          if (irq_pending_active) begin
            csr_mepc <= pc;
            csr_mcause <= irq_ext_en ? 32'h8000_000b : 32'h8000_0007;
            csr_mstatus[7] <= csr_mstatus[3];
            csr_mstatus[3] <= 1'b0;
            pc <= csr_mtvec;
            state <= FETCH;
          end else if (opcode == OP_LOAD || opcode == OP_STORE) begin
            if (mem_misaligned ||
                (opcode == OP_STORE && (funct3 == 3'b100 || funct3 == 3'b101 || funct3[2:0] > 3'b010)) ||
                (opcode == OP_LOAD && (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111))) begin
              if (mem_misaligned && csr_mtvec != 32'd0) begin
                csr_mepc <= pc;
                csr_mcause <= (opcode == OP_STORE) ? 32'd6 : 32'd4;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                pc <= csr_mtvec;
                state <= FETCH;
              end else begin
                trap <= 1'b1;
                state <= TRAP;
              end
            end else begin
              mem_addr_q <= effective_addr;
              mem_wdata_q <= rs2_value << (8 * effective_addr[1:0]);
              mem_write_q <= (opcode == OP_STORE);
              mem_is_load_q <= (opcode == OP_LOAD);
              mem_funct3_q <= funct3;
              mem_rd_q <= rd;
              state <= MEM_REQUEST;
              case (funct3)
                3'b000: mem_wstrb_q <= (opcode == OP_STORE) ? (4'b0001 << effective_addr[1:0]) : 4'b0000;
                3'b001: mem_wstrb_q <= (opcode == OP_STORE) ? (4'b0011 << effective_addr[1:0]) : 4'b0000;
                3'b010: mem_wstrb_q <= (opcode == OP_STORE) ? 4'b1111 : 4'b0000;
                default: mem_wstrb_q <= 4'b0000;
              endcase
            end
          end else begin
            perf_instructions <= perf_instructions + 32'd1;
            if (opcode == OP_BRANCH) perf_branches <= perf_branches + 32'd1;
            case (opcode)
              OP_LUI: begin if (rd != 5'd0) regs[rd] <= imm_u; pc <= pc + 32'd4; end
              OP_AUIPC: begin if (rd != 5'd0) regs[rd] <= pc + imm_u; pc <= pc + 32'd4; end
              OP_JAL: begin
                if (jal_target[1] != 1'b0) begin
                  if (csr_mtvec != 32'd0) begin
                    csr_mepc <= pc;
                    csr_mcause <= 32'd0;
                    csr_mstatus[7] <= csr_mstatus[3];
                    csr_mstatus[3] <= 1'b0;
                    pc <= csr_mtvec;
                  end else begin
                    trap <= 1'b1;
                    state <= TRAP;
                  end
                end else begin
                  if (rd != 5'd0) regs[rd] <= pc + 32'd4;
                  pc <= jal_target;
                end
              end
              OP_JALR: begin
                if (jalr_target[1] != 1'b0) begin
                  if (csr_mtvec != 32'd0) begin
                    csr_mepc <= pc;
                    csr_mcause <= 32'd0;
                    csr_mstatus[7] <= csr_mstatus[3];
                    csr_mstatus[3] <= 1'b0;
                    pc <= csr_mtvec;
                  end else begin
                    trap <= 1'b1;
                    state <= TRAP;
                  end
                end else begin
                  if (rd != 5'd0) regs[rd] <= pc + 32'd4;
                  pc <= jalr_target;
                end
              end
              OP_BRANCH: begin
                case (funct3)
                  3'b000: pc <= (rs1_value == rs2_value) ? pc + imm_b : pc + 32'd4;
                  3'b001: pc <= (rs1_value != rs2_value) ? pc + imm_b : pc + 32'd4;
                  3'b100: pc <= ($signed(rs1_value) < $signed(rs2_value)) ? pc + imm_b : pc + 32'd4;
                  3'b101: pc <= ($signed(rs1_value) >= $signed(rs2_value)) ? pc + imm_b : pc + 32'd4;
                  3'b110: pc <= (rs1_value < rs2_value) ? pc + imm_b : pc + 32'd4;
                  3'b111: pc <= (rs1_value >= rs2_value) ? pc + imm_b : pc + 32'd4;
                  default: begin pc <= pc + 32'd4; trap <= 1'b1; state <= TRAP; end
                endcase
              end
              OP_OPIMM: begin
                case (funct3)
                  3'b000: begin if (rd != 5'd0) regs[rd] <= rs1_value + imm_i; pc <= pc + 32'd4; end
                  3'b010: begin if (rd != 5'd0) regs[rd] <= ($signed(rs1_value) < $signed(imm_i)) ? 32'd1 : 32'd0; pc <= pc + 32'd4; end
                  3'b011: begin if (rd != 5'd0) regs[rd] <= (rs1_value < imm_i) ? 32'd1 : 32'd0; pc <= pc + 32'd4; end
                  3'b100: begin if (rd != 5'd0) regs[rd] <= rs1_value ^ imm_i; pc <= pc + 32'd4; end
                  3'b110: begin if (rd != 5'd0) regs[rd] <= rs1_value | imm_i; pc <= pc + 32'd4; end
                  3'b111: begin if (rd != 5'd0) regs[rd] <= rs1_value & imm_i; pc <= pc + 32'd4; end
                  3'b001: begin
                    if (funct7 == 7'b0000000) begin
                      if (rd != 5'd0) regs[rd] <= rs1_value << imem_rdata[24:20];
                      pc <= pc + 32'd4;
                    end else begin
                      trap <= 1'b1;
                      state <= TRAP;
                    end
                  end
                  3'b101: begin
                    if (funct7 == 7'b0000000) begin
                      if (rd != 5'd0) regs[rd] <= rs1_value >> imem_rdata[24:20];
                      pc <= pc + 32'd4;
                    end else if (funct7 == 7'b0100000) begin
                      if (rd != 5'd0) regs[rd] <= $signed(rs1_value) >>> imem_rdata[24:20];
                      pc <= pc + 32'd4;
                    end else begin
                      trap <= 1'b1;
                      state <= TRAP;
                    end
                  end
                  default: begin trap <= 1'b1; state <= TRAP; end
                endcase
              end
              OP_OP: begin
                case ({funct7, funct3})
                  10'b0000000_000: begin if (rd != 5'd0) regs[rd] <= rs1_value + rs2_value; pc <= pc + 32'd4; end
                  10'b0100000_000: begin if (rd != 5'd0) regs[rd] <= rs1_value - rs2_value; pc <= pc + 32'd4; end
                  10'b0000000_001: begin if (rd != 5'd0) regs[rd] <= rs1_value << rs2_value[4:0]; pc <= pc + 32'd4; end
                  10'b0000000_010: begin if (rd != 5'd0) regs[rd] <= ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0; pc <= pc + 32'd4; end
                  10'b0000000_011: begin if (rd != 5'd0) regs[rd] <= (rs1_value < rs2_value) ? 32'd1 : 32'd0; pc <= pc + 32'd4; end
                  10'b0000000_100: begin if (rd != 5'd0) regs[rd] <= rs1_value ^ rs2_value; pc <= pc + 32'd4; end
                  10'b0000000_101: begin if (rd != 5'd0) regs[rd] <= rs1_value >> rs2_value[4:0]; pc <= pc + 32'd4; end
                  10'b0100000_101: begin if (rd != 5'd0) regs[rd] <= $signed(rs1_value) >>> rs2_value[4:0]; pc <= pc + 32'd4; end
                  10'b0000000_110: begin if (rd != 5'd0) regs[rd] <= rs1_value | rs2_value; pc <= pc + 32'd4; end
                  10'b0000000_111: begin if (rd != 5'd0) regs[rd] <= rs1_value & rs2_value; pc <= pc + 32'd4; end
                  10'b0000001_000: begin if (rd != 5'd0) regs[rd] <= rs1_value * rs2_value; pc <= pc + 32'd4; end
                  10'b0000001_001: begin if (rd != 5'd0) regs[rd] <= 32'($signed({{32{rs1_value[31]}}, rs1_value}) * $signed({{32{rs2_value[31]}}, rs2_value}) >>> 32); pc <= pc + 32'd4; end
                  10'b0000001_010: begin if (rd != 5'd0) regs[rd] <= 32'($signed({{32{rs1_value[31]}}, rs1_value}) * $signed({32'd0, rs2_value}) >>> 32); pc <= pc + 32'd4; end
                  10'b0000001_011: begin if (rd != 5'd0) regs[rd] <= 32'(({32'd0, rs1_value} * {32'd0, rs2_value}) >> 32); pc <= pc + 32'd4; end
                  10'b0000001_100: begin if (rd != 5'd0) regs[rd] <= (rs2_value == 32'd0) ? 32'hffff_ffff : ((rs1_value == 32'h8000_0000 && rs2_value == 32'hffff_ffff) ? 32'h8000_0000 : 32'($signed(rs1_value) / $signed(rs2_value))); pc <= pc + 32'd4; end
                  10'b0000001_101: begin if (rd != 5'd0) regs[rd] <= (rs2_value == 32'd0) ? 32'hffff_ffff : (rs1_value / rs2_value); pc <= pc + 32'd4; end
                  10'b0000001_110: begin if (rd != 5'd0) regs[rd] <= (rs2_value == 32'd0) ? rs1_value : ((rs1_value == 32'h8000_0000 && rs2_value == 32'hffff_ffff) ? 32'd0 : 32'($signed(rs1_value) % $signed(rs2_value))); pc <= pc + 32'd4; end
                  10'b0000001_111: begin if (rd != 5'd0) regs[rd] <= (rs2_value == 32'd0) ? rs1_value : (rs1_value % rs2_value); pc <= pc + 32'd4; end
                  default: begin trap <= 1'b1; state <= TRAP; end
                endcase
              end
              OP_MISC_MEM: begin
                if (funct3 == 3'b000 || funct3 == 3'b001) begin
                  pc <= pc + 32'd4;
                end else begin
                  trap <= 1'b1;
                  state <= TRAP;
                end
              end
              OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                  if (imem_rdata == 32'h1050_0073) begin
                    pc <= pc + 32'd4;
                    state <= WFI_WAIT;
                  end else if (imem_rdata == 32'h3020_0073) begin
                    pc <= csr_mepc;
                    csr_mstatus[3] <= csr_mstatus[7];
                    csr_mstatus[7] <= 1'b1;
                  end else if (imem_rdata == 32'h0000_0073) begin
                    if (csr_mtvec != 32'd0) begin
                      csr_mepc <= pc;
                      csr_mcause <= 32'd11;
                      csr_mstatus[7] <= csr_mstatus[3];
                      csr_mstatus[3] <= 1'b0;
                      pc <= csr_mtvec;
                    end else begin
                      trap <= 1'b1;
                      state <= TRAP;
                    end
                  end else if (imem_rdata == 32'h0010_0073) begin
                    if (csr_mtvec != 32'd0) begin
                      csr_mepc <= pc;
                      csr_mcause <= 32'd3;
                      csr_mstatus[7] <= csr_mstatus[3];
                      csr_mstatus[3] <= 1'b0;
                      pc <= csr_mtvec;
                    end else begin
                      trap <= 1'b1;
                      state <= TRAP;
                    end
                  end else begin
                    trap <= 1'b1;
                    state <= TRAP;
                  end
                end else if (funct3[1:0] != 2'b00) begin
                  if (rd != 5'd0) regs[rd] <= csr_rdata;
                  if (csr_write_en) begin
                    case (csr_addr)
                      12'h300: csr_mstatus <= csr_wdata;
                      12'h304: csr_mie <= csr_wdata;
                      12'h305: csr_mtvec <= csr_wdata;
                      12'h341: csr_mepc <= csr_wdata;
                      12'h342: csr_mcause <= csr_wdata;
                      default: begin end
                    endcase
                  end
                  pc <= pc + 32'd4;
                end else begin
                  trap <= 1'b1;
                  state <= TRAP;
                end
              end
              default: begin trap <= 1'b1; state <= TRAP; end
            endcase
          end
        end
        MEM_REQUEST: begin
          if (req_ready) begin
            perf_bus_requests <= perf_bus_requests + 32'd1;
            if (rsp_valid) begin
              if (rsp_err) begin
                if (csr_mtvec != 32'd0) begin
                  csr_mepc <= pc;
                  csr_mcause <= mem_is_load_q ? 32'd5 : 32'd7;
                  csr_mstatus[7] <= csr_mstatus[3];
                  csr_mstatus[3] <= 1'b0;
                  pc <= csr_mtvec;
                  state <= FETCH;
                end else begin
                  trap <= 1'b1;
                  state <= TRAP;
                end
              end else begin
                perf_instructions <= perf_instructions + 32'd1;
                if (mem_is_load_q) perf_loads <= perf_loads + 32'd1;
                else perf_stores <= perf_stores + 32'd1;
                if (mem_is_load_q && mem_rd_q != 5'd0) regs[mem_rd_q] <= load_extend(rsp_rdata, mem_funct3_q, mem_addr_q[1:0]);
                pc <= pc + 32'd4;
                state <= FETCH;
              end
            end else state <= MEM_WAIT;
          end
        end
        MEM_WAIT: begin
          perf_wait_cycles <= perf_wait_cycles + 32'd1;
          if (rsp_valid) begin
            if (rsp_err) begin
              if (csr_mtvec != 32'd0) begin
                csr_mepc <= pc;
                csr_mcause <= mem_is_load_q ? 32'd5 : 32'd7;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                pc <= csr_mtvec;
                state <= FETCH;
              end else begin
                trap <= 1'b1;
                state <= TRAP;
              end
            end else begin
              perf_instructions <= perf_instructions + 32'd1;
              if (mem_is_load_q) perf_loads <= perf_loads + 32'd1;
              else perf_stores <= perf_stores + 32'd1;
              if (mem_is_load_q && mem_rd_q != 5'd0) regs[mem_rd_q] <= load_extend(rsp_rdata, mem_funct3_q, mem_addr_q[1:0]);
              pc <= pc + 32'd4;
              state <= FETCH;
            end
          end
        end
        WFI_WAIT: begin
          if (irq_ext_en || irq_tim_en) begin
            if (csr_mstatus[3]) begin
              csr_mepc <= pc;
              csr_mcause <= irq_ext_en ? 32'h8000_000b : 32'h8000_0007;
              csr_mstatus[7] <= csr_mstatus[3];
              csr_mstatus[3] <= 1'b0;
              pc <= csr_mtvec;
            end
            state <= FETCH;
          end else begin
            state <= WFI_WAIT;
          end
        end
        TRAP: begin state <= TRAP; end
        default: state <= TRAP;
      endcase
    end
  end
endmodule
