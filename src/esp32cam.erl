%%
%% Copyright (c) 2020 dushin.net
%% All rights reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
-module(esp32cam).

-export([
    init/0, init/1,
    init_nif/1,
    set_control/2,
    set_control_nif/2,
    capture/0, capture/1,
    capture_nif/1,
    capture_frame/0, capture_frame/1,
    capture_frame_nif/1,
    frame_binary/1,
    frame_binary_nif/1,
    frame_info/1,
    frame_info_nif/1,
    release_frame/1,
    release_frame_nif/1,
    capture_with_flash/1, capture_with_flash/2,
    has_flash/0, has_flash/1,
    validate_init_config/1,
    get_board_info/0,
    get_board_info_nif/0,
    psram_size/0,
    psram_size_nif/0,
    resolve_fb_count/2
]).

-define(SUPPORTED_BOARDS, [
    ai_thinker,
    wrover_kit,
    esp32s3_wroom,
    esp32s3_goouuu,
    esp32s3_xiao,
    m5cam,
    m5cam_wide,
    m5cam_psram,
    lilygo_t_camera_s3,
    lilygo_t_camera,
    lilygo_t_camera_plus,
    lilygo_t_journal,
    m5cam_timer,
    m5cam_unit_s3_5mp,
    esp_eye,
    custom
]).
-define(SUPPORTED_FRAME_SIZES, [
    '96x96',
    qqvga,
    '128x128',
    qcif,
    hqvga,
    '240x240',
    qvga,
    '320x320',
    cif,
    hvga,
    vga,
    svga,
    xga,
    hd,
    sxga,
    uxga,
    fhd,
    p_hd,
    p_3mp,
    qxga,
    qhd,
    wqxga,
    p_fhd,
    qsxga,
    '5mp'
]).
-define(SUPPORTED_PIXEL_FORMATS, [
    jpeg, grayscale, rgb565, yuv422, yuv420, rgb888, raw, rgb444, rgb555, raw8
]).
-define(SUPPORTED_FB_LOCATIONS, [psram, dram]).
-define(SUPPORTED_GRAB_MODES, [when_empty, latest]).
-define(SUPPORTED_CONV_MODES, [disable, rgb565_to_yuv422, yuv422_to_rgb565, yuv422_to_yuv420]).
-define(MAX_WARM_UP_FRAMES, 100).

-type esp32cam_config_item() ::
    {board,
        ai_thinker
        | wrover_kit
        | esp32s3_wroom
        | esp32s3_goouuu
        | esp32s3_xiao
        | m5cam
        | m5cam_wide
        | m5cam_psram
        | lilygo_t_camera_s3
        | lilygo_t_camera
        | lilygo_t_camera_plus
        | lilygo_t_journal
        | m5cam_timer
        | m5cam_unit_s3_5mp
        | esp_eye
        | custom}
    | {frame_size,
        '96x96'
        | qqvga
        | '128x128'
        | qcif
        | hqvga
        | '240x240'
        | qvga
        | '320x320'
        | cif
        | hvga
        | vga
        | svga
        | xga
        | hd
        | sxga
        | uxga
        | fhd
        | p_hd
        | p_3mp
        | qxga
        | qhd
        | wqxga
        | p_fhd
        | qsxga
        | '5mp'}
    | {jpeg_quality, 0..63}
    | {pixel_format,
        jpeg | grayscale | rgb565 | yuv422 | yuv420 | rgb888 | raw | rgb444 | rgb555 | raw8}
    | {xclk_freq_hz, pos_integer()}
    | {fb_count, pos_integer() | auto}
    | {fb_location, psram | dram}
    | {grab_mode, when_empty | latest}
    | {sccb_i2c_port, non_neg_integer()}
    | {ledc_timer, 0..3}
    | {ledc_channel, 0..7}
    | {conv_mode, disable | rgb565_to_yuv422 | yuv422_to_rgb565 | yuv422_to_yuv420}
    | {warm_up_frames, 0..100}
    | {auto_white_balance, boolean()}
    | {awb_gain, boolean()}
    | {wb_mode, auto | sunny | cloudy | office | home}
    | {brightness, -2..2}
    | {contrast, -2..2}
    | {saturation, -2..2}
    | {hmirror, boolean()}
    | {vflip, boolean()}
    | {pin_pwdn, integer()}
    | {pin_reset, integer()}
    | {pin_xclk, integer()}
    | {pin_sccb_sda, integer()}
    | {pin_sccb_scl, integer()}
    | {pin_d7, integer()}
    | {pin_d6, integer()}
    | {pin_d5, integer()}
    | {pin_d4, integer()}
    | {pin_d3, integer()}
    | {pin_d2, integer()}
    | {pin_d1, integer()}
    | {pin_d0, integer()}
    | {pin_vsync, integer()}
    | {pin_href, integer()}
    | {pin_pclk, integer()}
    | {pin_flash, integer()}.
