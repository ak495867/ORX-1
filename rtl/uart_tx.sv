module uart_tx (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic tx
);
  typedef enum logic [1:0] {UART_IDLE, UART_START, UART_DATA, UART_STOP} uart_state_t;
  uart_state_t state;
  logic [15:0] baud_div;
  logic [15:0] div_count;
  logic [7:0] tx_data;
  logic [7:0] tx_shift;
  logic [2:0] bit_index;
  logic busy;
  logic tx_done;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {24'd0, tx_data};
      8'h04: csr_rdata = {30'd0, tx_done, busy};
      8'h08: csr_rdata = {16'd0, baud_div};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= UART_IDLE;
      baud_div <= 16'd16;
      div_count <= 16'd0;
      tx_data <= 8'd0;
      tx_shift <= 8'd0;
      bit_index <= 3'd0;
      busy <= 1'b0;
      tx_done <= 1'b0;
      tx <= 1'b1;
    end else begin
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (!busy) begin
              tx_data <= csr_wdata[7:0];
              tx_shift <= csr_wdata[7:0];
              div_count <= 16'd0;
              bit_index <= 3'd0;
              busy <= 1'b1;
              tx_done <= 1'b0;
              tx <= 1'b0;
              state <= UART_START;
            end
          end
          8'h08: baud_div <= csr_wdata[15:0];
          default: begin end
        endcase
      end
      case (state)
        UART_IDLE: begin
          tx <= 1'b1;
          busy <= 1'b0;
        end
        UART_START: begin
          tx <= 1'b0;
          if (div_count >= baud_div) begin
            div_count <= 16'd0;
            tx <= tx_shift[0];
            state <= UART_DATA;
          end else begin
            div_count <= div_count + 16'd1;
          end
        end
        UART_DATA: begin
          tx <= tx_shift[0];
          if (div_count >= baud_div) begin
            div_count <= 16'd0;
            if (bit_index == 3'd7) begin
              tx <= 1'b1;
              state <= UART_STOP;
            end else begin
              bit_index <= bit_index + 3'd1;
              tx_shift <= {1'b0, tx_shift[7:1]};
              tx <= tx_shift[1];
            end
          end else begin
            div_count <= div_count + 16'd1;
          end
        end
        UART_STOP: begin
          tx <= 1'b1;
          if (div_count >= baud_div) begin
            div_count <= 16'd0;
            busy <= 1'b0;
            tx_done <= 1'b1;
            state <= UART_IDLE;
          end else begin
            div_count <= div_count + 16'd1;
          end
        end
        default: state <= UART_IDLE;
      endcase
    end
  end
endmodule
