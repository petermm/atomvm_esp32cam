-module(esp32cam_mock).

%% Mock implementation for testing ESP32 camera without hardware
-export([
    init/0,
    init/1,
    set_control/2,
    capture/0,
    capture/1,
    capture_with_flash/1,
    capture_with_flash/2,
    start_mock_mode/0,
    stop_mock_mode/0,
    set_mock_behavior/1
]).

%% Mock behavior configuration
-define(MOCK_KEY, esp32cam_mock_mode).
-define(MOCK_BEHAVIOR_KEY, esp32cam_mock_behavior).

%% Default mock image data (small JPEG header)
-define(MOCK_IMAGE_DATA,
    <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 1, 0, 72, 0, 72, 0, 0, 255, 219, 0, 67, 0,
        8, 6, 6, 7, 6, 5, 8, 7, 7, 7, 9, 9, 8, 10, 12, 20, 13, 12, 11, 11, 12, 25, 18, 19, 15, 20,
        29, 26, 31, 30, 29, 26, 28, 28, 32, 36, 46, 39, 32, 34, 44, 35, 28, 28, 40, 55, 41, 44, 48,
        49, 52, 52, 52, 31, 39, 57, 61, 56, 50, 60, 46, 51, 52, 50, 255, 192, 0, 17, 8, 0, 1, 0, 1,
        1, 1, 17, 0, 2, 17, 1, 3, 17, 1, 255, 196, 0, 20, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 8, 255, 196, 0, 20, 16, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255,
        218, 0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0, 146, 255, 217>>
).

%%-----------------------------------------------------------------------------
%% Mock Control Functions
%%-----------------------------------------------------------------------------

%% Start mock mode
start_mock_mode() ->
    put(?MOCK_KEY, true),
    put(?MOCK_BEHAVIOR_KEY, default),
    %% Mock mode enabled
    ok.

%% Stop mock mode
stop_mock_mode() ->
    erase(?MOCK_KEY),
    erase(?MOCK_BEHAVIOR_KEY),
    %% Mock mode disabled
    ok.

%% Set mock behavior
%% Behaviors: default, always_error, slow_capture, flash_sensitive
set_mock_behavior(Behavior) when is_atom(Behavior) ->
    put(?MOCK_BEHAVIOR_KEY, Behavior),
    %% Mock behavior set to: Behavior
    ok.

%%-----------------------------------------------------------------------------
%% Mock Camera Functions
%%-----------------------------------------------------------------------------

%% Mock initialization
init() ->
    case is_mock_mode() of
        true ->
            mock_init([{board, ai_thinker}, {frame_size, xga}, {jpeg_quality, 12}]);
        false ->
            try
                case esp32cam:init() of
                    {error, gpio_init_failed} ->
                        mock_init([{board, ai_thinker}, {frame_size, xga}, {jpeg_quality, 12}]);
                    Result ->
                        Result
                end
            catch
                throw:nif_error ->
                    mock_init([{board, ai_thinker}, {frame_size, xga}, {jpeg_quality, 12}]);
                _:_ ->
                    mock_init([{board, ai_thinker}, {frame_size, xga}, {jpeg_quality, 12}])
            end
    end.

init(Config) ->
    case is_mock_mode() of
        true ->
            mock_init(Config);
        false ->
            try
                case esp32cam:init(Config) of
                    {error, gpio_init_failed} -> mock_init(Config);
                    Result -> Result
                end
            catch
                throw:nif_error -> mock_init(Config);
                _:_ -> mock_init(Config)
            end
    end.

set_control(Control, Value) ->
    case is_mock_mode() of
        true ->
            mock_set_control(Control, Value);
        false ->
            try
                esp32cam:set_control(Control, Value)
            catch
                throw:nif_error -> mock_set_control(Control, Value);
                _:_ -> mock_set_control(Control, Value)
            end
    end.

