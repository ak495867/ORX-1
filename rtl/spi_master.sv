module spi_master (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic spi_sck,
  output logic spi_mosi,
  input logic spi_miso,
  output logic spi_cs_n,
  output logic spi_irq
);
  logic busy;
  logic done;
  logic cs_active;
  logic cpol;
  logic cpha;
  logic word32;
  logic [31:0] tx_data;
  logic [31:0] rx_data;
  logic [31:0] tx_shift;
  logic [31:0] rx_shift;
  logic [15:0] clk_div;
  logic [15:0] div_cnt;
  logic [5:0] bit_cnt;
  logic sck_phase;

  assign spi_cs_n = ~cs_active;
  assign spi_mosi = tx_shift[31];

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {25'd0, word32, cpha, cpol, cs_active, done, busy, 1'b0};
      8'h04: csr_rdata = tx_data;
      8'h08: csr_rdata = rx_data;
      8'h0c: csr_rdata = {16'd0, clk_div};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      busy <= 1'b0;
      done <= 1'b0;
      cs_active <= 1'b0;
      cpol <= 1'b0;
      cpha <= 1'b0;
      word32 <= 1'b0;
      tx_data <= 32'd0;
      rx_data <= 32'd0;
      tx_shift <= 32'd0;
      rx_shift <= 32'd0;
      clk_div <= 16'd2;
      div_cnt <= 16'd0;
      bit_cnt <= 6'd0;
      sck_phase <= 1'b0;
      spi_sck <= 1'b0;
      spi_irq <= 1'b0;
    end else begin
      spi_irq <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            cs_active <= csr_wdata[3];
            if (!busy) begin
              cpol <= csr_wdata[4];
              cpha <= csr_wdata[5];
              word32 <= csr_wdata[6];
              if (!csr_wdata[0]) spi_sck <= csr_wdata[4];
            end
            if (csr_wdata[2]) done <= 1'b0;
            if (csr_wdata[0] && !busy) begin
              busy <= 1'b1;
              done <= 1'b0;
              tx_shift <= csr_wdata[6] ? tx_data : {tx_data[7:0], 24'd0};
              rx_shift <= 32'd0;
              bit_cnt <= csr_wdata[6] ? 6'd31 : 6'd7;
              div_cnt <= clk_div;
              sck_phase <= 1'b0;
              spi_sck <= csr_wdata[4];
            end
          end
          8'h04: tx_data <= csr_wdata;
          8'h0c: clk_div <= csr_wdata[15:0];
          default: begin end
        endcase
      end else if (busy) begin
        if (div_cnt == 16'd0) begin
          div_cnt <= clk_div;
          if (!sck_phase) begin
            sck_phase <= 1'b1;
            spi_sck <= ~cpol;
            if (!cpha) begin
              rx_shift <= {rx_shift[30:0], spi_miso};
            end
          end else begin
            sck_phase <= 1'b0;
            spi_sck <= cpol;
            if (cpha) begin
              rx_shift <= {rx_shift[30:0], spi_miso};
            end
            if (bit_cnt == 6'd0) begin
              busy <= 1'b0;
              done <= 1'b1;
              spi_irq <= 1'b1;
              rx_data <= cpha ? {rx_shift[30:0], spi_miso} : rx_shift;
            end else begin
              bit_cnt <= bit_cnt - 6'd1;
              tx_shift <= {tx_shift[30:0], 1'b0};
            end
          end
        end else begin
          div_cnt <= div_cnt - 16'd1;
        end
      end
    end
  end
endmodule
