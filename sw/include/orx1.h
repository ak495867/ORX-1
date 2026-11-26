#ifndef ORX1_H
#define ORX1_H

#include <stdint.h>

#ifdef ORX1_HOST_TEST
extern volatile uint32_t *orx1_host_reg(uint32_t addr);
#define REG32(addr) (*orx1_host_reg((uint32_t)(addr)))
#else
#define REG32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#endif

#define ORX1_BOOT_BASE     0x00000000
#define ORX1_SRAM_BASE     0x00010000
#define ORX1_SENSOR_BASE   0x40000000
#define ORX1_ACCEL_BASE    0x40001000
#define ORX1_BOOTCTRL_BASE 0x40002000
#define ORX1_UART_BASE     0x40003000
#define ORX1_ENERGY_BASE   0x40004000
#define ORX1_TIMER_BASE    0x40005000
#define ORX1_DMA_BASE      0x40006000
#define ORX1_CORDIC_BASE   0x40007000
#define ORX1_IRQ_BASE      0x40008000
#define ORX1_GPIO_BASE     0x40009000
#define ORX1_SPI_BASE      0x4000A000
#define ORX1_SYS_BASE      0x4000B000

#define SENSOR_CTRL        REG32(ORX1_SENSOR_BASE + 0x00)
#define SENSOR_IRQ         REG32(ORX1_SENSOR_BASE + 0x04)
#define SENSOR_CLEAR       REG32(ORX1_SENSOR_BASE + 0x04)
#define SENSOR_RESULT      REG32(ORX1_SENSOR_BASE + 0x08)
#define SENSOR_INJECT      REG32(ORX1_SENSOR_BASE + 0x08)
#define SENSOR_VALID       REG32(ORX1_SENSOR_BASE + 0x0C)
#define SENSOR_DEPTH       REG32(ORX1_SENSOR_BASE + 0x10)
#define SENSOR_THRESH_LOW  REG32(ORX1_SENSOR_BASE + 0x14)
#define SENSOR_THRESH_HIGH REG32(ORX1_SENSOR_BASE + 0x18)
#define SENSOR_ALERT       REG32(ORX1_SENSOR_BASE + 0x1C)

