# Examples & Recipes

This document provides copy-pasteable Erlang code recipes for using the AtomVM ESP32 Camera driver under different scenarios.

---

## Quick Start (AI-Thinker Board)

This snippet initializes the camera with default parameters (AI-Thinker board, XGA resolution, JPEG format) and captures a single image.

```erlang
-module(simple_capture).
-export([run/0]).

run() ->
    % 1. Initialize the camera with default settings (ai_thinker, xga resolution)
    ok = esp32cam:init(),
    
    % 2. Capture a JPEG frame
    {ok, ImageData} = esp32cam:capture(),
    
    % 3. Log the size of the captured binary
    io:format("Successfully captured ~p bytes!~n", [byte_size(ImageData)]).
```

---

## High-Quality Capture (PSRAM required)

Use this recipe to capture high-definition images using board configurations with external PSRAM (e.g. M5CAM-PSRAM, Seeed XIAO Sense, ESP32-S3 WROOM).

```erlang
-module(hd_capture).
-export([run/0]).

run() ->
    Config = [
        {board, m5cam_psram},      % M5Stack camera with PSRAM
        {frame_size, uxga},        % 1600x1200 resolution
        {jpeg_quality, 5},         % Lower value = high detail / low compression
        {fb_location, psram}       % Enforce buffer allocation in PSRAM
    ],
    ok = esp32cam:init(Config),
    
    {ok, Image} = esp32cam:capture(),
    io:format("Captured high-res image (~p bytes)~n", [byte_size(Image)]).
```

---

## Auto-Detecting Board Type with Camera Scanner

Instead of hardcoding the `board` parameter, you can use the `camera_scanner` module to probe the connected hardware pins at runtime. It automatically detects the chip (ESP32 or ESP32-S3) and tries matching configurations.

```erlang
-module(auto_detect_capture).
-export([run/0]).

run() ->
    % 1. Scan for the connected board type
    case camera_scanner:scan() of
        {ok, DetectedBoard} ->
            io:format("Detected board: ~p~n", [DetectedBoard]),
            
            % 2. Initialize with the detected board + custom resolution
            Config = [
                {board, DetectedBoard},
                {frame_size, vga},
                {jpeg_quality, 10}
            ],
            ok = esp32cam:init(Config),
            
            % 3. Capture image
            {ok, Image} = esp32cam:capture(),
            io:format("Captured ~p bytes using ~p~n", [byte_size(Image), DetectedBoard]);
            
        {error, not_found} ->
            io:format("Error: Could not automatically detect board type!~n")
    end.
```

### Tip {: .tip}
> You can also supply a base configuration list to `camera_scanner:scan/1`. The scanner will append the detected `{board, Board}` to your options list:
> ```erlang
> {ok, Board} = camera_scanner:scan([{frame_size, qvga}]).
> ```

---

## High-Performance Streaming Configuration

This recipe configures double frame buffering and a fast camera clock. Grab mode is set to `latest` to ensure your program reads the newest available frame instead of queueing older ones, minimizing video latency.

```erlang
-module(video_streamer).
-export([start_stream/0]).

start_stream() ->
    Config = [
        {board, ai_thinker},
        {frame_size, svga},          % 800x600 resolution
        {jpeg_quality, 10},
        {fb_count, 2},               % Double-buffering for fluid rates
        {fb_location, psram},        % Allocate in PSRAM
        {grab_mode, latest},         % Lower latency, drops old frames
        {xclk_freq_hz, 24000000}     % Fast 24 MHz camera clock
    ],
    ok = esp32cam:init(Config),
    stream_loop().

stream_loop() ->
    {ok, Frame} = esp32cam:capture(),
    % Transmit frame over UDP or WebSockets
    ok = send_frame_to_network(Frame),
    stream_loop().

send_frame_to_network(_Frame) ->
    % Your network code here
    ok.
```

---

## Flash Photography with Exposure Delay

If your board has a flash LED (e.g. AI-Thinker or ESP32-S3 WROOM), you can turn it on during capture. A pre-shot delay (`flash_delay_ms`) gives the sensor time to adjust exposure (avoiding completely white/overexposed pictures).

```erlang
-module(flash_photos).
-export([capture_night_shot/0]).

capture_night_shot() ->
    ok = esp32cam:init([{board, ai_thinker}, {frame_size, vga}]),
    
    % Capture with flash active and a 100ms exposure delay
    CaptureParams = [
        {flash, on},
        {flash_delay_ms, 100}
    ],
    {ok, FlashImage} = esp32cam:capture(CaptureParams),
    io:format("Flash picture captured! (~p bytes)~n", [byte_size(FlashImage)]).
```

### Note {: .note}
> The driver safely turns off the flash LED even if the capture operation crashes mid-flight.

---

## Raw Color Grabbing (No JPEG compression)

If you are rendering to an SPI TFT screen or running a simple edge detection program on the SoC, you can capture raw uncompressed `rgb565` or `grayscale` data instead of JPEG.

```erlang
-module(raw_processor).
-export([process_grayscale/0]).

process_grayscale() ->
    Config = [
        {board, ai_thinker},
        {frame_size, qqvga},         % Keep it small (160x120) to fit SRAM
        {pixel_format, grayscale},   % Raw 8-bit gray values (1 byte per pixel)
        {fb_location, dram}          % Use internal DRAM for fast reads
    ],
    ok = esp32cam:init(Config),
    
    {ok, RawData} = esp32cam:capture(),
    % RawData is exactly 160 * 120 = 19,200 bytes
    io:format("Raw grayscale buffer size: ~p bytes~n", [byte_size(RawData)]),
    analyze_pixels(RawData).

analyze_pixels(_RawData) ->
    % Custom logic
    ok.
```

---

## Low-Power Setup

For battery-powered IoT applications, lower the clock frequency to 10 MHz, reduce resolution, and use a single frame buffer stored in internal DRAM (allowing you to power down external PSRAM blocks).

```erlang
-module(low_power_sensor).
-export([capture_and_sleep/0]).

capture_and_sleep() ->
    Config = [
        {board, m5cam},
        {frame_size, qvga},
        {pixel_format, jpeg},
        {jpeg_quality, 20},          % Smaller binary transfers
        {fb_count, 1},               % Single frame buffer
        {xclk_freq_hz, 10000000}     % Lower clock speed reduces power
    ],
    ok = esp32cam:init(Config),
    {ok, Image} = esp32cam:capture(),
    ok = send_to_cloud(Image),
    
    % Put ESP32 into deep sleep (sensor pins power down automatically)
    ok.

send_to_cloud(_Image) ->
    ok.
```
