#include "tinyml.h"

#ifdef ORX1_HOST_TEST
extern uint32_t orx1_host_to_bus(const void *ptr);
#else
static uint32_t orx1_host_to_bus(const void *ptr) {
  return (uint32_t)(uintptr_t)ptr;
}
#endif

static uint32_t pack4_i8(int8_t b0, int8_t b1, int8_t b2, int8_t b3) {
  return ((uint32_t)(uint8_t)b0) |
         (((uint32_t)(uint8_t)b1) << 8) |
         (((uint32_t)(uint8_t)b2) << 16) |
         (((uint32_t)(uint8_t)b3) << 24);
}

static void write_biases_4(const int32_t *biases_4) {
  ACCEL_BIAS_0 = (uint32_t)biases_4[0];
  ACCEL_BIAS_1 = (uint32_t)biases_4[1];
  ACCEL_BIAS_2 = (uint32_t)biases_4[2];
  ACCEL_BIAS_3 = (uint32_t)biases_4[3];
}

static void launch_and_wait(uint32_t ctrl, uint8_t shift) {
  ACCEL_SHIFT = (uint32_t)shift;
  ACCEL_CTRL = ctrl;
  while (ACCEL_CTRL & 0x01u) {
  }
}

static void launch_and_read_4(uint32_t ctrl, uint8_t shift, int32_t *out_4) {
  launch_and_wait(ctrl, shift);
  out_4[0] = (int32_t)ACCEL_RESULT_0;
  out_4[1] = (int32_t)ACCEL_RESULT_1;
  out_4[2] = (int32_t)ACCEL_RESULT_2;
  out_4[3] = (int32_t)ACCEL_RESULT_3;
}

void tinyml_init(void) {
  ACCEL_CTRL = 0x02u;
  ACCEL_SHIFT = 0x00u;
  ACCEL_TDMA_CTRL = 0x02u;
}

void tinyml_dense_4x4_ex(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu, uint8_t accum, uint8_t clamp) {
  ACCEL_ACT_PACKED = pack4_i8(activations[0], activations[1], activations[2], activations[3]);
  ACCEL_W_ROW0 = pack4_i8(weights_4x4[0], weights_4x4[1], weights_4x4[2], weights_4x4[3]);
  ACCEL_W_ROW1 = pack4_i8(weights_4x4[4], weights_4x4[5], weights_4x4[6], weights_4x4[7]);
  ACCEL_W_ROW2 = pack4_i8(weights_4x4[8], weights_4x4[9], weights_4x4[10], weights_4x4[11]);
  ACCEL_W_ROW3 = pack4_i8(weights_4x4[12], weights_4x4[13], weights_4x4[14], weights_4x4[15]);

  uint32_t ctrl = 0x23u;
  if (accum) ctrl |= 0x04u;
  if (relu) ctrl |= 0x08u;
  if (biases_4) {
    write_biases_4(biases_4);
    ctrl |= 0x10u;
  }
  if (clamp) ctrl |= 0x100u;

  launch_and_read_4(ctrl, shift, out_4);
}

void tinyml_dense_4x4(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu) {
  tinyml_dense_4x4_ex(activations, weights_4x4, biases_4, out_4, shift, relu, 0u, 0u);
}