#define ACCEL_CTRL         REG32(ORX1_ACCEL_BASE + 0x00)
#define ACCEL_RESULT_0     REG32(ORX1_ACCEL_BASE + 0x04)
#define ACCEL_BIAS_0       REG32(ORX1_ACCEL_BASE + 0x08)
#define ACCEL_SHIFT        REG32(ORX1_ACCEL_BASE + 0x0C)
#define ACCEL_ACT_0        REG32(ORX1_ACCEL_BASE + 0x10)
#define ACCEL_ACT_1        REG32(ORX1_ACCEL_BASE + 0x14)
#define ACCEL_ACT_2        REG32(ORX1_ACCEL_BASE + 0x18)
#define ACCEL_ACT_3        REG32(ORX1_ACCEL_BASE + 0x1C)
#define ACCEL_W_0          REG32(ORX1_ACCEL_BASE + 0x20)
#define ACCEL_W_1          REG32(ORX1_ACCEL_BASE + 0x24)
#define ACCEL_W_2          REG32(ORX1_ACCEL_BASE + 0x28)
#define ACCEL_W_3          REG32(ORX1_ACCEL_BASE + 0x2C)
#define ACCEL_ACT_PACKED   REG32(ORX1_ACCEL_BASE + 0x30)
#define ACCEL_W_ROW0       REG32(ORX1_ACCEL_BASE + 0x34)
#define ACCEL_W_ROW1       REG32(ORX1_ACCEL_BASE + 0x38)
#define ACCEL_W_ROW2       REG32(ORX1_ACCEL_BASE + 0x3C)
#define ACCEL_W_ROW3       REG32(ORX1_ACCEL_BASE + 0x40)
#define ACCEL_RESULT_1     REG32(ORX1_ACCEL_BASE + 0x44)
#define ACCEL_RESULT_2     REG32(ORX1_ACCEL_BASE + 0x48)
#define ACCEL_RESULT_3     REG32(ORX1_ACCEL_BASE + 0x4C)
#define ACCEL_SW_ROW0      REG32(ORX1_ACCEL_BASE + 0x50)
#define ACCEL_SW_ROW1      REG32(ORX1_ACCEL_BASE + 0x54)
#define ACCEL_SW_ROW2      REG32(ORX1_ACCEL_BASE + 0x58)
#define ACCEL_SW_ROW3      REG32(ORX1_ACCEL_BASE + 0x5C)
#define ACCEL_BIAS_1       REG32(ORX1_ACCEL_BASE + 0x60)
#define ACCEL_BIAS_2       REG32(ORX1_ACCEL_BASE + 0x64)
#define ACCEL_BIAS_3       REG32(ORX1_ACCEL_BASE + 0x68)
#define ACCEL_THRESH       REG32(ORX1_ACCEL_BASE + 0x6C)
#define ACCEL_RESULT_PACKED    REG32(ORX1_ACCEL_BASE + 0x70)
#define ACCEL_ACT_HI_PACKED    REG32(ORX1_ACCEL_BASE + 0x74)
#define ACCEL_W_HI_ROW0        REG32(ORX1_ACCEL_BASE + 0x78)
#define ACCEL_W_HI_ROW1        REG32(ORX1_ACCEL_BASE + 0x7C)
#define ACCEL_W_HI_ROW2        REG32(ORX1_ACCEL_BASE + 0x80)
#define ACCEL_W_HI_ROW3        REG32(ORX1_ACCEL_BASE + 0x84)
#define ACCEL_W_ROW4           REG32(ORX1_ACCEL_BASE + 0x88)
#define ACCEL_W_ROW5           REG32(ORX1_ACCEL_BASE + 0x8C)
#define ACCEL_W_ROW6           REG32(ORX1_ACCEL_BASE + 0x90)
#define ACCEL_W_ROW7           REG32(ORX1_ACCEL_BASE + 0x94)
#define ACCEL_W_HI_ROW4        REG32(ORX1_ACCEL_BASE + 0x98)
#define ACCEL_W_HI_ROW5        REG32(ORX1_ACCEL_BASE + 0x9C)
#define ACCEL_W_HI_ROW6        REG32(ORX1_ACCEL_BASE + 0xA0)
#define ACCEL_W_HI_ROW7        REG32(ORX1_ACCEL_BASE + 0xA4)
#define ACCEL_BIAS_4           REG32(ORX1_ACCEL_BASE + 0xA8)
#define ACCEL_BIAS_5           REG32(ORX1_ACCEL_BASE + 0xAC)
#define ACCEL_BIAS_6           REG32(ORX1_ACCEL_BASE + 0xB0)
#define ACCEL_BIAS_7           REG32(ORX1_ACCEL_BASE + 0xB4)
#define ACCEL_RESULT_4         REG32(ORX1_ACCEL_BASE + 0xB8)
#define ACCEL_RESULT_5         REG32(ORX1_ACCEL_BASE + 0xBC)
#define ACCEL_RESULT_6         REG32(ORX1_ACCEL_BASE + 0xC0)
#define ACCEL_RESULT_7         REG32(ORX1_ACCEL_BASE + 0xC4)
#define ACCEL_RESULT_HI_PACKED REG32(ORX1_ACCEL_BASE + 0xC8)
#define ACCEL_TDMA_ACT_BASE    REG32(ORX1_ACCEL_BASE + 0xCC)
#define ACCEL_TDMA_W_BASE      REG32(ORX1_ACCEL_BASE + 0xD0)
#define ACCEL_TDMA_BIAS_BASE   REG32(ORX1_ACCEL_BASE + 0xD4)
#define ACCEL_TDMA_DST_BASE    REG32(ORX1_ACCEL_BASE + 0xD8)
#define ACCEL_TDMA_SHAPE       REG32(ORX1_ACCEL_BASE + 0xDC)
#define ACCEL_TDMA_CTRL        REG32(ORX1_ACCEL_BASE + 0xE0)

