#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "orx1.h"
#include "tinyml.h"

static uint32_t sensor_regs[8];
static uint32_t accel_regs[32];
static uint32_t uart_regs[8];
static uint32_t energy_regs[16];
static uint32_t cordic_regs[8];
static uint32_t irq_regs[4];
static uint32_t scratch_reg;
static uint32_t last_addr = 0;
static int cordic_ran = 0;

static char uart_buf[256];
static int uart_len = 0;

static const int32_t atan_lut[16] = {
  8192, 4836, 2555, 1297, 651, 326, 163, 81,
  41, 20, 10, 5, 3, 1, 1, 0
};

static int32_t mac_row_hw(uint32_t act_p, uint32_t w_p, int32_t prev, int32_t bias, uint8_t shift, uint32_t ctrl) {
  int8_t a[4];
  int8_t w[4];
  int32_t p_sum;
  int32_t a_sum;
  int32_t s_sum;

  for (int i = 0; i < 4; ++i) {
    a[i] = (int8_t)((act_p >> (8 * i)) & 0xFF);
    w[i] = (int8_t)((w_p >> (8 * i)) & 0xFF);
  }

  if (ctrl & 0x80) {
    uint8_t idx0 = (uint8_t)(w[2] & 0x03);
    uint8_t idx1 = (uint8_t)((w[2] >> 2) & 0x03);
    p_sum = (int32_t)a[idx0] * (int32_t)w[0] + (int32_t)a[idx1] * (int32_t)w[1];
  } else {
    p_sum = (int32_t)a[0] * (int32_t)w[0] +
            (int32_t)a[1] * (int32_t)w[1] +
            (int32_t)a[2] * (int32_t)w[2] +
            (int32_t)a[3] * (int32_t)w[3];
  }

  a_sum = ((ctrl & 0x04) ? prev : 0) + p_sum + ((ctrl & 0x10) ? bias : 0);
  s_sum = a_sum >> shift;
  if ((ctrl & 0x08) && s_sum < 0) s_sum = 0;
  if (ctrl & 0x100u) {
    if (s_sum > 127) s_sum = 127;
    if (s_sum < -128) s_sum = -128;
  }
  return s_sum;
}