void tinyml_dense_8x8_ex(const int8_t *activations, const int8_t *weights_8x8, const int32_t *biases_8, int32_t *out_8, uint8_t shift, uint8_t relu, uint8_t accum, uint8_t clamp) {
  ACCEL_ACT_PACKED = pack4_i8(activations[0], activations[1], activations[2], activations[3]);
  ACCEL_ACT_HI_PACKED = pack4_i8(activations[4], activations[5], activations[6], activations[7]);

  ACCEL_W_ROW0 = pack4_i8(weights_8x8[0], weights_8x8[1], weights_8x8[2], weights_8x8[3]);
  ACCEL_W_ROW1 = pack4_i8(weights_8x8[8], weights_8x8[9], weights_8x8[10], weights_8x8[11]);
  ACCEL_W_ROW2 = pack4_i8(weights_8x8[16], weights_8x8[17], weights_8x8[18], weights_8x8[19]);
  ACCEL_W_ROW3 = pack4_i8(weights_8x8[24], weights_8x8[25], weights_8x8[26], weights_8x8[27]);
  ACCEL_W_HI_ROW0 = pack4_i8(weights_8x8[4], weights_8x8[5], weights_8x8[6], weights_8x8[7]);
  ACCEL_W_HI_ROW1 = pack4_i8(weights_8x8[12], weights_8x8[13], weights_8x8[14], weights_8x8[15]);
  ACCEL_W_HI_ROW2 = pack4_i8(weights_8x8[20], weights_8x8[21], weights_8x8[22], weights_8x8[23]);
  ACCEL_W_HI_ROW3 = pack4_i8(weights_8x8[28], weights_8x8[29], weights_8x8[30], weights_8x8[31]);

  ACCEL_W_ROW4 = pack4_i8(weights_8x8[32], weights_8x8[33], weights_8x8[34], weights_8x8[35]);
  ACCEL_W_ROW5 = pack4_i8(weights_8x8[40], weights_8x8[41], weights_8x8[42], weights_8x8[43]);
  ACCEL_W_ROW6 = pack4_i8(weights_8x8[48], weights_8x8[49], weights_8x8[50], weights_8x8[51]);
  ACCEL_W_ROW7 = pack4_i8(weights_8x8[56], weights_8x8[57], weights_8x8[58], weights_8x8[59]);
  ACCEL_W_HI_ROW4 = pack4_i8(weights_8x8[36], weights_8x8[37], weights_8x8[38], weights_8x8[39]);
  ACCEL_W_HI_ROW5 = pack4_i8(weights_8x8[44], weights_8x8[45], weights_8x8[46], weights_8x8[47]);
  ACCEL_W_HI_ROW6 = pack4_i8(weights_8x8[52], weights_8x8[53], weights_8x8[54], weights_8x8[55]);
  ACCEL_W_HI_ROW7 = pack4_i8(weights_8x8[60], weights_8x8[61], weights_8x8[62], weights_8x8[63]);

  uint32_t ctrl = 0x423u;
  if (accum) ctrl |= 0x04u;
  if (relu) ctrl |= 0x08u;
  if (biases_8) {
    write_biases_4(biases_8);
    ACCEL_BIAS_4 = (uint32_t)biases_8[4];
    ACCEL_BIAS_5 = (uint32_t)biases_8[5];
    ACCEL_BIAS_6 = (uint32_t)biases_8[6];
    ACCEL_BIAS_7 = (uint32_t)biases_8[7];
    ctrl |= 0x10u;
  }
  if (clamp) ctrl |= 0x100u;

  launch_and_wait(ctrl, shift);
  out_8[0] = (int32_t)ACCEL_RESULT_0;
  out_8[1] = (int32_t)ACCEL_RESULT_1;
  out_8[2] = (int32_t)ACCEL_RESULT_2;
  out_8[3] = (int32_t)ACCEL_RESULT_3;
  out_8[4] = (int32_t)ACCEL_RESULT_4;
  out_8[5] = (int32_t)ACCEL_RESULT_5;
  out_8[6] = (int32_t)ACCEL_RESULT_6;
  out_8[7] = (int32_t)ACCEL_RESULT_7;
}