-type esp32cam_config() :: [esp32cam_config_item()].

-type capture_param() :: {flash, on | off} | {flash_delay_ms, non_neg_integer()}.
-type capture_params() :: [capture_param()].
-type flash_options() :: [{delay_ms, non_neg_integer()}].
-type control() ::
    wb_mode | auto_white_balance | awb_gain | brightness | contrast | saturation | hmirror | vflip.
-type control_value() :: auto | sunny | cloudy | office | home | boolean() | -2..2.
-type image() :: binary().
-opaque frame() :: term().
-export_type([frame/0]).

%% Flash pin mappings for different boards
-define(FLASH_PINS, #{
    ai_thinker => 4,
    esp32s3_wroom => 48,
    esp32s3_goouuu => 48,
    esp32s3_xiao => undefined,
    m5cam => 14,
    m5cam_wide => 14,
    m5cam_psram => 14,
    m5cam_unit_s3_5mp => 14,
    % No flash LED
    wrover_kit => undefined,
    lilygo_t_camera_s3 => undefined,
    lilygo_t_camera => undefined,
    lilygo_t_camera_plus => undefined,
    lilygo_t_journal => undefined,
    m5cam_timer => undefined,
    esp_eye => undefined
}).

%% Current board type (stored after init)
-define(BOARD_KEY, esp32cam_current_board).
-define(CUSTOM_FLASH_PIN_KEY, esp32cam_custom_flash_pin).

-define(DEFAULT_CONFIG, [{board, ai_thinker}, {frame_size, xga}, {jpeg_quality, 12}]).

%%-----------------------------------------------------------------------------
%% Internal functions
%%-----------------------------------------------------------------------------

%% Store current board type for flash pin lookup
store_board_type(Config) ->
    Board = proplists:get_value(board, Config, ai_thinker),
    put(?BOARD_KEY, Board),
    case Board of
        custom ->
            store_custom_flash_pin(Config);
        _ ->
            erase(?CUSTOM_FLASH_PIN_KEY),
            ok
    end,
    Board.

store_custom_flash_pin(Config) ->
    case proplists:get_value(pin_flash, Config, undefined) of
        FlashPin when is_integer(FlashPin), FlashPin >= 0 ->
            put(?CUSTOM_FLASH_PIN_KEY, FlashPin);
        _ ->
            erase(?CUSTOM_FLASH_PIN_KEY)
    end.

%% Get flash pin for current board
get_flash_pin() ->
    case get_board_info() of
        {ok, custom, CustomFlashPin} ->
            CustomFlashPin;
        {ok, Board, _FlashPin} ->
            maps:get(Board, ?FLASH_PINS, undefined);
        undefined ->
            undefined
    end.

%% Initialize GPIO for flash control
init_flash_gpio() ->
    case get_flash_pin() of
        undefined ->
            % No flash support
            ok;
        Pin ->
            try
                GPIO = gpio:start(),
                ok = gpio:set_direction(GPIO, Pin, output),
                % Ensure flash is off
                gpio:set_level(GPIO, Pin, 0)
            catch
                _:_ -> {error, gpio_init_failed}
            end
    end.

%% Control flash LED
control_flash(on) ->
    control_flash_level(1);
