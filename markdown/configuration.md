# Configuration Reference

When initializing the camera with `esp32cam:init/1`, you pass a proplist of options. This document describes all configuration settings supported by the driver.

---

## Configuration Options

### Board Selection
* **Key**: `board`
* **Type**: `ai_thinker | wrover_kit | esp32s3_wroom | esp32s3_goouuu | esp32s3_xiao | m5cam | m5cam_wide | m5cam_psram | lilygo_t_camera_s3 | lilygo_t_camera | lilygo_t_camera_plus | lilygo_t_journal | m5cam_timer | m5cam_unit_s3_5mp | esp_eye | custom`
* **Default**: `ai_thinker`
* **Description**: Selects the target board configuration (or `custom` with explicit pin assignments). This determines the pin mappings and flash LED GPIO assignments used by the driver. See [Supported Boards](board_support.md) for pin details.

---

### Frame Size
* **Key**: `frame_size`
* **Type**: `atom` (representing resolution)
* **Default**: `xga`
* **Description**: Set the capture resolution. Larger resolutions require more memory and may have slower frame rates.

| Option | Resolution | Aspect Ratio | Recommended Board Feature |
|---|---|---|---|
| `'96x96'` | 96 x 96 | 1:1 | Low-power / Small footprint |
| `qqvga` | 160 x 120 | 4:3 | Low-power / Small footprint |
| `'128x128'` | 128 x 128 | 1:1 | Low-power |
| `qcif` | 176 x 144 | 11:9 | Low-power |
| `hqvga` | 240 x 176 | 4:3 | Low-power |
| `'240x240'` | 240 x 240 | 1:1 | Low-power |
| `qvga` | 320 x 240 | 4:3 | Low-power / Quick preview |
| `'320x320'` | 320 x 320 | 1:1 | Low-power |
| `cif` | 400 x 296 | 4:3 | Low-power |
| `hvga` | 480 x 320 | 3:2 | Standard |
| `vga` | 640 x 480 | 4:3 | Standard |
| `svga` | 800 x 600 | 4:3 | Standard |
| `xga` | 1024 x 768 | 4:3 | Standard |
| `hd` | 1280 x 720 | 16:9 | High Resolution (Requires PSRAM) |
| `sxga` | 1280 x 1024 | 5:4 | High Resolution (Requires PSRAM) |
| `uxga` | 1600 x 1200 | 4:3 | High Resolution (Requires PSRAM) |
| `fhd` | 1920 x 1080 | 16:9 | High Resolution (Requires PSRAM) |
| `qxga` | 2048 x 1536 | 4:3 | High Resolution (Requires PSRAM) |
| `'5mp'` | 2592 x 1944 | 4:3 | High Resolution (Requires PSRAM) |

### Warning {: .warning}
> High resolutions (such as `hd` and above) consume significant memory. Boards without external PSRAM (like the classic `m5cam` or custom barebones chips) will crash or fail to initialize when configured with large resolutions. Ensure your frame buffers are placed in PSRAM if using high resolutions.

---

### JPEG Quality
* **Key**: `jpeg_quality`
* **Type**: `0..63`
* **Default**: `12`
* **Description**: Controls the JPEG compression level. A **lower** value produces higher image quality (more detail, less compression) but results in a larger file size. A **higher** value increases compression, resulting in lower image quality and smaller file sizes.
* **Recommended Range**: `5-15` (good balance between quality and binary size).

---

### Pixel Format
* **Key**: `pixel_format`
* **Type**: `jpeg | grayscale | rgb565 | yuv422 | yuv420 | rgb888 | raw | rgb444 | rgb555 | raw8`
* **Default**: `jpeg`
* **Description**: Specifies the output pixel format of captured images. `jpeg` is optimized for web delivery and transmission over networks. Uncompressed formats like `rgb565` or `grayscale` are useful for local computer vision or display rendering but require large memory allocations.

---

### Clock Frequency
* **Key**: `xclk_freq_hz`
* **Type**: `pos_integer()`
* **Default**: `20000000` (20 MHz)
* **Description**: Camera sensor master clock frequency in Hertz.
* **Range**: Typically `10,000,000` to `24,000,000` Hz.
* **Effects**: Higher clock speeds increase the camera's frame rate/throughput but increase power consumption and EMI (electromagnetic interference). If you observe frame distortions or static lines, try lowering this clock frequency (e.g. to `10000000`).

---

### Frame Buffer Count
* **Key**: `fb_count`
* **Type**: `pos_integer() | auto`
* **Default**: `auto`
* **Description**: Number of frame buffers allocated for the camera sensor. Setting `auto` selects `1`, `2`, or `3` buffers automatically based on available PSRAM (`psram_size/0`), `fb_location`, `frame_size`, and `pixel_format` (keeping total buffers within 25% of PSRAM, or `1` when using DRAM or when PSRAM is unavailable). Setting an integer `2` or higher explicitly configures multi-buffering.

