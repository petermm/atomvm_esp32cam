//
// Copyright (c) dushin.net
// All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#include <atomvm_esp32cam.h>
#include <context.h>
#include <defaultatoms.h>
#include <driver/gpio.h>
#include <esp32_sys.h>
#include <esp_camera.h>
#include <esp_heap_caps.h>
#include <esp_log.h>
#include <interop.h>
#include <nifs.h>
#include <erl_nif_priv.h>
#include <port.h>
#include <sdkconfig.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <term.h>
// GPIO control moved to Erlang level
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <resources.h>

#define DEFAULT_JPEG_QUALITY 12
#define INVALID_JPEG_QUALITY -1
#define DEFAULT_XCLK_FREQ_HZ 20000000
#define DEFAULT_FB_COUNT 1
#define DEFAULT_SCCB_I2C_PORT 0
#define DEFAULT_LEDC_TIMER 0
#define DEFAULT_LEDC_CHANNEL 0
#define DEFAULT_CONV_MODE 0
#define MAX_WARM_UP_FRAMES 100
#define MAX_TERM_IMAGE_SIZE 262144
#define TERM_IMAGE_BASE64_BUFFER_SIZE 512
#define INVALID_CONFIG_VALUE -1
#define INVALID_PIN_VALUE -2

struct CameraFrame {
    camera_fb_t *fb;
    bool released;
    int active_views;
};

struct CameraView {
    struct CameraFrame *frame;
};

static SemaphoreHandle_t camera_mutex = NULL;
static int configured_fb_count = DEFAULT_FB_COUNT;
static int outstanding_leases = 0;
static ErlNifResourceType *camera_frame_resource_type = NULL;
static ErlNifResourceType *camera_view_resource_type = NULL;
static bool camera_resources_ready = false;

#define LOCK()   xSemaphoreTakeRecursive(camera_mutex, portMAX_DELAY)
#define UNLOCK() xSemaphoreGiveRecursive(camera_mutex)

#define ENABLE_TRACE
#include "trace.h"

#define TAG "atomvm_esp32cam"

// Board configuration structure
typedef struct
{
    int pin_pwdn;
    int pin_reset;
    int pin_xclk;
    int pin_sccb_sda;
    int pin_sccb_scl;
    int pin_d7;
    int pin_d6;
    int pin_d5;
    int pin_d4;
    int pin_d3;
    int pin_d2;
    int pin_d1;
    int pin_d0;
    int pin_vsync;
    int pin_href;
    int pin_pclk;
    int pin_flash;
    const char *name;
} board_config_t;

// Board type enumeration
typedef enum
{
    BOARD_AI_THINKER = 0,
    BOARD_WROVER_KIT,
    BOARD_ESP32S3_WROOM,
    BOARD_ESP32S3_GOOUUU,
    BOARD_ESP32S3_XIAO,
    BOARD_M5CAM,
    BOARD_M5CAM_WIDE,
    BOARD_M5CAM_PSRAM,
    BOARD_LILYGO_T_CAMERA_S3,
    BOARD_LILYGO_T_CAMERA,
    BOARD_LILYGO_T_CAMERA_PLUS,
    BOARD_LILYGO_T_JOURNAL,
    BOARD_M5CAM_TIMER,
    BOARD_M5CAM_UNIT_S3_5MP,
    BOARD_ESP_EYE,
    BOARD_CUSTOM,
    BOARD_INVALID
} board_type_t;

// Predefined board configurations
static const board_config_t board_configs[] = {
    // AI-THINKER (ESP32CAM)
    {
        .pin_pwdn = 32,
        .pin_reset = -1,
        .pin_xclk = 0,
        .pin_sccb_sda = 26,
        .pin_sccb_scl = 27,
        .pin_d7 = 35,
        .pin_d6 = 34,
        .pin_d5 = 39,
        .pin_d4 = 36,
        .pin_d3 = 21,
        .pin_d2 = 19,
        .pin_d1 = 18,
        .pin_d0 = 5,
        .pin_vsync = 25,
        .pin_href = 23,
        .pin_pclk = 22,
        .pin_flash = 4,
        .name = "AI-THINKER" },
    // WROVER-KIT
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 21,
        .pin_sccb_sda = 26,
        .pin_sccb_scl = 27,
        .pin_d7 = 35,
        .pin_d6 = 34,
        .pin_d5 = 39,
        .pin_d4 = 36,
        .pin_d3 = 19,
        .pin_d2 = 18,
        .pin_d1 = 5,
        .pin_d0 = 4,
        .pin_vsync = 25,
        .pin_href = 23,
        .pin_pclk = 22,
        .pin_flash = -1,
        .name = "WROVER-KIT" },
    // ESP32S3-WROOM
    {
        .pin_pwdn = 38,
        .pin_reset = -1,
        .pin_xclk = 15,
        .pin_sccb_sda = 4,
        .pin_sccb_scl = 5,
        .pin_d7 = 16,
        .pin_d6 = 17,
        .pin_d5 = 18,
        .pin_d4 = 12,
        .pin_d3 = 10,
        .pin_d2 = 8,
        .pin_d1 = 9,
        .pin_d0 = 11,
        .pin_vsync = 6,
        .pin_href = 7,
        .pin_pclk = 13,
        .pin_flash = 48,
        .name = "ESP32S3-WROOM" },
    // ESP32S3-GOOUUU
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 15,
        .pin_sccb_sda = 4,
        .pin_sccb_scl = 5,
        .pin_d7 = 16,
        .pin_d6 = 17,
        .pin_d5 = 18,
        .pin_d4 = 12,
        .pin_d3 = 10,
        .pin_d2 = 8,
        .pin_d1 = 9,
        .pin_d0 = 11,
        .pin_vsync = 6,
        .pin_href = 7,
        .pin_pclk = 13,
        .pin_flash = 48,
        .name = "ESP32S3-GOOUUU" },
    // ESP32S3-XIAO
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 10,
        .pin_sccb_sda = 40,
        .pin_sccb_scl = 39,
        .pin_d7 = 48,
        .pin_d6 = 11,
        .pin_d5 = 12,
        .pin_d4 = 14,
        .pin_d3 = 16,
        .pin_d2 = 18,
        .pin_d1 = 17,
        .pin_d0 = 15,
        .pin_vsync = 38,
        .pin_href = 47,
        .pin_pclk = 13,
        .pin_flash = -1,
        .name = "ESP32S3-XIAO" },
    // M5CAM (ESP32-CAM - original M5Stack model)
    {
        .pin_pwdn = -1, // Pulled down with 12kΩ resistor
        .pin_reset = 15,
        .pin_xclk = 27,
        .pin_sccb_sda = 25, // SIOD
        .pin_sccb_scl = 23, // SIOC
        .pin_d7 = 19, // D9
        .pin_d6 = 36, // D8
        .pin_d5 = 18, // D7
        .pin_d4 = 39, // D6
        .pin_d3 = 5, // D5
        .pin_d2 = 34, // D4
        .pin_d1 = 35, // D3
        .pin_d0 = 17, // D2
        .pin_vsync = 22,
        .pin_href = 26,
        .pin_pclk = 21,
        .pin_flash = 14,
        .name = "M5CAM" },
    // M5Camera (Model A - with PSRAM)
    {
        .pin_pwdn = -1, // Pulled down with 12kΩ resistor
        .pin_reset = 15,
        .pin_xclk = 27,
        .pin_sccb_sda = 25, // SIOD
        .pin_sccb_scl = 23, // SIOC
        .pin_d7 = 19, // D9
        .pin_d6 = 36, // D8
        .pin_d5 = 18, // D7
        .pin_d4 = 39, // D6
        .pin_d3 = 5, // D5
        .pin_d2 = 34, // D4
        .pin_d1 = 35, // D3
        .pin_d0 = 32, // D2
        .pin_vsync = 25,
        .pin_href = 26,
        .pin_pclk = 21,
        .pin_flash = 14,
        .name = "M5CAM-WIDE" },
    // M5Camera (Model B - with PSRAM)
    {
        .pin_pwdn = -1, // Pulled down with 12kΩ resistor
        .pin_reset = 15,
        .pin_xclk = 27,
        .pin_sccb_sda = 22, // SIOD
        .pin_sccb_scl = 23, // SIOC
        .pin_d7 = 19, // D9
        .pin_d6 = 36, // D8
        .pin_d5 = 18, // D7
        .pin_d4 = 39, // D6
        .pin_d3 = 5, // D5
        .pin_d2 = 34, // D4
        .pin_d1 = 35, // D3
        .pin_d0 = 32, // D2
        .pin_vsync = 25,
        .pin_href = 26,
        .pin_pclk = 21,
        .pin_flash = 14,
        .name = "M5CAM-PSRAM" },
    // LilyGO T-Camera S3 (ESP32-S3)
    {
        .pin_pwdn = -1,
        .pin_reset = 39,
        .pin_xclk = 38,
        .pin_sccb_sda = 5,
        .pin_sccb_scl = 4,
        .pin_d7 = 9,
        .pin_d6 = 10,
        .pin_d5 = 11,
        .pin_d4 = 13,
        .pin_d3 = 21,
        .pin_d2 = 48,
        .pin_d1 = 47,
        .pin_d0 = 14,
        .pin_vsync = 8,
        .pin_href = 18,
        .pin_pclk = 12,
        .pin_flash = -1,
        .name = "LILYGO-T-CAMERA-S3" },
    // LilyGO T-Camera Classic (ESP32-WROVER)
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 32,
        .pin_sccb_sda = 22,
        .pin_sccb_scl = 23,
        .pin_d7 = 36,
        .pin_d6 = 37,
        .pin_d5 = 38,
        .pin_d4 = 39,
        .pin_d3 = 35,
        .pin_d2 = 14,
        .pin_d1 = 13,
        .pin_d0 = 34,
        .pin_vsync = 5,
        .pin_href = 27,
        .pin_pclk = 25,
        .pin_flash = -1,
        .name = "LILYGO-T-CAMERA" },
    // LilyGO T-Camera Plus (ESP32-WROVER)
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 4,
        .pin_sccb_sda = 18,
        .pin_sccb_scl = 23,
        .pin_d7 = 36,
        .pin_d6 = 37,
        .pin_d5 = 38,
        .pin_d4 = 39,
        .pin_d3 = 35,
        .pin_d2 = 26,
        .pin_d1 = 13,
        .pin_d0 = 34,
        .pin_vsync = 5,
        .pin_href = 27,
        .pin_pclk = 25,
        .pin_flash = -1,
        .name = "LILYGO-T-CAMERA-PLUS" },
    // LilyGO T-Journal (ESP32)
    {
        .pin_pwdn = 0,
        .pin_reset = 15,
        .pin_xclk = 27,
        .pin_sccb_sda = 25,
        .pin_sccb_scl = 23,
        .pin_d7 = 19,
        .pin_d6 = 36,
        .pin_d5 = 18,
        .pin_d4 = 39,
        .pin_d3 = 34,
        .pin_d2 = 35,
        .pin_d1 = 17,
        .pin_d0 = 32,
        .pin_vsync = 22,
        .pin_href = 26,
        .pin_pclk = 21,
        .pin_flash = -1,
        .name = "LILYGO-T-JOURNAL" },
    // M5Stack Timer Camera (ESP32)
    {
        .pin_pwdn = -1,
        .pin_reset = 15,
        .pin_xclk = 27,
        .pin_sccb_sda = 25,
        .pin_sccb_scl = 23,
        .pin_d7 = 19,
        .pin_d6 = 36,
        .pin_d5 = 18,
        .pin_d4 = 39,
        .pin_d3 = 5,
        .pin_d2 = 34,
        .pin_d1 = 35,
        .pin_d0 = 32,
        .pin_vsync = 22,
        .pin_href = 26,
        .pin_pclk = 21,
        .pin_flash = -1,
        .name = "M5CAM-TIMER" },
    // M5Stack Unit CamS3-5MP (ESP32-S3)
    {
        .pin_pwdn = -1,
        .pin_reset = 21,
        .pin_xclk = 11,
        .pin_sccb_sda = 17,
        .pin_sccb_scl = 41,
        .pin_d7 = 13,
        .pin_d6 = 4,
        .pin_d5 = 10,
        .pin_d4 = 5,
        .pin_d3 = 7,
        .pin_d2 = 16,
        .pin_d1 = 15,
        .pin_d0 = 6,
        .pin_vsync = 42,
        .pin_href = 18,
        .pin_pclk = 12,
        .pin_flash = 14,
        .name = "M5CAM-UNIT-S3-5MP" },
    // ESP-EYE (ESP32)
    {
        .pin_pwdn = -1,
        .pin_reset = -1,
        .pin_xclk = 4,
        .pin_sccb_sda = 18,
        .pin_sccb_scl = 23,
        .pin_d7 = 36,
        .pin_d6 = 37,
        .pin_d5 = 38,
        .pin_d4 = 39,
        .pin_d3 = 35,
        .pin_d2 = 14,
        .pin_d1 = 13,
        .pin_d0 = 34,
        .pin_vsync = 5,
        .pin_href = 27,
        .pin_pclk = 25,
        .pin_flash = -1,
        .name = "ESP-EYE" }
};

