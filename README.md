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
