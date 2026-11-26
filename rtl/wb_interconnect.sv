module wb_interconnect (
  input logic clk,
  input logic reset,

  input logic m0_cyc_i,
  input logic m0_stb_i,
  input logic m0_we_i,
  input logic [31:0] m0_adr_i,
  input logic [31:0] m0_dat_i,
  input logic [3:0] m0_sel_i,
  output logic m0_ack_o,
  output logic [31:0] m0_dat_o,
  output logic m0_err_o,

  input logic m1_cyc_i,
  input logic m1_stb_i,
  input logic m1_we_i,
  input logic [31:0] m1_adr_i,
  input logic [31:0] m1_dat_i,
  input logic [3:0] m1_sel_i,
  output logic m1_ack_o,
  output logic [31:0] m1_dat_o,
  output logic m1_err_o,

  input logic m2_cyc_i,
  input logic m2_stb_i,
  input logic m2_we_i,
  input logic [31:0] m2_adr_i,
  input logic [31:0] m2_dat_i,
  input logic [3:0] m2_sel_i,
  output logic m2_ack_o,
  output logic [31:0] m2_dat_o,
  output logic m2_err_o,

  output logic [1:0] grant_master_o,
  output logic [13:0] s_cyc_o,
  output logic [13:0] s_stb_o,
  output logic s_we_o,
  output logic [31:0] s_adr_o,
  output logic [31:0] s_dat_o,
  output logic [3:0] s_sel_o,

  input logic [13:0] s_ack_i,
  input logic [31:0] s0_dat_i,
  input logic [31:0] s1_dat_i,
  input logic [31:0] s2_dat_i,
  input logic [31:0] s3_dat_i,
  input logic [31:0] s4_dat_i,
  input logic [31:0] s5_dat_i,
  input logic [31:0] s6_dat_i,
  input logic [31:0] s7_dat_i,
  input logic [31:0] s8_dat_i,
  input logic [31:0] s9_dat_i,
  input logic [31:0] s10_dat_i,
  input logic [31:0] s11_dat_i,
  input logic [31:0] s12_dat_i,
  input logic [31:0] s13_dat_i,
  input logic [13:0] s_err_i
);
  logic [2:0] m_req;
  logic [1:0] grant_id;
  logic [1:0] locked_id;
  logic locked;
  logic [1:0] last_grant;

  assign m_req = {m2_cyc_i && m2_stb_i, m1_cyc_i && m1_stb_i, m0_cyc_i && m0_stb_i};
  assign grant_master_o = grant_id;

  always_comb begin
    grant_id = 2'd0;
    if (locked && m_req[locked_id]) begin
      grant_id = locked_id;
    end else begin
      case (last_grant)
        2'd0: begin
          if (m_req[1]) grant_id = 2'd1;
          else if (m_req[2]) grant_id = 2'd2;
          else grant_id = 2'd0;
        end
        2'd1: begin
          if (m_req[2]) grant_id = 2'd2;
          else if (m_req[0]) grant_id = 2'd0;
          else grant_id = 2'd1;
        end
        default: begin
          if (m_req[0]) grant_id = 2'd0;
          else if (m_req[1]) grant_id = 2'd1;
          else grant_id = 2'd2;
        end
      endcase
    end
  end

  logic [31:0] g_adr;
  logic [31:0] g_dat;
  logic [3:0] g_sel;
  logic g_we;
  logic g_cyc;
  logic g_stb;

  always_comb begin
    case (grant_id)
      2'd1: begin
        g_cyc = m1_cyc_i;
        g_stb = m1_stb_i;
        g_we  = m1_we_i;
        g_adr = m1_adr_i;
        g_dat = m1_dat_i;
        g_sel = m1_sel_i;
      end
      2'd2: begin
        g_cyc = m2_cyc_i;
        g_stb = m2_stb_i;
        g_we  = m2_we_i;
        g_adr = m2_adr_i;
        g_dat = m2_dat_i;
        g_sel = m2_sel_i;
      end
      default: begin
        g_cyc = m0_cyc_i;
        g_stb = m0_stb_i;
        g_we  = m0_we_i;
        g_adr = m0_adr_i;
        g_dat = m0_dat_i;
        g_sel = m0_sel_i;
      end
    endcase
  end

  logic [13:0] slave_sel;

  always_comb begin
    slave_sel = 14'b0;
    if (g_cyc && g_stb) begin
      if (g_adr >= `ORX1_BOOT_BASE && g_adr <= `ORX1_BOOT_LAST) slave_sel[0] = 1'b1;
      else if (g_adr >= `ORX1_SRAM_BASE && g_adr <= `ORX1_SRAM_LAST) slave_sel[1] = 1'b1;
      else if (g_adr >= `ORX1_SENSOR_BASE && g_adr < `ORX1_SENSOR_BASE + `ORX1_REGION_SIZE) slave_sel[2] = 1'b1;
      else if (g_adr >= `ORX1_ACCEL_BASE && g_adr < `ORX1_ACCEL_BASE + `ORX1_REGION_SIZE) slave_sel[3] = 1'b1;
      else if (g_adr >= `ORX1_BOOTCTRL_BASE && g_adr < `ORX1_BOOTCTRL_BASE + `ORX1_REGION_SIZE) slave_sel[4] = 1'b1;
      else if (g_adr >= `ORX1_UART_BASE && g_adr < `ORX1_UART_BASE + `ORX1_REGION_SIZE) slave_sel[5] = 1'b1;
      else if (g_adr >= `ORX1_ENERGY_BASE && g_adr < `ORX1_ENERGY_BASE + `ORX1_REGION_SIZE) slave_sel[6] = 1'b1;
      else if (g_adr >= `ORX1_TIMER_BASE && g_adr < `ORX1_TIMER_BASE + `ORX1_REGION_SIZE) slave_sel[7] = 1'b1;
      else if (g_adr >= `ORX1_DMA_BASE && g_adr < `ORX1_DMA_BASE + `ORX1_REGION_SIZE) slave_sel[8] = 1'b1;
      else if (g_adr >= `ORX1_CORDIC_BASE && g_adr < `ORX1_CORDIC_BASE + `ORX1_REGION_SIZE) slave_sel[9] = 1'b1;
      else if (g_adr >= `ORX1_IRQ_BASE && g_adr < `ORX1_IRQ_BASE + `ORX1_REGION_SIZE) slave_sel[10] = 1'b1;
      else if (g_adr >= `ORX1_GPIO_BASE && g_adr < `ORX1_GPIO_BASE + `ORX1_REGION_SIZE) slave_sel[11] = 1'b1;
      else if (g_adr >= `ORX1_SPI_BASE && g_adr < `ORX1_SPI_BASE + `ORX1_REGION_SIZE) slave_sel[12] = 1'b1;
      else if (g_adr >= `ORX1_SYS_BASE && g_adr < `ORX1_SYS_BASE + `ORX1_REGION_SIZE) slave_sel[13] = 1'b1;
    end
  end

  assign s_adr_o = g_adr;
  assign s_dat_o = g_dat;
  assign s_sel_o = g_sel;
  assign s_we_o  = g_we;
  assign s_cyc_o = slave_sel & {14{g_cyc}};
  assign s_stb_o = slave_sel & {14{g_stb}};

  logic [31:0] selected_rdata;
  logic selected_ack;
  logic selected_err;
  logic unmapped_err;

  assign unmapped_err = g_cyc && g_stb && (slave_sel == 14'b0);

  always_comb begin
    selected_rdata = 32'd0;
    selected_ack = 1'b0;
    selected_err = unmapped_err;
    case (1'b1)
      slave_sel[0]:  begin selected_rdata = s0_dat_i;  selected_ack = s_ack_i[0];  selected_err = s_err_i[0];  end
      slave_sel[1]:  begin selected_rdata = s1_dat_i;  selected_ack = s_ack_i[1];  selected_err = s_err_i[1];  end
      slave_sel[2]:  begin selected_rdata = s2_dat_i;  selected_ack = s_ack_i[2];  selected_err = s_err_i[2];  end
      slave_sel[3]:  begin selected_rdata = s3_dat_i;  selected_ack = s_ack_i[3];  selected_err = s_err_i[3];  end
      slave_sel[4]:  begin selected_rdata = s4_dat_i;  selected_ack = s_ack_i[4];  selected_err = s_err_i[4];  end
      slave_sel[5]:  begin selected_rdata = s5_dat_i;  selected_ack = s_ack_i[5];  selected_err = s_err_i[5];  end
      slave_sel[6]:  begin selected_rdata = s6_dat_i;  selected_ack = s_ack_i[6];  selected_err = s_err_i[6];  end
      slave_sel[7]:  begin selected_rdata = s7_dat_i;  selected_ack = s_ack_i[7];  selected_err = s_err_i[7];  end
      slave_sel[8]:  begin selected_rdata = s8_dat_i;  selected_ack = s_ack_i[8];  selected_err = s_err_i[8];  end
      slave_sel[9]:  begin selected_rdata = s9_dat_i;  selected_ack = s_ack_i[9];  selected_err = s_err_i[9];  end
      slave_sel[10]: begin selected_rdata = s10_dat_i; selected_ack = s_ack_i[10]; selected_err = s_err_i[10]; end
      slave_sel[11]: begin selected_rdata = s11_dat_i; selected_ack = s_ack_i[11]; selected_err = s_err_i[11]; end
      slave_sel[12]: begin selected_rdata = s12_dat_i; selected_ack = s_ack_i[12]; selected_err = s_err_i[12]; end
      slave_sel[13]: begin selected_rdata = s13_dat_i; selected_ack = s_ack_i[13]; selected_err = s_err_i[13]; end
      default: begin selected_rdata = 32'd0; selected_ack = 1'b0; selected_err = unmapped_err; end
    endcase
  end

  assign m0_dat_o = selected_rdata;
  assign m1_dat_o = selected_rdata;
  assign m2_dat_o = selected_rdata;
  assign m0_ack_o = (grant_id == 2'd0) ? selected_ack : 1'b0;
  assign m1_ack_o = (grant_id == 2'd1) ? selected_ack : 1'b0;
  assign m2_ack_o = (grant_id == 2'd2) ? selected_ack : 1'b0;
  assign m0_err_o = (grant_id == 2'd0) ? selected_err : 1'b0;
  assign m1_err_o = (grant_id == 2'd1) ? selected_err : 1'b0;
  assign m2_err_o = (grant_id == 2'd2) ? selected_err : 1'b0;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      locked <= 1'b0;
      locked_id <= 2'd0;
      last_grant <= 2'd2;
    end else begin
      if (g_cyc && g_stb && (selected_ack || selected_err)) begin
        locked <= 1'b0;
        last_grant <= grant_id;
      end else if (|m_req && !locked) begin
        locked <= 1'b1;
        locked_id <= grant_id;
      end else if (locked && !m_req[locked_id]) begin
        locked <= 1'b0;
      end
    end
  end
endmodule
