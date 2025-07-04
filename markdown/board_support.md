# Supported Boards

The AtomVM ESP32 Camera driver supports a variety of popular ESP32 and ESP32-S3 boards equipped with OV2640 and compatible camera sensors. This document lists the supported boards, their capabilities, and pin specifications.

---

## Overview

Here is a summary of the supported boards and their hardware identifiers used in the configuration:

| Board ID | SoC | Description | PSRAM | Flash LED |
|---|---|---|---|---|
| `ai_thinker` | ESP32 | AI-Thinker ESP32-CAM | 4 MB | Yes (GPIO 4) |
| `wrover_kit` | ESP32 | ESP32 WROVER-KIT | 4 MB | No |
| `esp32s3_wroom` | ESP32-S3 | ESP32-S3 WROOM with Camera | 8 MB | Yes (GPIO 48) |
| `esp32s3_goouuu` | ESP32-S3 | ESP32-S3 GOOUUU-CAM | 8 MB | Yes (GPIO 48) |
| `esp32s3_xiao` | ESP32-S3 | Seeed Studio XIAO ESP32-S3 Sense | 8 MB | No |
| `lilygo_t_camera_s3` | ESP32-S3 | LilyGO T-Camera S3 | 8 MB | No |
| `lilygo_t_camera` | ESP32 | LilyGO T-Camera Classic (v1.7) | 4 MB | No |
| `lilygo_t_camera_plus` | ESP32 | LilyGO T-Camera Plus | 8 MB | No |
| `lilygo_t_journal` | ESP32 | LilyGO T-Journal | None | No |
| `m5cam` | ESP32 | M5Stack Camera Model A (Classic) | None | Yes (GPIO 14) |
| `m5cam_wide` | ESP32 | M5Stack Camera Model A (Wide Angle) | 4 MB | Yes (GPIO 14) |
| `m5cam_psram` | ESP32 | M5Stack Camera Model B (with PSRAM) | 4 MB | Yes (GPIO 14) |
| `m5cam_timer` | ESP32 | M5Stack Timer Camera / Timer Camera X | 4 MB | No |
| `m5cam_unit_s3_5mp` | ESP32-S3 | M5Stack Unit CamS3-5MP | 8 MB | Yes (GPIO 14) |
| `esp_eye` | ESP32 | Espressif ESP-EYE Reference Board | 8 MB | No |

---

## Board Details

### AI-Thinker ESP32-CAM
* **Board ID**: `ai_thinker` (Default configuration)
* **Description**: The most popular and cost-effective ESP32 camera module.
* **Flash LED**: Connected to GPIO 4.
* **Features**: 4 MB Flash, 520 KB SRAM, 4 MB external PSRAM, and a built-in antenna.

### ESP32 WROVER-KIT
* **Board ID**: `wrover_kit`
* **Description**: Official Espressif development board with camera support.
* **Flash LED**: None.
* **Features**: Integrated LCD display, PSRAM support, and an external antenna connector.

### ESP32-S3 Boards
The ESP32-S3 chip features a dual-core Xtensa LX7 processor running up to 240 MHz, vector instructions for AI/acceleration, and native USB support.

* **ESP32-S3 WROOM** (`esp32s3_wroom`): A standard development board with an ESP32-S3 WROOM-1 module and camera interface. Flash LED is on GPIO 48.
* **ESP32-S3 GOOUUU-CAM** (`esp32s3_goouuu`): A compact development board designed for camera applications. Flash LED is on GPIO 48.
* **Seeed XIAO ESP32-S3 Sense** (`esp32s3_xiao`): A tiny, thumb-sized module with an integrated camera extension board. It supports both the original OV2640 and upgraded OV3660 camera sensors.
* **LilyGO T-Camera S3** (`lilygo_t_camera_s3`): LilyGO's ESP32-S3 camera board. Standard sensor is OV2640 or OV5640 (5MP).
* **M5Stack Unit CamS3-5MP** (`m5cam_unit_s3_5mp`): S3-based camera unit with 8MB PSRAM and flash support.

### LilyGO ESP32 Boards
LilyGO produces several feature-rich ESP32 camera boards, often featuring onboard screens, buttons, and sensors.

* **LilyGO T-Camera** (`lilygo_t_camera`): Classic version (such as v1.7) containing a PIR sensor and 128x64 OLED display.
* **LilyGO T-Camera Plus** (`lilygo_t_camera_plus`): Classic ESP32 version featuring a 1.3-inch TFT color screen, MicroSD card slot, and microphone.
* **LilyGO T-Journal** (`lilygo_t_journal`): A board with an external Wi-Fi antenna connector, SSD1306 OLED display, and camera.

### M5Stack Camera Boards
M5Stack offers several compact camera modules. The driver supports the original `m5cam`, its wide-angle/PSRAM variants, and the newer low-power Timer/Unit models.

* **M5CAM** (`m5cam`): Original version without external PSRAM.
* **M5CAM-WIDE** (`m5cam_wide`): Wide-angle (150° FOV) lens version with 4 MB PSRAM.
* **M5CAM-PSRAM** (`m5cam_psram`): Model B camera with 4 MB PSRAM.
* **Timer Camera / Timer Camera X** (`m5cam_timer`): Low-power modules equipped with BM8563 RTC and OV3660 sensor.
* **Unit CamS3-5MP** (`m5cam_unit_s3_5mp`): High-resolution module based on ESP32-S3.

### Espressif Reference Boards
* **ESP-EYE** (`esp_eye`): First-party development board for image and speech recognition.

---

## Flash Pin Mapping

If your application controls the flash LED programmatically using `esp32cam:capture/1` or `esp32cam:capture_with_flash/2`, the driver automatically configures and controls the correct GPIO pin based on the initialized board type:

* **GPIO 4**: `ai_thinker`
* **GPIO 14**: `m5cam`, `m5cam_wide`, `m5cam_psram`, `m5cam_unit_s3_5mp`
* **GPIO 48**: `esp32s3_wroom`, `esp32s3_goouuu`
* **Unsupported (undefined)**: `lilygo_t_camera_s3`, `lilygo_t_camera`, `lilygo_t_camera_plus`, `lilygo_t_journal`, `m5cam_timer`, `esp_eye`, `esp32s3_xiao`, `wrover_kit` (Flash commands will do nothing)


---

## Custom Board Pin Configuration

If you have a board that is not on the list of predefined board types, you can initialize the camera by setting `{board, custom}` and passing the custom pin assignments directly in the configuration proplist:

```erlang
esp32cam:init([
    {board, custom},
    {pin_xclk, 10},
    {pin_pclk, 13},
    {pin_vsync, 38},
    {pin_href, 47},
    {pin_sccb_sda, 40},
    {pin_sccb_scl, 39},
    {pin_d0, 15},
    {pin_d1, 17},
    {pin_d2, 18},
    {pin_d3, 16},
    {pin_d4, 14},
    {pin_d5, 12},
    {pin_d6, 11},
    {pin_d7, 48},
    {pin_pwdn, -1},   % Optional (defaults to -1)
    {pin_reset, -1},  % Optional (defaults to -1)
    {pin_flash, 25}   % Optional (defaults to -1)
]).
```

The camera data pins (`d0`–`d7`), bus control signals (`xclk`, `pclk`, `vsync`, `href`), and SCCB interface pins (`sccb_sda`, `sccb_scl`) are **mandatory** when using a custom board configuration. Optional pins default to `-1` (not connected) if omitted.
