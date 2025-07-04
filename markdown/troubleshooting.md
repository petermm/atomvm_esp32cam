# Troubleshooting Guide

This guide helps you diagnose and resolve common issues encountered when building, flashing, and running applications with the AtomVM ESP32 Camera driver.

---

## 1. Camera Initialization Fails

If calling `esp32cam:init/0` or `esp32cam:init/1` returns `{error, Reason}` (e.g. `{error, ESP_ERR_CAMERA_NOT_DETECTED}` or similar driver errors), check the following:

### Check the Board Identifier
Ensure the `{board, BoardId}` option matches your physical board. If you specify `ai_thinker` but you are using an `m5cam_psram`, the pin mapping will be wrong, causing the camera sensor to be undetectable.
* **Tip**: If you are unsure about the board type, run `camera_scanner:scan()` to auto-detect the configuration.

### Verify Power Supply
ESP32 camera boards can draw significant peak currents (up to 350mA) during camera initialization and image capture (especially when the flash LED is on).
* A weak USB port or a low-quality USB cable can cause voltage drops, causing camera initialization failures or spontaneous ESP32 brownout reboots.
* **Solution**: Power the board with a stable 5V external power source, and use a high-quality USB data cable.

### Pin Conflicts
Ensure that none of the GPIO pins allocated to the camera are initialized by other parts of your Erlang/Elixir code (e.g., trying to write to GPIO 4 while the camera driver is using it for the flash).

---

## 2. Memory Allocation & Out of Memory Crashes

Captured image data is represented as an AtomVM reference-counted binary. Large images can easily saturate the ESP32's internal RAM.

### Decrease Resolution and Quality
If you encounter memory allocation failures (such as `refc_binary` allocations returning `enomem` or causing immediate VM crashes):
1. **Reduce Resolution**: Decrease `frame_size` (e.g., from `uxga` to `svga` or `vga`).
2. **Increase Compression**: Increase `jpeg_quality` (e.g., from `5` to `12` or `15`) to reduce the final file size.

### Enforce PSRAM Placement
Ensure that `fb_location` is set to `psram` (default). If you configure `fb_location` as `dram`, the frame buffer will be placed in internal DRAM, leaving very little space for AtomVM processes.

### Force Garbage Collection
In loops or high-frequency captures, the garbage collector might not reclaim memory quickly enough, leading to heap exhaustion.
* **Solution**: Manually call `erlang:garbage_collect/0` in your loop after processing or sending each captured image:
```erlang
loop() ->
    {ok, Image} = esp32cam:capture(),
    send_image(Image),
    % Force immediate collection of the binary reference
    erlang:garbage_collect(),
    loop().
```

---

## 3. Poor Image Quality or Glitches

### Horizontal Lines / Static
Noise in the captured image is typically caused by electrical interference (EMI) or signal integrity issues on the clock lines.
* **Solution**: Lower the clock frequency configuration. Set `{xclk_freq_hz, 10000000}` (10 MHz) instead of the default 20 MHz. This will slow down the frame capture rate slightly but significantly clean up signal lines.

### Blurred / Out of Focus Images
Most ESP32-CAM modules have manually adjustable lenses.
* **Solution**: Gently rotate the plastic camera lens ring left or right until the image preview becomes sharp.

### Very Green or Distorted Image on First Capture
When the camera sensor first powers up or wakes from deep sleep, its internal Automatic Exposure Control (AEC) and Auto White Balance (AWB) algorithms require a few frames to calibrate to ambient light levels. Capturing an image immediately after initialization often results in a strong green or dark tint.
* **Solution**: Enable the `warm_up_frames` option during initialization to automatically discard the first few frames (10 to 20 frames is highly recommended):
  ```erlang
  esp32cam:init([{board, ai_thinker}, {warm_up_frames, 15}])
  ```

### Completely Black or Blown Out Flash Pictures
If you use flash (`{flash, on}`), the picture might capture too early before the sensor has calibrated exposure to the new light, or after the flash has turned off.
* **Solution**: Specify a `{flash_delay_ms, Delay}` parameter. A delay between `50` and `150` milliseconds gives the sensor's Auto Exposure Control (AEC) enough time to settle and expose the picture correctly.

---

## 4. Web Installer & Flashing Issues

If the Web Installer fails to recognize your device or write firmware, try these steps:

### Install Drivers
Ensure your operating system has the correct USB-to-UART bridge drivers installed:
* **CP2102**: [Silicon Labs CP210x Driver](https://www.silabs.com/products/development-tools/software/usb-to-uart-bridge-vcp-drivers)
* **CH340 / CH341 / CH9102**: [WCH Driver Page](https://www.wch-ic.com/downloads/CH341SER_ZIP.html)

### Enter Bootloader Mode Manually
Some boards lack automatic bootloader circuit lines.
* **Solution**: 
  1. Hold down the **BOOT** (or IO0) button.
  2. Click **Install** in your browser.
  3. Briefly press the **EN** (or RST) button on the board while continuing to hold the BOOT button.
  4. Release the BOOT button once the browser connection screen starts.
