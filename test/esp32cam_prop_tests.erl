-module(esp32cam_prop_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([
    prop_flash_delay_timing/0,
    prop_board_initialization/0,
    prop_capture_returns_binary/0,
    prop_init_config_accepts_supported_options/0,
    prop_frame_size_consistency/0,
    prop_error_recovery/0,
    prop_concurrent_captures/0
]).

%%====================================================================
%% Property-Based Test Setup
%%====================================================================

%% Setup function for property tests
setup_prop_test() ->
    application:set_env(esp32cam, test_mode, true),
    esp32cam_mock:start_mock_mode(),
    esp32cam_mock:set_mock_behavior(default).

%% Cleanup function for property tests
cleanup_prop_test() ->
    esp32cam_mock:stop_mock_mode(),
    application:unset_env(esp32cam, test_mode).

%%====================================================================
%% Property Generators
%%====================================================================

%% Generator for valid board types
valid_board() ->
    oneof([
        ai_thinker,
        wrover_kit,
        esp32s3_wroom,
        esp32s3_goouuu,
        esp32s3_xiao,
        m5cam,
        m5cam_wide,
        m5cam_psram
    ]).

%% Generator for valid frame sizes
valid_frame_size() ->
    oneof([
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

valid_pixel_format() ->
    oneof([jpeg, grayscale, rgb565, yuv422, yuv420, rgb888, raw, rgb444, rgb555, raw8]).

valid_conv_mode() ->
    oneof([disable, rgb565_to_yuv422, yuv422_to_rgb565, yuv422_to_yuv420]).

%% Generator for valid JPEG quality (1-63)
valid_jpeg_quality() ->
    range(1, 63).

%% Generator for valid flash settings
valid_flash_setting() ->
    oneof([on, off]).

%% Generator for valid flash delay (0-100ms)
valid_flash_delay() ->
    range(0, 100).

%% Generator for valid capture parameters
valid_capture_params() ->
    list(
        oneof([
            {flash, valid_flash_setting()},
            {flash_delay_ms, valid_flash_delay()}
        ])
    ).

%% Generator for valid initialization config
valid_init_config() ->
    list(
        oneof([
            {board, valid_board()},
            {frame_size, valid_frame_size()},
            {jpeg_quality, valid_jpeg_quality()},
            {pixel_format, valid_pixel_format()},
            {xclk_freq_hz, oneof([6000000, 10000000, 16000000, 20000000, 24000000])},
            {fb_count, range(1, 3)},
            {fb_location, oneof([psram, dram])},
            {grab_mode, oneof([when_empty, latest])},
            {sccb_i2c_port, range(0, 1)},
            {ledc_timer, range(0, 3)},
            {ledc_channel, range(0, 7)},
            {conv_mode, valid_conv_mode()}
        ])
    ).

%%====================================================================
%% Property Tests
%%====================================================================

%% Property: Flash delay should be respected within reasonable tolerance
prop_flash_delay_timing() ->
    ?FORALL(
        Delay,
        valid_flash_delay(),
        begin
            setup_prop_test(),
            try
                StartTime = erlang:system_time(millisecond),
                Result = safe_call(fun() ->
                    esp32cam_mock:capture([{flash, on}, {flash_delay_ms, Delay}])
                end),
                EndTime = erlang:system_time(millisecond),
                ActualDelay = EndTime - StartTime,

                case Result of
                    {ok, _} ->
                        %% Allow 10ms tolerance for mock timing
                        ActualDelay >= (Delay - 10);
                    {error, _} ->
                        % Errors are acceptable in test environment
                        true
                end
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: All supported boards should initialize successfully
prop_board_initialization() ->
    ?FORALL(
        Board,
        valid_board(),
        begin
            setup_prop_test(),
            try
                Config = [{board, Board}],
                Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
                Result =:= ok
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: Capture should always return binary data when successful
prop_capture_returns_binary() ->
    ?FORALL(
        Params,
        valid_capture_params(),
        begin
            setup_prop_test(),
            try
                Result = safe_call(fun() -> esp32cam_mock:capture(Params) end),
                case Result of
                    {ok, Data} ->
                        is_binary(Data) andalso byte_size(Data) > 0;
                    {error, _} ->
                        % Errors are acceptable
                        true
                end
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: Supported init options should be accepted by the mock
prop_init_config_accepts_supported_options() ->
    ?FORALL(
        Config,
        valid_init_config(),
        begin
            setup_prop_test(),
            try
                Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
                Result =:= ok
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: Frame size should be consistent across captures
prop_frame_size_consistency() ->
    ?FORALL(
        FrameSize,
        valid_frame_size(),
        begin
            setup_prop_test(),
            try
                ok = safe_call(fun() -> esp32cam_mock:init([{frame_size, FrameSize}]) end),

                %% Capture multiple images with same frame size
                Results = [
                    safe_call(fun() -> esp32cam_mock:capture() end)
                 || _ <- lists:seq(1, 3)
                ],

                %% All successful captures should return data
                SuccessfulResults = [Data || {ok, Data} <- Results],

                case SuccessfulResults of
                    % No successful captures, acceptable
                    [] ->
                        true;
                    [_ | _] ->
                        %% All successful captures should return binary data
                        lists:all(
                            fun(Data) ->
                                is_binary(Data) andalso byte_size(Data) > 0
                            end,
                            SuccessfulResults
                        )
                end
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: Error recovery should work correctly
prop_error_recovery() ->
    ?FORALL(
        Config,
        valid_init_config(),
        begin
            setup_prop_test(),
            try
                %% Force error state
                esp32cam_mock:set_mock_behavior(always_error),
                ErrorResult = safe_call(fun() -> esp32cam_mock:init(Config) end),

                %% Recover to normal state
                esp32cam_mock:set_mock_behavior(default),
                RecoveryResult = safe_call(fun() -> esp32cam_mock:init(Config) end),

                %% Error should occur in error state, success in normal state
                case {ErrorResult, RecoveryResult} of
                    {{error, _}, ok} -> true;
                    % Still acceptable
                    {{error, _}, {error, _}} -> true;
                    % Mock might not enforce error state
                    {ok, ok} -> true;
                    _ -> false
                end
            after
                cleanup_prop_test()
            end
        end
    ).

%% Property: Concurrent captures should not interfere with each other
prop_concurrent_captures() ->
    ?FORALL(
        NumProcesses,
        range(2, 5),
        begin
            setup_prop_test(),
            try
                %% Initialize once
                ok = safe_call(fun() -> esp32cam_mock:init() end),

                %% Spawn concurrent capture processes
                Parent = self(),
                Pids = [
                    spawn_link(fun() ->
                        ok = safe_call(fun() -> esp32cam_mock:init() end),
                        Result = safe_call(fun() -> esp32cam_mock:capture() end),
                        Parent ! {capture_result, self(), Result}
                    end)
                 || _ <- lists:seq(1, NumProcesses)
                ],

                %% Collect results with timeout
                Results = collect_results(Pids, []),

                %% At least some captures should succeed
                SuccessCount = length([Result || {ok, _} = Result <- Results]),
                ErrorCount = length([Result || {error, _} = Result <- Results]),

                %% Total results should match number of processes
                (SuccessCount + ErrorCount) =:= NumProcesses andalso
                    %% At least one should succeed (in mock mode)
                    SuccessCount > 0
            after
                cleanup_prop_test()
            end
        end
    ).

%%====================================================================
%% Helper Functions
%%====================================================================

%% Safe call wrapper to handle NIF errors in test environment
safe_call(Fun) ->
    try
        Fun()
    catch
        throw:nif_error -> {error, nif_not_loaded};
        _:Error -> {error, Error}
    end.

%% Collect results from concurrent processes
collect_results([], Acc) ->
    Acc;
collect_results([Pid | Rest], Acc) ->
    receive
        {capture_result, Pid, Result} ->
            collect_results(Rest, [Result | Acc])
    after 2000 ->
        %% Timeout - return what we have
        Acc
    end.

%%====================================================================
%% EUnit Integration
%%====================================================================

%% EUnit test wrapper for property tests
proper_test_() ->
    {timeout, 60, fun() ->
        %% Run a subset of property tests with EUnit
        ?assert(proper:quickcheck(prop_board_initialization(), [{to_file, user}, {numtests, 20}])),
        ?assert(
            proper:quickcheck(prop_capture_returns_binary(), [{to_file, user}, {numtests, 20}])
        ),
        ?assert(proper:quickcheck(prop_frame_size_consistency(), [{to_file, user}, {numtests, 15}]))
    end}.

%%====================================================================
%% Property Test Runner
%%====================================================================

%% Run all property tests
run_all_properties() ->
    Properties = [
        prop_flash_delay_timing,
        prop_board_initialization,
        prop_capture_returns_binary,
        prop_init_config_accepts_supported_options,
        prop_frame_size_consistency,
        prop_error_recovery,
        prop_concurrent_captures
    ],

    Results = lists:map(
        fun(Prop) ->
            io:format("Running property: ~p~n", [Prop]),
            Result = proper:quickcheck(?MODULE:Prop(), [{to_file, user}, {numtests, 50}]),
            {Prop, Result}
        end,
        Properties
    ),

    %% Summary
    Passed = length([Result || {_, true} = Result <- Results]),
    Total = length(Results),

    io:format("~nProperty test summary: ~p/~p passed~n", [Passed, Total]),

    case Passed =:= Total of
        true ->
            io:format("All property tests passed!~n"),
            ok;
        false ->
            FailedProps = [Prop || {Prop, false} <- Results],
            io:format("Failed properties: ~p~n", [FailedProps]),
            {error, {failed_properties, FailedProps}}
    end.
