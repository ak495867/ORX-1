module rv32i_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input  logic clk,
  input  logic reset,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  output logic d_valid,
  output logic d_write,
  output logic [31:0] d_addr,
  output logic [31:0] d_wdata,
  output logic [3:0] d_wstrb,
  input  logic [31:0] d_rdata,
  input logic d_ready,
  output logic trap
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

  logic [31:0] pc;
  logic [31:0] regs [0:31];
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

  always_comb begin
    d_valid = 1'b0;
    d_write = 1'b0;
    d_addr = 32'd0;
    d_wdata = 32'd0;
    d_wstrb = 4'd0;
    if (opcode == OP_LOAD || opcode == OP_STORE) begin
      d_valid = 1'b1;
      d_write = opcode == OP_STORE;
      d_addr = rs1_value + ((opcode == OP_LOAD) ? imm_i : imm_s);
      d_wdata = rs2_value;
      if (opcode == OP_STORE) begin
        case (funct3)
          3'b000: d_wstrb = 4'b0001;
          3'b001: d_wstrb = 4'b0011;
          default: d_wstrb = 4'b1111;
        endcase
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc <= RESET_PC;
      trap <= 1'b0;
      for (index = 0; index < 32; index = index + 1) regs[index] <= 32'd0;
    end else begin
      regs[0] <= 32'd0;
      if (d_valid) begin
        if (d_ready) begin
          if (opcode == OP_LOAD && rd != 5'd0) regs[rd] <= d_rdata;
          pc <= pc + 32'd4;
        end
      end else begin
        case (opcode)
          OP_LUI: begin
            if (rd != 5'd0) regs[rd] <= imm_u;
            pc <= pc + 32'd4;
          end
          OP_AUIPC: begin
            if (rd != 5'd0) regs[rd] <= pc + imm_u;
            pc <= pc + 32'd4;
          end
          OP_JAL: begin
            if (rd != 5'd0) regs[rd] <= pc + 32'd4;
            pc <= pc + imm_j;
          end
          OP_JALR: begin
            if (rd != 5'd0) regs[rd] <= pc + 32'd4;
            pc <= (rs1_value + imm_i) & 32'hffff_fffe;
          end
          OP_BRANCH: begin
            case (funct3)
              3'b000: pc <= (rs1_value == rs2_value) ? pc + imm_b : pc + 32'd4;
              3'b001: pc <= (rs1_value != rs2_value) ? pc + imm_b : pc + 32'd4;
              3'b100: pc <= ($signed(rs1_value) < $signed(rs2_value)) ? pc + imm_b : pc + 32'd4;
              3'b101: pc <= ($signed(rs1_value) >= $signed(rs2_value)) ? pc + imm_b : pc + 32'd4;
              3'b110: pc <= (rs1_value < rs2_value) ? pc + imm_b : pc + 32'd4;
              3'b111: pc <= (rs1_value >= rs2_value) ? pc + imm_b : pc + 32'd4;
              default: begin pc <= pc + 32'd4; trap <= 1'b1; end
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
                default: begin regs[rd] <= 32'd0; trap <= 1'b1; end
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
                default: begin regs[rd] <= 32'd0; trap <= 1'b1; end
              endcase
            end
            pc <= pc + 32'd4;
          end
          OP_SYSTEM: begin
            trap <= 1'b1;
            pc <= pc + 32'd4;
          end
          default: begin
            trap <= 1'b1;
            pc <= pc + 32'd4;
          end
        endcase
      end
    end
  end
endmodule
