#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "orx1.h"
#include "tinyml.h"

static uint32_t g_accel_regs[64];
static uint64_t g_hw_launches = 0;
static uint64_t g_hw_macs = 0;
static uint8_t g_host_sram[16384];

uint32_t orx1_host_to_bus(const void *ptr) {
  const uint8_t *p = (const uint8_t *)ptr;
  if (p >= g_host_sram && p < g_host_sram + sizeof(g_host_sram)) {
    return ORX1_SRAM_BASE + (uint32_t)(p - g_host_sram);
  }
  return 0u;
}

static uint32_t sram_rd32(uint32_t bus_addr) {
  uint32_t off = bus_addr - ORX1_SRAM_BASE;
  if (bus_addr < ORX1_SRAM_BASE || off + 4u > sizeof(g_host_sram)) return 0u;
  return ((uint32_t)g_host_sram[off]) |
         (((uint32_t)g_host_sram[off + 1u]) << 8) |
         (((uint32_t)g_host_sram[off + 2u]) << 16) |
         (((uint32_t)g_host_sram[off + 3u]) << 24);
}

static void sram_wr32(uint32_t bus_addr, uint32_t val) {
  uint32_t off = bus_addr - ORX1_SRAM_BASE;
  if (bus_addr < ORX1_SRAM_BASE || off + 4u > sizeof(g_host_sram)) return;
  g_host_sram[off]      = (uint8_t)(val & 0xFFu);
  g_host_sram[off + 1u] = (uint8_t)((val >> 8) & 0xFFu);
  g_host_sram[off + 2u] = (uint8_t)((val >> 16) & 0xFFu);
  g_host_sram[off + 3u] = (uint8_t)((val >> 24) & 0xFFu);
}

static int32_t arith_rshift(int32_t val, uint32_t sh) {
  if (sh == 0u) return val;
  if (sh >= 31u) return (val < 0) ? -1 : 0;
  if (val < 0) {
    return (int32_t)(~((uint32_t)(~val) >> sh));
  }
  return (int32_t)((uint32_t)val >> sh);
}

static uint8_t sat_s8_u(int32_t val) {
  if (val > 127) return 127u;
  if (val < -128) return (uint8_t)(int8_t)-128;
  return (uint8_t)(val & 0xFF);
}

