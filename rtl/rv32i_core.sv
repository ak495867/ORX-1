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
  input logic irq_external
);
  localparam logic [6:0] OP_LUI = 7'b0110111;
  localparam logic [6:0] OP_AUIPC = 7'b0010111;
  localparam logic [6:0] OP_JAL = 7'b1101111;
  localparam logic [6:0] OP_JALR = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD = 7'b0000011;
  localparam logic [6:0] OP_STORE = 7'b0100011;
  localparam logic [6:0] OP_OPIMM = 7'b0010011;
  localparam logic [6:0] OP_OP = 7'b0110011;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

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
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  integer index;

  assign imem_addr = pc;
  assign opcode = imem_rdata[6:0];
  assign rd = imem_rdata[11:7];
  assign funct3 = imem_rdata[14:12];
  assign rs1 = imem_rdata[19:15];
  assign rs2 = imem_rdata[24:20];
  assign funct7 = imem_rdata[31:25];
  assign rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  assign rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];
  assign imm_i = {{20{imem_rdata[31]}}, imem_rdata[31:20]};
  assign imm_s = {{20{imem_rdata[31]}}, imem_rdata[31:25], imem_rdata[11:7]};
  assign imm_b = {{19{imem_rdata[31]}}, imem_rdata[31], imem_rdata[7], imem_rdata[30:25], imem_rdata[11:8], 1'b0};
  assign imm_u = {imem_rdata[31:12], 12'd0};
  assign imm_j = {{11{imem_rdata[31]}}, imem_rdata[31], imem_rdata[19:12], imem_rdata[20], imem_rdata[30:21], 1'b0};
  assign effective_addr = rs1_value + ((opcode == OP_LOAD) ? imm_i : imm_s);

  assign req_valid = (state == MEM_REQUEST);
  assign req_write = mem_write_q;
  assign req_addr = mem_addr_q;
  assign req_wdata = mem_wdata_q;
  assign req_wstrb = mem_wstrb_q;

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
      for (index = 0; index < 32; index = index + 1) regs[index] <= 32'd0;
    end else begin
      perf_cycles <= perf_cycles + 32'd1;
      regs[0] <= 32'd0;
      case (state)
        FETCH: begin
          if (opcode == OP_LOAD || opcode == OP_STORE) begin
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
              3'b100: begin
                if (opcode == OP_LOAD) mem_wstrb_q <= 4'b0000;
                else begin mem_wstrb_q <= 4'b0000; trap <= 1'b1; state <= TRAP; end
              end
              3'b101: begin
                if (opcode == OP_LOAD) mem_wstrb_q <= 4'b0000;
                else begin mem_wstrb_q <= 4'b0000; trap <= 1'b1; state <= TRAP; end
              end
              default: begin mem_wstrb_q <= 4'b0000; trap <= 1'b1; state <= TRAP; end
            endcase
          end else begin
            perf_instructions <= perf_instructions + 32'd1;
            if (opcode == OP_BRANCH) perf_branches <= perf_branches + 32'd1;
            case (opcode)
              OP_LUI: begin if (rd != 5'd0) regs[rd] <= imm_u; pc <= pc + 32'd4; end
              OP_AUIPC: begin if (rd != 5'd0) regs[rd] <= pc + imm_u; pc <= pc + 32'd4; end
              OP_JAL: begin if (rd != 5'd0) regs[rd] <= pc + 32'd4; pc <= pc + imm_j; end
              OP_JALR: begin if (rd != 5'd0) regs[rd] <= pc + 32'd4; pc <= (rs1_value + imm_i) & 32'hffff_fffe; end
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
                if (rd != 5'd0) begin
                  case (funct3)
                    3'b000: regs[rd] <= rs1_value + imm_i;
                    3'b010: regs[rd] <= ($signed(rs1_value) < $signed(imm_i)) ? 32'd1 : 32'd0;
                    3'b011: regs[rd] <= (rs1_value < imm_i) ? 32'd1 : 32'd0;
                    3'b100: regs[rd] <= rs1_value ^ imm_i;
                    3'b110: regs[rd] <= rs1_value | imm_i;
                    3'b111: regs[rd] <= rs1_value & imm_i;
                    3'b001: regs[rd] <= rs1_value << imem_rdata[24:20];
                    3'b101: regs[rd] <= (funct7[5]) ? $signed(rs1_value) >>> imem_rdata[24:20] : rs1_value >> imem_rdata[24:20];
                    default: begin regs[rd] <= 32'd0; trap <= 1'b1; state <= TRAP; end
                  endcase
                end
                pc <= pc + 32'd4;
              end
              OP_OP: begin
                if (rd != 5'd0) begin
                  case ({funct7, funct3})
                    10'b0000000_000: regs[rd] <= rs1_value + rs2_value;
                    10'b0100000_000: regs[rd] <= rs1_value - rs2_value;
                    10'b0000000_001: regs[rd] <= rs1_value << rs2_value[4:0];
                    10'b0000000_010: regs[rd] <= ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0;
                    10'b0000000_011: regs[rd] <= (rs1_value < rs2_value) ? 32'd1 : 32'd0;
                    10'b0000000_100: regs[rd] <= rs1_value ^ rs2_value;
                    10'b0000000_101: regs[rd] <= rs1_value >> rs2_value[4:0];
                    10'b0100000_101: regs[rd] <= $signed(rs1_value) >>> rs2_value[4:0];
                    10'b0000000_110: regs[rd] <= rs1_value | rs2_value;
                    10'b0000000_111: regs[rd] <= rs1_value & rs2_value;
                    default: begin regs[rd] <= 32'd0; trap <= 1'b1; state <= TRAP; end
                  endcase
                end
                pc <= pc + 32'd4;
              end
              OP_SYSTEM: begin
                if (imem_rdata == 32'h1050_0073) begin
                  perf_instructions <= perf_instructions + 32'd1;
                  pc <= pc + 32'd4;
                  state <= WFI_WAIT;
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
              if (rsp_err) begin trap <= 1'b1; state <= TRAP; end
              else begin
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
            if (rsp_err) trap <= 1'b1;
            else begin
              perf_instructions <= perf_instructions + 32'd1;
              if (mem_is_load_q) perf_loads <= perf_loads + 32'd1;
              else perf_stores <= perf_stores + 32'd1;
              if (mem_is_load_q && mem_rd_q != 5'd0) regs[mem_rd_q] <= load_extend(rsp_rdata, mem_funct3_q, mem_addr_q[1:0]);
            end
            if (rsp_err) state <= TRAP;
            else begin pc <= pc + 32'd4; state <= FETCH; end
          end
        end
        WFI_WAIT: begin
          if (irq_external) state <= FETCH;
          else state <= WFI_WAIT;
        end
        TRAP: begin state <= TRAP; end
        default: state <= TRAP;
      endcase
    end
  end
endmodule
