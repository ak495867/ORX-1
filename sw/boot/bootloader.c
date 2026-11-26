#include <stdint.h>
#include "orx1.h"

#define BOOT_MAGIC 0x4F525831u
#define BOOT_SRAM_BASE 0x00010000u
#define BOOT_MAX_WORDS 2048u

static uint32_t spi_flash_xfer32(uint32_t tx_word) {
  SPI_TX_DATA = tx_word;
  SPI_CTRL = 0x49u;
  while (SPI_CTRL & 0x02u) {
  }
  return SPI_RX_DATA;
}

void orx1_boot_abort(void) {
  uart_putc('F');
  for (;;) {
#ifndef ORX1_HOST_TEST
    __asm__ volatile ("wfi");
#else
    break;
#endif
  }
}

int orx1_spi_boot(void) {
  uint32_t *sram_dst = (uint32_t *)(uintptr_t)BOOT_SRAM_BASE;
  uint32_t magic;
  uint32_t word_len;

  SPI_CLK_DIV = 0u;
  SPI_CTRL = 0x08u;

  (void)spi_flash_xfer32(0x03000000u);
  magic = spi_flash_xfer32(0u);
  if (magic != BOOT_MAGIC) {
    SPI_CTRL = 0x00u;
    return -1;
  }

  word_len = spi_flash_xfer32(0u);
  if (word_len == 0u || word_len > BOOT_MAX_WORDS) {
    SPI_CTRL = 0x00u;
    return -2;
  }

  for (uint32_t i = 0; i < 8u; ++i) {
    BOOT_EFUSE_IDX = i;
    BOOT_EFUSE_DATA = spi_flash_xfer32(0u);
  }
  BOOT_CTRL = 0x40u;

  for (uint32_t i = 0; i < word_len; ++i) {
    sram_dst[i] = spi_flash_xfer32(0u);
  }
  SPI_CTRL = 0x00u;

  BOOT_IMAGE_WORDS = word_len;
  BOOT_CTRL = 0xA1u;
  while ((BOOT_CTRL & 0x02u) == 0u) {
  }

  if ((BOOT_CTRL & 0x04u) == 0u) {
    return -3;
  }
  return 0;
}

#ifndef ORX1_HOST_TEST
int main(void) {
  if (orx1_spi_boot() == 0) {
    void (*entry)(void) = (void (*)(void))(uintptr_t)BOOT_SRAM_BASE;
    entry();
  }
  orx1_boot_abort();
  return 0;
}
#endif