control_flash(off) ->
    control_flash_level(0).

control_flash_level(Level) ->
    case get_flash_pin() of
        % No flash support
        undefined ->
            ok;
        Pin ->
            try
                GPIO = gpio:start(),
                gpio:set_level(GPIO, Pin, Level)
            catch
                _:_ -> {error, gpio_flash_failed}
            end
    end.

%% Capture with flash control
capture_with_flash_control(CaptureParams, DelayMs) ->
    case init_flash_gpio() of
        ok ->
            try
                case control_flash(on) of
                    ok ->
                        % Optional pre-shot delay
                        case DelayMs of
                            0 -> ok;
                            _ -> timer:sleep(DelayMs)
                        end,

                        % Capture image
                        esp32cam:capture_nif(strip_flash_params(CaptureParams));
                    GpioError ->
                        GpioError
                end
            catch
                Class:Reason ->
                    {error, {Class, Reason}}
            after
                % Always turn off flash, including capture errors.
                _ = control_flash(off)
            end;
        Error ->
            Error
    end.

%% Capture frame with flash control
capture_frame_with_flash_control(CaptureParams, DelayMs) ->
    case init_flash_gpio() of
        ok ->
            try
                case control_flash(on) of
                    ok ->
                        % Optional pre-shot delay
                        case DelayMs of
                            0 -> ok;
                            _ -> timer:sleep(DelayMs)
                        end,

                        % Capture frame
                        esp32cam:capture_frame_nif(strip_flash_params(CaptureParams));
                    GpioError ->
                        GpioError
                end
            catch
                Class:Reason ->
                    {error, {Class, Reason}}
            after
                % Always turn off flash, including capture errors.
                _ = control_flash(off)
            end;
        Error ->
            Error
    end.

validate_capture_params(CaptureParams) ->
    validate_options(CaptureParams, fun validate_capture_param/1).

validate_capture_param({flash, Value}) when Value =:= on; Value =:= off ->
    ok;
validate_capture_param({flash_delay_ms, DelayMs}) when is_integer(DelayMs), DelayMs >= 0 ->
    ok;
validate_capture_param(_) ->
    {error, badarg}.

flash_delay(FlashOptions) ->
    case validate_options(FlashOptions, fun validate_flash_option/1) of
        ok ->
            {ok, proplists:get_value(delay_ms, FlashOptions, 0)};
        Error ->
            Error
    end.

validate_flash_option({delay_ms, DelayMs}) when is_integer(DelayMs), DelayMs >= 0 ->
    ok;
validate_flash_option(_) ->
    {error, badarg}.

validate_options(Options, Validator) when is_list(Options) ->
    validate_options_1(Options, Validator);
validate_options(_, _Validator) ->
    {error, badarg}.

validate_options_1([], _Validator) ->
    ok;
validate_options_1([Option | Rest], Validator) ->
    case Validator(Option) of
        ok -> validate_options_1(Rest, Validator);
        Error -> Error
    end.

strip_flash_params(CaptureParams) ->
    lists:filter(
        fun
            ({flash, _}) -> false;
            ({flash_delay_ms, _}) -> false;
            (_) -> true
        end,
        CaptureParams
    ).

%% NIF function for actual capture (without flash parameter)
capture_nif(_CaptureParams) ->
    throw(nif_error).

capture_frame_nif(_CaptureParams) ->
    throw(nif_error).

frame_binary_nif(_Frame) ->
    throw(nif_error).

frame_info_nif(_Frame) ->
    throw(nif_error).

release_frame_nif(_Frame) ->
    throw(nif_error).

