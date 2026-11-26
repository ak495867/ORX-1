#include "tinyml.h"

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

static void launch_and_read_4(uint32_t ctrl, uint8_t shift, int32_t *out_4) {
  ACCEL_SHIFT = (uint32_t)shift;
  ACCEL_CTRL = ctrl;
  while (ACCEL_CTRL & 0x01u) {
  }
  out_4[0] = (int32_t)ACCEL_RESULT_0;
  out_4[1] = (int32_t)ACCEL_RESULT_1;
  out_4[2] = (int32_t)ACCEL_RESULT_2;
  out_4[3] = (int32_t)ACCEL_RESULT_3;
}

void tinyml_init(void) {
  ACCEL_CTRL = 0x02u;
  ACCEL_SHIFT = 0x00u;
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
  int8_t in_buf[4];
  int8_t w_buf[16];
  int32_t b_buf[4];
  int32_t out_res[4];

  if (in_dim <= 0 || out_dim <= 0) return;

  for (int o = 0; o < out_dim; o += 4) {
    for (int r = 0; r < 4; ++r) {
      b_buf[r] = (biases && (o + r < out_dim)) ? biases[o + r] : 0;
    }

    for (int i = 0; i < in_dim; i += 4) {
      for (int c = 0; c < 4; ++c) {
        in_buf[c] = (i + c < in_dim) ? in[i + c] : 0;
      }
      for (int r = 0; r < 4; ++r) {
        for (int c = 0; c < 4; ++c) {
          w_buf[r * 4 + c] = ((o + r < out_dim) && (i + c < in_dim)) ? weights[(o + r) * in_dim + (i + c)] : 0;
        }
      }

      uint8_t is_first = (i == 0) ? 1u : 0u;
      uint8_t is_last = (i + 4 >= in_dim) ? 1u : 0u;
      tinyml_dense_4x4_ex(
        in_buf,
        w_buf,
        (is_first && biases) ? b_buf : 0,
        out_res,
        is_last ? shift : 0u,
        is_last ? relu : 0u,
        is_first ? 0u : 1u,
        is_last
      );
    }

    for (int r = 0; r < 4; ++r) {
      if (o + r < out_dim) {
        out[o + r] = (int8_t)out_res[r];
      }
    }
  }
}
