#include "orx1.h"
#include "tinyml.h"

static const int8_t layer1_weights[16] = {
  10, -5,  2,  8,
  -3, 12, -4,  1,
   7,  0, 11, -6,
  -8,  9,  4, 15
};

static const int32_t layer1_biases[4] = {
  16, -8, 4, 32
};

int main(void) {
  uart_puts("ORX1 Edge-AI System Initialized\r\n");

  SENSOR_CTRL = 0x01;
  SENSOR_DEPTH = 0x02;
  SENSOR_THRESH_LOW = 100;
  SENSOR_THRESH_HIGH = 1500;

  tinyml_init();

  int8_t input_features[4] = {12, 45, -20, 30};
  int8_t output_classes[4] = {0, 0, 0, 0};

  ENERGY_CLEAR = 0x01;

  tinyml_dense(input_features, layer1_weights, layer1_biases, output_classes, 4, 4, 3, 1);

  uart_puts("Inference Complete. Output Score: ");
  uart_putc('0' + (output_classes[0] % 10));
  uart_puts("\r\n");

  uint32_t energy = ENERGY_WEIGHTED;
  uart_puts("Weighted Activity: ");
  uart_putc('0' + ((energy / 100) % 10));
  uart_putc('0' + ((energy / 10) % 10));
  uart_putc('0' + (energy % 10));
  uart_puts("\r\n");

  return 0;
}