%%-----------------------------------------------------------------------------
%% @returns `ok' or error with reason
%% @doc     Initialize the camera.
%%          Use this function to initialize the ESP32 camera with default configuration.
%% @end
%%-----------------------------------------------------------------------------
-spec init() -> ok | {error, Reason :: term()}.
init() ->
    init(?DEFAULT_CONFIG).

%%-----------------------------------------------------------------------------
%% @param   Config  the ESP32cam configuration
%% @returns `ok' or error with reason
%% @doc     Initialize the camera.
%%          Use this function to initialize the ESP32 camera
%% @end
%%-----------------------------------------------------------------------------
-spec init(Config :: esp32cam_config()) -> ok | {error, Reason :: term()}.
init(Config) ->
    case validate_init_config(Config) of
        {ok, _} ->
            erase(?BOARD_KEY),
            erase(?CUSTOM_FLASH_PIN_KEY),
            ResolvedFbCount = resolve_fb_count(proplists:get_value(fb_count, Config, auto), Config),
            ResolvedConfig = [{fb_count, ResolvedFbCount} | proplists:delete(fb_count, Config)],
            case esp32cam:init_nif(ResolvedConfig) of
                ok ->
                    % Store board type for flash control after init succeeds.
                    store_board_type(Config),
                    ok;
                Error ->
                    Error
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% NIF function for camera initialization
init_nif(_Config) ->
    throw(nif_error).

%%-----------------------------------------------------------------------------
%% @param   Control sensor control name
%% @param   Value sensor control value
%% @returns `ok' or error with reason
%% @doc     Change a supported camera sensor control at runtime.
%% @end
%%-----------------------------------------------------------------------------
-spec set_control(Control :: control(), Value :: control_value()) ->
    ok | {error, Reason :: term()}.
set_control(Control, Value) ->
    case validate_control(Control, Value) of
        ok -> esp32cam:set_control_nif(Control, Value);
        Error -> Error
    end.

validate_control(wb_mode, Value) when
    Value =:= auto; Value =:= sunny; Value =:= cloudy; Value =:= office; Value =:= home
->
    ok;
validate_control(auto_white_balance, Value) when is_boolean(Value) ->
    ok;
validate_control(awb_gain, Value) when is_boolean(Value) ->
    ok;
validate_control(brightness, Value) when is_integer(Value), Value >= -2, Value =< 2 ->
    ok;
validate_control(contrast, Value) when is_integer(Value), Value >= -2, Value =< 2 ->
    ok;
validate_control(saturation, Value) when is_integer(Value), Value >= -2, Value =< 2 ->
    ok;
validate_control(hmirror, Value) when is_boolean(Value) ->
    ok;
validate_control(vflip, Value) when is_boolean(Value) ->
    ok;
validate_control(_, _) ->
    {error, badarg}.

%% NIF function for changing sensor controls at runtime
set_control_nif(_Control, _Value) ->
    throw(nif_error).

%%-----------------------------------------------------------------------------
%% @returns The image data (e.g., JPEG).
%% @doc     Capture an image with the camera.
%%          Use this function to capture an image using the ESP32 camera
%% @end
%%-----------------------------------------------------------------------------
-spec capture() -> {ok, image()} | {error, Reason :: term()}.
capture() ->
    esp32cam:capture_nif([]).

%%-----------------------------------------------------------------------------
%% @param   CaptureParams capture parameters
%% @returns The image data (e.g., JPEG).
%% @doc     Capture an image with the camera.
%%          Use this function to capture an image using the ESP32 camera.
%%          Flash control is handled at the Erlang level using GPIO.
%% @end
%%-----------------------------------------------------------------------------
-spec capture(CaptureParams :: capture_params()) -> {ok, image()} | {error, Reason :: term()}.
capture(CaptureParams) ->
    case validate_capture_params(CaptureParams) of
        ok ->
            case lists:keyfind(flash, 1, CaptureParams) of
                {flash, on} ->
                    FlashDelay = proplists:get_value(flash_delay_ms, CaptureParams, 0),
                    capture_with_flash_control(CaptureParams, FlashDelay);
                {flash, off} ->
                    esp32cam:capture_nif(strip_flash_params(CaptureParams));
                false ->
                    esp32cam:capture_nif(strip_flash_params(CaptureParams))
            end;
        Error ->
            Error
    end.

%%-----------------------------------------------------------------------------
%% @returns `ok' with the camera frame reference, or error.
%% @doc     Capture a frame with the camera leasing the PSRAM framebuffer.
%% @end
%%-----------------------------------------------------------------------------
-spec capture_frame() -> {ok, frame()} | {error, Reason :: term()}.
capture_frame() ->
    esp32cam:capture_frame_nif([]).