static int32_t hw_mac_row(
  uint32_t act_lo, uint32_t act_hi,
  uint32_t w_lo, uint32_t w_hi,
  int32_t prev, int32_t bias,
  uint32_t sh, uint32_t ctrl
) {
  int8_t a[8];
  int8_t w[8];
  int32_t p_sum = 0;
  int wide = (ctrl & 0x400u) ? 1 : 0;

  for (int i = 0; i < 4; ++i) {
    a[i] = (int8_t)((act_lo >> (8 * i)) & 0xFFu);
    w[i] = (int8_t)((w_lo >> (8 * i)) & 0xFFu);
    a[i + 4] = wide ? (int8_t)((act_hi >> (8 * i)) & 0xFFu) : 0;
    w[i + 4] = wide ? (int8_t)((w_hi >> (8 * i)) & 0xFFu) : 0;
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

  int32_t a_sum = ((ctrl & 0x04u) ? prev : 0) + p_sum + ((ctrl & 0x10u) ? bias : 0);
  int32_t s_sum = arith_rshift(a_sum, sh & 0x1fu);
  int32_t r_sum = ((ctrl & 0x08u) && s_sum < 0) ? 0 : s_sum;

  if (ctrl & 0x100u) {
    if (r_sum > 127) return 127;
    if (r_sum < -128) return -128;
  }
  return r_sum;
}

static void accel_step_if_started(void) {
  uint32_t ctrl = g_accel_regs[0];
  if (ctrl & 0x02u) {
    g_accel_regs[0] &= ~0x02u;
  }
  if ((ctrl & 0x01u) == 0u) return;

  static const uint32_t w_lo_addr[8] = {0x34u/4u, 0x38u/4u, 0x3cu/4u, 0x40u/4u, 0x88u/4u, 0x8cu/4u, 0x90u/4u, 0x94u/4u};
  static const uint32_t w_hi_addr[8] = {0x78u/4u, 0x7cu/4u, 0x80u/4u, 0x84u/4u, 0x98u/4u, 0x9cu/4u, 0xa0u/4u, 0xa4u/4u};
  static const uint32_t b_addr[8]    = {0x08u/4u, 0x60u/4u, 0x64u/4u, 0x68u/4u, 0xa8u/4u, 0xacu/4u, 0xb0u/4u, 0xb4u/4u};
  static const uint32_t r_addr[8]    = {0x04u/4u, 0x44u/4u, 0x48u/4u, 0x4cu/4u, 0xb8u/4u, 0xbcu/4u, 0xc0u/4u, 0xc4u/4u};
  uint32_t act_lo = g_accel_regs[0x30u / 4u];
  uint32_t act_hi = g_accel_regs[0x74u / 4u];
  uint32_t sh = g_accel_regs[0x0cu / 4u];
  uint32_t rows = (ctrl & 0x400u) ? 8u : ((ctrl & 0x20u) ? 4u : 1u);
  uint32_t cols = (ctrl & 0x400u) ? 8u : 4u;

  for (uint32_t r = 0; r < rows; ++r) {
    int32_t res = hw_mac_row(
      act_lo, act_hi,
      g_accel_regs[w_lo_addr[r]],
      g_accel_regs[w_hi_addr[r]],
      (int32_t)g_accel_regs[r_addr[r]],
      (int32_t)g_accel_regs[b_addr[r]],
      sh,
      ctrl
    );
    g_accel_regs[r_addr[r]] = (uint32_t)res;
  }

  {
    uint32_t p0 = 0u, p1 = 0u;
    for (uint32_t r = 0; r < 4u; ++r) {
      p0 |= ((uint32_t)sat_s8_u((int32_t)g_accel_regs[r_addr[r]])) << (8u * r);
      p1 |= ((uint32_t)sat_s8_u((int32_t)g_accel_regs[r_addr[r + 4u]])) << (8u * r);
    }
    g_accel_regs[0x70u / 4u] = p0;
    g_accel_regs[0xc8u / 4u] = p1;
  }

  g_hw_launches += 1u;
  g_hw_macs += (ctrl & 0x80u) ? (rows * (cols / 2u)) : (rows * cols);
  g_accel_regs[0] = (ctrl & ~0x01u) | 0x02u;
}

static void tdma_step_if_started(void) {
  uint32_t ctrl = g_accel_regs[0xE0u / 4u];
  if (ctrl & 0x02u) g_accel_regs[0xE0u / 4u] &= ~0x02u;
  if ((ctrl & 0x01u) == 0u) return;

  uint32_t act_base = g_accel_regs[0xCCu / 4u];
  uint32_t w_base = g_accel_regs[0xD0u / 4u];
  uint32_t b_base = g_accel_regs[0xD4u / 4u];
  uint32_t d_base = g_accel_regs[0xD8u / 4u];
  uint32_t shape = g_accel_regs[0xDCu / 4u];

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
            b_buf[r] = (int32_t)sram_rd32(cur_b);
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
            uint32_t wl = sram_rd32(cur_w);
            cur_w += 4u;
            for (int c = 0; c < 4; ++c) w_buf[r][c] = (int8_t)((wl >> (8 * c)) & 0xFFu);
          }
          if (chunk == 2u) {
            for (uint32_t r = 0; r < rows; ++r) {
              uint32_t wh = sram_rd32(cur_w);
              cur_w += 4u;
              for (int c = 0; c < 4; ++c) w_buf[r][4 + c] = (int8_t)((wh >> (8 * c)) & 0xFFu);
            }
          }
        }
        for (uint32_t kc = 0; kc < chunk; ++kc) {
          uint32_t aw = sram_rd32(cur_a);
          cur_a += 4u;
          for (int c = 0; c < 4; ++c) act_buf[kc * 4u + (uint32_t)c] = (int8_t)((aw >> (8 * c)) & 0xFFu);
        }
        uint32_t cols = chunk * 4u;
        for (uint32_t r = 0; r < rows; ++r) {
          int32_t p_sum = 0;
          for (uint32_t c = 0; c < cols; ++c) {
            p_sum += (int32_t)act_buf[c] * (int32_t)w_buf[r][c];
          }
          int32_t acc = ((k != 0u) ? res_buf[r] : 0) + p_sum + ((k == 0u && bias_en) ? b_buf[r] : 0);
          if (is_last) {
            acc = arith_rshift(acc, shift);
            if (relu && acc < 0) acc = 0;
            if (clamp) {
              if (acc > 127) acc = 127;
              if (acc < -128) acc = -128;
            }
          }
          res_buf[r] = acc;
        }
        g_hw_macs += (uint64_t)rows * (uint64_t)cols;
        k += chunk;
      }
      cached_weights = 1;
      {
        uint32_t pw0 = ((uint32_t)sat_s8_u(res_buf[0])) |
                       (((uint32_t)sat_s8_u(res_buf[1])) << 8) |
                       (((uint32_t)sat_s8_u(res_buf[2])) << 16) |
                       (((uint32_t)sat_s8_u(res_buf[3])) << 24);
        sram_wr32(cur_d, pw0);
        cur_d += 4u;
        if (mode_8out) {
          uint32_t pw1 = ((uint32_t)sat_s8_u(res_buf[4])) |
                         (((uint32_t)sat_s8_u(res_buf[5])) << 8) |
                         (((uint32_t)sat_s8_u(res_buf[6])) << 16) |
                         (((uint32_t)sat_s8_u(res_buf[7])) << 24);
          sram_wr32(cur_d, pw1);
          cur_d += 4u;
        }
      }
    }
  }
  g_hw_launches += 1u;
  g_accel_regs[0xE0u / 4u] = (ctrl & ~0x01u) | 0x02u;
}

