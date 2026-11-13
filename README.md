# AtomVM ESP32 Camera Driver

[![Build Status](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml/badge.svg)](https://github.com/atomvm/atomvm_esp32cam/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/esp32cam.svg)](https://hex.pm/packages/esp32cam)

An [AtomVM](https://atomvm.net) NIF driver and Erlang library for controlling ESP32 and ESP32-S3 camera modules (supporting OV2640, OV3660, OV5640, GC0308, and compatible sensors). It brings native camera capture, zero-copy streaming, runtime reconfiguration, and autofocus control to the Erlang/Elixir BEAM ecosystem.

This driver runs as a native ESP-IDF component compiled directly into the AtomVM firmware. Pre-built firmware binaries for popular ESP32 and ESP32-S3 camera boards can be flashed straight from your browser using the [Web Installer](markdown/installer.md).

---

## Key Features

* **15 Predefined Boards + Custom Pinouts**: Out-of-the-box support for popular ESP32 and ESP32-S3 boards (including AI-Thinker, WROVER-KIT, ESP32-S3 WROOM/XIAO/GOOUUU, M5Cam, LilyGO T-Camera, and ESP-EYE), arbitrary `{board, custom}` GPIO pinouts, and runtime detection via `camera_scanner`.
* **Standard & Zero-Copy Frame Capture**: Capture reference-counted Erlang binaries (`capture/0,1`) or lease PSRAM/driver framebuffers directly with zero extra copies (`capture_frame/0,1`, `frame_binary/1`, `frame_info/1`, `release_frame/1`) and non-blocking readiness checks (`available_frames/0`).
* **Up to 5MP Resolution & 10 Pixel Formats**: Capture from `96x96` up to `'5mp'` (`2592x1944`) across `jpeg`, `rgb565`, `grayscale`, `yuv422`, `yuv420`, `rgb888`, `raw`, `rgb444`, `rgb555`, and `raw8`.
* **Runtime Reconfiguration & Sensor Controls**: Dynamically resize or switch pixel formats without a full teardown via `reconfigure/1`, adjust live controls (`brightness`, `contrast`, `saturation`, `hmirror`, `vflip`, `wb_mode` presets or custom `{custom, R, G, B}` RGB gains), and toggle PSRAM DMA mode (`set_psram_mode/1`).
* **Flash LED & Warm-Up Calibration**: Built-in board flash control with pre-shot exposure delay (`{flash, on}`, `{flash_delay_ms, Ms}`) and C-level `warm_up_frames` discarding.
* **OV5640 Autofocus Support**: Opt-in autofocus configuration, triggering, polling, and wait APIs (`af_init/1`, `af_set_mode/1`, `af_trigger/0`, `af_get_status/0`, `af_wait/1`, `af_set_manual_position/1`).
* **Terminal Preview & Off-Hardware Mocks**: Render captured binaries or leased frames directly in iTerm2-compatible terminals with `term_image:display/1`, and run unit/Common Test suites on your host using `esp32cam_mock`.

---

## Requirements

* **ESP-IDF**: `>= 5.1.0`
* **Driver Component**: `espressif/esp32-camera >= 2.1.9,<3.0.0` (configured in `idf_component.yml`)

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
% Optional non-blocking readiness check
case esp32cam:available_frames() of
    true ->
        {ok, Frame} = esp32cam:capture_frame(),
        {ok, Info} = esp32cam:frame_info(Frame),
        io:format("Frame ~px~p (~p)~n", [
            maps:get(width, Info),
            maps:get(height, Info),
            maps:get(format, Info)
        ]),
        % Display directly from the leased framebuffer or read its binary view
        ok = term_image:display(Frame),
        ok = esp32cam:release_frame(Frame);
    false ->
        ok
end.
```

> **Note**: While any zero-copy view from `frame_binary/1` is still referenced by live Erlang terms, `release_frame/1` prevents premature buffer return; let references go out of scope (or trigger GC) before releasing.

### 4. Runtime Reconfiguration & Sensor Controls
Adjust sensor image controls, apply custom RGB white balance gains, switch PSRAM DMA mode, or reconfigure resolution/pixel format on the fly without calling `init/1` from scratch:

```erlang
% Change resolution and grab mode (all zero-copy frames must be released first)
ok = esp32cam:reconfigure([
    {frame_size, vga},
    {pixel_format, jpeg},
    {grab_mode, latest}
]),

% Tune sensor controls live
ok = esp32cam:set_control(brightness, 1),
ok = esp32cam:set_control(wb_mode, sunny),

% Or set normalized 8-bit custom RGB white balance gains (0..255, 64 = ~1.0x)
% Supported on OV2640, OV3660, OV5640, and GC0308 sensors
ok = esp32cam:set_control(wb_mode, {custom, 80, 64, 52}),

% Toggle PSRAM DMA mode (ESP32-S3)
ok = esp32cam:set_psram_mode(true).
```

### 5. Autofocus Control (OV5640 Sensors)
Autofocus requires an OV5640 module with an autofocus coil, `esp32-camera >= 2.1.9`,
and both `CONFIG_OV5640_SUPPORT=y` and `CONFIG_CAMERA_AF_SUPPORT=y` in your firmware configuration.
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
Initializing, reconfiguring the camera (`reconfigure/1`), or setting PSRAM DMA mode (even to the current value)
requires another `af_init/1`. A failed driver-level AF initialization also invalidates AF readiness.

Timeouts are unsigned 32-bit milliseconds. `af_wait(0)` uses the configured timeout;
initializing AF with `timeout_ms = 0` keeps the driver's previous timeout (initially 2000 ms).
Range and step values are unsigned 16-bit integers, with `range_min =< range_max`.
Both range endpoints default to zero, so a nonzero minimum requires an explicit maximum.
The v2.1.9 driver still does not apply range/step settings, and its OV5640 manual-position
callback is unimplemented: `af_set_manual_position/1` returns `{error, -1}` (`ESP_FAIL`).

---

## API Overview

| Category | Functions |
|---|---|
| **Lifecycle & Info** | `esp32cam:init/0,1`, `esp32cam:reconfigure/1`, `esp32cam:get_board_info/0`, `esp32cam:has_flash/0,1`, `esp32cam:psram_size/0` |
| **Standard Capture** | `esp32cam:capture/0,1`, `esp32cam:capture_with_flash/1,2` |
| **Zero-Copy Capture** | `esp32cam:capture_frame/0,1`, `esp32cam:frame_binary/1`, `esp32cam:frame_info/1`, `esp32cam:release_frame/1`, `esp32cam:available_frames/0` |
| **Controls & DMA** | `esp32cam:set_control/2`, `esp32cam:set_psram_mode/1`, `esp32cam:get_psram_mode/0` |
| **Autofocus (OV5640)** | `esp32cam:af_init/1`, `esp32cam:af_set_mode/1`, `esp32cam:af_trigger/0`, `esp32cam:af_get_status/0`, `esp32cam:af_wait/1`, `esp32cam:af_set_manual_position/1` |
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
* ⚙️ **[Configuration Reference](markdown/configuration.md)**: Initialization options, `reconfigure/1`, `set_control/2` controls, resolutions, and capture parameters.
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
