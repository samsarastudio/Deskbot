#pragma once

/* Reserved onboard pins — do not reassign without checking the Waveshare schematic. */
#define PIN_TF_CS        4
#define PIN_TF_MISO      5
#define PIN_SPI_MOSI     6   /* LCD + TF shared */
#define PIN_SPI_SCLK     7   /* LCD + TF shared */
#define PIN_RGB          8
#define PIN_LCD_CS       14
#define PIN_LCD_DC       15
#define PIN_LCD_RST      21
#define PIN_LCD_BL       22

/*
 * I2S / I2C / PCA9685 pins must be chosen from free header GPIOs on the
 * specific board revision. Leave unset until the schematic is confirmed.
 */
#define PIN_I2S_MIC_SCK  -1
#define PIN_I2S_MIC_WS   -1
#define PIN_I2S_MIC_SD   -1
#define PIN_I2S_SPK_BCLK -1
#define PIN_I2S_SPK_LRC  -1
#define PIN_I2S_SPK_DIN  -1
#define PIN_I2C_SDA      -1
#define PIN_I2C_SCL      -1