#define BOOT_CTRL          REG32(ORX1_BOOTCTRL_BASE + 0x00)
#define BOOT_DIGEST        REG32(ORX1_BOOTCTRL_BASE + 0x04)
#define BOOT_EXPECTED      REG32(ORX1_BOOTCTRL_BASE + 0x08)
#define BOOT_EFUSE_IDX     REG32(ORX1_BOOTCTRL_BASE + 0x0C)
#define BOOT_EFUSE_DATA    REG32(ORX1_BOOTCTRL_BASE + 0x10)
#define BOOT_IMAGE_WORDS   REG32(ORX1_BOOTCTRL_BASE + 0x14)
#define BOOT_DIGEST_WORD   REG32(ORX1_BOOTCTRL_BASE + 0x18)

#define UART_DATA          REG32(ORX1_UART_BASE + 0x00)
#define UART_STATUS        REG32(ORX1_UART_BASE + 0x04)
#define UART_BAUD          REG32(ORX1_UART_BASE + 0x08)
#define UART_CLEAR         REG32(ORX1_UART_BASE + 0x0C)
#define UART_IRQ_EN        REG32(ORX1_UART_BASE + 0x10)

#define ENERGY_CYCLES      REG32(ORX1_ENERGY_BASE + 0x00)
#define ENERGY_SENSOR      REG32(ORX1_ENERGY_BASE + 0x04)
#define ENERGY_ACCEL       REG32(ORX1_ENERGY_BASE + 0x08)
#define ENERGY_MEM         REG32(ORX1_ENERGY_BASE + 0x0C)
#define ENERGY_WEIGHTED    REG32(ORX1_ENERGY_BASE + 0x10)
#define ENERGY_CLEAR       REG32(ORX1_ENERGY_BASE + 0x14)
#define ENERGY_CPU_CYCLES  REG32(ORX1_ENERGY_BASE + 0x18)
#define ENERGY_CPU_INSTRET REG32(ORX1_ENERGY_BASE + 0x1C)
#define ENERGY_CPU_LOADS   REG32(ORX1_ENERGY_BASE + 0x20)
#define ENERGY_CPU_STORES  REG32(ORX1_ENERGY_BASE + 0x24)
#define ENERGY_CPU_BRANCH  REG32(ORX1_ENERGY_BASE + 0x28)
#define ENERGY_CPU_BUSREQ  REG32(ORX1_ENERGY_BASE + 0x2C)
#define ENERGY_CPU_WAITS   REG32(ORX1_ENERGY_BASE + 0x30)
#define ENERGY_ACTIVE      REG32(ORX1_ENERGY_BASE + 0x34)
#define ENERGY_SLEEP       REG32(ORX1_ENERGY_BASE + 0x38)

#define TIMER_MTIME_L      REG32(ORX1_TIMER_BASE + 0x00)
#define TIMER_MTIME_H      REG32(ORX1_TIMER_BASE + 0x04)
#define TIMER_MTIMECMP_L   REG32(ORX1_TIMER_BASE + 0x08)
#define TIMER_MTIMECMP_H   REG32(ORX1_TIMER_BASE + 0x0C)

#define DMA_SRC            REG32(ORX1_DMA_BASE + 0x00)
#define DMA_DST            REG32(ORX1_DMA_BASE + 0x04)
#define DMA_LEN            REG32(ORX1_DMA_BASE + 0x08)
#define DMA_CTRL           REG32(ORX1_DMA_BASE + 0x0C)
#define DMA_CH1_SRC        REG32(ORX1_DMA_BASE + 0x10)
#define DMA_CH1_DST        REG32(ORX1_DMA_BASE + 0x14)
#define DMA_CH1_LEN        REG32(ORX1_DMA_BASE + 0x18)
#define DMA_CH1_CTRL       REG32(ORX1_DMA_BASE + 0x1C)

#define CORDIC_CTRL        REG32(ORX1_CORDIC_BASE + 0x00)
#define CORDIC_X           REG32(ORX1_CORDIC_BASE + 0x04)
#define CORDIC_Y           REG32(ORX1_CORDIC_BASE + 0x08)
#define CORDIC_Z           REG32(ORX1_CORDIC_BASE + 0x0C)
#define CORDIC_MAG         REG32(ORX1_CORDIC_BASE + 0x10)

#define IRQ_PENDING        REG32(ORX1_IRQ_BASE + 0x00)
#define IRQ_ENABLE         REG32(ORX1_IRQ_BASE + 0x04)
#define IRQ_STATUS         REG32(ORX1_IRQ_BASE + 0x08)