static const char *const frame_size_a = "\xA"
                                        "frame_size";
static const char *const jpeg_quality_a = "\xC"
                                          "jpeg_quality";
static const char *const board_a = "\x5"
                                   "board";
static const char *const xclk_freq_hz_a = "\xC"
                                          "xclk_freq_hz";
static const char *const fb_count_a = "\x8"
                                      "fb_count";
static const char *const sccb_i2c_port_a = "\xD"
                                           "sccb_i2c_port";
static const char *const ledc_timer_a = "\xA"
                                        "ledc_timer";
static const char *const ledc_channel_a = "\xC"
                                          "ledc_channel";
static const char *const conv_mode_a = "\x9"
                                       "conv_mode";
static const char *const fb_location_a = "\xB"
                                         "fb_location";
static const char *const grab_mode_a = "\x9"
                                       "grab_mode";
static const char *const pixel_format_a = "\xC"
                                          "pixel_format";
static const char *const size_96x96_a = "\x5"
                                        "96x96";
static const char *const qqvga_a = "\x5"
                                   "qqvga";
static const char *const size_128x128_a = "\x7"
                                          "128x128";
static const char *const qcif_a = "\x4"
                                  "qcif";
static const char *const hqvga_a = "\x5"
                                   "hqvga";
static const char *const size_240x240_a = "\x7"
                                          "240x240";
static const char *const qvga_a = "\x4"
                                  "qvga";
static const char *const size_320x320_a = "\x7"
                                          "320x320";
static const char *const cif_a = "\x3"
                                 "cif";
static const char *const hvga_a = "\x4"
                                  "hvga";
static const char *const vga_a = "\x3"
                                 "vga";
static const char *const svga_a = "\x4"
                                  "svga";
static const char *const xga_a = "\x3"
                                 "xga";
static const char *const hd_a = "\x2"
                                "hd";
static const char *const sxga_a = "\x4"
                                  "sxga";
static const char *const uxga_a = "\x4"
                                  "uxga";
static const char *const fhd_a = "\x3"
                                 "fhd";
static const char *const p_hd_a = "\x4"
                                  "p_hd";
static const char *const p_3mp_a = "\x5"
                                   "p_3mp";
static const char *const qxga_a = "\x4"
                                  "qxga";
static const char *const qhd_a = "\x3"
                                 "qhd";
static const char *const wqxga_a = "\x5"
                                   "wqxga";
static const char *const p_fhd_a = "\x5"
                                   "p_fhd";
static const char *const qsxga_a = "\x5"
                                   "qsxga";
static const char *const size_5mp_a = "\x3"
                                      "5mp";
static const char *const ai_thinker_a = "\xA"
                                        "ai_thinker";
static const char *const wrover_kit_a = "\xA"
                                        "wrover_kit";
static const char *const esp32s3_wroom_a = "\xD"
                                           "esp32s3_wroom";
static const char *const esp32s3_goouuu_a = "\xE"
                                            "esp32s3_goouuu";
static const char *const esp32s3_xiao_a = "\xC"
                                          "esp32s3_xiao";
static const char *const m5cam_a = "\x5"
                                   "m5cam";
static const char *const m5cam_wide_a = "\xA"
                                        "m5cam_wide";
static const char *const m5cam_psram_a = "\xB"
                                         "m5cam_psram";
static const char *const lilygo_t_camera_s3_a = "\x12"
                                                "lilygo_t_camera_s3";
static const char *const lilygo_t_camera_a = "\x0F"
                                             "lilygo_t_camera";
static const char *const lilygo_t_camera_plus_a = "\x14"
                                                  "lilygo_t_camera_plus";
static const char *const lilygo_t_journal_a = "\x10"
                                              "lilygo_t_journal";
static const char *const m5cam_timer_a = "\x0B"
                                         "m5cam_timer";
static const char *const m5cam_unit_s3_5mp_a = "\x11"
                                               "m5cam_unit_s3_5mp";
static const char *const esp_eye_a = "\x07"
                                     "esp_eye";
static const char *const custom_a = "\x06"
                                    "custom";
static const char *const pin_pwdn_a = "\x08"
                                      "pin_pwdn";
static const char *const pin_reset_a = "\x09"
                                       "pin_reset";
static const char *const pin_xclk_a = "\x08"
                                      "pin_xclk";
static const char *const pin_sccb_sda_a = "\x0C"
                                          "pin_sccb_sda";
static const char *const pin_sccb_scl_a = "\x0C"
                                          "pin_sccb_scl";
static const char *const pin_d7_a = "\x06"
                                    "pin_d7";
static const char *const pin_d6_a = "\x06"
                                    "pin_d6";
static const char *const pin_d5_a = "\x06"
                                    "pin_d5";
static const char *const pin_d4_a = "\x06"
                                    "pin_d4";
static const char *const pin_d3_a = "\x06"
                                    "pin_d3";
static const char *const pin_d2_a = "\x06"
                                    "pin_d2";
static const char *const pin_d1_a = "\x06"
                                    "pin_d1";
static const char *const pin_d0_a = "\x06"
                                    "pin_d0";