---

### Frame Buffer Location
* **Key**: `fb_location`
* **Type**: `psram | dram`
* **Default**: `psram` (stored in external RAM)
* **Description**: Specifies where frame buffers are allocated:
  - `psram`: Use external SPI RAM. Highly recommended, as DRAM space is extremely limited.
  - `dram`: Use internal Data RAM. Faster access speeds, but limits you to small frame sizes (e.g., QVGA or VGA).

---

### Grab Mode
* **Key**: `grab_mode`
* **Type**: `when_empty | latest`
* **Default**: `when_empty`
* **Description**: Determines how the driver grabs images from the frame buffers:
  - `when_empty`: The driver blocks and waits for a new frame to be captured by the sensor. Best for taking one-off pictures.
  - `latest`: The driver always returns the most recently completed frame, discarding older frames. Recommended for low-latency video streaming.

---

### Warm-Up Frames
* **Key**: `warm_up_frames`
* **Type**: `0..100`
* **Default**: `0`
* **Description**: Number of initial frames to discard during initialization, limited to 100 to keep initialization bounded. When the sensor first initializes or wakes from sleep, the Automatic Exposure Control (AEC), Automatic Gain Control (AGC), and Auto White Balance (AWB) need several frame cycles to calibrate to ambient light. Setting this option to a value like `15` prevents the first captured picture from appearing with a strong green or dark tint. Discarding is performed in C, avoiding Erlang heap allocations and garbage collection overhead. Initialization fails if a warm-up frame cannot be captured.

---

### Auto White Balance Control
* **Key**: `auto_white_balance`
* **Type**: `boolean()`
* **Default**: `true`
* **Description**: Enable or disable Automatic White Balance (AWB).

---

### Auto White Balance Gain Control
* **Key**: `awb_gain`
* **Type**: `boolean()`
* **Default**: `true`
* **Description**: Enable or disable Automatic White Balance gain control.

---

### White Balance Mode
* **Key**: `wb_mode`
* **Type**: `auto | sunny | cloudy | office | home | {custom, R, G, B}` (where `R`, `G`, `B` are integers `0..255`)
* **Default**: `auto`
* **Description**: Selects the white balance preset mode or manual custom RGB channel gains:
  - `auto`: Auto adjustments (default).
  - `sunny`: Preset for outdoor daylight.
  - `cloudy`: Preset for overcast conditions.
  - `office`: Preset for indoor/office lighting.
  - `home`: Preset for warm home lighting.
  - `{custom, R, G, B}`: Normalized 8-bit manual RGB gains (`0..255`, where `64` represents nominal `1.0x` unity gain). Supported on OV2640, OV3660, OV5640, and GC0308 sensors; returns `{error, unsupported}` on other sensors. Presets require `auto_white_balance` and `awb_gain` to be enabled.

---

### Brightness
* **Key**: `brightness`
* **Type**: `-100..100`
* **Default**: `0`
* **Description**: Controls image brightness using smooth register-level steps on OV2640, OV3660, OV5640, and GC0308 sensors (returns `{error, unsupported}` on other sensors).

---

### Contrast
* **Key**: `contrast`
* **Type**: `-100..100`
* **Default**: `0`
* **Description**: Controls image contrast using smooth register-level steps on OV2640, OV3660, OV5640, and GC0308 sensors (returns `{error, unsupported}` on other sensors).

---

### Saturation
* **Key**: `saturation`
* **Type**: `-100..100`
* **Default**: `0`
* **Description**: Controls image saturation using smooth register-level steps on OV2640, OV3660, OV5640, and GC0308 sensors (returns `{error, unsupported}` on other sensors).

---

### Exposure & Gain Controls
* **`ae_level`** (`-100..100`, default `0`): Auto-exposure compensation target. Interpolates AE target registers on OV2640, OV3660, OV5640, and GC0308 sensors.
* **`exposure_ctrl`** (`boolean()`, default `true`): Enable or disable Automatic Exposure Control (AEC).
* **`aec2`** (`boolean()`, default `false`): Enable or disable DSP-level secondary AEC processing.
* **`aec_value`** (`0..1200`): Manual exposure time value when `exposure_ctrl` is `false`.
* **`gain_ctrl`** (`boolean()`, default `true`): Enable or disable Automatic Gain Control (AGC).
* **`agc_gain`** (`0..64`): Manual sensor analog/digital gain when `gain_ctrl` is `false` (note: some sensors such as OV2640 and GC0308 clamp the upper range to `30`).
* **`gainceiling`** (`'2x' | '4x' | '8x' | '16x' | '32x' | '64x' | '128x' | 0..6`, default `'2x'`): Maximum automatic gain ceiling when `gain_ctrl` is `true`.

---

