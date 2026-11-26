#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "orx1.h"
#include "tinyml.h"

static uint32_t sensor_regs[8];
static uint32_t accel_regs[64];
static uint32_t uart_regs[8];
static uint32_t energy_regs[16];
static uint32_t cordic_regs[8];
static uint32_t irq_regs[4];
static uint32_t scratch_reg;
static uint32_t last_addr = 0;
static int cordic_ran = 0;
static uint8_t host_sram[16384];

static char uart_buf[256];
static int uart_len = 0;

static const int32_t atan_lut[16] = {
  8192, 4836, 2555, 1297, 651, 326, 163, 81,
  41, 20, 10, 5, 3, 1, 1, 0
};

uint32_t orx1_host_to_bus(const void *ptr) {
  const uint8_t *p = (const uint8_t *)ptr;
  if (p >= host_sram && p < host_sram + sizeof(host_sram)) {
    return ORX1_SRAM_BASE + (uint32_t)(p - host_sram);
  }
  return 0u;
}

static uint32_t host_sram_read32(uint32_t bus_addr) {
  uint32_t off = bus_addr - ORX1_SRAM_BASE;
  if (bus_addr < ORX1_SRAM_BASE || off + 4u > sizeof(host_sram)) return 0u;
  return ((uint32_t)host_sram[off]) |
         (((uint32_t)host_sram[off + 1u]) << 8) |
         (((uint32_t)host_sram[off + 2u]) << 16) |
         (((uint32_t)host_sram[off + 3u]) << 24);
}

static void host_sram_write32(uint32_t bus_addr, uint32_t val) {
  uint32_t off = bus_addr - ORX1_SRAM_BASE;
  if (bus_addr < ORX1_SRAM_BASE || off + 4u > sizeof(host_sram)) return;
  host_sram[off]      = (uint8_t)(val & 0xFFu);
  host_sram[off + 1u] = (uint8_t)((val >> 8) & 0xFFu);
  host_sram[off + 2u] = (uint8_t)((val >> 16) & 0xFFu);
  host_sram[off + 3u] = (uint8_t)((val >> 24) & 0xFFu);
}

static uint8_t sat_s8_u(int32_t v) {
  if (v > 127) return 127u;
  if (v < -128) return (uint8_t)(int8_t)-128;
  return (uint8_t)(v & 0xFF);
}

static int32_t mac_row_hw(uint32_t act_lo, uint32_t act_hi, uint32_t w_lo, uint32_t w_hi, int32_t prev, int32_t bias, uint8_t shift, uint32_t ctrl) {
  int8_t a[8];
  int8_t w[8];
  int32_t p_sum = 0;
  int32_t a_sum;
  int32_t s_sum;
  int wide = (ctrl & 0x400u) ? 1 : 0;

  for (int i = 0; i < 4; ++i) {
    a[i] = (int8_t)((act_lo >> (8 * i)) & 0xFF);
    w[i] = (int8_t)((w_lo >> (8 * i)) & 0xFF);
    a[i + 4] = wide ? (int8_t)((act_hi >> (8 * i)) & 0xFF) : 0;
    w[i + 4] = wide ? (int8_t)((w_hi >> (8 * i)) & 0xFF) : 0;
  }

  if (ctrl & 0x80u) {
    uint8_t idx0 = (uint8_t)(w[2] & 0x03);
    uint8_t idx1 = (uint8_t)((w[2] >> 2) & 0x03);
    p_sum = (int32_t)a[idx0] * (int32_t)w[0] + (int32_t)a[idx1] * (int32_t)w[1];
    if (wide) {
      uint8_t idx2 = (uint8_t)(w[6] & 0x03);
      uint8_t idx3 = (uint8_t)((w[6] >> 2) & 0x03);
      p_sum += (int32_t)a[4 + idx2] * (int32_t)w[4] + (int32_t)a[4 + idx3] * (int32_t)w[5];
    }
  } else {
    int cols = wide ? 8 : 4;
    for (int i = 0; i < cols; ++i) {
      p_sum += (int32_t)a[i] * (int32_t)w[i];
    }
  }

  a_sum = ((ctrl & 0x04u) ? prev : 0) + p_sum + ((ctrl & 0x10u) ? bias : 0);
  s_sum = a_sum >> shift;
  if ((ctrl & 0x08u) && s_sum < 0) s_sum = 0;
  if (ctrl & 0x100u) {
    if (s_sum > 127) s_sum = 127;
    if (s_sum < -128) s_sum = -128;
  }
  return s_sum;
}