static const char *const pin_vsync_a = "\x09"
                                       "pin_vsync";
static const char *const pin_href_a = "\x08"
                                      "pin_href";
static const char *const pin_pclk_a = "\x08"
                                      "pin_pclk";
static const char *const pin_flash_a = "\x09"
                                       "pin_flash";
// Pixel format atoms
static const char *const jpeg_a = "\x4"
                                  "jpeg";
static const char *const grayscale_a = "\x9"
                                       "grayscale";
static const char *const rgb565_a = "\x6"
                                    "rgb565";
static const char *const yuv422_a = "\x6"
                                    "yuv422";
static const char *const yuv420_a = "\x6"
                                    "yuv420";
static const char *const rgb888_a = "\x6"
                                    "rgb888";
static const char *const raw_a = "\x3"
                                 "raw";
static const char *const rgb444_a = "\x6"
                                    "rgb444";
static const char *const rgb555_a = "\x6"
                                    "rgb555";
static const char *const raw8_a = "\x4"
                                  "raw8";
// Converter mode atoms
static const char *const disable_a = "\x7"
                                     "disable";
#if defined(CONFIG_CAMERA_CONVERTER_ENABLED) && CONFIG_CAMERA_CONVERTER_ENABLED
static const char *const rgb565_to_yuv422_a = "\x10"
                                              "rgb565_to_yuv422";
static const char *const yuv422_to_rgb565_a = "\x10"
                                              "yuv422_to_rgb565";
static const char *const yuv422_to_yuv420_a = "\x10"
                                              "yuv422_to_yuv420";
#endif
// Frame buffer location atoms
static const char *const psram_a = "\x5"
                                   "psram";
static const char *const dram_a = "\x4"
                                  "dram";
// Grab mode atoms
static const char *const when_empty_a = "\xA"
                                        "when_empty";
static const char *const latest_a = "\x6"
                                    "latest";

static const char *const bad_state_a = "\x9"
                                       "bad_state";
static const char *const capture_failed_a = "\xE"
                                            "capture_failed";

// New configuration keys and values
static const char *const warm_up_frames_a = "\xE"
                                            "warm_up_frames";
static const char *const auto_white_balance_a = "\x12"
                                                "auto_white_balance";
static const char *const awb_gain_a = "\x8"
                                      "awb_gain";
static const char *const wb_mode_a = "\x7"
                                     "wb_mode";
static const char *const brightness_a = "\xA"
                                        "brightness";
static const char *const contrast_a = "\x8"
                                      "contrast";
static const char *const saturation_a = "\xA"
                                        "saturation";
static const char *const hmirror_a = "\x7"
                                     "hmirror";
static const char *const vflip_a = "\x5"
                                   "vflip";

// wb_mode atom values
static const char *const auto_a = "\x4"
                                  "auto";
static const char *const sunny_a = "\x5"
                                   "sunny";
static const char *const cloudy_a = "\x6"
                                    "cloudy";
static const char *const office_a = "\x6"
                                    "office";
static const char *const home_a = "\x4"
                                  "home";
static const char *const undefined_a = "\x9"
                                       "undefined";
static const char *const frames_in_use_a = "\xD"
                                           "frames_in_use";
static const char *const binary_views_active_a = "\x13"
                                                 "binary_views_active";
static const char *const already_released_a = "\x10"
                                              "already_released";
static const char *const size_a = "\x4"
                                  "size";
static const char *const width_a = "\x5"
                                   "width";
static const char *const height_a = "\x6"
                                    "height";
static const char *const timestamp_a = "\x9"
                                       "timestamp";
static const char *const enomem_a = "\x6"
                                    "enomem";
static const char *const too_large_a = "\x9"
                                       "too_large";
static const char *const io_error_a = "\x8"
                                      "io_error";

//                                                    123456789ABCDEF

uint8_t camera_initialized = 0;
board_type_t initialized_board_type = BOARD_INVALID;
int initialized_flash_pin = -1;
int initialized_xclk_pin = -1;

static void deinit_camera_and_reset_xclk(int pin_xclk)
{
    esp_camera_deinit();
    if (pin_xclk >= 0) {
        gpio_reset_pin(pin_xclk);
    }
}

static board_type_t get_board_type(Context *ctx, term board_term)
{
    if (term_is_nil(board_term)) {
        return BOARD_AI_THINKER;
    } else if (board_term == globalcontext_make_atom(ctx->global, ai_thinker_a)) {
        return BOARD_AI_THINKER;
    } else if (board_term == globalcontext_make_atom(ctx->global, wrover_kit_a)) {
        return BOARD_WROVER_KIT;
    } else if (board_term == globalcontext_make_atom(ctx->global, esp32s3_wroom_a)) {
        return BOARD_ESP32S3_WROOM;
    } else if (board_term == globalcontext_make_atom(ctx->global, esp32s3_goouuu_a)) {
        return BOARD_ESP32S3_GOOUUU;
    } else if (board_term == globalcontext_make_atom(ctx->global, esp32s3_xiao_a)) {
        return BOARD_ESP32S3_XIAO;
    } else if (board_term == globalcontext_make_atom(ctx->global, m5cam_a)) {
        return BOARD_M5CAM;
    } else if (board_term == globalcontext_make_atom(ctx->global, m5cam_wide_a)) {
        return BOARD_M5CAM_WIDE;
    } else if (board_term == globalcontext_make_atom(ctx->global, m5cam_psram_a)) {
        return BOARD_M5CAM_PSRAM;
    } else if (board_term == globalcontext_make_atom(ctx->global, lilygo_t_camera_s3_a)) {
        return BOARD_LILYGO_T_CAMERA_S3;
    } else if (board_term == globalcontext_make_atom(ctx->global, lilygo_t_camera_a)) {
        return BOARD_LILYGO_T_CAMERA;
    } else if (board_term == globalcontext_make_atom(ctx->global, lilygo_t_camera_plus_a)) {
        return BOARD_LILYGO_T_CAMERA_PLUS;
    } else if (board_term == globalcontext_make_atom(ctx->global, lilygo_t_journal_a)) {
        return BOARD_LILYGO_T_JOURNAL;
    } else if (board_term == globalcontext_make_atom(ctx->global, m5cam_timer_a)) {
        return BOARD_M5CAM_TIMER;
    } else if (board_term == globalcontext_make_atom(ctx->global, m5cam_unit_s3_5mp_a)) {
        return BOARD_M5CAM_UNIT_S3_5MP;
    } else if (board_term == globalcontext_make_atom(ctx->global, esp_eye_a)) {
        return BOARD_ESP_EYE;
    } else if (board_term == globalcontext_make_atom(ctx->global, custom_a)) {
        return BOARD_CUSTOM;
    } else {
        return BOARD_INVALID;
    }
}

static framesize_t get_frame_size(Context *ctx, term frame_size)
{
    if (term_is_nil(frame_size)) {
        return FRAMESIZE_XGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, size_96x96_a)) {
        return FRAMESIZE_96X96;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qqvga_a)) {
        return FRAMESIZE_QQVGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, size_128x128_a)) {
        return FRAMESIZE_128X128;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qcif_a)) {
        return FRAMESIZE_QCIF;
    } else if (frame_size == globalcontext_make_atom(ctx->global, hqvga_a)) {
        return FRAMESIZE_HQVGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, size_240x240_a)) {
        return FRAMESIZE_240X240;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qvga_a)) {
        return FRAMESIZE_QVGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, size_320x320_a)) {
        return FRAMESIZE_320X320;
    } else if (frame_size == globalcontext_make_atom(ctx->global, cif_a)) {
        return FRAMESIZE_CIF;
    } else if (frame_size == globalcontext_make_atom(ctx->global, hvga_a)) {
        return FRAMESIZE_HVGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, vga_a)) {
        return FRAMESIZE_VGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, svga_a)) {
        return FRAMESIZE_SVGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, xga_a)) {
        return FRAMESIZE_XGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, hd_a)) {
        return FRAMESIZE_HD;
    } else if (frame_size == globalcontext_make_atom(ctx->global, sxga_a)) {
        return FRAMESIZE_SXGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, uxga_a)) {
        return FRAMESIZE_UXGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, fhd_a)) {
        return FRAMESIZE_FHD;
    } else if (frame_size == globalcontext_make_atom(ctx->global, p_hd_a)) {
        return FRAMESIZE_P_HD;
    } else if (frame_size == globalcontext_make_atom(ctx->global, p_3mp_a)) {
        return FRAMESIZE_P_3MP;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qxga_a)) {
        return FRAMESIZE_QXGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qhd_a)) {
        return FRAMESIZE_QHD;
    } else if (frame_size == globalcontext_make_atom(ctx->global, wqxga_a)) {
        return FRAMESIZE_WQXGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, p_fhd_a)) {
        return FRAMESIZE_P_FHD;
    } else if (frame_size == globalcontext_make_atom(ctx->global, qsxga_a)) {
        return FRAMESIZE_QSXGA;
    } else if (frame_size == globalcontext_make_atom(ctx->global, size_5mp_a)) {
        return FRAMESIZE_5MP;
    } else {
        return FRAMESIZE_INVALID;
    }
}