static void flush_hw_side_effects(void) {
  if (last_addr == (ORX1_ACCEL_BASE + 0x00u)) {
    uint32_t ctrl = accel_regs[0];
    if (ctrl & 0x02) {
      ctrl &= ~0x02u;
    }
    if (ctrl & 0x40) {
      for (int r = 0; r < 4; ++r) {
        uint32_t tmp = accel_regs[(0x34 >> 2) + r];
        accel_regs[(0x34 >> 2) + r] = accel_regs[(0x50 >> 2) + r];
        accel_regs[(0x50 >> 2) + r] = tmp;
      }
      ctrl &= ~0x40u;
    }
    if (ctrl & 0x01) {
      uint32_t act_p = accel_regs[0x30 >> 2];
      uint8_t shift = (uint8_t)(accel_regs[0x0C >> 2] & 0x1F);
      accel_regs[0x04 >> 2] = (uint32_t)mac_row_hw(act_p, accel_regs[0x34 >> 2], (int32_t)accel_regs[0x04 >> 2], (int32_t)accel_regs[0x08 >> 2], shift, ctrl);
      if (ctrl & 0x20) {
        accel_regs[0x44 >> 2] = (uint32_t)mac_row_hw(act_p, accel_regs[0x38 >> 2], (int32_t)accel_regs[0x44 >> 2], (int32_t)accel_regs[0x60 >> 2], shift, ctrl);
        accel_regs[0x48 >> 2] = (uint32_t)mac_row_hw(act_p, accel_regs[0x3C >> 2], (int32_t)accel_regs[0x48 >> 2], (int32_t)accel_regs[0x64 >> 2], shift, ctrl);
        accel_regs[0x4C >> 2] = (uint32_t)mac_row_hw(act_p, accel_regs[0x40 >> 2], (int32_t)accel_regs[0x4C >> 2], (int32_t)accel_regs[0x68 >> 2], shift, ctrl);
      }
      ctrl = (ctrl & ~0x01u) | 0x02u;
      energy_regs[0x08 >> 2] += 1;
      energy_regs[0x10 >> 2] += 8;
    }
    accel_regs[0] = ctrl;
  }

  if (last_addr == (ORX1_CORDIC_BASE + 0x04u)) {
    cordic_ran = 0;
  }

  if (last_addr == (ORX1_CORDIC_BASE + 0x00u) && (cordic_regs[0] & 0x04u) && !cordic_ran) {
    uint32_t ctrl = cordic_regs[0];
    int32_t x = (int32_t)cordic_regs[0x04 >> 2];
    int32_t y = (int32_t)cordic_regs[0x08 >> 2];
    int32_t z = (int32_t)cordic_regs[0x0C >> 2];
    int mode_rot = (int)(ctrl & 0x01);

    for (int step = 0; step < 16; ++step) {
      int32_t xs = x >> step;
      int32_t ys = y >> step;
      int32_t ang = atan_lut[step];
      int d_dir = mode_rot ? (z >= 0) : (y < 0);
      if (d_dir) {
        x = x - ys;
        y = y + xs;
        z = z - ang;
      } else {
        x = x + ys;
        y = y - xs;
        z = z + ang;
      }
    }
    cordic_regs[0x04 >> 2] = (uint32_t)x;
    cordic_regs[0x08 >> 2] = (uint32_t)y;
    cordic_regs[0x0C >> 2] = (uint32_t)z;
    cordic_regs[0x10 >> 2] = (uint32_t)((int32_t)(((int64_t)x * 39797) >> 16));
    cordic_regs[0] = (ctrl & ~0x06u) | 0x04u;
    cordic_ran = 1;
  }

  if (last_addr == (ORX1_UART_BASE + 0x00u) && uart_regs[0] != 0) {
    if (uart_len < (int)sizeof(uart_buf) - 1) {
      uart_buf[uart_len++] = (char)(uart_regs[0] & 0xFF);
      uart_buf[uart_len] = '\0';
    }
    uart_regs[0] = 0;
  }

  if (last_addr == (ORX1_ENERGY_BASE + 0x14u) && (energy_regs[0x14 >> 2] & 0x01)) {
    memset(energy_regs, 0, sizeof(energy_regs));
  }

  last_addr = 0;
}

volatile uint32_t *orx1_host_reg(uint32_t addr) {
  flush_hw_side_effects();
  last_addr = addr;
  uint32_t off = addr & 0xFFu;
  if (addr >= ORX1_SENSOR_BASE && addr < ORX1_SENSOR_BASE + 0x100u) return &sensor_regs[off >> 2];
  if (addr >= ORX1_ACCEL_BASE && addr < ORX1_ACCEL_BASE + 0x100u) return &accel_regs[off >> 2];
  if (addr >= ORX1_UART_BASE && addr < ORX1_UART_BASE + 0x100u) return &uart_regs[off >> 2];
  if (addr >= ORX1_ENERGY_BASE && addr < ORX1_ENERGY_BASE + 0x100u) return &energy_regs[off >> 2];
  if (addr >= ORX1_CORDIC_BASE && addr < ORX1_CORDIC_BASE + 0x100u) return &cordic_regs[off >> 2];
  if (addr >= ORX1_IRQ_BASE && addr < ORX1_IRQ_BASE + 0x100u) return &irq_regs[off >> 2];
  return &scratch_reg;
}

static void ref_dense(const int8_t *in, const int8_t *w, const int32_t *b, int8_t *out, int in_dim, int out_dim, uint8_t shift, uint8_t relu) {
  for (int o = 0; o < out_dim; ++o) {
    int32_t acc = b ? b[o] : 0;
    for (int i = 0; i < in_dim; ++i) {
      acc += (int32_t)in[i] * (int32_t)w[o * in_dim + i];
    }
    acc = acc >> shift;
    if (relu && acc < 0) acc = 0;
    if (acc > 127) acc = 127;
    if (acc < -128) acc = -128;
    out[o] = (int8_t)acc;
  }
}