%%-----------------------------------------------------------------------------
%% @param   CaptureParams capture parameters
%% @returns `ok' with the camera frame reference, or error.
%% @doc     Capture a frame with the camera leasing the PSRAM framebuffer.
%% @end
%%-----------------------------------------------------------------------------
-spec capture_frame(CaptureParams :: capture_params()) -> {ok, frame()} | {error, Reason :: term()}.
capture_frame(CaptureParams) ->
    case validate_capture_params(CaptureParams) of
        ok ->
            case lists:keyfind(flash, 1, CaptureParams) of
                {flash, on} ->
                    FlashDelay = proplists:get_value(flash_delay_ms, CaptureParams, 0),
                    capture_frame_with_flash_control(CaptureParams, FlashDelay);
                _ ->
                    esp32cam:capture_frame_nif(strip_flash_params(CaptureParams))
            end;
        Error ->
            Error
    end.

%%-----------------------------------------------------------------------------
%% @param   Frame camera frame reference
%% @returns `{ok, binary()}' with a zero-copy view of the frame data, or error.
%% @doc     Return a zero-copy view of the frame data as a resource-managed binary.
%% @end
%%-----------------------------------------------------------------------------
-spec frame_binary(Frame :: frame()) -> {ok, binary()} | {error, Reason :: term()}.
frame_binary(Frame) ->
    esp32cam:frame_binary_nif(Frame).

%%-----------------------------------------------------------------------------
%% @param   Frame camera frame reference
%% @returns `{ok, map()}' with frame metadata, or error.
%% @doc     Get metadata info of a frame.
%% @end
%%-----------------------------------------------------------------------------
-spec frame_info(Frame :: frame()) -> {ok, map()} | {error, Reason :: term()}.
frame_info(Frame) ->
    esp32cam:frame_info_nif(Frame).

%%-----------------------------------------------------------------------------
%% @param   Frame camera frame reference
%% @returns `ok' or error.
%% @doc     Explicitly release a leased camera frame back to the driver.
%% @end
%%-----------------------------------------------------------------------------
-spec release_frame(Frame :: frame()) -> ok | {error, Reason :: term()}.
release_frame(Frame) ->
    esp32cam:release_frame_nif(Frame).

%%-----------------------------------------------------------------------------
%% @param   FlashOptions flash control options
%% @returns The image data (e.g., JPEG).
%% @doc     Capture an image with flash control.
%%          Provides advanced flash control with timing options.
%% @end
%%-----------------------------------------------------------------------------
-spec capture_with_flash(FlashOptions :: flash_options()) ->
    {ok, image()} | {error, Reason :: term()}.
capture_with_flash(FlashOptions) ->
    capture_with_flash(FlashOptions, []).

%%-----------------------------------------------------------------------------
%% @param   FlashOptions flash control options
%% @param   CaptureParams capture parameters
%% @returns The image data (e.g., JPEG).
%% @doc     Capture an image with flash control and capture parameters.
%%          Provides advanced flash control with timing options.
%% @end
%%-----------------------------------------------------------------------------
-spec capture_with_flash(FlashOptions :: flash_options(), CaptureParams :: capture_params()) ->
    {ok, image()} | {error, Reason :: term()}.
capture_with_flash(FlashOptions, CaptureParams) ->
    case {flash_delay(FlashOptions), validate_capture_params(CaptureParams)} of
        {{ok, DelayMs}, ok} ->
            capture_with_flash_control(CaptureParams, DelayMs);
        {{error, _} = Error, _} ->
            Error;
        {_, Error} ->
            Error
    end.