### Sharpness & Denoise
* **`sharpness`** (`-100..100`, default `0`): Controls edge enhancement/sharpness on supported sensors (OV3660, OV5640, GC0308; returns `{error, unsupported}` on OV2640 and other sensors).
* **`denoise`** (`0..8`, default `0`): Controls hardware noise reduction level (`0` disables denoise) on supported sensors (e.g., OV3660, OV5640).

---

### Horizontal Mirror
* **Key**: `hmirror`
* **Type**: `boolean()`
* **Default**: `false`
* **Description**: Horizontally mirrors the captured frame.

---

### Vertical Flip
* **Key**: `vflip`
* **Type**: `boolean()`
* **Default**: `false`
* **Description**: Vertically flips/inverts the captured frame.

---

## Runtime Reconfiguration (`reconfigure/1`)

Instead of performing a full sensor teardown and reinitialization, an already-initialized camera can be reconfigured at runtime:

```erlang
ok = esp32cam:reconfigure([
    {frame_size, svga},
    {pixel_format, jpeg},
    {jpeg_quality, 10},
    {fb_count, auto},
    {grab_mode, latest}
]).
```

Unspecified options inherit their active values (including the active board and custom pin mapping when `board` is omitted). All active zero-copy frames from `capture_frame/0,1` must be released before calling `reconfigure/1` (otherwise it returns `{error, frames_in_use}`). Reconfiguring invalidates autofocus readiness, so call `af_init/1` again if autofocus is in use.

---

## Runtime Camera Controls

Camera settings can be changed after initialization without restarting the camera:

```erlang
ok = esp32cam:set_control(wb_mode, sunny),
ok = esp32cam:set_control(wb_mode, {custom, 80, 64, 52}),
ok = esp32cam:set_control(auto_white_balance, true),
ok = esp32cam:set_control(awb_gain, true),
ok = esp32cam:set_control(brightness, 25),
ok = esp32cam:set_control(contrast, -15),
ok = esp32cam:set_control(saturation, 40),
ok = esp32cam:set_control(ae_level, 10),
ok = esp32cam:set_control(exposure_ctrl, false),
ok = esp32cam:set_control(aec_value, 450),
ok = esp32cam:set_control(gain_ctrl, false),
ok = esp32cam:set_control(agc_gain, 12),
ok = esp32cam:set_control(hmirror, true),
ok = esp32cam:set_control(vflip, false).
```

Supported controls and values:

* `wb_mode`: `auto | sunny | cloudy | office | home | {custom, 0..255, 0..255, 0..255}`
* `auto_white_balance`: `boolean()`
* `awb_gain`: `boolean()`
* `brightness`: `-100..100`
* `contrast`: `-100..100`
* `saturation`: `-100..100`
* `ae_level`: `-100..100`
* `sharpness`: `-100..100`
* `exposure_ctrl`: `boolean()`
* `aec2`: `boolean()`
* `aec_value`: `0..1200`
* `gain_ctrl`: `boolean()`
* `agc_gain`: `0..64`
* `gainceiling`: `'2x' | '4x' | '8x' | '16x' | '32x' | '64x' | '128x' | 0..6`
* `denoise`: `0..8`
* `hmirror`: `boolean()`
* `vflip`: `boolean()`

The camera must be initialized first. Missing callbacks and rejected values return an error. Some upstream sensor drivers implement unsupported controls as successful no-ops.

---

## Low-Level Driver Settings

The following options are advanced settings intended for troubleshooting or custom hardware integrations:

* **`sccb_i2c_port`** (`non_neg_integer()`): Specifies the ESP32 hardware I2C port number to use for sensor control communications. Defaults to `0`.
* **`ledc_timer`** (`0..3`): LEDC timer resource used for generating the XCLK clock signal. Defaults to `0`.
* **`ledc_channel`** (`0..7`): LEDC channel resource used for XCLK generation. Defaults to `0`.
* **`conv_mode`** (`disable | rgb565_to_yuv422 | yuv422_to_rgb565 | yuv422_to_yuv420`): Enables hardware color conversion. Defaults to `disable`.

### Note {: .note}
> Hardware color conversion (`conv_mode` options other than `disable`) requires compiling the AtomVM ESP32 firmware image with the Espressif option `CONFIG_CAMERA_CONVERTER_ENABLED` turned on in the IDF configuration.

---

## Capture-Time Flash Options

When calling `esp32cam:capture/1`, `esp32cam:capture_frame/1`, or `esp32cam:capture_with_flash/2`, you can pass options to control flash photography:

* **`{flash, on | off}`**: Enforce turning on or off the board's high-power LED flash during capture. Defaults to `off`.
* **`{flash_delay_ms, non_neg_integer()}`**: Specifies a pre-shot delay in milliseconds after turning on the flash LED before capturing the frame. This is crucial for allowing the sensor to auto-adjust exposure and focus under the bright light. Defaults to `0` (immediate capture).