void tinyml_sparse_2_4(const int8_t *activations, const int8_t *sparse_weights_2, const uint8_t *indices_2, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu) {
  ACCEL_ACT_PACKED = pack4_i8(activations[0], activations[1], activations[2], activations[3]);

  uint8_t idx0 = (uint8_t)((indices_2[0] & 0x03u) | ((indices_2[1] & 0x03u) << 2));
  uint8_t idx1 = (uint8_t)((indices_2[2] & 0x03u) | ((indices_2[3] & 0x03u) << 2));
  uint8_t idx2 = (uint8_t)((indices_2[4] & 0x03u) | ((indices_2[5] & 0x03u) << 2));
  uint8_t idx3 = (uint8_t)((indices_2[6] & 0x03u) | ((indices_2[7] & 0x03u) << 2));

  ACCEL_W_ROW0 = pack4_i8(sparse_weights_2[0], sparse_weights_2[1], (int8_t)idx0, 0);
  ACCEL_W_ROW1 = pack4_i8(sparse_weights_2[2], sparse_weights_2[3], (int8_t)idx1, 0);
  ACCEL_W_ROW2 = pack4_i8(sparse_weights_2[4], sparse_weights_2[5], (int8_t)idx2, 0);
  ACCEL_W_ROW3 = pack4_i8(sparse_weights_2[6], sparse_weights_2[7], (int8_t)idx3, 0);

  uint32_t ctrl = 0xa3u;
  if (relu) ctrl |= 0x08u;
  if (biases_4) {
    write_biases_4(biases_4);
    ctrl |= 0x10u;
  }

  launch_and_read_4(ctrl, shift, out_4);
}