static int get_jpeg_quality(term jpeg_quality)
{
    if (term_is_nil(jpeg_quality)) {
        return DEFAULT_JPEG_QUALITY;
    } else if (term_is_any_integer(jpeg_quality)) {
        avm_int_t val = term_to_int(jpeg_quality);
        if (val < 0 || val > 63) {
            return INVALID_JPEG_QUALITY;
        } else {
            return val;
        }
    } else {
        return INVALID_JPEG_QUALITY;
    }
}

static int get_pixel_format(Context *ctx, term pixel_format)
{
    if (term_is_nil(pixel_format)) {
        return PIXFORMAT_JPEG;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, jpeg_a)) {
        return PIXFORMAT_JPEG;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, grayscale_a)) {
        return PIXFORMAT_GRAYSCALE;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, rgb565_a)) {
        return PIXFORMAT_RGB565;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, yuv422_a)) {
        return PIXFORMAT_YUV422;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, yuv420_a)) {
        return PIXFORMAT_YUV420;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, rgb888_a)) {
        return PIXFORMAT_RGB888;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, raw_a)) {
        return PIXFORMAT_RAW;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, rgb444_a)) {
        return PIXFORMAT_RGB444;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, rgb555_a)) {
        return PIXFORMAT_RGB555;
    } else if (pixel_format == globalcontext_make_atom(ctx->global, raw8_a)) {
        return PIXFORMAT_RAW8;
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_fb_location(Context *ctx, term fb_location)
{
    if (term_is_nil(fb_location)) {
        return CAMERA_FB_IN_PSRAM;
    } else if (fb_location == globalcontext_make_atom(ctx->global, psram_a)) {
        return CAMERA_FB_IN_PSRAM;
    } else if (fb_location == globalcontext_make_atom(ctx->global, dram_a)) {
        return CAMERA_FB_IN_DRAM;
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_grab_mode(Context *ctx, term grab_mode)
{
    if (term_is_nil(grab_mode)) {
        return CAMERA_GRAB_WHEN_EMPTY;
    } else if (grab_mode == globalcontext_make_atom(ctx->global, when_empty_a)) {
        return CAMERA_GRAB_WHEN_EMPTY;
    } else if (grab_mode == globalcontext_make_atom(ctx->global, latest_a)) {
        return CAMERA_GRAB_LATEST;
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_xclk_freq_hz(term xclk_freq_hz)
{
    if (term_is_nil(xclk_freq_hz)) {
        return DEFAULT_XCLK_FREQ_HZ;
    } else if (term_is_any_integer(xclk_freq_hz)) {
        avm_int_t val = term_to_int(xclk_freq_hz);
        if (val > 0) {
            return val;
        } else {
            return INVALID_CONFIG_VALUE;
        }
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_fb_count(term fb_count)
{
    if (term_is_nil(fb_count)) {
        return DEFAULT_FB_COUNT;
    } else if (term_is_any_integer(fb_count)) {
        avm_int_t val = term_to_int(fb_count);
        if (val > 0) {
            return val;
        } else {
            return INVALID_CONFIG_VALUE;
        }
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_sccb_i2c_port(term sccb_i2c_port)
{
    if (term_is_nil(sccb_i2c_port)) {
        return DEFAULT_SCCB_I2C_PORT;
    } else if (term_is_any_integer(sccb_i2c_port)) {
        avm_int_t val = term_to_int(sccb_i2c_port);
        if (val >= 0) {
            return val;
        } else {
            return INVALID_CONFIG_VALUE;
        }
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_ledc_timer(term ledc_timer)
{
    if (term_is_nil(ledc_timer)) {
        return DEFAULT_LEDC_TIMER;
    } else if (term_is_any_integer(ledc_timer)) {
        avm_int_t val = term_to_int(ledc_timer);
        if (val >= 0 && val <= 3) {
            return val;
        } else {
            return INVALID_CONFIG_VALUE;
        }
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_ledc_channel(term ledc_channel)
{
    if (term_is_nil(ledc_channel)) {
        return DEFAULT_LEDC_CHANNEL;
    } else if (term_is_any_integer(ledc_channel)) {
        avm_int_t val = term_to_int(ledc_channel);
        if (val >= 0 && val <= 7) {
            return val;
        } else {
            return INVALID_CONFIG_VALUE;
        }
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_conv_mode(Context *ctx, term conv_mode)
{
    if (term_is_nil(conv_mode)) {
        return DEFAULT_CONV_MODE;
    } else if (conv_mode == globalcontext_make_atom(ctx->global, disable_a)) {
        return DEFAULT_CONV_MODE;
#if defined(CONFIG_CAMERA_CONVERTER_ENABLED) && CONFIG_CAMERA_CONVERTER_ENABLED
    } else if (conv_mode == globalcontext_make_atom(ctx->global, rgb565_to_yuv422_a)) {
        return RGB565_TO_YUV422;
    } else if (conv_mode == globalcontext_make_atom(ctx->global, yuv422_to_rgb565_a)) {
        return YUV422_TO_RGB565;
    } else if (conv_mode == globalcontext_make_atom(ctx->global, yuv422_to_yuv420_a)) {
        return YUV422_TO_YUV420;
#endif
    } else {
        return INVALID_CONFIG_VALUE;
    }
}

static int get_pin_value(term pin_term, int default_val)
{
    if (term_is_nil(pin_term)) {
        return default_val;
    } else if (term_is_any_integer(pin_term)) {
        avm_int_t val = term_to_int(pin_term);
        if (val >= -1) {
            return val;
        }
    }
    return INVALID_PIN_VALUE;
}

static camera_config_t *create_camera_config(const board_config_t *board_config, framesize_t frame_size, int jpeg_quality,
    int pixel_format, int xclk_freq_hz, int fb_count,
    int fb_location, int grab_mode, int sccb_i2c_port, int ledc_timer, int ledc_channel, int conv_mode)
{
    if (IS_NULL_PTR(board_config)) {
        ESP_LOGE(TAG, "Invalid board configuration");
        return NULL;
    }

    camera_config_t *config = calloc(1, sizeof(camera_config_t));
    if (IS_NULL_PTR(config)) {
        ESP_LOGE(TAG, "Memory allocation failed");
        return NULL;
    }

    // Set pin configuration from board config
    config->pin_pwdn = board_config->pin_pwdn;
    config->pin_reset = board_config->pin_reset;
    config->pin_xclk = board_config->pin_xclk;
    config->pin_sccb_sda = board_config->pin_sccb_sda;
    config->pin_sccb_scl = board_config->pin_sccb_scl;
    config->pin_d7 = board_config->pin_d7;
    config->pin_d6 = board_config->pin_d6;
    config->pin_d5 = board_config->pin_d5;
    config->pin_d4 = board_config->pin_d4;
    config->pin_d3 = board_config->pin_d3;
    config->pin_d2 = board_config->pin_d2;
    config->pin_d1 = board_config->pin_d1;
    config->pin_d0 = board_config->pin_d0;
    config->pin_vsync = board_config->pin_vsync;
    config->pin_href = board_config->pin_href;
    config->pin_pclk = board_config->pin_pclk;

    // Set camera configuration with new parameters
    config->xclk_freq_hz = xclk_freq_hz;
    config->ledc_timer = (ledc_timer_t) ledc_timer;
    config->ledc_channel = (ledc_channel_t) ledc_channel;
    config->pixel_format = (pixformat_t) pixel_format;
    config->frame_size = frame_size;
    config->jpeg_quality = jpeg_quality;
    config->fb_count = fb_count;
    config->fb_location = (camera_fb_location_t) fb_location;
    config->grab_mode = (camera_grab_mode_t) grab_mode;
    config->sccb_i2c_port = sccb_i2c_port;
#if defined(CONFIG_CAMERA_CONVERTER_ENABLED) && CONFIG_CAMERA_CONVERTER_ENABLED
    config->conv_mode = (camera_conv_mode_t) conv_mode;
#else
    UNUSED(conv_mode);
#endif

    ESP_LOGI(TAG, "Camera config created for board: %s, pixel_format: %d, xclk: %d Hz, fb_count: %d",
        board_config->name, pixel_format, xclk_freq_hz, fb_count);
    return config;
}

static bool is_valid_gpio(int pin)
{
    return GPIO_IS_VALID_GPIO(pin);
}

static bool is_valid_output_gpio(int pin)
{
    return GPIO_IS_VALID_OUTPUT_GPIO(pin);
}

static term nif_esp32cam_init_locked(Context *ctx, int argc, term argv[])
{
    // Check if camera is already initialized
    if (camera_initialized) {
        if (outstanding_leases > 0) {
            if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
                RAISE_ERROR(MEMORY_ATOM);
            }
            return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, frames_in_use_a));
        }
        ESP_LOGW(TAG, "Camera already initialized, deinitializing first");
        deinit_camera_and_reset_xclk(initialized_xclk_pin);
        camera_initialized = 0;
        initialized_board_type = BOARD_INVALID;
        initialized_flash_pin = -1;
        initialized_xclk_pin = -1;
    }

    term config;
    if (argc == 0) {
        config = term_nil();
    } else {
        VALIDATE_VALUE(argv[0], term_is_list);
        config = argv[0];
    }

    // Parse board type
    board_type_t board_type = get_board_type(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, board_a)));
    if (board_type == BOARD_INVALID) {
        ESP_LOGE(TAG, "Invalid board type");
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("board_type: %i\n", board_type);

    board_config_t custom_board_config;
    const board_config_t *selected_board_config = NULL;

    if (board_type == BOARD_CUSTOM) {
        // Parse custom pins
        custom_board_config.pin_pwdn = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_pwdn_a)), -1);
        custom_board_config.pin_reset = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_reset_a)), -1);
        custom_board_config.pin_xclk = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_xclk_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_sccb_sda = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_sccb_sda_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_sccb_scl = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_sccb_scl_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d7 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d7_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d6 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d6_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d5 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d5_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d4 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d4_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d3 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d3_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d2 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d2_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d1 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d1_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_d0 = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_d0_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_vsync = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_vsync_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_href = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_href_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_pclk = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_pclk_a)), INVALID_PIN_VALUE);
        custom_board_config.pin_flash = get_pin_value(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pin_flash_a)), -1);
        custom_board_config.name = "CUSTOM";

        // Validate custom pin assignments
        if ((custom_board_config.pin_pwdn != -1 && !is_valid_output_gpio(custom_board_config.pin_pwdn)) ||
            (custom_board_config.pin_reset != -1 && !is_valid_output_gpio(custom_board_config.pin_reset)) ||
            (custom_board_config.pin_flash != -1 && !is_valid_output_gpio(custom_board_config.pin_flash)) ||
            !is_valid_output_gpio(custom_board_config.pin_xclk) ||
            !is_valid_output_gpio(custom_board_config.pin_sccb_sda) ||
            !is_valid_output_gpio(custom_board_config.pin_sccb_scl) ||
            !is_valid_gpio(custom_board_config.pin_pclk) ||
            !is_valid_gpio(custom_board_config.pin_vsync) ||
            !is_valid_gpio(custom_board_config.pin_href) ||
            !is_valid_gpio(custom_board_config.pin_d7) ||
            !is_valid_gpio(custom_board_config.pin_d6) ||
            !is_valid_gpio(custom_board_config.pin_d5) ||
            !is_valid_gpio(custom_board_config.pin_d4) ||
            !is_valid_gpio(custom_board_config.pin_d3) ||
            !is_valid_gpio(custom_board_config.pin_d2) ||
            !is_valid_gpio(custom_board_config.pin_d1) ||
            !is_valid_gpio(custom_board_config.pin_d0)) {
            ESP_LOGE(TAG, "Missing or invalid pin in custom board configuration");
            RAISE_ERROR(BADARG_ATOM);
        }
        selected_board_config = &custom_board_config;
    } else {
        selected_board_config = &board_configs[board_type];
    }

    framesize_t frame_size = get_frame_size(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, frame_size_a)));
    if (frame_size == FRAMESIZE_INVALID) {
        ESP_LOGE(TAG, "Invalid frame_size=%i", frame_size);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("frame_size: %i\n", frame_size);

    int jpeg_quality = get_jpeg_quality(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, jpeg_quality_a)));
    if (jpeg_quality == INVALID_JPEG_QUALITY) {
        ESP_LOGE(TAG, "Invalid jpeg_quality=%i", jpeg_quality);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("jpeg_quality: %i\n", jpeg_quality);

    // Parse new configuration options
    int pixel_format = get_pixel_format(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, pixel_format_a)));
    if (pixel_format == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid pixel_format=%i", pixel_format);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("pixel_format: %i\n", pixel_format);

    int xclk_freq_hz = get_xclk_freq_hz(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, xclk_freq_hz_a)));
    if (xclk_freq_hz == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid xclk_freq_hz=%i", xclk_freq_hz);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("xclk_freq_hz: %i\n", xclk_freq_hz);

    int fb_count = get_fb_count(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, fb_count_a)));
    if (fb_count == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid fb_count=%i", fb_count);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("fb_count: %i\n", fb_count);

    int fb_location = get_fb_location(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, fb_location_a)));
    if (fb_location == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid fb_location=%i", fb_location);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("fb_location: %i\n", fb_location);

    int grab_mode = get_grab_mode(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, grab_mode_a)));
    if (grab_mode == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid grab_mode=%i", grab_mode);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("grab_mode: %i\n", grab_mode);

    int sccb_i2c_port = get_sccb_i2c_port(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, sccb_i2c_port_a)));
    if (sccb_i2c_port == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid sccb_i2c_port=%i", sccb_i2c_port);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("sccb_i2c_port: %i\n", sccb_i2c_port);

    int ledc_timer = get_ledc_timer(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, ledc_timer_a)));
    if (ledc_timer == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid ledc_timer=%i", ledc_timer);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("ledc_timer: %i\n", ledc_timer);

    int ledc_channel = get_ledc_channel(interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, ledc_channel_a)));
    if (ledc_channel == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid ledc_channel=%i", ledc_channel);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("ledc_channel: %i\n", ledc_channel);

    int conv_mode = get_conv_mode(ctx, interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, conv_mode_a)));
    if (conv_mode == INVALID_CONFIG_VALUE) {
        ESP_LOGE(TAG, "Invalid conv_mode=%i", conv_mode);
        RAISE_ERROR(BADARG_ATOM);
    }
    TRACE("conv_mode: %i\n", conv_mode);

    int auto_white_balance = INVALID_CONFIG_VALUE;
    term auto_white_balance_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, auto_white_balance_a));
    if (!term_is_nil(auto_white_balance_term)) {
        if (auto_white_balance_term == TRUE_ATOM) {
            auto_white_balance = 1;
        } else if (auto_white_balance_term == FALSE_ATOM) {
            auto_white_balance = 0;
        } else {
            ESP_LOGE(TAG, "Invalid auto_white_balance parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    int awb_gain = INVALID_CONFIG_VALUE;
    term awb_gain_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, awb_gain_a));
    if (!term_is_nil(awb_gain_term)) {
        if (awb_gain_term == TRUE_ATOM) {
            awb_gain = 1;
        } else if (awb_gain_term == FALSE_ATOM) {
            awb_gain = 0;
        } else {
            ESP_LOGE(TAG, "Invalid awb_gain parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    int wb_mode = INVALID_CONFIG_VALUE;
    term wb_mode_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, wb_mode_a));
    if (!term_is_nil(wb_mode_term)) {
        if (wb_mode_term == globalcontext_make_atom(ctx->global, auto_a)) {
            wb_mode = 0;
        } else if (wb_mode_term == globalcontext_make_atom(ctx->global, sunny_a)) {
            wb_mode = 1;
        } else if (wb_mode_term == globalcontext_make_atom(ctx->global, cloudy_a)) {
            wb_mode = 2;
        } else if (wb_mode_term == globalcontext_make_atom(ctx->global, office_a)) {
            wb_mode = 3;
        } else if (wb_mode_term == globalcontext_make_atom(ctx->global, home_a)) {
            wb_mode = 4;
        } else {
            ESP_LOGE(TAG, "Invalid wb_mode parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    bool brightness_set = false;
    int brightness = 0;
    term brightness_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, brightness_a));
    if (!term_is_nil(brightness_term)) {
        if (!term_is_any_integer(brightness_term)) {
            ESP_LOGE(TAG, "Invalid brightness parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
        brightness = term_to_int(brightness_term);
        if (brightness < -2 || brightness > 2) {
            ESP_LOGE(TAG, "Invalid brightness parameter range");
            RAISE_ERROR(BADARG_ATOM);
        }
        brightness_set = true;
    }

    bool contrast_set = false;
    int contrast = 0;
    term contrast_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, contrast_a));
    if (!term_is_nil(contrast_term)) {
        if (!term_is_any_integer(contrast_term)) {
            ESP_LOGE(TAG, "Invalid contrast parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
        contrast = term_to_int(contrast_term);
        if (contrast < -2 || contrast > 2) {
            ESP_LOGE(TAG, "Invalid contrast parameter range");
            RAISE_ERROR(BADARG_ATOM);
        }
        contrast_set = true;
    }

    bool saturation_set = false;
    int saturation = 0;
    term saturation_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, saturation_a));
    if (!term_is_nil(saturation_term)) {
        if (!term_is_any_integer(saturation_term)) {
            ESP_LOGE(TAG, "Invalid saturation parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
        saturation = term_to_int(saturation_term);
        if (saturation < -2 || saturation > 2) {
            ESP_LOGE(TAG, "Invalid saturation parameter range");
            RAISE_ERROR(BADARG_ATOM);
        }
        saturation_set = true;
    }

    int hmirror = INVALID_CONFIG_VALUE;
    term hmirror_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, hmirror_a));
    if (!term_is_nil(hmirror_term)) {
        if (hmirror_term == TRUE_ATOM) {
            hmirror = 1;
        } else if (hmirror_term == FALSE_ATOM) {
            hmirror = 0;
        } else {
            ESP_LOGE(TAG, "Invalid hmirror parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    int vflip = INVALID_CONFIG_VALUE;
    term vflip_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, vflip_a));
    if (!term_is_nil(vflip_term)) {
        if (vflip_term == TRUE_ATOM) {
            vflip = 1;
        } else if (vflip_term == FALSE_ATOM) {
            vflip = 0;
        } else {
            ESP_LOGE(TAG, "Invalid vflip parameter");
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    avm_int_t warm_up_frames = 0;
    term warm_up_frames_term = interop_proplist_get_value(config, globalcontext_make_atom(ctx->global, warm_up_frames_a));
    if (!term_is_nil(warm_up_frames_term)) {
        if (!term_is_any_integer(warm_up_frames_term)) {
            ESP_LOGE(TAG, "Invalid warm_up_frames parameter (must be an integer)");
            RAISE_ERROR(BADARG_ATOM);
        }
        warm_up_frames = term_to_int(warm_up_frames_term);
        if (warm_up_frames < 0 || warm_up_frames > MAX_WARM_UP_FRAMES) {
            ESP_LOGE(TAG, "Invalid warm_up_frames parameter (must be between 0 and %d)", MAX_WARM_UP_FRAMES);
            RAISE_ERROR(BADARG_ATOM);
        }
    }

    // Initialize camera config
    camera_config_t *camera_config = create_camera_config(selected_board_config, frame_size, jpeg_quality,
        pixel_format, xclk_freq_hz, fb_count,
        fb_location, grab_mode, sccb_i2c_port, ledc_timer, ledc_channel, conv_mode);
    if (IS_NULL_PTR(camera_config)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    ESP_LOGI(TAG, "Attempting to initialize camera with config: board=%s, frame_size=%d, jpeg_quality=%d",
        selected_board_config->name, frame_size, jpeg_quality);

    esp_err_t err = esp_camera_init(camera_config);
    free(camera_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize esp_camera: err=0x%x (%s)", err, esp_err_to_name(err));
        ESP_LOGE(TAG, "Common causes: 1) Hardware not connected properly, 2) Pin conflicts, 3) PSRAM issues, 4) Power supply insufficient");
        deinit_camera_and_reset_xclk(selected_board_config->pin_xclk);
        if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
            RAISE_ERROR(MEMORY_ATOM);
        }
        term error = port_create_error_tuple(ctx, term_from_int28(err));
        return error;
    }

    sensor_t *s = esp_camera_sensor_get();
    if (s != NULL) {
        int sensor_err = 0;
        if (auto_white_balance != INVALID_CONFIG_VALUE) {
            sensor_err = s->set_whitebal != NULL
                ? s->set_whitebal(s, auto_white_balance)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && awb_gain != INVALID_CONFIG_VALUE) {
            sensor_err = s->set_awb_gain != NULL
                ? s->set_awb_gain(s, awb_gain)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && wb_mode != INVALID_CONFIG_VALUE) {
            sensor_err = s->set_wb_mode != NULL
                ? s->set_wb_mode(s, wb_mode)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && brightness_set) {
            sensor_err = s->set_brightness != NULL
                ? s->set_brightness(s, brightness)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && contrast_set) {
            sensor_err = s->set_contrast != NULL
                ? s->set_contrast(s, contrast)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && saturation_set) {
            sensor_err = s->set_saturation != NULL
                ? s->set_saturation(s, saturation)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && hmirror != INVALID_CONFIG_VALUE) {
            sensor_err = s->set_hmirror != NULL
                ? s->set_hmirror(s, hmirror)
                : ESP_FAIL;
        }
        if (sensor_err == 0 && vflip != INVALID_CONFIG_VALUE) {
            sensor_err = s->set_vflip != NULL
                ? s->set_vflip(s, vflip)
                : ESP_FAIL;
        }
        if (sensor_err != 0) {
            ESP_LOGE(TAG, "Failed to apply camera settings: err=%d", sensor_err);
            deinit_camera_and_reset_xclk(selected_board_config->pin_xclk);
            if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
                RAISE_ERROR(MEMORY_ATOM);
            }
            return port_create_error_tuple(ctx, term_from_int28(sensor_err));
        }
    } else if (auto_white_balance != INVALID_CONFIG_VALUE || awb_gain != INVALID_CONFIG_VALUE || wb_mode != INVALID_CONFIG_VALUE
        || brightness_set || contrast_set || saturation_set
        || hmirror != INVALID_CONFIG_VALUE || vflip != INVALID_CONFIG_VALUE) {
        ESP_LOGW(TAG, "Could not get sensor pointer to apply camera settings");
        deinit_camera_and_reset_xclk(selected_board_config->pin_xclk);
        if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
            RAISE_ERROR(MEMORY_ATOM);
        }
        return port_create_error_tuple(ctx, term_from_int28(ESP_FAIL));
    }

    if (warm_up_frames > 0) {
        ESP_LOGI(TAG, "Warming up camera sensor: discarding %d frames", (int) warm_up_frames);
        for (avm_int_t i = 0; i < warm_up_frames; i++) {
            camera_fb_t *fb = esp_camera_fb_get();
            if (!fb) {
                ESP_LOGE(TAG, "Camera capture failed during warm-up at frame %d", (int) (i + 1));
                deinit_camera_and_reset_xclk(selected_board_config->pin_xclk);
                if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
                    RAISE_ERROR(MEMORY_ATOM);
                }
                return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, capture_failed_a));
            }
            esp_camera_fb_return(fb);
        }
    }

    configured_fb_count = fb_count;
    outstanding_leases = 0;
    camera_initialized = 1;
    initialized_board_type = board_type;
    initialized_flash_pin = selected_board_config->pin_flash;
    initialized_xclk_pin = selected_board_config->pin_xclk;
    return OK_ATOM;
}