volatile uint32_t *orx1_host_reg(uint32_t addr) {
  static uint32_t dummy = 0u;
  if (addr >= ORX1_ACCEL_BASE && addr < ORX1_ACCEL_BASE + 0x100u) {
    uint32_t off = addr - ORX1_ACCEL_BASE;
    if (off == 0u) {
      accel_step_if_started();
    } else if (off == 0xE0u) {
      tdma_step_if_started();
    }
    return &g_accel_regs[off / 4u];
  }
  dummy = 0u;
  return &dummy;
}

static void ref_dense(
  const int8_t *in,
  const int8_t *weights,
  const int32_t *biases,
  int8_t *out,
  int in_dim,
  int out_dim,
  uint8_t shift,
  uint8_t relu
) {
  for (int o = 0; o < out_dim; ++o) {
    int32_t acc = biases ? biases[o] : 0;
    for (int i = 0; i < in_dim; ++i) {
      acc += (int32_t)in[i] * (int32_t)weights[o * in_dim + i];
    }
    int32_t val = arith_rshift(acc, (uint32_t)shift);
    if (relu && val < 0) val = 0;
    if (val > 127) val = 127;
    if (val < -128) val = -128;
    out[o] = (int8_t)val;
  }
}

static int argmax_i8(const int8_t *v, int n) {
  int best = 0;
  for (int i = 1; i < n; ++i) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

static double elapsed_sec(clock_t t0, clock_t t1) {
  double s = (double)(t1 - t0) / (double)CLOCKS_PER_SEC;
  return (s > 1e-9) ? s : 1e-9;
}

static void run_mlp2(
  const int8_t *inp,
  const int8_t *w1, const int32_t *b1, int d1,
  const int8_t *w2, const int32_t *b2, int d_in, int d_out,
  uint8_t sh1, uint8_t sh2,
  int8_t *h_buf, int8_t *out, int use_npu
) {
  if (use_npu) {
    tinyml_dense(inp, w1, b1, h_buf, d_in, d1, sh1, 1);
    tinyml_dense(h_buf, w2, b2, out, d1, d_out, sh2, 0);
  } else {
    ref_dense(inp, w1, b1, h_buf, d_in, d1, sh1, 1);
    ref_dense(h_buf, w2, b2, out, d1, d_out, sh2, 0);
  }
}

static void run_sparse_16x4(
  const int8_t *inp,
  const int8_t *sp_w, const uint8_t *sp_idx, const int32_t *bias,
  int8_t *out
) {
  int32_t acc[4] = {0, 0, 0, 0};
  for (int grp = 0; grp < 4; ++grp) {
    int32_t tile[4];
    tinyml_sparse_2_4(inp + grp * 4, sp_w + grp * 8, sp_idx + grp * 8, NULL, tile, 0, 0);
    for (int r = 0; r < 4; ++r) acc[r] += tile[r];
  }
  for (int r = 0; r < 4; ++r) {
    int32_t v = arith_rshift(acc[r] + bias[r], 3u);
    if (v < 0) v = 0;
    if (v > 127) v = 127;
    out[r] = (int8_t)v;
  }
}

static void record_model(
  FILE *csv, const char *name,
  uint64_t inf_cnt, uint64_t macs, uint64_t launches,
  double dt_api, double dt_ref,
  int exact_cnt, int total_logits, int cls_cnt, int has_cls
) {
  double inf_s = (double)inf_cnt / dt_api;
  double mops = ((double)macs * 2.0 / 1e6) / dt_api;
  printf("C_MODEL %-16s | inf=%7llu | macs/inf=%3llu | npu_ops=%7llu | t_api=%6.3fs | inf/s=%10.0f | MOPS=%6.1f | ref_t=%6.3fs | exact=%3d/%3d | ",
         name, (unsigned long long)inf_cnt, (unsigned long long)(macs / inf_cnt),
         (unsigned long long)launches, dt_api, inf_s, mops, dt_ref, exact_cnt, total_logits);
  if (has_cls) printf("cls=%2d/16\n", cls_cnt);
  else printf("cls= N/A\n");
  if (csv) {
    fprintf(csv, "%s,%llu,%llu,%llu,%.6f,%.1f,%.1f,%.6f,%d,%d\n",
            name, (unsigned long long)inf_cnt, (unsigned long long)(macs / inf_cnt),
            (unsigned long long)launches, dt_api, inf_s, mops, dt_ref, exact_cnt, total_logits);
  }
}

int main(void) {
  int failures = 0;
  int8_t w_8x4[32], w_4x4[16], w_16x8[128], w_8x4_b[32], w_16x4_dense[64], w_16x16[256];
  int8_t sp_w[32];
  uint8_t sp_idx[32];
  int32_t b_4[4], b_8[8], b_16[16], b_out[4];
  int8_t x_16[16 * 16];

  for (int i = 0; i < 32; ++i) w_8x4[i] = (int8_t)(((i * 7 + 3) % 19) - 9);
  for (int i = 0; i < 16; ++i) w_4x4[i] = (int8_t)(((i * 5 + 2) % 17) - 8);
  for (int i = 0; i < 128; ++i) w_16x8[i] = (int8_t)(((i * 11 + 5) % 21) - 10);
  for (int i = 0; i < 32; ++i) w_8x4_b[i] = (int8_t)(((i * 9 + 1) % 15) - 7);
  for (int i = 0; i < 256; ++i) w_16x16[i] = (int8_t)(((i * 13 + 7) % 23) - 11);
  for (int i = 0; i < 4; ++i) {
    b_4[i] = (i - 1) * 12;
    b_out[i] = (i * 8) - 10;
  }
  for (int i = 0; i < 8; ++i) b_8[i] = (i - 3) * 10;
  for (int i = 0; i < 16; ++i) b_16[i] = (i - 7) * 9;

  memset(w_16x4_dense, 0, sizeof(w_16x4_dense));
  for (int grp = 0; grp < 4; ++grp) {
    for (int o = 0; o < 4; ++o) {
      int slot = grp * 4 + o;
      uint8_t i0 = (uint8_t)((o + grp) % 4);
      uint8_t i1 = (uint8_t)((i0 + 2) % 4);
      int8_t v0 = (int8_t)(((slot * 5 + 3) % 13) - 6);
      int8_t v1 = (int8_t)(((slot * 7 + 1) % 13) - 6);
      if (v0 == 0) v0 = 3;
      if (v1 == 0) v1 = -4;
      sp_idx[slot * 2 + 0] = i0;
      sp_idx[slot * 2 + 1] = i1;
      sp_w[slot * 2 + 0] = v0;
      sp_w[slot * 2 + 1] = v1;
      w_16x4_dense[o * 16 + grp * 4 + i0] = v0;
      w_16x4_dense[o * 16 + grp * 4 + i1] = v1;
    }
  }

  for (int s = 0; s < 16; ++s) {
    for (int f = 0; f < 16; ++f) {
      int v = ((s * 13 + f * 7) % 49) - 24;
      if (s >= 12) v += (f & 1) ? 15 : -12;
      if (v > 127) v = 127;
      if (v < -128) v = -128;
      x_16[s * 16 + f] = (int8_t)v;
    }
  }

  tinyml_init();

  const int epochs_m1 = 100000;
  int exact_m1 = 0, class_m1 = 0;
  int8_t h4[4], h8[8], out4_npu[4], out4_ref[4], out16_npu[16], out16_ref[16];
  volatile int sink = 0;

  uint64_t l0 = g_hw_launches, mc0 = g_hw_macs;
  clock_t t0 = clock();
  for (int e = 0; e < epochs_m1; ++e) {
    for (int s = 0; s < 16; ++s) {
      run_mlp2(&x_16[s * 16], w_8x4, b_4, 4, w_4x4, b_out, 8, 4, 3, 3, h4, out4_npu, 1);
      sink += out4_npu[0];
    }
  }
  clock_t t1 = clock();
  uint64_t m1_launches = g_hw_launches - l0, m1_macs = g_hw_macs - mc0;

  clock_t t2 = clock();
  for (int e = 0; e < epochs_m1; ++e) {
    for (int s = 0; s < 16; ++s) {
      run_mlp2(&x_16[s * 16], w_8x4, b_4, 4, w_4x4, b_out, 8, 4, 3, 3, h4, out4_ref, 0);
      sink += out4_ref[0];
    }
  }
  clock_t t3 = clock();

  for (int s = 0; s < 16; ++s) {
    run_mlp2(&x_16[s * 16], w_8x4, b_4, 4, w_4x4, b_out, 8, 4, 3, 3, h4, out4_npu, 1);
    run_mlp2(&x_16[s * 16], w_8x4, b_4, 4, w_4x4, b_out, 8, 4, 3, 3, h4, out4_ref, 0);
    for (int k = 0; k < 4; ++k) {
      if (out4_npu[k] == out4_ref[k]) exact_m1++; else failures++;
    }
    if (argmax_i8(out4_npu, 4) == argmax_i8(out4_ref, 4)) class_m1++; else failures++;
  }

  const int epochs_m2 = 50000;
  int exact_m2 = 0, class_m2 = 0;
  l0 = g_hw_launches; mc0 = g_hw_macs;
  clock_t t4 = clock();
  for (int e = 0; e < epochs_m2; ++e) {
    for (int s = 0; s < 16; ++s) {
      run_mlp2(&x_16[s * 16], w_16x8, b_8, 8, w_8x4_b, b_out, 16, 4, 4, 3, h8, out4_npu, 1);
      sink += out4_npu[0];
    }
  }
  clock_t t5 = clock();
  uint64_t m2_launches = g_hw_launches - l0, m2_macs = g_hw_macs - mc0;

  clock_t t6 = clock();
  for (int e = 0; e < epochs_m2; ++e) {
    for (int s = 0; s < 16; ++s) {
      run_mlp2(&x_16[s * 16], w_16x8, b_8, 8, w_8x4_b, b_out, 16, 4, 4, 3, h8, out4_ref, 0);
      sink += out4_ref[0];
    }
  }
  clock_t t7 = clock();

  for (int s = 0; s < 16; ++s) {
    run_mlp2(&x_16[s * 16], w_16x8, b_8, 8, w_8x4_b, b_out, 16, 4, 4, 3, h8, out4_npu, 1);
    run_mlp2(&x_16[s * 16], w_16x8, b_8, 8, w_8x4_b, b_out, 16, 4, 4, 3, h8, out4_ref, 0);
    for (int k = 0; k < 4; ++k) {
      if (out4_npu[k] == out4_ref[k]) exact_m2++; else failures++;
    }
    if (argmax_i8(out4_npu, 4) == argmax_i8(out4_ref, 4)) class_m2++; else failures++;
  }

  const int epochs_m3 = 100000;
  int exact_m3 = 0;
  l0 = g_hw_launches; mc0 = g_hw_macs;
  clock_t t8 = clock();
  for (int e = 0; e < epochs_m3; ++e) {
    for (int s = 0; s < 16; ++s) {
      run_sparse_16x4(&x_16[s * 16], sp_w, sp_idx, b_out, out4_npu);
      sink += out4_npu[0];
    }
  }
  clock_t t9 = clock();
  uint64_t m3_launches = g_hw_launches - l0, m3_macs = g_hw_macs - mc0;

  clock_t t10 = clock();
  for (int e = 0; e < epochs_m3; ++e) {
    for (int s = 0; s < 16; ++s) {
      ref_dense(&x_16[s * 16], w_16x4_dense, b_out, out4_ref, 16, 4, 3, 1);
      sink += out4_ref[0];
    }
  }
  clock_t t11 = clock();

  for (int s = 0; s < 16; ++s) {
    run_sparse_16x4(&x_16[s * 16], sp_w, sp_idx, b_out, out4_npu);
    ref_dense(&x_16[s * 16], w_16x4_dense, b_out, out4_ref, 16, 4, 3, 1);
    for (int k = 0; k < 4; ++k) {
      if (out4_npu[k] == out4_ref[k]) exact_m3++; else failures++;
    }
  }

  const int epochs_m4 = 50000;
  int exact_m4 = 0;
  l0 = g_hw_launches; mc0 = g_hw_macs;
  clock_t t12 = clock();
  for (int e = 0; e < epochs_m4; ++e) {
    for (int s = 0; s < 16; ++s) {
      tinyml_dense(&x_16[s * 16], w_16x16, b_16, out16_npu, 16, 16, 4, 1);
      sink += out16_npu[0];
    }
  }
  clock_t t13 = clock();
  uint64_t m4_launches = g_hw_launches - l0, m4_macs = g_hw_macs - mc0;

  clock_t t14 = clock();
  for (int e = 0; e < epochs_m4; ++e) {
    for (int s = 0; s < 16; ++s) {
      ref_dense(&x_16[s * 16], w_16x16, b_16, out16_ref, 16, 16, 4, 1);
      sink += out16_ref[0];
    }
  }
  clock_t t15 = clock();

  for (int s = 0; s < 16; ++s) {
    tinyml_dense(&x_16[s * 16], w_16x16, b_16, out16_npu, 16, 16, 4, 1);
    ref_dense(&x_16[s * 16], w_16x16, b_16, out16_ref, 16, 16, 4, 1);
    for (int k = 0; k < 16; ++k) {
      if (out16_npu[k] == out16_ref[k]) exact_m4++; else failures++;
    }
  }

  int8_t *tdma_act = (int8_t *)&g_host_sram[0];
  int8_t *tdma_w1 = (int8_t *)&g_host_sram[256];
  int8_t *tdma_w2 = (int8_t *)&g_host_sram[320];
  int32_t *tdma_b1 = (int32_t *)&g_host_sram[512];
  int32_t *tdma_b2 = (int32_t *)&g_host_sram[576];
  int8_t *tdma_h = (int8_t *)&g_host_sram[768];
  int8_t *tdma_out = (int8_t *)&g_host_sram[1024];

  for (int s = 0; s < 16; ++s) {
    for (int f = 0; f < 8; ++f) tdma_act[s * 8 + f] = x_16[s * 16 + f];
  }
  for (int r = 0; r < 4; ++r) {
    tdma_b1[r] = b_4[r];
    tdma_b2[r] = b_out[r];
    for (int c = 0; c < 4; ++c) {
      tdma_w1[r * 4 + c] = w_8x4[r * 8 + c];
      tdma_w1[16 + r * 4 + c] = w_8x4[r * 8 + 4 + c];
      tdma_w2[r * 4 + c] = w_4x4[r * 4 + c];
    }
  }

  const int epochs_m5 = epochs_m1;
  int exact_m5 = 0, class_m5 = 0;
  l0 = g_hw_launches; mc0 = g_hw_macs;
  clock_t t16 = clock();
  for (int e = 0; e < epochs_m5; ++e) {
    tinyml_dense_tdma(tdma_act, tdma_w1, tdma_b1, tdma_h, 8, 4, 16, 3, 1, 1);
    tinyml_dense_tdma(tdma_h, tdma_w2, tdma_b2, tdma_out, 4, 4, 16, 3, 0, 1);
    sink += tdma_out[0];
  }
  clock_t t17 = clock();
  uint64_t m5_launches = g_hw_launches - l0, m5_macs = g_hw_macs - mc0;

  tinyml_dense_tdma(tdma_act, tdma_w1, tdma_b1, tdma_h, 8, 4, 16, 3, 1, 1);
  tinyml_dense_tdma(tdma_h, tdma_w2, tdma_b2, tdma_out, 4, 4, 16, 3, 0, 1);
  for (int s = 0; s < 16; ++s) {
    run_mlp2(&x_16[s * 16], w_8x4, b_4, 4, w_4x4, b_out, 8, 4, 3, 3, h4, out4_ref, 0);
    for (int k = 0; k < 4; ++k) {
      if (tdma_out[s * 4 + k] == out4_ref[k]) exact_m5++; else failures++;
    }
    if (argmax_i8(&tdma_out[s * 4], 4) == argmax_i8(out4_ref, 4)) class_m5++; else failures++;
  }

  printf("----------------------------------------------------------------------------------------------------------------------------------\n");
  printf("ORX-1 Host C TinyML Model Benchmark (sink=%d)\n", sink);
  printf("----------------------------------------------------------------------------------------------------------------------------------\n");
  FILE *csv = fopen("build/c_model_benchmark.csv", "w");
  if (csv) {
    fprintf(csv, "model,inferences,macs_per_inf,npu_launches,api_time_s,api_inf_per_s,host_mops,ref_time_s,exact_logits,total_logits\n");
  }
  record_model(csv, "mlp_8x4x4",       (uint64_t)epochs_m1 * 16u, m1_macs, m1_launches, elapsed_sec(t0, t1), elapsed_sec(t2, t3), exact_m1, 64, class_m1, 1);
  record_model(csv, "mlp_16x8x4",      (uint64_t)epochs_m2 * 16u, m2_macs, m2_launches, elapsed_sec(t4, t5), elapsed_sec(t6, t7), exact_m2, 64, class_m2, 1);
  record_model(csv, "sparse_2_4_16x4", (uint64_t)epochs_m3 * 16u, m3_macs, m3_launches, elapsed_sec(t8, t9), elapsed_sec(t10, t11), exact_m3, 64, 0, 0);
  record_model(csv, "dense_16x16_8x8", (uint64_t)epochs_m4 * 16u, m4_macs, m4_launches, elapsed_sec(t12, t13), elapsed_sec(t14, t15), exact_m4, 256, 0, 0);
  record_model(csv, "mlp_8x4x4_tdma",  (uint64_t)epochs_m5 * 16u, m5_macs, m5_launches, elapsed_sec(t16, t17), elapsed_sec(t2, t3), exact_m5, 64, class_m5, 1);
  if (csv) fclose(csv);
  printf("----------------------------------------------------------------------------------------------------------------------------------\n");

  if (failures == 0) {
    printf("BENCH_MODELS_PASS\n");
    return 0;
  }
  printf("BENCH_MODELS_FAIL %d\n", failures);
  return 1;
}
