# esp32_example

Welcome to the esp32_example AtomVM application.

To build and flash this application to your ESP32 device, issue the `esp32_flash` target

    shell$ rebar3 esp32_flash

## Zero-copy stress test

After the example starts and identifies the camera board, run the zero-copy
frame lifecycle stress test from the AtomVM console:

```erlang
esp32cam_example:zero_copy_stress(ai_thinker, 1000).
```

Replace `ai_thinker` with the detected board atom. The test configures two
PSRAM framebuffers and checks:

- a rapid five-frame native iTerm display burst directly from leased
  framebuffers;
- two simultaneous leases and immediate rejection of a third;
- rejection of camera reinitialization while frames are leased;
- zero-copy binary size and metadata consistency;
- rejection of explicit release while a binary view is alive;
- successful release after forced garbage collection;
- periodic GC-only framebuffer return without explicit release;
- reference-counted binary memory throughout the run.

It returns `ok` after all iterations or `{error, ...}` at the first failed
lifecycle invariant. A shorter default run is available as
`esp32cam_example:zero_copy_stress(Board)`.

The native display path can also be used directly:

```erlang
{ok, Frame} = esp32cam:capture_frame(),
ok = term_image:display(Frame),
ok = esp32cam:release_frame(Frame).
```

Unlike `term_image:display(Binary)`, displaying a frame streams base64 from
PSRAM through a small fixed buffer and does not allocate a complete JPEG or
base64 copy.

## MJPEG HTTP Streaming Server

You can start an HTTP MJPEG video streaming server directly on the device using the zero-copy frame lease API:

```erlang
esp32cam_mjpeg:start(ai_thinker).
```

This starts the server on the default port `8080` (or pass a second parameter to specify a different port). Once your device connects to Wi-Fi, open your browser and navigate to `http://<esp32-ip>:8080` to view the live video stream.