static void accel_sync_packed(void) {
  static const uint32_t r_off[8] = {0x04u, 0x44u, 0x48u, 0x4Cu, 0xB8u, 0xBCu, 0xC0u, 0xC4u};
  uint32_t lo = 0u, hi = 0u;
  for (int r = 0; r < 4; ++r) {
    lo |= ((uint32_t)sat_s8_u((int32_t)accel_regs[r_off[r] >> 2])) << (8 * r);
    hi |= ((uint32_t)sat_s8_u((int32_t)accel_regs[r_off[r + 4] >> 2])) << (8 * r);
  }
  accel_regs[0x70u >> 2] = lo;
  accel_regs[0xC8u >> 2] = hi;
}

static void run_tdma_hw(void) {
  uint32_t ctrl = accel_regs[0xE0u >> 2];
  uint32_t act_base = accel_regs[0xCCu >> 2];
  uint32_t w_base = accel_regs[0xD0u >> 2];
  uint32_t b_base = accel_regs[0xD4u >> 2];
  uint32_t d_base = accel_regs[0xD8u >> 2];
  uint32_t shape = accel_regs[0xDCu >> 2];

  uint32_t k_words = shape & 0x1Fu;
  uint32_t out_tiles = (shape >> 8) & 0x07u;
  uint32_t batch_cnt = (shape >> 16) & 0xFFu;
  if (k_words == 0u) k_words = 1u;
  if (out_tiles == 0u) out_tiles = 1u;
  if (batch_cnt == 0u) batch_cnt = 1u;

  uint32_t ws = (ctrl >> 2) & 1u;
  uint32_t relu = (ctrl >> 3) & 1u;
  uint32_t bias_en = (ctrl >> 4) & 1u;
  uint32_t clamp = (ctrl >> 5) & 1u;
  uint32_t shift = (ctrl >> 6) & 0x1Fu;
  uint32_t mode_8out = (ctrl >> 11) & 1u;
  uint32_t rows = mode_8out ? 8u : 4u;

  uint32_t cur_d = d_base;
  int8_t act_buf[8];
  int8_t w_buf[8][8];
  int32_t b_buf[8];
  int32_t res_buf[8];
  int cached_weights = 0;

  for (uint32_t bi = 0; bi < batch_cnt; ++bi) {
    uint32_t a_batch = act_base + bi * k_words * 4u;
    uint32_t cur_b = b_base;
    uint32_t cur_w = w_base;
    for (uint32_t ti = 0; ti < out_tiles; ++ti) {
      if (!(ws && cached_weights && (k_words <= 2u) && (out_tiles == 1u))) {
        if (bias_en) {
          for (uint32_t r = 0; r < rows; ++r) {
            b_buf[r] = (int32_t)host_sram_read32(cur_b);
            cur_b += 4u;
          }
        }
      }
      uint32_t cur_a = a_batch;
      for (uint32_t k = 0; k < k_words; ) {
        uint32_t rem = k_words - k;
        uint32_t chunk = (rem >= 2u) ? 2u : 1u;
        uint32_t is_last = (k + chunk >= k_words) ? 1u : 0u;
        if (!(ws && cached_weights && (k_words <= 2u) && (out_tiles == 1u))) {
          for (uint32_t r = 0; r < rows; ++r) {
            uint32_t wl = host_sram_read32(cur_w);
            cur_w += 4u;
            for (int c = 0; c < 4; ++c) w_buf[r][c] = (int8_t)((wl >> (8 * c)) & 0xFF);
          }
          if (chunk == 2u) {
            for (uint32_t r = 0; r < rows; ++r) {
              uint32_t wh = host_sram_read32(cur_w);
              cur_w += 4u;
              for (int c = 0; c < 4; ++c) w_buf[r][4 + c] = (int8_t)((wh >> (8 * c)) & 0xFF);
            }
          }
        }
        for (uint32_t kc = 0; kc < chunk; ++kc) {
          uint32_t aw = host_sram_read32(cur_a);
          cur_a += 4u;
          for (int c = 0; c < 4; ++c) act_buf[kc * 4u + (uint32_t)c] = (int8_t)((aw >> (8 * c)) & 0xFF);
        }
        for (uint32_t r = 0; r < rows; ++r) {
          int32_t p_sum = 0;
          uint32_t cols = chunk * 4u;
          for (uint32_t c = 0; c < cols; ++c) {
            p_sum += (int32_t)act_buf[c] * (int32_t)w_buf[r][c];
          }
          int32_t acc = ((k != 0u) ? res_buf[r] : 0) + p_sum + ((k == 0u && bias_en) ? b_buf[r] : 0);
          if (is_last) {
            acc = acc >> shift;
            if (relu && acc < 0) acc = 0;
            if (clamp) {
              if (acc > 127) acc = 127;
              if (acc < -128) acc = -128;
            }
          }
          res_buf[r] = acc;
        }
        k += chunk;
      }
      cached_weights = 1;
      {
        uint32_t pw0 = ((uint32_t)sat_s8_u(res_buf[0])) |
                       (((uint32_t)sat_s8_u(res_buf[1])) << 8) |
                       (((uint32_t)sat_s8_u(res_buf[2])) << 16) |
                       (((uint32_t)sat_s8_u(res_buf[3])) << 24);
        host_sram_write32(cur_d, pw0);
        cur_d += 4u;
        if (mode_8out) {
          uint32_t pw1 = ((uint32_t)sat_s8_u(res_buf[4])) |
                         (((uint32_t)sat_s8_u(res_buf[5])) << 8) |
                         (((uint32_t)sat_s8_u(res_buf[6])) << 16) |
                         (((uint32_t)sat_s8_u(res_buf[7])) << 24);
          host_sram_write32(cur_d, pw1);
          cur_d += 4u;
        }
      }
    }
  }
  accel_regs[0xE0u >> 2] = (ctrl & ~0x01u) | 0x02u;
  energy_regs[0x08u >> 2] += 1u;
  energy_regs[0x10u >> 2] += 8u;
}

