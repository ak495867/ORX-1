module caravel_user_project_wrapper (
  input logic wb_clk_i,
  input logic wb_rst_i,
  input logic wbs_stb_i,
  input logic wbs_cyc_i,
  input logic wbs_we_i,
  input logic [3:0] wbs_sel_i,
  input logic [31:0] wbs_dat_i,
  input logic [31:0] wbs_adr_i,
  output logic wbs_ack_o,
  output logic [31:0] wbs_dat_o,

  input logic [127:0] la_data_in,
  output logic [127:0] la_data_out,
  input logic [127:0] la_oenb,

  input logic [37:0] io_in,
  output logic [37:0] io_out,
  output logic [37:0] io_oeb,

  output logic [2:0] user_irq
);
  logic clk;
  logic reset;
  logic soc_reset;
  logic sensor_valid;
  logic [15:0] sensor_data;
  logic sensor_result_valid;
  logic [15:0] sensor_result;
  logic accelerator_irq;
  logic boot_release;
  logic boot_fail;
  logic core_trap;
  logic sensor_alert;
  logic uart_rx;
  logic uart_tx;

  assign clk = wb_clk_i;
  assign reset = wb_rst_i;
  assign soc_reset = reset | (!la_oenb[0] & la_data_in[0]);

  assign uart_rx = io_in[0];
  assign io_out[0] = 1'b0;
  assign io_oeb[0] = 1'b1;

  assign io_out[1] = uart_tx;
  assign io_oeb[1] = 1'b0;

  assign sensor_data = io_in[17:2];
  assign sensor_valid = io_in[18];

  assign io_out[17:2] = 16'd0;
  assign io_oeb[17:2] = 16'hffff;
  assign io_out[18] = 1'b0;
  assign io_oeb[18] = 1'b1;

  assign io_out[19] = sensor_result_valid;
  assign io_oeb[19] = 1'b0;

  assign io_out[35:20] = sensor_result;
  assign io_oeb[35:20] = 16'd0;

  assign io_out[36] = sensor_alert;
  assign io_oeb[36] = 1'b0;

  assign io_out[37] = boot_release;
  assign io_oeb[37] = 1'b0;

  assign user_irq[0] = core_trap;
  assign user_irq[1] = accelerator_irq;
  assign user_irq[2] = boot_fail;

  assign la_data_out[0] = boot_release;
  assign la_data_out[1] = boot_fail;
  assign la_data_out[2] = core_trap;
  assign la_data_out[3] = accelerator_irq;
  assign la_data_out[4] = sensor_alert;
  assign la_data_out[5] = sensor_result_valid;
  assign la_data_out[21:6] = sensor_result;
  assign la_data_out[127:22] = 106'd0;

  orx1_soc u_soc (
    .clk(clk),
    .reset(soc_reset),
    .sensor_valid(sensor_valid),
    .sensor_data(sensor_data),
    .sensor_result_valid(sensor_result_valid),
    .sensor_result(sensor_result),
    .accelerator_irq(accelerator_irq),
    .boot_release(boot_release),
    .boot_fail(boot_fail),
    .core_trap(core_trap),
    .sensor_alert(sensor_alert),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .wb_host_cyc_i(wbs_cyc_i),
    .wb_host_stb_i(wbs_stb_i),
    .wb_host_we_i(wbs_we_i),
    .wb_host_sel_i(wbs_sel_i),
    .wb_host_adr_i(wbs_adr_i),
    .wb_host_dat_i(wbs_dat_i),
    .wb_host_ack_o(wbs_ack_o),
    .wb_host_dat_o(wbs_dat_o)
  );
endmodule