%%-----------------------------------------------------------------------------
%% @returns `true' if the currently initialized board has a flash LED, `false' otherwise.
%% @doc     Check if the current board supports flash photography.
%% @end
%%-----------------------------------------------------------------------------
-spec has_flash() -> boolean().
has_flash() ->
    case get_board_info() of
        {ok, custom, CustomFlashPin} ->
            CustomFlashPin =/= undefined;
        {ok, Board, _} ->
            case maps:get(Board, ?FLASH_PINS, undefined) of
                undefined -> false;
                _ -> true
            end;
        undefined ->
            false
    end.

%%-----------------------------------------------------------------------------
%% @param   Board the camera board type
%% @returns `true' if the board has a flash LED, `false' otherwise.
%% @doc     Check if a specific board supports flash photography.
%% @end
%%-----------------------------------------------------------------------------
-spec has_flash(Board :: atom()) -> boolean().
has_flash(Board) ->
    case Board of
        custom ->
            case get_board_info() of
                {ok, custom, CustomFlashPin} -> CustomFlashPin =/= undefined;
                _ -> false
            end;
        _ ->
            case maps:get(Board, ?FLASH_PINS, undefined) of
                undefined -> false;
                _ -> true
            end
    end.

%%-----------------------------------------------------------------------------
%% Query NIF for globally initialized board info
%%-----------------------------------------------------------------------------
get_board_info() ->
    try
        case get_board_info_nif() of
            undefined -> undefined;
            {NifBoard, NifFlashPin} -> {ok, NifBoard, NifFlashPin}
        end
    catch
        throw:nif_error ->
            case get(?BOARD_KEY) of
                undefined ->
                    undefined;
                MockBoard ->
                    MockFlashPin = get(?CUSTOM_FLASH_PIN_KEY),
                    {ok, MockBoard, MockFlashPin}
            end
    end.

get_board_info_nif() ->
    throw(nif_error).

%%-----------------------------------------------------------------------------
%% @returns Total PSRAM size in bytes, or `undefined' / `0' if not available.
%% @doc     Query the total PSRAM size.
%% @end
%%-----------------------------------------------------------------------------
-spec psram_size() -> integer() | undefined.
psram_size() ->
    try
        esp32cam:psram_size_nif()
    catch
        throw:nif_error ->
            case get(esp32cam_mock_psram_size) of
                undefined -> undefined;
                Size -> Size
            end
    end.

psram_size_nif() ->
    throw(nif_error).