static term nif_esp32cam_init(Context *ctx, int argc, term argv[])
{
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    term result = nif_esp32cam_init_locked(ctx, argc, argv);
    UNLOCK();
    return result;
}

static term nif_esp32cam_capture_locked(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);

    if (!camera_initialized) {
        ESP_LOGE(TAG, "Camera not initialized! Call esp32cam:init() first.");
        RAISE_ERROR(globalcontext_make_atom(ctx->global, bad_state_a));
    }

    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
        ESP_LOGE(TAG, "Camera capture failed");
        if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
            RAISE_ERROR(MEMORY_ATOM);
        }
        term error = port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, capture_failed_a));
        return error;
    }

    if (UNLIKELY(memory_ensure_free(ctx, term_binary_data_size_in_terms(fb->len) + BINARY_HEADER_SIZE + 4) != MEMORY_GC_OK)) {
        esp_camera_fb_return(fb);
        ESP_LOGE(TAG, "Image memory allocation (%i) failed", fb->len);
        RAISE_ERROR(MEMORY_ATOM);
    }
    term image = term_from_literal_binary((const char *) fb->buf, fb->len, &ctx->heap, ctx->global);
    esp_camera_fb_return(fb);

    return port_create_tuple2(ctx, OK_ATOM, image);
}

static term nif_esp32cam_capture(Context *ctx, int argc, term argv[])
{
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    term result = nif_esp32cam_capture_locked(ctx, argc, argv);
    UNLOCK();
    return result;
}