void tinyml_dense(const int8_t *in, const int8_t *weights, const int32_t *biases, int8_t *out, int in_dim, int out_dim, uint8_t shift, uint8_t relu) {
  int8_t in_buf[8];
  int8_t w_buf[64];
  int32_t b_buf[8];

  if (in_dim <= 0 || out_dim <= 0) return;

  if ((in_dim > 4) || (out_dim > 4)) {
    for (int o = 0; o < out_dim; o += 8) {
      int use_8out = (out_dim - o > 4) ? 1 : 0;
      for (int r = 0; r < 8; ++r) {
        b_buf[r] = (biases && (o + r < out_dim)) ? biases[o + r] : 0;
      }

      for (int i = 0; i < in_dim; i += 8) {
        int use_8col = (in_dim - i > 4) ? 1 : 0;
        uint8_t is_first = (i == 0) ? 1u : 0u;
        uint8_t is_last = (i + 8 >= in_dim) ? 1u : 0u;

        if (!use_8out && !use_8col) {
          for (int c = 0; c < 4; ++c) {
            in_buf[c] = (i + c < in_dim) ? in[i + c] : 0;
          }
          for (int r = 0; r < 4; ++r) {
            for (int c = 0; c < 4; ++c) {
              w_buf[r * 4 + c] = ((o + r < out_dim) && (i + c < in_dim)) ? weights[(o + r) * in_dim + (i + c)] : 0;
            }
          }
          ACCEL_ACT_PACKED = pack4_i8(in_buf[0], in_buf[1], in_buf[2], in_buf[3]);
          ACCEL_W_ROW0 = pack4_i8(w_buf[0], w_buf[1], w_buf[2], w_buf[3]);
          ACCEL_W_ROW1 = pack4_i8(w_buf[4], w_buf[5], w_buf[6], w_buf[7]);
          ACCEL_W_ROW2 = pack4_i8(w_buf[8], w_buf[9], w_buf[10], w_buf[11]);
          ACCEL_W_ROW3 = pack4_i8(w_buf[12], w_buf[13], w_buf[14], w_buf[15]);
          uint32_t ctrl = 0x23u | (is_first ? 0u : 0x04u) | (is_last ? (relu ? 0x108u : 0x100u) : 0u);
          if (is_first && biases) {
            write_biases_4(b_buf);
            ctrl |= 0x10u;
          }
          launch_and_wait(ctrl, is_last ? shift : 0u);
        } else {
          for (int c = 0; c < 8; ++c) {
            in_buf[c] = (i + c < in_dim) ? in[i + c] : 0;
          }
          for (int r = 0; r < 8; ++r) {
            for (int c = 0; c < 8; ++c) {
              w_buf[r * 8 + c] = ((o + r < out_dim) && (i + c < in_dim)) ? weights[(o + r) * in_dim + (i + c)] : 0;
            }
          }
          ACCEL_ACT_PACKED = pack4_i8(in_buf[0], in_buf[1], in_buf[2], in_buf[3]);
          ACCEL_ACT_HI_PACKED = pack4_i8(in_buf[4], in_buf[5], in_buf[6], in_buf[7]);
          ACCEL_W_ROW0 = pack4_i8(w_buf[0], w_buf[1], w_buf[2], w_buf[3]);
          ACCEL_W_ROW1 = pack4_i8(w_buf[8], w_buf[9], w_buf[10], w_buf[11]);
          ACCEL_W_ROW2 = pack4_i8(w_buf[16], w_buf[17], w_buf[18], w_buf[19]);
          ACCEL_W_ROW3 = pack4_i8(w_buf[24], w_buf[25], w_buf[26], w_buf[27]);
          ACCEL_W_HI_ROW0 = pack4_i8(w_buf[4], w_buf[5], w_buf[6], w_buf[7]);
          ACCEL_W_HI_ROW1 = pack4_i8(w_buf[12], w_buf[13], w_buf[14], w_buf[15]);
          ACCEL_W_HI_ROW2 = pack4_i8(w_buf[20], w_buf[21], w_buf[22], w_buf[23]);
          ACCEL_W_HI_ROW3 = pack4_i8(w_buf[28], w_buf[29], w_buf[30], w_buf[31]);
          ACCEL_W_ROW4 = pack4_i8(w_buf[32], w_buf[33], w_buf[34], w_buf[35]);
          ACCEL_W_ROW5 = pack4_i8(w_buf[40], w_buf[41], w_buf[42], w_buf[43]);
          ACCEL_W_ROW6 = pack4_i8(w_buf[48], w_buf[49], w_buf[50], w_buf[51]);
          ACCEL_W_ROW7 = pack4_i8(w_buf[56], w_buf[57], w_buf[58], w_buf[59]);
          ACCEL_W_HI_ROW4 = pack4_i8(w_buf[36], w_buf[37], w_buf[38], w_buf[39]);
          ACCEL_W_HI_ROW5 = pack4_i8(w_buf[44], w_buf[45], w_buf[46], w_buf[47]);
          ACCEL_W_HI_ROW6 = pack4_i8(w_buf[52], w_buf[53], w_buf[54], w_buf[55]);
          ACCEL_W_HI_ROW7 = pack4_i8(w_buf[60], w_buf[61], w_buf[62], w_buf[63]);
          uint32_t ctrl = 0x423u | (is_first ? 0u : 0x04u) | (is_last ? (relu ? 0x108u : 0x100u) : 0u);
          if (is_first && biases) {
            write_biases_4(b_buf);
            ACCEL_BIAS_4 = (uint32_t)b_buf[4];
            ACCEL_BIAS_5 = (uint32_t)b_buf[5];
            ACCEL_BIAS_6 = (uint32_t)b_buf[6];
            ACCEL_BIAS_7 = (uint32_t)b_buf[7];
            ctrl |= 0x10u;
          }
          launch_and_wait(ctrl, is_last ? shift : 0u);
        }
      }

      uint32_t packed0 = ACCEL_RESULT_PACKED;
      for (int r = 0; r < 4; ++r) {
        if (o + r < out_dim) {
          out[o + r] = (int8_t)((packed0 >> (8 * r)) & 0xFFu);
        }
      }
      if (use_8out) {
        uint32_t packed1 = ACCEL_RESULT_HI_PACKED;
        for (int r = 0; r < 4; ++r) {
          if (o + 4 + r < out_dim) {
            out[o + 4 + r] = (int8_t)((packed1 >> (8 * r)) & 0xFFu);
          }
        }
      }
    }
    return;
  }

  for (int r = 0; r < 4; ++r) {
    b_buf[r] = (biases && (r < out_dim)) ? biases[r] : 0;
  }
  for (int c = 0; c < 4; ++c) {
    in_buf[c] = (c < in_dim) ? in[c] : 0;
  }
  for (int r = 0; r < 4; ++r) {
    for (int c = 0; c < 4; ++c) {
      w_buf[r * 4 + c] = ((r < out_dim) && (c < in_dim)) ? weights[r * in_dim + c] : 0;
    }
  }
  ACCEL_ACT_PACKED = pack4_i8(in_buf[0], in_buf[1], in_buf[2], in_buf[3]);
  ACCEL_W_ROW0 = pack4_i8(w_buf[0], w_buf[1], w_buf[2], w_buf[3]);
  ACCEL_W_ROW1 = pack4_i8(w_buf[4], w_buf[5], w_buf[6], w_buf[7]);
  ACCEL_W_ROW2 = pack4_i8(w_buf[8], w_buf[9], w_buf[10], w_buf[11]);
  ACCEL_W_ROW3 = pack4_i8(w_buf[12], w_buf[13], w_buf[14], w_buf[15]);
  {
    uint32_t ctrl = 0x123u | (relu ? 0x08u : 0u);
    if (biases) {
      write_biases_4(b_buf);
      ctrl |= 0x10u;
    }
    launch_and_wait(ctrl, shift);
  }
  {
    uint32_t packed0 = ACCEL_RESULT_PACKED;
    for (int r = 0; r < 4; ++r) {
      if (r < out_dim) {
        out[r] = (int8_t)((packed0 >> (8 * r)) & 0xFFu);
      }
    }
  }
}