int main(void) {
  int failures = 0;
  tinyml_init();

  {
    int8_t act[4] = {2, -3, 4, 5};
    int8_t w[16] = {
      1, 2, 3, 4,
      -5, -5, -5, -5,
      10, 0, -2, 1,
      -1, 1, -1, 1
    };
    int32_t b[4] = {10, 0, -4, 16};
    int32_t out[4] = {0};
    tinyml_dense_4x4(act, w, b, out, 1, 1);
    if (out[0] != 19 || out[1] != 0 || out[2] != 6 || out[3] != 6) {
      printf("FAIL dense_4x4: %d %d %d %d\n", out[0], out[1], out[2], out[3]);
      failures++;
    }
  }

  {
    int8_t act[4] = {2, 3, 4, 5};
    int8_t sw[8] = {5, 10, -2, 4, 3, -1, 7, 2};
    uint8_t idx[8] = {0, 1, 2, 3, 1, 2, 0, 3};
    int32_t b[4] = {0, 20, 0, -5};
    int32_t out[4] = {0};
    tinyml_sparse_2_4(act, sw, idx, b, out, 0, 1);
    if (out[0] != 40 || out[1] != 32 || out[2] != 5 || out[3] != 19) {
      printf("FAIL sparse_2_4: %d %d %d %d\n", out[0], out[1], out[2], out[3]);
      failures++;
    }
  }

  {
    int8_t in[6] = {12, -7, 20, 3, -15, 9};
    int8_t w[30] = {
      3, -2, 4, 1, -5, 2,
      -8, 6, -3, 4, 2, -1,
      10, 10, 10, 10, 10, 10,
      -10, -10, -10, -10, -10, -10,
      1, 0, -1, 2, -2, 3
    };
    int32_t b[5] = {8, -12, 50, -50, 0};
    int8_t hw_out[5] = {0};
    int8_t sw_out[5] = {0};

    tinyml_dense(in, w, b, hw_out, 6, 5, 1, 1);
    ref_dense(in, w, b, sw_out, 6, 5, 1, 1);
    for (int i = 0; i < 5; ++i) {
      if (hw_out[i] != sw_out[i]) {
        printf("FAIL dense_6x5_relu idx=%d hw=%d sw=%d\n", i, hw_out[i], sw_out[i]);
        failures++;
      }
    }

    tinyml_dense(in, w, NULL, hw_out, 6, 5, 0, 0);
    ref_dense(in, w, NULL, sw_out, 6, 5, 0, 0);
    for (int i = 0; i < 5; ++i) {
      if (hw_out[i] != sw_out[i]) {
        printf("FAIL dense_6x5_nobias idx=%d hw=%d sw=%d\n", i, hw_out[i], sw_out[i]);
        failures++;
      }
    }
  }

  {
    int32_t mag = cordic_vector_magnitude(300, 400);
    if (mag < 495 || mag > 505) {
      printf("FAIL cordic_mag: %d\n", mag);
      failures++;
    }
    int16_t rx = 0, ry = 0;
    cordic_rotate(1000, 0, 8192, &rx, &ry);
    if (rx < 1150 || rx > 1180 || ry < 1150 || ry > 1180) {
      printf("FAIL cordic_rot: %d %d\n", rx, ry);
      failures++;
    }
  }

  {
    int8_t input_features[4] = {12, 45, -20, 30};
    int8_t layer1_weights[16] = {
      10, -5,  2,  8,
      -3, 12, -4,  1,
       7,  0, 11, -6,
      -8,  9,  4, 15
    };
    int32_t layer1_biases[4] = {16, -8, 4, 32};
    int8_t out_c[4] = {0};
    ENERGY_CLEAR = 0x01;
    tinyml_dense(input_features, layer1_weights, layer1_biases, out_c, 4, 4, 3, 1);
    flush_hw_side_effects();
    uart_puts("OK");
    flush_hw_side_effects();
    if (out_c[0] != 13 || out_c[1] != 75 || out_c[2] != 0 || out_c[3] != 88) {
      printf("FAIL anomaly: %d %d %d %d\n", out_c[0], out_c[1], out_c[2], out_c[3]);
      failures++;
    }
    if (strcmp(uart_buf, "OK") != 0 || ENERGY_WEIGHTED == 0) {
      printf("FAIL uart_or_energy: uart=%s energy=%u\n", uart_buf, (unsigned)ENERGY_WEIGHTED);
      failures++;
    }
  }

  if (failures == 0) {
    printf("SW_TINYML_TEST_PASS\n");
    return 0;
  }
  printf("SW_TINYML_TEST_FAIL %d\n", failures);
  return 1;
}
