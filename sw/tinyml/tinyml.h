#ifndef TINYML_H
#define TINYML_H

#include "orx1.h"

void tinyml_init(void);
void tinyml_dense_4x4(const int8_t *activations, const int8_t *weights_4x4, const int32_t *biases_4, int32_t *out_4, uint8_t shift, uint8_t relu);
void tinyml_dense(const int8_t *in, const int8_t *weights, const int32_t *biases, int8_t *out, int in_dim, int out_dim, uint8_t shift, uint8_t relu);

#endif
