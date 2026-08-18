module energy_monitor (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  input logic sensor_event,
  input logic accelerator_event,
  input logic memory_event
);
  logic [31:0] cycle_count;
  logic [31:0] sensor_count;
  logic [31:0] accelerator_count;
  logic [31:0] memory_count;
  logic [31:0] weighted_activity;

  assign weighted_activity = cycle_count + (sensor_count << 1) + (accelerator_count << 3) + (memory_count << 2);

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = cycle_count;
      8'h04: csr_rdata = sensor_count;
      8'h08: csr_rdata = accelerator_count;
      8'h0c: csr_rdata = memory_count;
      8'h10: csr_rdata = weighted_activity;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      cycle_count <= 32'd0;
      sensor_count <= 32'd0;
      accelerator_count <= 32'd0;
      memory_count <= 32'd0;
    end else if (csr_valid && csr_write && csr_addr == 8'h14 && csr_wdata[0]) begin
      cycle_count <= 32'd0;
      sensor_count <= 32'd0;
      accelerator_count <= 32'd0;
      memory_count <= 32'd0;
    end else begin
      cycle_count <= cycle_count + 32'd1;
      if (sensor_event) sensor_count <= sensor_count + 32'd1;
      if (accelerator_event) accelerator_count <= accelerator_count + 32'd1;
      if (memory_event) memory_count <= memory_count + 32'd1;
    end
  end
endmodule