static void flush_hw_side_effects(void) {
  if (last_addr == (ORX1_ACCEL_BASE + 0x00u)) {
    uint32_t ctrl = accel_regs[0];
    if (ctrl & 0x02u) {
      ctrl &= ~0x02u;
    }
    if (ctrl & 0x40u) {
      for (int r = 0; r < 4; ++r) {
        uint32_t tmp = accel_regs[(0x34 >> 2) + r];
        accel_regs[(0x34 >> 2) + r] = accel_regs[(0x50 >> 2) + r];
        accel_regs[(0x50 >> 2) + r] = tmp;
      }
      ctrl &= ~0x40u;
    }
    if (ctrl & 0x01u) {
      static const uint32_t w_lo_off[8] = {0x34u, 0x38u, 0x3Cu, 0x40u, 0x88u, 0x8Cu, 0x90u, 0x94u};
      static const uint32_t w_hi_off[8] = {0x78u, 0x7Cu, 0x80u, 0x84u, 0x98u, 0x9Cu, 0xA0u, 0xA4u};
      static const uint32_t b_off[8]    = {0x08u, 0x60u, 0x64u, 0x68u, 0xA8u, 0xACu, 0xB0u, 0xB4u};
      static const uint32_t r_off[8]    = {0x04u, 0x44u, 0x48u, 0x4Cu, 0xB8u, 0xBCu, 0xC0u, 0xC4u};
      uint32_t act_lo = accel_regs[0x30 >> 2];
      uint32_t act_hi = accel_regs[0x74 >> 2];
      uint8_t shift = (uint8_t)(accel_regs[0x0C >> 2] & 0x1F);
      int rows = (ctrl & 0x400u) ? 8 : ((ctrl & 0x20u) ? 4 : 1);
      for (int r = 0; r < rows; ++r) {
        accel_regs[r_off[r] >> 2] = (uint32_t)mac_row_hw(
          act_lo, act_hi, accel_regs[w_lo_off[r] >> 2], accel_regs[w_hi_off[r] >> 2],
          (int32_t)accel_regs[r_off[r] >> 2], (int32_t)accel_regs[b_off[r] >> 2], shift, ctrl
        );
      }
      accel_sync_packed();
      ctrl = (ctrl & ~0x01u) | 0x02u;
      energy_regs[0x08 >> 2] += 1;
      energy_regs[0x10 >> 2] += 8;
    }
    accel_regs[0] = ctrl;
  }

  if (last_addr == (ORX1_ACCEL_BASE + 0xE0u)) {
    uint32_t tctrl = accel_regs[0xE0u >> 2];
    if (tctrl & 0x02u) accel_regs[0xE0u >> 2] &= ~0x02u;
    if (tctrl & 0x01u) run_tdma_hw();
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
    int8_t in8[8] = {4, -2, 7, 1, -5, 3, 6, -4};
    int8_t w8[64];
    int32_t b8[8];
    int32_t out_ex[8] = {0};
    int8_t hw8[8] = {0};
    int8_t sw8[8] = {0};
    for (int r = 0; r < 8; ++r) {
      b8[r] = (r - 3) * 15;
      for (int c = 0; c < 8; ++c) {
        w8[r * 8 + c] = (int8_t)(((r * 7 + c * 5 + 3) % 13) - 6);
      }
    }
    tinyml_dense_8x8_ex(in8, w8, b8, out_ex, 1, 1, 0, 1);
    tinyml_dense(in8, w8, b8, hw8, 8, 8, 1, 1);
    ref_dense(in8, w8, b8, sw8, 8, 8, 1, 1);
    for (int r = 0; r < 8; ++r) {
      if ((int32_t)sw8[r] != out_ex[r] || hw8[r] != sw8[r]) {
        printf("FAIL dense_8x8 idx=%d ex=%d hw=%d sw=%d\n", r, out_ex[r], hw8[r], sw8[r]);
        failures++;
      }
    }
  }

  {
    int8_t *act_sram = (int8_t *)&host_sram[0];
    int8_t *w_tiled = (int8_t *)&host_sram[256];
    int32_t *bias_sram = (int32_t *)&host_sram[512];
    int8_t *dst_sram = (int8_t *)&host_sram[768];
    int8_t w_rm[32];
    for (int b = 0; b < 4; ++b) {
      for (int c = 0; c < 8; ++c) {
        act_sram[b * 8 + c] = (int8_t)(((b * 9 + c * 5 + 2) % 21) - 10);
      }
    }
    for (int r = 0; r < 4; ++r) {
      bias_sram[r] = (r * 6) - 8;
      for (int c = 0; c < 8; ++c) {
        w_rm[r * 8 + c] = (int8_t)(((r * 5 + c * 3 + 1) % 11) - 5);
      }
      for (int c = 0; c < 4; ++c) {
        w_tiled[r * 4 + c] = w_rm[r * 8 + c];
        w_tiled[16 + r * 4 + c] = w_rm[r * 8 + 4 + c];
      }
    }
    tinyml_dense_tdma(act_sram, w_tiled, bias_sram, dst_sram, 8, 4, 4, 2, 1, 1);
    for (int b = 0; b < 4; ++b) {
      int8_t ref4[4];
      ref_dense(&act_sram[b * 8], w_rm, bias_sram, ref4, 8, 4, 2, 1);
      for (int r = 0; r < 4; ++r) {
        if (dst_sram[b * 4 + r] != ref4[r]) {
          printf("FAIL tdma b=%d r=%d got=%d exp=%d\n", b, r, dst_sram[b * 4 + r], ref4[r]);
          failures++;
        }
      }
    }
  }

  {
    int32_t d0 = orx_dot4(0x04030201u, 0xfffefdfcu);
    int32_t c0 = orx_clip8(-20, 0x21u);
    int32_t c1 = orx_clip8(500, 0x01u);
    uint32_t p = 0u;
    p = orx_pack4(p, 0x11);
    p = orx_pack4(p, 0x22);
    p = orx_pack4(p, 0x33);
    p = orx_pack4(p, 0x44);
    if (d0 != -20 || c0 != 0 || c1 != 127 || p != 0x44332211u) {
      printf("FAIL custom0: d=%d c0=%d c1=%d p=0x%08x\n", d0, c0, c1, p);
      failures++;
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
