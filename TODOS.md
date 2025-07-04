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