%% Mock capture
capture() ->
    case is_mock_mode() of
        true ->
            mock_capture([]);
        false ->
            try
                esp32cam:capture()
            catch
                throw:nif_error -> mock_capture([]);
                _:_ -> mock_capture([])
            end
    end.

capture(Params) ->
    case is_mock_mode() of
        true ->
            mock_capture(Params);
        false ->
            try
                case esp32cam:capture(Params) of
                    {error, {throw, nif_error}} -> mock_capture(Params);
                    {error, {_, nif_error}} -> mock_capture(Params);
                    {error, gpio_init_failed} -> mock_capture(Params);
                    Result -> Result
                end
            catch
                throw:nif_error -> mock_capture(Params);
                _:_ -> mock_capture(Params)
            end
    end.

%% Mock flash capture
capture_with_flash(FlashOptions) ->
    case is_mock_mode() of
        true ->
            mock_capture_with_flash(FlashOptions, []);
        false ->
            try
                case esp32cam:capture_with_flash(FlashOptions) of
                    {error, {throw, nif_error}} -> mock_capture_with_flash(FlashOptions, []);
                    {error, {_, nif_error}} -> mock_capture_with_flash(FlashOptions, []);
                    {error, gpio_init_failed} -> mock_capture_with_flash(FlashOptions, []);
                    Result -> Result
                end
            catch
                throw:nif_error -> mock_capture_with_flash(FlashOptions, []);
                _:_ -> mock_capture_with_flash(FlashOptions, [])
            end
    end.

capture_with_flash(FlashOptions, CaptureParams) ->
    case is_mock_mode() of
        true ->
            mock_capture_with_flash(FlashOptions, CaptureParams);
        false ->
            try
                case esp32cam:capture_with_flash(FlashOptions, CaptureParams) of
                    {error, {throw, nif_error}} ->
                        mock_capture_with_flash(FlashOptions, CaptureParams);
                    {error, {_, nif_error}} ->
                        mock_capture_with_flash(FlashOptions, CaptureParams);
                    {error, gpio_init_failed} ->
                        mock_capture_with_flash(FlashOptions, CaptureParams);
                    Result ->
                        Result
                end
            catch
                throw:nif_error -> mock_capture_with_flash(FlashOptions, CaptureParams);
                _:_ -> mock_capture_with_flash(FlashOptions, CaptureParams)
            end
    end.

%%-----------------------------------------------------------------------------
%% Mock Implementation
%%-----------------------------------------------------------------------------

%% Check if mock mode is enabled
is_mock_mode() ->
    get(?MOCK_KEY) =:= true.

%% Mock initialization implementation
mock_init(Config) ->
    Behavior = get(?MOCK_BEHAVIOR_KEY),
    erase(esp32cam_current_board),
    erase(esp32cam_custom_flash_pin),
    clear_init_controls(),

    case Behavior of
        always_error ->
            {error, mock_init_failed};
        _ ->
            case esp32cam:validate_init_config(Config) of
                {ok, Board} ->
                    put(esp32cam_current_board, Board),
                    store_custom_flash_pin(Config, Board),
                    store_init_controls(Config),

                    % Simulate GPIO initialization
                    %% Mock initialization with board
                    ok;
                Error ->
                    Error
            end
    end.

clear_init_controls() ->
    lists:foreach(
        fun(Control) -> erase({esp32cam_control, Control}) end,
        supported_controls()
    ).

store_init_controls(Config) ->
    lists:foreach(
        fun(Control) ->
            case proplists:get_value(Control, Config) of
                undefined -> ok;
                Val -> put({esp32cam_control, Control}, Val)
            end
        end,
        supported_controls()
    ).

supported_controls() ->
    [wb_mode, auto_white_balance, awb_gain, brightness, contrast, saturation, hmirror, vflip].

mock_set_control(Control, Value) ->
    case validate_control(Control, Value) of
        ok ->
            case get(esp32cam_current_board) of
                undefined ->
                    {error, bad_state};
                _ ->
                    case get(?MOCK_BEHAVIOR_KEY) of
                        always_error ->
                            {error, mock_control_failed};
                        _ ->
                            put({esp32cam_control, Control}, Value),
                            ok
                    end
            end;
        Error ->
            Error
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

