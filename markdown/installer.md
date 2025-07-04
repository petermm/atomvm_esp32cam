# Web Installer

You can flash a pre-built AtomVM firmware image—compiled with ESP32 camera driver support—directly from your web browser using [ESP Web Tools](https://esphome.github.io/esp-web-tools/).

---

## Requirements

### Browser Compatibility {: .note}
> **Web Serial API Required**: Flashing requires Google Chrome or Microsoft Edge on a desktop computer.
> Apple Safari, Mozilla Firefox, and mobile browsers are not supported.

Before attempting to flash:
1. Connect your ESP32 or ESP32-S3 board to your computer via a USB data cable.
2. Ensure you have the appropriate USB-to-serial drivers installed for your board's bridge chip.

### Driver Download Links

If your operating system does not automatically recognize the connected board, download and install the drivers for its interface chip:

* **CP2102 / CP2104** (common on AI-Thinker ESP32-CAM):
  [Windows & Mac VCP Drivers](https://www.silabs.com/products/development-tools/software/usb-to-uart-bridge-vcp-drivers)
* **CH342 / CH343 / CH9102**:
  [Windows Driver](https://www.wch.cn/downloads/CH343SER_ZIP.html) | [Mac Driver](https://www.wch.cn/downloads/CH34XSER_MAC_ZIP.html)
* **CH340 / CH341**:
  [Windows Driver](https://www.wch.cn/downloads/CH341SER_ZIP.html) | [Mac Driver](https://www.wch.cn/downloads/CH341SER_MAC_ZIP.html)

---

## ⚡ Erlang Firmware Installer

This installs AtomVM with built-in camera driver support. Ideal for standard Erlang projects.

<div>
  <script type="module"
          src="https://unpkg.com/esp-web-tools@10/dist/web/install-button.js?module">
  </script>

  <esp-web-install-button manifest="manifest.json">
    <button slot="activate" style="cursor: pointer; padding: 10px 20px; font-weight: bold; background-color: #4CAF50; color: white; border: none; border-radius: 4px;">⚡ Install Erlang Firmware</button>
    <span slot="unsupported">
      Web Serial is not available in this browser. Please use Chrome or Edge on a desktop computer.
    </span>
  </esp-web-install-button>
</div>

---

## ⚡ Elixir Firmware Installer

This installs AtomVM with both camera driver support and the Elixir standard library.

<div>
  <esp-web-install-button manifest="manifest-elixir.json">
    <button slot="activate" style="cursor: pointer; padding: 10px 20px; font-weight: bold; background-color: #9c27b0; color: white; border: none; border-radius: 4px;">⚡ Install Elixir Firmware</button>
    <span slot="unsupported">
      Web Serial is not available in this browser. Please use Chrome or Edge on a desktop computer.
    </span>
  </esp-web-install-button>
</div>

---

## Deploying Applications After Flashing

Once the base firmware image is flashed, you can compile and deploy your Erlang/Elixir applications directly to the device's flash using the Rebar3 command-line plugin:

```sh
rebar3 atomvm esp32_flash -p /dev/ttyUSB0
```

### Next Steps {: .tip}
> - Review the [Examples & Recipes](examples.html) to see how to capture images and control the flash.
> - Consult the [Configuration Reference](configuration.html) for full details on image sizes, formats, and clock options.

---

## Flashing Troubleshooting

### Flashing Fails or Hangs {: .warning}
> If the installer times out or fails to connect:
> 1. Press and hold the **BOOT** (or IO0) button on your board.
> 2. Click the **Install** button in your browser.
> 3. Press and release the **EN** (or RST) button on the board, then release the BOOT button. This forces the board into bootloader mode.
