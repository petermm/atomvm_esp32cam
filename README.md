# AtomVM ESP32 Camera Driver

[![Build Status](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml/badge.svg)](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/esp32cam.svg)](https://hex.pm/packages/esp32cam)

An [AtomVM](https://atomvm.net) NIF driver and Erlang library for controlling ESP32 and ESP32-S3 camera modules (supporting OV2640, OV3660, and compatible image sensors). It brings native camera capture, zero-copy streaming, and runtime sensor controls to the Erlang/Elixir BEAM ecosystem.

This driver runs as a native ESP-IDF component compiled directly into the AtomVM firmware. Pre-built firmware binaries for popular ESP32 and ESP32-S3 camera boards can be flashed straight from your browser using the [Web Installer](markdown/installer.md).

---

## Key Features

* **15 Predefined Boards + Custom Pinouts**: Out-of-the-box support for popular ESP32 and ESP32-S3 boards (including AI-Thinker, WROVER-KIT, ESP32-S3 WROOM/XIAO/GOOUUU, M5Cam, LilyGO T-Camera, and ESP-EYE), arbitrary `{board, custom}` GPIO pinouts, and runtime detection via `camera_scanner`.
* **Standard & Zero-Copy Frame Capture**: Capture reference-counted Erlang binaries (`capture/0,1`) or lease PSRAM/driver framebuffers directly with zero extra copies (`capture_frame/0,1`, `frame_binary/1`, `frame_info/1`, `release_frame/1`).
* **Up to 5MP Resolution & 10 Pixel Formats**: Capture from `96x96` up to `'5mp'` (`2592x1944`) across `jpeg`, `rgb565`, `grayscale`, `yuv422`, `yuv420`, `rgb888`, `raw`, `rgb444`, `rgb555`, and `raw8`.
* **Runtime Sensor Controls & PSRAM DMA**: Adjust live controls (`brightness`, `contrast`, `saturation`, `hmirror`, `vflip`, `wb_mode`, `auto_white_balance`, `awb_gain`) without restarting the camera, and toggle PSRAM DMA mode (`set_psram_mode/1`).
* **Flash LED & Warm-Up Calibration**: Built-in board flash control with pre-shot exposure delay (`{flash, on}`, `{flash_delay_ms, Ms}`) and C-level `warm_up_frames` discarding.
* **Terminal Preview & Off-Hardware Mocks**: Render captured binaries or leased frames directly in iTerm2-compatible terminals with `term_image:display/1`, and run unit/Common Test suites on your host using `esp32cam_mock`.

---

## Quick Start

### 1. Initialize & Capture (Default Settings)
By default, `esp32cam:init/0` configures an AI-Thinker ESP32-CAM at XGA (`1024x768`) resolution in JPEG format with automatic frame buffer sizing (`{fb_count, auto}`):

```erlang
% Initialize camera
ok = esp32cam:init(),

% Capture a single JPEG binary
{ok, ImageData} = esp32cam:capture(),
io:format("Captured JPEG image: ~p bytes~n", [byte_size(ImageData)]).
```

### 2. Board Auto-Detection, Warm-Up & Flash Photography
Detect the connected board automatically with `camera_scanner`, tune buffer settings, discard initial AWB/AEC calibration frames with `warm_up_frames`, and capture with the flash LED:

```erlang
{ok, Board} = camera_scanner:scan(),

Config = [
    {board, Board},
    {frame_size, uxga},        % 1600x1200 (requires PSRAM)
    {jpeg_quality, 5},         % 0..63 (lower = higher quality)
    {fb_count, auto},          % Default: picks 1..3 buffers from PSRAM budget
    {fb_location, psram},
    {warm_up_frames, 10}       % Discard initial frames while exposure settles
],
ok = esp32cam:init(Config),

% Capture with flash active and a 100ms delay for exposure calibration
{ok, Image} = esp32cam:capture([{flash, on}, {flash_delay_ms, 100}]).
```

### 3. Zero-Copy Frame Capture & Terminal Preview
For streaming or memory-constrained loops, `capture_frame/0,1` leases the driver framebuffer without copying it into a new Erlang heap binary. Always call `release_frame/1` once you are done reading `frame_binary/1`:

```erlang
{ok, Frame} = esp32cam:capture_frame(),
{ok, Info} = esp32cam:frame_info(Frame),
io:format("Frame ~px~p (~p)~n", [
    maps:get(width, Info),
    maps:get(height, Info),
    maps:get(format, Info)
]),
% Display directly from the leased framebuffer or read its binary view
ok = term_image:display(Frame),
ok = esp32cam:release_frame(Frame).
```

> **Note**: While any zero-copy view from `frame_binary/1` is still referenced by live Erlang terms, `release_frame/1` prevents premature buffer return; let references go out of scope (or trigger GC) before releasing.

### 4. Runtime Sensor Controls & PSRAM DMA
Adjust sensor image controls or toggle PSRAM DMA mode on the fly without calling `init/1` from scratch:

```erlang
% Tune sensor controls live
ok = esp32cam:set_control(brightness, 1),
ok = esp32cam:set_control(wb_mode, sunny),

% Toggle PSRAM DMA mode (ESP32-S3)
ok = esp32cam:set_psram_mode(true).
```

---

## API Overview

| Category | Functions |
|---|---|
| **Lifecycle & Info** | `esp32cam:init/0,1`, `esp32cam:get_board_info/0`, `esp32cam:has_flash/0,1`, `esp32cam:psram_size/0` |
| **Standard Capture** | `esp32cam:capture/0,1`, `esp32cam:capture_with_flash/1,2` |
| **Zero-Copy Capture** | `esp32cam:capture_frame/0,1`, `esp32cam:frame_binary/1`, `esp32cam:frame_info/1`, `esp32cam:release_frame/1` |
| **Controls & DMA** | `esp32cam:set_control/2`, `esp32cam:set_psram_mode/1`, `esp32cam:get_psram_mode/0` |
| **Utilities** | `camera_scanner:scan/0,1`, `term_image:display/1` |

---

## Local Development & Testing

You can run the host-side formatting checks, EUnit tests, and Common Test suite (powered by `esp32cam_mock`) without connected ESP32 hardware:

```sh
rebar3 fmt --check
rebar3 eunit
rebar3 ct
```

---

## Documentation

### Guides
* 🔌 **[Supported Boards](markdown/board_support.md)**: Pinouts, SoC specs, custom GPIO configuration, and flash GPIO mappings.
* ⚙️ **[Configuration Reference](markdown/configuration.md)**: Initialization options, `set_control/2` controls, resolutions, and capture parameters.
* 💡 **[Examples & Recipes](markdown/examples.md)**: Copy-pasteable Erlang snippets for streaming, board auto-detection, flash shots, and low-power setups.
* ⚡ **[Web Installer](markdown/installer.md)**: Flash official AtomVM + camera firmware directly from your browser.
* 🛠️ **[Troubleshooting Guide](markdown/troubleshooting.md)**: Diagnostics for initialization errors, memory allocation, signal quality, and flashing.

### Module API Reference
* [esp32cam](esp32cam.html) — The core driver API.
* [camera_scanner](camera_scanner.html) — Runtime board auto-detection and SD card helpers.
* [term_image](term_image.html) — Terminal inline image rendering (`iTerm2` / compatible consoles).
* [esp32cam_mock](esp32cam_mock.html) — Simulated driver for local off-hardware testing.

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](license.html) for details.