static term nif_esp32cam_set_control_locked(Context *ctx, int argc, term argv[])
{
    if (argc != 2) {
        RAISE_ERROR(BADARG_ATOM);
    }
    if (!camera_initialized) {
        ESP_LOGE(TAG, "Camera not initialized! Call esp32cam:init() first.");
        RAISE_ERROR(globalcontext_make_atom(ctx->global, bad_state_a));
    }

    sensor_t *s = esp_camera_sensor_get();
    if (s == NULL) {
        ESP_LOGE(TAG, "Could not get sensor pointer");
        if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
            RAISE_ERROR(MEMORY_ATOM);
        }
        return port_create_error_tuple(ctx, term_from_int28(ESP_FAIL));
    }

    term control = argv[0];
    term value = argv[1];
    int sensor_err = ESP_FAIL;

    if (control == globalcontext_make_atom(ctx->global, wb_mode_a)) {
        int wb_mode;
        if (value == globalcontext_make_atom(ctx->global, auto_a)) {
            wb_mode = 0;
        } else if (value == globalcontext_make_atom(ctx->global, sunny_a)) {
            wb_mode = 1;
        } else if (value == globalcontext_make_atom(ctx->global, cloudy_a)) {
            wb_mode = 2;
        } else if (value == globalcontext_make_atom(ctx->global, office_a)) {
            wb_mode = 3;
        } else if (value == globalcontext_make_atom(ctx->global, home_a)) {
            wb_mode = 4;
        } else {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_wb_mode != NULL) {
            sensor_err = s->set_wb_mode(s, wb_mode);
        }
    } else if (control == globalcontext_make_atom(ctx->global, auto_white_balance_a)) {
        if (value != TRUE_ATOM && value != FALSE_ATOM) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_whitebal != NULL) {
            sensor_err = s->set_whitebal(s, value == TRUE_ATOM);
        }
    } else if (control == globalcontext_make_atom(ctx->global, awb_gain_a)) {
        if (value != TRUE_ATOM && value != FALSE_ATOM) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_awb_gain != NULL) {
            sensor_err = s->set_awb_gain(s, value == TRUE_ATOM);
        }
    } else if (control == globalcontext_make_atom(ctx->global, brightness_a)) {
        if (!term_is_any_integer(value)) {
            RAISE_ERROR(BADARG_ATOM);
        }
        avm_int_t val = term_to_int(value);
        if (val < -2 || val > 2) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_brightness != NULL) {
            sensor_err = s->set_brightness(s, val);
        }
    } else if (control == globalcontext_make_atom(ctx->global, contrast_a)) {
        if (!term_is_any_integer(value)) {
            RAISE_ERROR(BADARG_ATOM);
        }
        avm_int_t val = term_to_int(value);
        if (val < -2 || val > 2) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_contrast != NULL) {
            sensor_err = s->set_contrast(s, val);
        }
    } else if (control == globalcontext_make_atom(ctx->global, saturation_a)) {
        if (!term_is_any_integer(value)) {
            RAISE_ERROR(BADARG_ATOM);
        }
        avm_int_t val = term_to_int(value);
        if (val < -2 || val > 2) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_saturation != NULL) {
            sensor_err = s->set_saturation(s, val);
        }
    } else if (control == globalcontext_make_atom(ctx->global, hmirror_a)) {
        if (value != TRUE_ATOM && value != FALSE_ATOM) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_hmirror != NULL) {
            sensor_err = s->set_hmirror(s, value == TRUE_ATOM ? 1 : 0);
        }
    } else if (control == globalcontext_make_atom(ctx->global, vflip_a)) {
        if (value != TRUE_ATOM && value != FALSE_ATOM) {
            RAISE_ERROR(BADARG_ATOM);
        }
        if (s->set_vflip != NULL) {
            sensor_err = s->set_vflip(s, value == TRUE_ATOM ? 1 : 0);
        }
    } else {
        RAISE_ERROR(BADARG_ATOM);
    }

    if (sensor_err != 0) {
        ESP_LOGE(TAG, "Failed to apply sensor control: err=%d", sensor_err);
        if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
            RAISE_ERROR(MEMORY_ATOM);
        }
        return port_create_error_tuple(ctx, term_from_int28(sensor_err));
    }

    return OK_ATOM;
}