void tinyml_tdma_run(
  uint32_t act_addr, uint32_t w_addr, uint32_t bias_addr, uint32_t dst_addr,
  uint8_t k_words, uint8_t out_tiles, uint8_t batch_cnt,
  uint8_t shift, uint8_t relu, uint8_t bias_en, uint8_t ws, uint8_t clamp, uint8_t mode_8out
) {
  ACCEL_TDMA_ACT_BASE = act_addr;
  ACCEL_TDMA_W_BASE = w_addr;
  ACCEL_TDMA_BIAS_BASE = bias_addr;
  ACCEL_TDMA_DST_BASE = dst_addr;
  ACCEL_TDMA_SHAPE = (((uint32_t)batch_cnt & 0xFFu) << 16) |
                     (((uint32_t)out_tiles & 0x07u) << 8) |
                     ((uint32_t)k_words & 0x1Fu);
  ACCEL_TDMA_CTRL = 0x01u |
                    (ws ? 0x04u : 0u) |
                    (relu ? 0x08u : 0u) |
                    (bias_en ? 0x10u : 0u) |
                    (clamp ? 0x20u : 0u) |
                    (((uint32_t)shift & 0x1Fu) << 6) |
                    (mode_8out ? 0x800u : 0u);
  while (ACCEL_TDMA_CTRL & 0x01u) {
  }
}

void tinyml_dense_tdma(
  const int8_t *act, const int8_t *weights, const int32_t *biases, int8_t *dst,
  int in_dim, int out_dim, int batch_cnt, uint8_t shift, uint8_t relu, uint8_t ws
) {
  uint8_t k_words = (uint8_t)((in_dim + 3) / 4);
  uint8_t mode_8out = (out_dim >= 8 && (out_dim % 8) == 0) ? 1u : 0u;
  uint8_t out_tiles = mode_8out ? (uint8_t)(out_dim / 8) : (uint8_t)((out_dim + 3) / 4);
  tinyml_tdma_run(
    orx1_host_to_bus(act),
    orx1_host_to_bus(weights),
    biases ? orx1_host_to_bus(biases) : 0u,
    orx1_host_to_bus(dst),
    k_words, out_tiles, (uint8_t)batch_cnt,
    shift, relu, biases ? 1u : 0u, ws, 1u, mode_8out
  );
}
