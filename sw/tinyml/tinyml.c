#include "tinyml.h"

void tinyml_init(void) {
  ACCEL_CTRL = 0x02;
  ACCEL_SHIFT = 0x00;
}

void tinyml_dense_4x4(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu) {
  uint32_t act_packed = ((uint32_t)(uint8_t)activations[0]) |
                        (((uint32_t)(uint8_t)activations[1]) << 8) |
                        (((uint32_t)(uint8_t)activations[2]) << 16) |
                        (((uint32_t)(uint8_t)activations[3]) << 24);

  ACCEL_ACT_PACKED = act_packed;

  ACCEL_W_ROW0 = ((uint32_t)(uint8_t)weights_4x4[0]) |
                 (((uint32_t)(uint8_t)weights_4x4[1]) << 8) |
                 (((uint32_t)(uint8_t)weights_4x4[2]) << 16) |
                 (((uint32_t)(uint8_t)weights_4x4[3]) << 24);

  ACCEL_W_ROW1 = ((uint32_t)(uint8_t)weights_4x4[4]) |
                 (((uint32_t)(uint8_t)weights_4x4[5]) << 8) |
                 (((uint32_t)(uint8_t)weights_4x4[6]) << 16) |
                 (((uint32_t)(uint8_t)weights_4x4[7]) << 24);

  ACCEL_W_ROW2 = ((uint32_t)(uint8_t)weights_4x4[8]) |
                 (((uint32_t)(uint8_t)weights_4x4[9]) << 8) |
                 (((uint32_t)(uint8_t)weights_4x4[10]) << 16) |
                 (((uint32_t)(uint8_t)weights_4x4[11]) << 24);

  ACCEL_W_ROW3 = ((uint32_t)(uint8_t)weights_4x4[12]) |
                 (((uint32_t)(uint8_t)weights_4x4[13]) << 8) |
                 (((uint32_t)(uint8_t)weights_4x4[14]) << 16) |
                 (((uint32_t)(uint8_t)weights_4x4[15]) << 24);

  if (biases_4) {
    ACCEL_BIAS_0 = (uint32_t)biases_4[0];
    ACCEL_BIAS_1 = (uint32_t)biases_4[1];
    ACCEL_BIAS_2 = (uint32_t)biases_4[2];
    ACCEL_BIAS_3 = (uint32_t)biases_4[3];
  } else {
    ACCEL_BIAS_0 = 0;
    ACCEL_BIAS_1 = 0;
    ACCEL_BIAS_2 = 0;
    ACCEL_BIAS_3 = 0;
  }

  ACCEL_SHIFT = (uint32_t)shift;

  uint32_t ctrl = 0x21;
  if (relu) ctrl |= 0x08;
  if (biases_4) ctrl |= 0x10;

  ACCEL_CTRL = ctrl;

  while (ACCEL_CTRL & 0x01);

  out_4[0] = (int32_t)ACCEL_RESULT_0;
  out_4[1] = (int32_t)ACCEL_RESULT_1;
  out_4[2] = (int32_t)ACCEL_RESULT_2;
  out_4[3] = (int32_t)ACCEL_RESULT_3;
}