static term nif_esp32cam_set_control(Context *ctx, int argc, term argv[])
{
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    term result = nif_esp32cam_set_control_locked(ctx, argc, argv);
    UNLOCK();
    return result;
}

static term nif_esp32cam_get_board_info_locked(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);

    if (!camera_initialized) {
        return globalcontext_make_atom(ctx->global, undefined_a);
    }

    if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    term board_atom;
    switch (initialized_board_type) {
        case BOARD_AI_THINKER: board_atom = globalcontext_make_atom(ctx->global, ai_thinker_a); break;
        case BOARD_WROVER_KIT: board_atom = globalcontext_make_atom(ctx->global, wrover_kit_a); break;
        case BOARD_ESP32S3_WROOM: board_atom = globalcontext_make_atom(ctx->global, esp32s3_wroom_a); break;
        case BOARD_ESP32S3_GOOUUU: board_atom = globalcontext_make_atom(ctx->global, esp32s3_goouuu_a); break;
        case BOARD_ESP32S3_XIAO: board_atom = globalcontext_make_atom(ctx->global, esp32s3_xiao_a); break;
        case BOARD_M5CAM: board_atom = globalcontext_make_atom(ctx->global, m5cam_a); break;
        case BOARD_M5CAM_WIDE: board_atom = globalcontext_make_atom(ctx->global, m5cam_wide_a); break;
        case BOARD_M5CAM_PSRAM: board_atom = globalcontext_make_atom(ctx->global, m5cam_psram_a); break;
        case BOARD_LILYGO_T_CAMERA_S3: board_atom = globalcontext_make_atom(ctx->global, lilygo_t_camera_s3_a); break;
        case BOARD_LILYGO_T_CAMERA: board_atom = globalcontext_make_atom(ctx->global, lilygo_t_camera_a); break;
        case BOARD_LILYGO_T_CAMERA_PLUS: board_atom = globalcontext_make_atom(ctx->global, lilygo_t_camera_plus_a); break;
        case BOARD_LILYGO_T_JOURNAL: board_atom = globalcontext_make_atom(ctx->global, lilygo_t_journal_a); break;
        case BOARD_M5CAM_TIMER: board_atom = globalcontext_make_atom(ctx->global, m5cam_timer_a); break;
        case BOARD_M5CAM_UNIT_S3_5MP: board_atom = globalcontext_make_atom(ctx->global, m5cam_unit_s3_5mp_a); break;
        case BOARD_ESP_EYE: board_atom = globalcontext_make_atom(ctx->global, esp_eye_a); break;
        case BOARD_CUSTOM: board_atom = globalcontext_make_atom(ctx->global, custom_a); break;
        default: board_atom = globalcontext_make_atom(ctx->global, undefined_a); break;
    }

    term flash_pin_term = (initialized_flash_pin >= 0) ? term_from_int28(initialized_flash_pin) : globalcontext_make_atom(ctx->global, undefined_a);
    return port_create_tuple2(ctx, board_atom, flash_pin_term);
}

static term nif_esp32cam_get_board_info(Context *ctx, int argc, term argv[])
{
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    term result = nif_esp32cam_get_board_info_locked(ctx, argc, argv);
    UNLOCK();
    return result;
}

static term nif_esp32cam_psram_size(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);

    size_t total_psram = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);

    if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    return term_from_int(total_psram);
}

static term pixformat_to_term(pixformat_t format, Context *ctx)
{
    switch (format) {
        case PIXFORMAT_RGB565: return globalcontext_make_atom(ctx->global, rgb565_a);
        case PIXFORMAT_YUV422: return globalcontext_make_atom(ctx->global, yuv422_a);
        case PIXFORMAT_YUV420: return globalcontext_make_atom(ctx->global, yuv420_a);
        case PIXFORMAT_GRAYSCALE: return globalcontext_make_atom(ctx->global, grayscale_a);
        case PIXFORMAT_JPEG: return globalcontext_make_atom(ctx->global, jpeg_a);
        case PIXFORMAT_RGB888: return globalcontext_make_atom(ctx->global, rgb888_a);
        case PIXFORMAT_RAW: return globalcontext_make_atom(ctx->global, raw_a);
        case PIXFORMAT_RGB444: return globalcontext_make_atom(ctx->global, rgb444_a);
        case PIXFORMAT_RGB555: return globalcontext_make_atom(ctx->global, rgb555_a);
        case PIXFORMAT_RAW8: return globalcontext_make_atom(ctx->global, raw8_a);
        default: return globalcontext_make_atom(ctx->global, undefined_a);
    }
}

static void camera_frame_dtor(ErlNifEnv *caller_env, void *obj)
{
    UNUSED(caller_env);
    struct CameraFrame *frame = (struct CameraFrame *) obj;
    LOCK();
    if (!frame->released) {
        if (frame->fb != NULL) {
            esp_camera_fb_return(frame->fb);
            frame->fb = NULL;
        }
        frame->released = true;
        outstanding_leases--;
    }
    UNLOCK();
}

static void camera_view_dtor(ErlNifEnv *caller_env, void *obj)
{
    UNUSED(caller_env);
    struct CameraView *view = (struct CameraView *) obj;
    LOCK();
    if (view->frame != NULL) {
        view->frame->active_views--;
        struct CameraFrame *frame = view->frame;
        view->frame = NULL;
        enif_release_resource(frame);
    }
    UNLOCK();
}

static const ErlNifResourceTypeInit camera_frame_resource_type_init = {
    .members = 1,
    .dtor = camera_frame_dtor,
    .stop = NULL,
    .down = NULL
};

static const ErlNifResourceTypeInit camera_view_resource_type_init = {
    .members = 1,
    .dtor = camera_view_dtor,
    .stop = NULL,
    .down = NULL
};

static term nif_esp32cam_capture_frame(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);

    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    if (!camera_initialized) {
        UNLOCK();
        ESP_LOGE(TAG, "Camera not initialized! Call esp32cam:init() first.");
        RAISE_ERROR(globalcontext_make_atom(ctx->global, bad_state_a));
    }

    if (UNLIKELY(memory_ensure_free(ctx, TERM_BOXED_REFERENCE_RESOURCE_SIZE + 3) != MEMORY_GC_OK)) {
        UNLOCK();
        RAISE_ERROR(MEMORY_ATOM);
    }

    if (outstanding_leases >= configured_fb_count) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, frames_in_use_a));
    }

    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
        UNLOCK();
        ESP_LOGE(TAG, "Camera capture failed");
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, capture_failed_a));
    }

    struct CameraFrame *frame = enif_alloc_resource(camera_frame_resource_type, sizeof(struct CameraFrame));
    if (IS_NULL_PTR(frame)) {
        esp_camera_fb_return(fb);
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, enomem_a));
    }

    frame->fb = fb;
    frame->released = false;
    frame->active_views = 0;
    outstanding_leases++;

    term frame_term = term_from_resource(frame, &ctx->heap);
    enif_release_resource(frame);

    term result = port_create_tuple2(ctx, OK_ATOM, frame_term);
    UNLOCK();
    return result;
}