%%-----------------------------------------------------------------------------
%% Configuration Validation
%%-----------------------------------------------------------------------------
validate_init_config(Config) when is_list(Config) ->
    Board = proplists:get_value(board, Config, ai_thinker),
    FrameSize = proplists:get_value(frame_size, Config, xga),
    JpegQuality = proplists:get_value(jpeg_quality, Config, 12),
    PixelFormat = proplists:get_value(pixel_format, Config, jpeg),
    XclkFreqHz = proplists:get_value(xclk_freq_hz, Config, 20000000),
    FbCount = proplists:get_value(fb_count, Config, auto),
    FbLocation = proplists:get_value(fb_location, Config, psram),
    GrabMode = proplists:get_value(grab_mode, Config, when_empty),
    SccbI2CPort = proplists:get_value(sccb_i2c_port, Config, 0),
    LedcTimer = proplists:get_value(ledc_timer, Config, 0),
    LedcChannel = proplists:get_value(ledc_channel, Config, 0),
    ConvMode = proplists:get_value(conv_mode, Config, disable),
    WarmUpFrames = proplists:get_value(warm_up_frames, Config, 0),
    AutoWhiteBalance = proplists:get_value(auto_white_balance, Config, true),
    AwbGain = proplists:get_value(awb_gain, Config, true),
    WbMode = proplists:get_value(wb_mode, Config, auto),
    Brightness = proplists:get_value(brightness, Config, 0),
    Contrast = proplists:get_value(contrast, Config, 0),
    Saturation = proplists:get_value(saturation, Config, 0),
    Hmirror = proplists:get_value(hmirror, Config, false),
    Vflip = proplists:get_value(vflip, Config, false),
    case
        first_config_error([
            {lists:member(Board, ?SUPPORTED_BOARDS), {invalid_board, Board}},
            {lists:member(FrameSize, ?SUPPORTED_FRAME_SIZES), {invalid_frame_size, FrameSize}},
            {
                is_integer(JpegQuality) andalso JpegQuality >= 0 andalso JpegQuality =< 63,
                {invalid_jpeg_quality, JpegQuality}
            },
            {
                lists:member(PixelFormat, ?SUPPORTED_PIXEL_FORMATS),
                {invalid_pixel_format, PixelFormat}
            },
            {is_integer(XclkFreqHz) andalso XclkFreqHz > 0, {invalid_xclk_freq_hz, XclkFreqHz}},
            {
                (FbCount =:= auto) orelse (is_integer(FbCount) andalso FbCount > 0),
                {invalid_fb_count, FbCount}
            },
            {lists:member(FbLocation, ?SUPPORTED_FB_LOCATIONS), {invalid_fb_location, FbLocation}},
            {lists:member(GrabMode, ?SUPPORTED_GRAB_MODES), {invalid_grab_mode, GrabMode}},
            {
                is_integer(SccbI2CPort) andalso SccbI2CPort >= 0,
                {invalid_sccb_i2c_port, SccbI2CPort}
            },
            {
                is_integer(LedcTimer) andalso LedcTimer >= 0 andalso LedcTimer =< 3,
                {invalid_ledc_timer, LedcTimer}
            },
            {
                is_integer(LedcChannel) andalso LedcChannel >= 0 andalso LedcChannel =< 7,
                {invalid_ledc_channel, LedcChannel}
            },
            {lists:member(ConvMode, ?SUPPORTED_CONV_MODES), {invalid_conv_mode, ConvMode}},
            {
                is_integer(WarmUpFrames) andalso
                    WarmUpFrames >= 0 andalso
                    WarmUpFrames =< ?MAX_WARM_UP_FRAMES,
                {invalid_warm_up_frames, WarmUpFrames}
            },
            {is_boolean(AutoWhiteBalance), {invalid_auto_white_balance, AutoWhiteBalance}},
            {is_boolean(AwbGain), {invalid_awb_gain, AwbGain}},
            {lists:member(WbMode, [auto, sunny, cloudy, office, home]), {invalid_wb_mode, WbMode}},
            {
                is_integer(Brightness) andalso Brightness >= -2 andalso Brightness =< 2,
                {invalid_brightness, Brightness}
            },
            {
                is_integer(Contrast) andalso Contrast >= -2 andalso Contrast =< 2,
                {invalid_contrast, Contrast}
            },
            {
                is_integer(Saturation) andalso Saturation >= -2 andalso Saturation =< 2,
                {invalid_saturation, Saturation}
            },
            {is_boolean(Hmirror), {invalid_hmirror, Hmirror}},
            {is_boolean(Vflip), {invalid_vflip, Vflip}}
        ])
    of
        ok ->
            case validate_custom_board_config(Board, Config) of
                ok -> {ok, Board};
                Error -> Error
            end;
        Error ->
            Error
    end;
validate_init_config(_) ->
    {error, badarg}.

validate_custom_board_config(custom, Config) ->
    MandatoryInputPins = [
        pin_pclk,
        pin_vsync,
        pin_href,
        pin_d7,
        pin_d6,
        pin_d5,
        pin_d4,
        pin_d3,
        pin_d2,
        pin_d1,
        pin_d0
    ],
    MandatoryOutputPins = [
        pin_xclk,
        pin_sccb_sda,
        pin_sccb_scl
    ],
    OptionalOutputPins = [
        pin_pwdn,
        pin_reset,
        pin_flash
    ],
    first_config_error(
        [
            {
                is_valid_input_pin(proplists:get_value(Pin, Config, undefined), custom),
                {invalid_pin, Pin}
            }
         || Pin <- MandatoryInputPins
        ] ++
            [
                {
                    is_valid_output_pin(proplists:get_value(Pin, Config, undefined), custom),
                    {invalid_pin, Pin}
                }
             || Pin <- MandatoryOutputPins
            ] ++
            [
                {
                    is_optional_output_pin(proplists:get_value(Pin, Config, -1), custom),
                    {invalid_pin, Pin}
                }
             || Pin <- OptionalOutputPins
            ]
    );