void tinyml_sparse_2_4(const int8_t *activations, const int8_t *sparse_weights_2, const uint8_t *indices_2, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu) {
  uint32_t act_packed = ((uint32_t)(uint8_t)activations[0]) |
                        (((uint32_t)(uint8_t)activations[1]) << 8) |
                        (((uint32_t)(uint8_t)activations[2]) << 16) |
                        (((uint32_t)(uint8_t)activations[3]) << 24);

  ACCEL_ACT_PACKED = act_packed;

  uint8_t idx_byte0 = (indices_2[0] & 0x03) | ((indices_2[1] & 0x03) << 2);
  uint8_t idx_byte1 = (indices_2[2] & 0x03) | ((indices_2[3] & 0x03) << 2);
  uint8_t idx_byte2 = (indices_2[4] & 0x03) | ((indices_2[5] & 0x03) << 2);
  uint8_t idx_byte3 = (indices_2[6] & 0x03) | ((indices_2[7] & 0x03) << 2);

  ACCEL_W_ROW0 = ((uint32_t)(uint8_t)sparse_weights_2[0]) |
                 (((uint32_t)(uint8_t)sparse_weights_2[1]) << 8) |
                 (((uint32_t)idx_byte0) << 16);

  ACCEL_W_ROW1 = ((uint32_t)(uint8_t)sparse_weights_2[2]) |
                 (((uint32_t)(uint8_t)sparse_weights_2[3]) << 8) |
                 (((uint32_t)idx_byte1) << 16);

  ACCEL_W_ROW2 = ((uint32_t)(uint8_t)sparse_weights_2[4]) |
                 (((uint32_t)(uint8_t)sparse_weights_2[5]) << 8) |
                 (((uint32_t)idx_byte2) << 16);

  ACCEL_W_ROW3 = ((uint32_t)(uint8_t)sparse_weights_2[6]) |
                 (((uint32_t)(uint8_t)sparse_weights_2[7]) << 8) |
                 (((uint32_t)idx_byte3) << 16);

  if (biases_4) {
    ACCEL_BIAS_0 = (uint32_t)biases_4[0];
    ACCEL_BIAS_1 = (uint32_t)biases_4[1];
    ACCEL_BIAS_2 = (uint32_t)biases_4[2];
    ACCEL_BIAS_3 = (uint32_t)biases_4[3];
  } else {
    ACCEL_BIAS_0 = 0;
    ACCEL_BIAS_1 = 0;
    ACCEL_BIAS_2 = 0;
    ACCEL_BIAS_3 = 0;
  }

  ACCEL_SHIFT = (uint32_t)shift;

  uint32_t ctrl = 0xa1;
  if (relu) ctrl |= 0x08;
  if (biases_4) ctrl |= 0x10;

  ACCEL_CTRL = ctrl;

  while (ACCEL_CTRL & 0x01);

  out_4[0] = (int32_t)ACCEL_RESULT_0;
  out_4[1] = (int32_t)ACCEL_RESULT_1;
  out_4[2] = (int32_t)ACCEL_RESULT_2;
  out_4[3] = (int32_t)ACCEL_RESULT_3;
}

void tinyml_dense(const int8_t *in, const int8_t *weights, const int32_t *biases, int8_t *out, int in_dim, int out_dim, uint8_t shift, uint8_t relu) {
  int8_t in_buf[4];
  int8_t w_buf[16];
  int32_t b_buf[4];
  int32_t out_acc[4];

  for (int o = 0; o < out_dim; o += 4) {
    for (int r = 0; r < 4; ++r) {
      out_acc[r] = (biases && (o + r < out_dim)) ? biases[o + r] : 0;
    }

    for (int i = 0; i < in_dim; i += 4) {
      for (int c = 0; c < 4; ++c) {
        in_buf[c] = (i + c < in_dim) ? in[i + c] : 0;
      }

      for (int r = 0; r < 4; ++r) {
        for (int c = 0; c < 4; ++c) {
          if ((o + r < out_dim) && (i + c < in_dim)) {
            w_buf[r * 4 + c] = weights[(o + r) * in_dim + (i + c)];
          } else {
            w_buf[r * 4 + c] = 0;
          }
        }
      }

      b_buf[0] = (i == 0) ? out_acc[0] : 0;
      b_buf[1] = (i == 0) ? out_acc[1] : 0;
      b_buf[2] = (i == 0) ? out_acc[2] : 0;
      b_buf[3] = (i == 0) ? out_acc[3] : 0;

      int32_t temp_res[4];
      tinyml_dense_4x4(in_buf, w_buf, b_buf, temp_res, (i + 4 >= in_dim) ? shift : 0, (i + 4 >= in_dim) ? relu : 0);

      for (int r = 0; r < 4; ++r) {
        out_acc[r] = temp_res[r];
      }
    }

    for (int r = 0; r < 4; ++r) {
      if (o + r < out_dim) {
        int32_t val = out_acc[r];
        if (val > 127) val = 127;
        if (val < -128) val = -128;
        out[o + r] = (int8_t)val;
      }
    }
  }
}