static term nif_esp32cam_frame_binary(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    void *frame_ptr;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], camera_frame_resource_type, &frame_ptr))) {
        RAISE_ERROR(BADARG_ATOM);
    }

    struct CameraFrame *frame = (struct CameraFrame *) frame_ptr;

    if (UNLIKELY(memory_ensure_free(ctx, 16) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    if (frame->released) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, already_released_a));
    }

    struct CameraView *view = enif_alloc_resource(camera_view_resource_type, sizeof(struct CameraView));
    if (IS_NULL_PTR(view)) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, enomem_a));
    }

    view->frame = frame;
    frame->active_views++;
    enif_keep_resource(frame);

    term bin_term = term_from_resource_binary(view, frame->fb->buf, frame->fb->len, &ctx->heap, ctx->global);
    enif_release_resource(view);

    term result = port_create_tuple2(ctx, OK_ATOM, bin_term);
    UNLOCK();
    return result;
}

static term nif_esp32cam_frame_info(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    void *frame_ptr;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], camera_frame_resource_type, &frame_ptr))) {
        RAISE_ERROR(BADARG_ATOM);
    }

    struct CameraFrame *frame = (struct CameraFrame *) frame_ptr;

    if (UNLIKELY(memory_ensure_free(ctx, 32) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    if (frame->released) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, already_released_a));
    }

    term size_val = term_from_int(frame->fb->len);
    term width_val = term_from_int(frame->fb->width);
    term height_val = term_from_int(frame->fb->height);
    term format_val = pixformat_to_term(frame->fb->format, ctx);

    time_t sec = frame->fb->timestamp.tv_sec;
    suseconds_t usec = frame->fb->timestamp.tv_usec;
    term megaseconds = term_from_int(sec / 1000000);
    term seconds = term_from_int(sec % 1000000);
    term microseconds = term_from_int(usec);

    term timestamp_tuple = port_create_tuple3(ctx, megaseconds, seconds, microseconds);

    term map = term_alloc_map(5, &ctx->heap);
    term_set_map_assoc(map, 0, globalcontext_make_atom(ctx->global, size_a), size_val);
    term_set_map_assoc(map, 1, globalcontext_make_atom(ctx->global, width_a), width_val);
    term_set_map_assoc(map, 2, globalcontext_make_atom(ctx->global, height_a), height_val);
    term_set_map_assoc(map, 3, globalcontext_make_atom(ctx->global, pixel_format_a), format_val);
    term_set_map_assoc(map, 4, globalcontext_make_atom(ctx->global, timestamp_a), timestamp_tuple);

    term result = port_create_tuple2(ctx, OK_ATOM, map);
    UNLOCK();
    return result;
}

static term nif_esp32cam_release_frame(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    void *frame_ptr;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], camera_frame_resource_type, &frame_ptr))) {
        RAISE_ERROR(BADARG_ATOM);
    }

    struct CameraFrame *frame = (struct CameraFrame *) frame_ptr;

    if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    LOCK();
    if (frame->released) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, already_released_a));
    }

    if (frame->active_views > 0) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, binary_views_active_a));
    }

    esp_camera_fb_return(frame->fb);
    frame->fb = NULL;
    frame->released = true;
    outstanding_leases--;

    UNLOCK();
    return OK_ATOM;
}

static bool term_image_write(const void *data, size_t size)
{
    return fwrite(data, 1, size, stdout) == size;
}

static bool term_image_write_base64(const uint8_t *data, size_t size)
{
    static const char base64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char output[TERM_IMAGE_BASE64_BUFFER_SIZE];
    size_t input_pos = 0;
    size_t output_pos = 0;

    while (input_pos + 3 <= size) {
        if (output_pos + 4 > sizeof(output)) {
            if (!term_image_write(output, output_pos)) {
                return false;
            }
            output_pos = 0;
        }

        uint32_t value = ((uint32_t) data[input_pos] << 16)
            | ((uint32_t) data[input_pos + 1] << 8)
            | data[input_pos + 2];
        output[output_pos++] = base64_table[(value >> 18) & 0x3F];
        output[output_pos++] = base64_table[(value >> 12) & 0x3F];
        output[output_pos++] = base64_table[(value >> 6) & 0x3F];
        output[output_pos++] = base64_table[value & 0x3F];
        input_pos += 3;
    }

    size_t remaining = size - input_pos;
    if (remaining > 0) {
        if (output_pos + 4 > sizeof(output)) {
            if (!term_image_write(output, output_pos)) {
                return false;
            }
            output_pos = 0;
        }

        uint32_t value = (uint32_t) data[input_pos] << 16;
        if (remaining == 2) {
            value |= (uint32_t) data[input_pos + 1] << 8;
        }
        output[output_pos++] = base64_table[(value >> 18) & 0x3F];
        output[output_pos++] = base64_table[(value >> 12) & 0x3F];
        output[output_pos++] = remaining == 2 ? base64_table[(value >> 6) & 0x3F] : '=';
        output[output_pos++] = '=';
    }

    return output_pos == 0 || term_image_write(output, output_pos);
}

static term nif_term_image_display_frame(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (UNLIKELY(!camera_resources_ready)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    if (UNLIKELY(memory_ensure_free(ctx, 3) != MEMORY_GC_OK)) {
        RAISE_ERROR(MEMORY_ATOM);
    }

    void *frame_ptr;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], camera_frame_resource_type, &frame_ptr))) {
        return port_create_error_tuple(ctx, BADARG_ATOM);
    }

    struct CameraFrame *frame = (struct CameraFrame *) frame_ptr;
    LOCK();
    if (frame->released) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, already_released_a));
    }
    if (frame->fb->len > MAX_TERM_IMAGE_SIZE) {
        UNLOCK();
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, too_large_a));
    }

    bool output_ok = fprintf(stdout, "\n\n\e]1337;File=size=%zu;inline=1:", frame->fb->len) >= 0
        && term_image_write_base64(frame->fb->buf, frame->fb->len)
        && term_image_write("\a\n", 2)
        && fflush(stdout) == 0;
    UNLOCK();

    if (!output_ok) {
        return port_create_error_tuple(ctx, globalcontext_make_atom(ctx->global, io_error_a));
    }
    return OK_ATOM;
}

static const struct Nif esp32cam_init_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_init
};
static const struct Nif esp32cam_capture_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_capture
};
static const struct Nif esp32cam_set_control_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_set_control
};
static const struct Nif esp32cam_get_board_info_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_get_board_info
};
static const struct Nif esp32cam_capture_frame_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_capture_frame
};
static const struct Nif esp32cam_frame_binary_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_frame_binary
};
static const struct Nif esp32cam_frame_info_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_frame_info
};
static const struct Nif esp32cam_release_frame_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_release_frame
};
static const struct Nif esp32cam_psram_size_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_esp32cam_psram_size
};
static const struct Nif term_image_display_frame_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_term_image_display_frame
};

void atomvm_esp32cam_init(GlobalContext *global)
{
    camera_mutex = xSemaphoreCreateRecursiveMutex();
    if (IS_NULL_PTR(camera_mutex)) {
        ESP_LOGE(TAG, "Failed to allocate camera mutex");
        return;
    }

    ErlNifEnv env;
    erl_nif_env_partial_init_from_globalcontext(&env, global);
    camera_frame_resource_type = enif_init_resource_type(&env, "camera_frame", &camera_frame_resource_type_init, ERL_NIF_RT_CREATE, NULL);
    camera_view_resource_type = enif_init_resource_type(&env, "camera_view", &camera_view_resource_type_init, ERL_NIF_RT_CREATE, NULL);

    if (IS_NULL_PTR(camera_frame_resource_type) || IS_NULL_PTR(camera_view_resource_type)) {
        ESP_LOGE(TAG, "Failed to initialize camera resource types");
        return;
    }

    camera_resources_ready = true;
}

const struct Nif *atomvm_esp32cam_get_nif(const char *nifname)
{
    if (strcmp("esp32cam:init_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_init_nif;
    }
    if (strcmp("esp32cam:capture_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_capture_nif;
    }
    if (strcmp("esp32cam:set_control_nif/2", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_set_control_nif;
    }
    if (strcmp("esp32cam:get_board_info_nif/0", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_get_board_info_nif;
    }
    if (strcmp("esp32cam:capture_frame_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_capture_frame_nif;
    }
    if (strcmp("esp32cam:frame_binary_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_frame_binary_nif;
    }
    if (strcmp("esp32cam:frame_info_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_frame_info_nif;
    }
    if (strcmp("esp32cam:release_frame_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_release_frame_nif;
    }
    if (strcmp("esp32cam:psram_size_nif/0", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &esp32cam_psram_size_nif;
    }
    if (strcmp("term_image:display_frame_nif/1", nifname) == 0) {
        TRACE("Resolved platform nif %s ...\n", nifname);
        return &term_image_display_frame_nif;
    }

    return NULL;
}

#ifdef CONFIG_AVM_ESP32CAM_ENABLE
REGISTER_NIF_COLLECTION(atomvm_esp32cam, atomvm_esp32cam_init, NULL, atomvm_esp32cam_get_nif)
#endif