#define GPIO_IN            REG32(ORX1_GPIO_BASE + 0x00)
#define GPIO_OUT           REG32(ORX1_GPIO_BASE + 0x04)
#define GPIO_OE            REG32(ORX1_GPIO_BASE + 0x08)
#define GPIO_IRQ_EN        REG32(ORX1_GPIO_BASE + 0x0C)
#define GPIO_IRQ_STATUS    REG32(ORX1_GPIO_BASE + 0x10)

#define SPI_CTRL           REG32(ORX1_SPI_BASE + 0x00)
#define SPI_TX_DATA        REG32(ORX1_SPI_BASE + 0x04)
#define SPI_RX_DATA        REG32(ORX1_SPI_BASE + 0x08)
#define SPI_CLK_DIV        REG32(ORX1_SPI_BASE + 0x0C)

#define SYS_BOOT_CTRL      REG32(ORX1_SYS_BASE + 0x00)
#define SYS_WDT_LOAD       REG32(ORX1_SYS_BASE + 0x04)
#define SYS_WDT_CTRL       REG32(ORX1_SYS_BASE + 0x08)
#define SYS_WDT_COUNT      REG32(ORX1_SYS_BASE + 0x0C)

static inline int32_t orx_dot4(uint32_t a, uint32_t b) {
#ifdef ORX1_HOST_TEST
  int32_t sum = 0;
  for (int i = 0; i < 4; ++i) {
    int8_t av = (int8_t)((a >> (8 * i)) & 0xFFu);
    int8_t bv = (int8_t)((b >> (8 * i)) & 0xFFu);
    sum += (int32_t)av * (int32_t)bv;
  }
  return sum;
#else
  int32_t res;
  __asm__ volatile (".insn r 0x0b, 0, 0, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
  return res;
#endif
}

static inline int32_t orx_clip8(int32_t val, uint32_t ctrl) {
#ifdef ORX1_HOST_TEST
  uint32_t sh = ctrl & 0x1Fu;
  int32_t sh_val;
  if (sh == 0u) sh_val = val;
  else if (val < 0) sh_val = (int32_t)(~((uint32_t)(~val) >> sh));
  else sh_val = (int32_t)((uint32_t)val >> sh);
  if ((ctrl & 0x20u) && (sh_val < 0)) sh_val = 0;
  if (sh_val > 127) sh_val = 127;
  if (sh_val < -128) sh_val = -128;
  return sh_val;
#else
  int32_t res;
  __asm__ volatile (".insn r 0x0b, 1, 0, %0, %1, %2" : "=r"(res) : "r"(val), "r"(ctrl));
  return res;
#endif
}

static inline uint32_t orx_pack4(uint32_t acc, int32_t val) {
#ifdef ORX1_HOST_TEST
  return ((((uint32_t)(uint8_t)val) & 0xFFu) << 24) | (acc >> 8);
#else
  uint32_t res;
  __asm__ volatile (".insn r 0x0b, 2, 0, %0, %1, %2" : "=r"(res) : "r"(acc), "r"(val));
  return res;
#endif
}

static inline int32_t cordic_vector_magnitude(int16_t x, int16_t y) {
  CORDIC_X = (int32_t)x;
  CORDIC_Y = (int32_t)y;
  CORDIC_Z = 0;
  CORDIC_CTRL = 0x04;
  while (CORDIC_CTRL & 0x02);
  return (int32_t)CORDIC_MAG;
}

static inline void cordic_rotate(int16_t x, int16_t y, int16_t angle, int16_t *out_x, int16_t *out_y) {
  CORDIC_X = (int32_t)x;
  CORDIC_Y = (int32_t)y;
  CORDIC_Z = (int32_t)angle;
  CORDIC_CTRL = 0x05;
  while (CORDIC_CTRL & 0x02);
  if (out_x) *out_x = (int16_t)CORDIC_X;
  if (out_y) *out_y = (int16_t)CORDIC_Y;
}

static inline void uart_putc(char c) {
  while (UART_STATUS & 0x01);
  UART_DATA = (uint32_t)c;
}

static inline void uart_puts(const char *s) {
  while (*s) {
    uart_putc(*s++);
  }
}

static inline uint32_t timer_get_cycles(void) {
  return TIMER_MTIME_L;
}

#endif