%% Mock capture implementation
mock_capture(Params) ->
    case ensure_initialized() of
        ok -> mock_capture_initialized(Params);
        Error -> Error
    end.

mock_capture_initialized(Params) ->
    Behavior = get(?MOCK_BEHAVIOR_KEY),

    case validate_capture_params(Params) of
        ok ->
            % Simulate flash control
            FlashUsed =
                case lists:keyfind(flash, 1, Params) of
                    {flash, on} -> true;
                    _ -> false
                end,

            FlashDelay = proplists:get_value(flash_delay_ms, Params, 0),

            case Behavior of
                always_error ->
                    {error, mock_capture_failed};
                slow_capture ->
                    timer:sleep(100 + FlashDelay),
                    generate_mock_image(FlashUsed);
                flash_sensitive ->
                    % Different image sizes based on flash
                    timer:sleep(FlashDelay),
                    case FlashUsed of
                        true -> {ok, <<"FLASH_IMAGE_DATA", ?MOCK_IMAGE_DATA/binary>>};
                        false -> {ok, ?MOCK_IMAGE_DATA}
                    end;
                _ ->
                    % Default behavior
                    if
                        FlashDelay > 0 -> timer:sleep(FlashDelay);
                        true -> ok
                    end,
                    generate_mock_image(FlashUsed)
            end;
        Error ->
            Error
    end.

%% Mock flash capture implementation
mock_capture_with_flash(FlashOptions, CaptureParams) ->
    case ensure_initialized() of
        ok -> mock_capture_with_flash_initialized(FlashOptions, CaptureParams);
        Error -> Error
    end.

mock_capture_with_flash_initialized(FlashOptions, CaptureParams) ->
    Behavior = get(?MOCK_BEHAVIOR_KEY),

    case {flash_delay(FlashOptions), validate_capture_params(CaptureParams)} of
        {{ok, DelayMs}, ok} ->
            case Behavior of
                always_error ->
                    {error, mock_flash_capture_failed};
                _ ->
                    % Simulate flash delay
                    if
                        DelayMs > 0 -> timer:sleep(DelayMs);
                        true -> ok
                    end,

                    % Generate image with flash effect
                    {ok,
                        <<"ADVANCED_FLASH_", (integer_to_binary(DelayMs))/binary, "_",
                            ?MOCK_IMAGE_DATA/binary>>}
            end;
        {{error, _} = Error, _} ->
            Error;
        {_, Error} ->
            Error
    end.

ensure_initialized() ->
    case get(esp32cam_current_board) of
        undefined -> {error, bad_state};
        _ -> ok
    end.

store_custom_flash_pin(Config, custom) ->
    case proplists:get_value(pin_flash, Config, -1) of
        FlashPin when is_integer(FlashPin), FlashPin >= 0 ->
            put(esp32cam_custom_flash_pin, FlashPin);
        _ ->
            erase(esp32cam_custom_flash_pin)
    end;
store_custom_flash_pin(_Config, _Board) ->
    erase(esp32cam_custom_flash_pin).

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
        ok -> {ok, proplists:get_value(delay_ms, FlashOptions, 0)};
        Error -> Error
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

%% Generate mock image data
generate_mock_image(FlashUsed) ->
    _BaseSize = byte_size(?MOCK_IMAGE_DATA),

    % Simulate different image sizes
    case FlashUsed of
        true ->
            % Flash images might be larger due to better lighting
            ExtraData = crypto:strong_rand_bytes(100),
            {ok, <<?MOCK_IMAGE_DATA/binary, ExtraData/binary>>};
        false ->
            {ok, ?MOCK_IMAGE_DATA}
    end.

%%-----------------------------------------------------------------------------
%% Mock Test Utilities
%%-----------------------------------------------------------------------------
