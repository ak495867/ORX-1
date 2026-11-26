#ifndef TINYML_H
#define TINYML_H

#include "orx1.h"

void tinyml_init(void);
void tinyml_dense_4x4_ex(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu, uint8_t accum, uint8_t clamp);
void tinyml_dense_4x4(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu);
void tinyml_dense_8x8_ex(const int8_t *activations, const int8_t *weights_8x8, const int32_t *biases_8, int32_t *out_8, uint8_t shift, uint8_t relu, uint8_t accum, uint8_t clamp);
void tinyml_sparse_2_4(const int8_t *activations, const int8_t *sparse_weights_2, const uint8_t *indices_2, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu);
void tinyml_dense(const int8_t *in, const int8_t *weights, const int32_t *biases, int8_t *out, int in_dim, int out_dim, uint8_t shift, uint8_t relu);
void tinyml_tdma_run(uint32_t act_addr, uint32_t w_addr, uint32_t bias_addr, uint32_t dst_addr, uint8_t k_words, uint8_t out_tiles, uint8_t batch_cnt, uint8_t shift, uint8_t relu, uint8_t bias_en, uint8_t ws, uint8_t clamp, uint8_t mode_8out);
void tinyml_dense_tdma(const int8_t *act, const int8_t *weights, const int32_t *biases, int8_t *dst, int in_dim, int out_dim, int batch_cnt, uint8_t shift, uint8_t relu, uint8_t ws);

#endif
