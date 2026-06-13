# TODOs

## Custom White Balance Gains

Add portable custom manual white balance configuration:

```erlang
{wb_mode, {custom, R, G, B}}
```

Implementation notes:

- Define normalized gain ranges and document their meaning rather than exposing raw sensor registers.
- Detect the active sensor through `sensor->id.PID`.
- Translate normalized RGB gains to each sensor's register layout and bit depth.
- Initially support OV2640, OV3660, OV5640, and GC0308.
- Return `{error, unsupported}` for sensors without a verified manual-gain implementation.
- Disable automatic white balance as required before applying custom gains.
- Validate gain ranges in both the native driver and `esp32cam_mock`.
- Add unit tests for configuration validation and hardware tests for each supported sensor.

The existing OV2640 preset bytes cannot be applied directly to every sensor:

- OV2640 uses three 8-bit gains in DSP registers `0xCC`, `0xCD`, and `0xCE`.
- OV3660 and OV5640 use wider RGB gains in registers `0x3400`, `0x3402`, and `0x3404`.
- GC0308 uses separate 8-bit RGB gain registers with different preset values.
- NT99141 uses a different multi-register sequence and needs separate investigation.

## Advanced Driver Capabilities

Integrate additional features from the Espressif `esp32-camera` driver:

### Autofocus Support (`esp_camera_af.h`)
For boards featuring camera modules with active autofocus coils (e.g. OV5640 modules on ESP32-S3 Eye / Seeed Sense):
- Expose APIs: `af_init/1`, `af_set_mode/1`, `af_trigger/0`, `af_get_status/0`, `af_wait/1`, and `af_set_manual_position/1`.
- Add mock implementations and configuration options.

### Runtime Reconfiguration (`esp_camera_reconfigure`)
Avoid full sensor reset cycles when switching frame size or pixel format:
- Implement `reconfigure/1` to dynamically change the camera config using `esp_camera_reconfigure` instead of a full deinit/init cycle.

### Non-blocking Frame Queries
Allow checking if a frame is ready in the driver queue without blocking:
- Expose `available_frames/0 -> boolean()` querying `esp_camera_available_frames()`.

### PSRAM DMA Mode Control
Enable toggling the transfer mechanism (Direct DMA vs DRAM intermediate copy) at runtime:
- Expose `set_psram_mode/1` and `get_psram_mode/0` wrapping `esp_camera_set_psram_mode/esp_camera_get_psram_mode`.

### NVS Settings Save/Load
Expose driver-level settings persistence to/from Non-Volatile Storage (NVS):
- Expose `save_to_nvs/1` and `load_from_nvs/1` wrapping `esp_camera_save_to_nvs/esp_camera_load_from_nvs`.