validate_custom_board_config(_Board, _Config) ->
    ok.

is_valid_input_pin(Pin, custom) ->
    is_integer(Pin) andalso Pin >= 0 andalso Pin =< 48.

is_valid_output_pin(Pin, custom) ->
    is_integer(Pin) andalso Pin >= 0 andalso Pin =< 48.

is_optional_output_pin(Pin, Board) ->
    Pin =:= -1 orelse is_valid_output_pin(Pin, Board).

first_config_error([{true, _} | Rest]) ->
    first_config_error(Rest);
first_config_error([{false, Reason} | _]) ->
    {error, Reason};
first_config_error([]) ->
    ok.

resolve_fb_count(auto, Config) ->
    case proplists:get_value(fb_location, Config, psram) of
        dram ->
            1;
        psram ->
            case psram_size() of
                undefined ->
                    1;
                0 ->
                    1;
                PsramSize ->
                    FrameSize = proplists:get_value(frame_size, Config, xga),
                    PixelFormat = proplists:get_value(pixel_format, Config, jpeg),
                    EstimatedSize = estimate_frame_size(FrameSize, PixelFormat),
                    MaxBufferMem = PsramSize div 4,
                    if
                        EstimatedSize * 3 =< MaxBufferMem -> 3;
                        EstimatedSize * 2 =< MaxBufferMem -> 2;
                        true -> 1
                    end
            end
    end;
resolve_fb_count(FbCount, _Config) when is_integer(FbCount) ->
    FbCount.

estimate_frame_size(FrameSize, jpeg) ->
    case FrameSize of
        '5mp' -> 500000;
        qxga -> 500000;
        fhd -> 500000;
        uxga -> 300000;
        sxga -> 300000;
        hd -> 300000;
        xga -> 150000;
        svga -> 150000;
        _ -> 75000
    end;
estimate_frame_size(FrameSize, PixelFormat) ->
    {W, H} = resolution_dimensions(FrameSize),
    BPP = bytes_per_pixel(PixelFormat),
    W * H * BPP.

resolution_dimensions('96x96') -> {96, 96};
resolution_dimensions(qqvga) -> {160, 120};
resolution_dimensions('128x128') -> {128, 128};
resolution_dimensions(qcif) -> {176, 144};
resolution_dimensions(hqvga) -> {240, 176};
resolution_dimensions('240x240') -> {240, 240};
resolution_dimensions(qvga) -> {320, 240};
resolution_dimensions('320x320') -> {320, 320};
resolution_dimensions(cif) -> {400, 296};
resolution_dimensions(hvga) -> {480, 320};
resolution_dimensions(vga) -> {640, 480};
resolution_dimensions(svga) -> {800, 600};
resolution_dimensions(xga) -> {1024, 768};
resolution_dimensions(hd) -> {1280, 720};
resolution_dimensions(sxga) -> {1280, 1024};
resolution_dimensions(uxga) -> {1600, 1200};
resolution_dimensions(fhd) -> {1920, 1080};
resolution_dimensions(p_hd) -> {720, 1280};
resolution_dimensions(p_3mp) -> {864, 1536};
resolution_dimensions(qxga) -> {2048, 1536};
resolution_dimensions(qhd) -> {2560, 1440};
resolution_dimensions(wqxga) -> {2560, 1600};
resolution_dimensions(p_fhd) -> {1080, 1920};
resolution_dimensions(qsxga) -> {2048, 1536};
resolution_dimensions('5mp') -> {2592, 1944};
resolution_dimensions(_) -> {640, 480}.

bytes_per_pixel(rgb565) -> 2;
bytes_per_pixel(yuv422) -> 2;
bytes_per_pixel(rgb888) -> 3;
bytes_per_pixel(grayscale) -> 1;
bytes_per_pixel(raw) -> 1;
bytes_per_pixel(raw8) -> 1;
bytes_per_pixel(_) -> 2.
