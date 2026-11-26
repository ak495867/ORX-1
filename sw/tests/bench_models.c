#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "orx1.h"
#include "tinyml.h"

static uint32_t g_accel_regs[32];
static uint64_t g_hw_launches = 0;
static uint64_t g_hw_macs = 0;

static int32_t arith_rshift(int32_t val, uint32_t sh) {
  if (sh == 0u) return val;
  if (sh >= 31u) return (val < 0) ? -1 : 0;
  if (val < 0) {
    return (int32_t)(~((uint32_t)(~val) >> sh));
  }
  return (int32_t)((uint32_t)val >> sh);
}

static int32_t hw_mac_row(
  int8_t a0, int8_t a1, int8_t a2, int8_t a3,
  uint32_t w_row_packed, int32_t prev, int32_t bias,
  uint32_t sh, uint32_t ctrl
) {
  int8_t w0 = (int8_t)(w_row_packed & 0xffu);
  int8_t w1 = (int8_t)((w_row_packed >> 8) & 0xffu);
  int8_t w2 = (int8_t)((w_row_packed >> 16) & 0xffu);
  int8_t w3 = (int8_t)((w_row_packed >> 24) & 0xffu);
  int32_t p_sum = 0;

  if (ctrl & 0x80u) {
    int8_t act[4] = {a0, a1, a2, a3};
    uint8_t idx0 = (uint8_t)(w2 & 0x03);
    uint8_t idx1 = (uint8_t)((w2 >> 2) & 0x03);
    p_sum = (int32_t)act[idx0] * (int32_t)w0 + (int32_t)act[idx1] * (int32_t)w1;
  } else {
    p_sum = (int32_t)a0 * (int32_t)w0 +
            (int32_t)a1 * (int32_t)w1 +
            (int32_t)a2 * (int32_t)w2 +
            (int32_t)a3 * (int32_t)w3;
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

  uint32_t act_p = g_accel_regs[0x30u / 4u];
  int8_t a0 = (int8_t)(act_p & 0xffu);
  int8_t a1 = (int8_t)((act_p >> 8) & 0xffu);
  int8_t a2 = (int8_t)((act_p >> 16) & 0xffu);
  int8_t a3 = (int8_t)((act_p >> 24) & 0xffu);

  uint32_t w_addr[4] = {0x34u / 4u, 0x38u / 4u, 0x3cu / 4u, 0x40u / 4u};
  uint32_t b_addr[4] = {0x08u / 4u, 0x60u / 4u, 0x64u / 4u, 0x68u / 4u};
  uint32_t r_addr[4] = {0x04u / 4u, 0x44u / 4u, 0x48u / 4u, 0x4cu / 4u};
  uint32_t sh = g_accel_regs[0x0cu / 4u];
  uint32_t rows = (ctrl & 0x20u) ? 4u : 1u;

  for (uint32_t r = 0; r < rows; ++r) {
    int32_t res = hw_mac_row(
      a0, a1, a2, a3,
      g_accel_regs[w_addr[r]],
      (int32_t)g_accel_regs[r_addr[r]],
      (int32_t)g_accel_regs[b_addr[r]],
      sh,
      ctrl
    );
    g_accel_regs[r_addr[r]] = (uint32_t)res;
  }

  g_hw_launches += 1u;
  g_hw_macs += (ctrl & 0x80u) ? (rows * 2u) : (rows * 4u);
  g_accel_regs[0] = (ctrl & ~0x01u) | 0x02u;
}

volatile uint32_t *orx1_host_reg(uint32_t addr) {
  static uint32_t dummy = 0u;
  if (addr >= ORX1_ACCEL_BASE && addr < ORX1_ACCEL_BASE + 0x80u) {
    uint32_t off = addr - ORX1_ACCEL_BASE;
    if (off == 0u) {
      accel_step_if_started();
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
  int exact_cnt, int cls_cnt, int has_cls
) {
  double inf_s = (double)inf_cnt / dt_api;
  double mops = ((double)macs * 2.0 / 1e6) / dt_api;
  printf("C_MODEL %-16s | inf=%7llu | macs/inf=%3llu | npu_ops=%7llu | t_api=%6.3fs | inf/s=%10.0f | MOPS=%6.1f | ref_t=%6.3fs | exact=%2d/64 | ",
         name, (unsigned long long)inf_cnt, (unsigned long long)(macs / inf_cnt),
         (unsigned long long)launches, dt_api, inf_s, mops, dt_ref, exact_cnt);
  if (has_cls) printf("cls=%2d/16\n", cls_cnt);
  else printf("cls= N/A\n");
  if (csv) {
    fprintf(csv, "%s,%llu,%llu,%llu,%.6f,%.1f,%.1f,%.6f,%d,64\n",
            name, (unsigned long long)inf_cnt, (unsigned long long)(macs / inf_cnt),
            (unsigned long long)launches, dt_api, inf_s, mops, dt_ref, exact_cnt);
  }
}

int main(void) {
  int failures = 0;
  int8_t w_8x4[32], w_4x4[16], w_16x8[128], w_8x4_b[32], w_16x4_dense[64];
  int8_t sp_w[32];
  uint8_t sp_idx[32];
  int32_t b_4[4], b_8[8], b_out[4];
  int8_t x_16[16 * 16];

  for (int i = 0; i < 32; ++i) w_8x4[i] = (int8_t)(((i * 7 + 3) % 19) - 9);
  for (int i = 0; i < 16; ++i) w_4x4[i] = (int8_t)(((i * 5 + 2) % 17) - 8);
  for (int i = 0; i < 128; ++i) w_16x8[i] = (int8_t)(((i * 11 + 5) % 21) - 10);
  for (int i = 0; i < 32; ++i) w_8x4_b[i] = (int8_t)(((i * 9 + 1) % 15) - 7);
  for (int i = 0; i < 4; ++i) {
    b_4[i] = (i - 1) * 12;
    b_out[i] = (i * 8) - 10;
  }
  for (int i = 0; i < 8; ++i) b_8[i] = (i - 3) * 10;

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
  int8_t h4[4], h8[8], out4_npu[4], out4_ref[4];
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

  printf("----------------------------------------------------------------------------------------------------------------------------------\n");
  printf("ORX-1 Host C TinyML Model Benchmark (sink=%d)\n", sink);
  printf("----------------------------------------------------------------------------------------------------------------------------------\n");
  FILE *csv = fopen("build/c_model_benchmark.csv", "w");
  if (csv) {
    fprintf(csv, "model,inferences,macs_per_inf,npu_launches,api_time_s,api_inf_per_s,host_mops,ref_time_s,exact_logits,total_logits\n");
  }
  record_model(csv, "mlp_8x4x4",       (uint64_t)epochs_m1 * 16u, m1_macs, m1_launches, elapsed_sec(t0, t1), elapsed_sec(t2, t3), exact_m1, class_m1, 1);
  record_model(csv, "mlp_16x8x4",      (uint64_t)epochs_m2 * 16u, m2_macs, m2_launches, elapsed_sec(t4, t5), elapsed_sec(t6, t7), exact_m2, class_m2, 1);
  record_model(csv, "sparse_2_4_16x4", (uint64_t)epochs_m3 * 16u, m3_macs, m3_launches, elapsed_sec(t8, t9), elapsed_sec(t10, t11), exact_m3, 0, 0);
  if (csv) fclose(csv);
  printf("----------------------------------------------------------------------------------------------------------------------------------\n");

  if (failures == 0) {
    printf("BENCH_MODELS_PASS\n");
    return 0;
  }
  printf("BENCH_MODELS_FAIL %d\n", failures);
  return 1;
}
