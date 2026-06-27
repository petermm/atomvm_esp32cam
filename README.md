# AtomVM ESP32 Camera Driver

[![Build Status](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml/badge.svg)](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/esp32cam.svg)](https://hex.pm/packages/esp32cam)

An [AtomVM](https://atomvm.net) port driver and Erlang library for controlling ESP32 and ESP32-S3 camera modules (supporting OV2640, OV3660, and compatible image sensors). It brings native camera integration to the Erlang/Elixir BEAM ecosystem on low-cost microcontrollers.

This driver runs as a custom component compiled directly into the AtomVM firmware. Pre-built firmware binaries for popular ESP32 camera development boards can be flashed directly from your browser using the [Web Installer](markdown/installer.md).

---

## Key Features

* **High-Speed Capturing**: Up to UXGA resolution (1600x1200) with double-buffering support.
* **Auto-Hardware Detection**: Detect board configurations automatically at runtime using `camera_scanner`.
* **Flash LED Control**: Native Erlang API for triggering high-power board flashes with pre-shot delay exposure calibration.
* **Memory Optimized**: Designed to handle reference-counted binaries efficiently inside AtomVM.
* **Multiple Pixel Formats**: Grab frames in JPEG, RGB565, Grayscale, or Raw format.

---

## Quick Start

### 1. Initialize & Capture (Default Settings)
By default, the driver initializes for the standard AI-Thinker ESP32-CAM board with an XGA (1024x768) JPEG configuration:

```erlang
% Initialize camera
ok = esp32cam:init(),

% Capture a single frame
{ok, ImageData} = esp32cam:capture(),
io:format("Captured JPEG image: ~p bytes~n", [byte_size(ImageData)]).
```

### 2. Custom Configuration & Flash Photography
Configure double buffering, high-quality resolution (requires board with PSRAM), and trigger the flash:

```erlang
Config = [
    {board, m5cam_psram},      % Board with PSRAM
    {frame_size, uxga},        % 1600x1200
    {jpeg_quality, 5},         % High detail
    {fb_count, 2},             % Double-buffering
    {fb_location, psram}       % Place buffer in PSRAM
],
ok = esp32cam:init(Config),

% Capture with flash active and a 100ms delay for exposure calibration
{ok, Image} = esp32cam:capture([{flash, on}, {flash_delay_ms, 100}]).
```

### 3. Autofocus Control (OV5640 Sensors)
Autofocus requires an OV5640 module with an autofocus lens, `esp32-camera >= 2.1.5`,
and `CONFIG_OV5640_SUPPORT=y` plus `CONFIG_CAMERA_AF_SUPPORT=y` in the firmware configuration.
AF is **disabled by default** in `sdkconfig.defaults.esp32cam` to save flash.
With AF disabled, all AF NIFs return `{error, unsupported}`. With AF enabled,
`af_init/1` returns `{error, unsupported}` for non-AF sensors such as OV2640.

```erlang
% Initialize autofocus config
ok = esp32cam:af_init([{mode, auto}, {timeout_ms, 2000}]),

% Trigger focusing
ok = esp32cam:af_trigger(),

% Wait for completion, then verify that focus was actually achieved.
% af_wait/1 can return {ok, Status} with focused => false.
{ok, #{busy := false, focused := true}} = esp32cam:af_wait(2000),

% Capture image now that it's focused!
{ok, Image} = esp32cam:capture().
```

With AF enabled, operations before successful `af_init/1` return `{error, bad_state}`.
Reinitializing the camera or setting PSRAM DMA mode (even to the current value)
requires another `af_init/1`. A failed driver-level AF initialization also invalidates AF readiness.

Timeouts are unsigned 32-bit milliseconds. `af_wait(0)` uses the configured timeout;
initializing AF with `timeout_ms = 0` keeps the driver's previous timeout (initially 2000 ms).
Range and step values are unsigned 16-bit integers, with `range_min =< range_max`.
Both range endpoints default to zero, so a nonzero minimum requires an explicit maximum.
The v2.1.5 driver does not apply range/step settings, and its OV5640 manual-position
callback is unimplemented: `af_set_manual_position/1` returns `{error, -1}` (`ESP_FAIL`).

---

## Documentation

To help you get started, the documentation is divided into the following sections:

### Guides
* 🔌 **[Supported Boards](markdown/board_support.md)**: Details on pinouts, SoC specifications, and flash GPIO configurations.
* ⚙️ **[Configuration Reference](markdown/configuration.md)**: Comprehensive guide to all initialization settings, resolutions, and quality parameters.
* 💡 **[Examples & Recipes](markdown/examples.md)**: Copy-pasteable Erlang examples for video streaming, auto-detection, low-power modes, and more.
* ⚡ **[Web Installer](markdown/installer.md)**: Flash official firmware containing this driver to your board directly in your browser.
* 🛠️ **[Troubleshooting Guide](markdown/troubleshooting.md)**: Fixing camera initialization, flashing issues, and VM memory allocation failures.

### Module API Reference
* [esp32cam](esp32cam.html) — The core driver API.
* [camera_scanner](camera_scanner.html) — The board auto-detection tool.
* [esp32cam_mock](esp32cam_mock.html) — Simulated driver for local off-hardware testing.

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](license.html) for details.
