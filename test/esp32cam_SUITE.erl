-module(esp32cam_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

suite() ->
    [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    %% Start mock mode for the entire suite
    application:set_env(esp32cam, test_mode, true),
    esp32cam_mock:start_mock_mode(),
    [{mock_mode, enabled} | Config].

end_per_suite(_Config) ->
    esp32cam_mock:stop_mock_mode(),
    application:unset_env(esp32cam, test_mode),
    ok.

init_per_group(performance, Config) ->
    %% Set up performance testing environment
    [{test_iterations, 100}, {timeout_ms, 5000} | Config];
init_per_group(integration, Config) ->
    %% Set up integration testing environment
    [{board_configs, supported_boards()} | Config];
init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    ct:pal("Starting test case: ~p", [TestCase]),
    %% Reset mock behavior for each test
    esp32cam_mock:set_mock_behavior(default),
    %% Don't clear process dictionary as it contains mock mode flag
    Config.

end_per_testcase(TestCase, _Config) ->
    ct:pal("Finished test case: ~p", [TestCase]),
    ok.

%%====================================================================
%% Test Groups
%%====================================================================

all() ->
    [
        {group, basic_functionality},
        {group, advanced_features},
        {group, error_handling},
        {group, performance},
        {group, integration}
    ].

groups() ->
    [
        {basic_functionality, [parallel], [
            test_init_default,
            test_init_with_config,
            test_capture_basic,
            test_capture_with_params,
            test_camera_scanner,
            test_sdcard_mounting
        ]},
        {advanced_features, [sequence], [
            test_flash_capture,
            test_board_switching,
            test_parameter_validation,
            test_has_flash
        ]},
        {error_handling, [parallel], [
            test_invalid_board_config,
            test_capture_without_init,
            test_error_recovery
        ]},
        {performance, [sequence], [
            test_capture_performance,
            test_flash_performance,
            test_memory_usage
        ]},
        {integration, [sequence], [
            test_board_integration,
            test_end_to_end_workflow,
            test_concurrent_operations
        ]}
    ].

%%====================================================================
%% Basic Functionality Tests
%%====================================================================

test_init_default(Config) ->
    ct:comment("Testing default initialization"),
    Result = esp32cam_mock:init(),
    ?assertEqual(ok, Result),
    ?assertEqual(ai_thinker, get(esp32cam_current_board)),
    Config.

test_camera_scanner(Config) ->
    ct:comment("Testing camera scanner auto-detection in mock mode"),
    Result = camera_scanner:scan([{frame_size, svga}, {jpeg_quality, 10}]),
    ?assertEqual({ok, ai_thinker}, Result),
    ?assertEqual(ai_thinker, get(esp32cam_current_board)),

    %% Let's also test when all boards fail
    esp32cam_mock:set_mock_behavior(always_error),
    ResultError = camera_scanner:scan(),
    ?assertEqual({error, not_found}, ResultError),
    Config.

test_sdcard_mounting(Config) ->
    ct:comment("Testing camera_scanner SD card helper functions"),

    %% 1. Test get_sdcard_options/1
    ?assertMatch({sdmmc, _}, camera_scanner:get_sdcard_options(ai_thinker)),
    ?assertMatch({sdmmc, _}, camera_scanner:get_sdcard_options(wrover_kit)),
    ?assertMatch({sdmmc, _}, camera_scanner:get_sdcard_options(esp32s3_wroom)),
    ?assertMatch({sdmmc, _}, camera_scanner:get_sdcard_options(esp32s3_goouuu)),
    ?assertMatch({sdspi, _, _}, camera_scanner:get_sdcard_options(esp32s3_xiao)),
    ?assertEqual({error, no_sdcard_support}, camera_scanner:get_sdcard_options(m5cam)),
    ?assertEqual({error, no_sdcard_support}, camera_scanner:get_sdcard_options(m5cam_wide)),
    ?assertEqual({error, no_sdcard_support}, camera_scanner:get_sdcard_options(m5cam_psram)),
    ?assertEqual({error, unknown_board}, camera_scanner:get_sdcard_options(unknown_board)),

    %% 2. Test mount_sdcard/2 and umount_sdcard/1 for SDMMC
    {ok, MountedSDMMC} = camera_scanner:mount_sdcard(ai_thinker, "/sdcard"),
    ?assertEqual(ok, camera_scanner:umount_sdcard(MountedSDMMC)),
    ?assertEqual({error, no_spi_port}, camera_scanner:get_spi_port(MountedSDMMC)),

    %% 3. Test mount_sdcard/2, get_spi_port/1, and umount_sdcard/1 for SDSPI
    {ok, MountedSDSPI} = camera_scanner:mount_sdcard(esp32s3_xiao, "/sdcard"),
    ?assertMatch({ok, SPIPort} when is_port(SPIPort), camera_scanner:get_spi_port(MountedSDSPI)),
    ?assertEqual(ok, camera_scanner:umount_sdcard(MountedSDSPI)),

    %% 4. Test error case (unknown board)
    ?assertEqual({error, unknown_board}, camera_scanner:mount_sdcard(unknown_board, "/sdcard")),
    Config.

test_init_with_config(Config) ->
    ct:comment("Testing initialization with custom configuration"),
    TestConfig = [{board, wrover_kit}, {frame_size, svga}, {jpeg_quality, 10}],
    Result = esp32cam_mock:init(TestConfig),
    ?assertEqual(ok, Result),
    ?assertEqual(wrover_kit, get(esp32cam_current_board)),
    Config.

test_capture_basic(Config) ->
    ct:comment("Testing basic image capture"),
    %% Initialize first
    ok = esp32cam_mock:init(),

    %% Capture image
    Result = esp32cam_mock:capture(),
    ?assertMatch({ok, ImageData} when is_binary(ImageData), Result),

    {ok, ImageData} = Result,
    ?assert(byte_size(ImageData) > 0),
    ct:pal("Captured image size: ~p bytes", [byte_size(ImageData)]),
    Config.

test_capture_with_params(Config) ->
    ct:comment("Testing capture with custom parameters"),
    ok = esp32cam_mock:init(),
    Params = [{flash, off}, {flash_delay_ms, 0}],
    Result = esp32cam_mock:capture(Params),
    ?assertMatch({ok, ImageData} when is_binary(ImageData), Result),
    Config.

%%====================================================================
%% Advanced Features Tests
%%====================================================================

test_flash_capture(Config) ->
    ct:comment("Testing flash capture functionality"),
    ok = esp32cam_mock:init(),

    %% Test basic flash capture
    Result1 = esp32cam_mock:capture_with_flash([{delay_ms, 100}]),
    ?assertMatch({ok, _}, Result1),

    %% Test flash with timing
    StartTime = erlang:system_time(millisecond),
    Result2 = esp32cam_mock:capture_with_flash([{delay_ms, 50}]),
    EndTime = erlang:system_time(millisecond),

    ?assertMatch({ok, _}, Result2),
    Duration = EndTime - StartTime,
    % Allow some tolerance
    ?assert(Duration >= 45),
    ct:pal("Flash capture duration: ~p ms", [Duration]),
    Config.

test_board_switching(Config) ->
    ct:comment("Testing switching between different board configurations"),

    lists:foreach(
        fun(Board) ->
            BoardConfig = [{board, Board}],
            Result = esp32cam_mock:init(BoardConfig),
            ?assertEqual(ok, Result),
            ?assertEqual(Board, get(esp32cam_current_board)),
            ct:pal("Successfully switched to board: ~p", [Board])
        end,
        supported_boards()
    ),
    Config.

test_parameter_validation(Config) ->
    ct:comment("Testing parameter validation"),
    ok = esp32cam_mock:init(),

    %% Test valid parameters
    ValidParams = [{flash, on}, {flash_delay_ms, 1}],
    Result1 = esp32cam_mock:capture(ValidParams),
    ?assertMatch({ok, _}, Result1),

    %% Test edge case parameters
    EdgeParams = [{flash_delay_ms, 0}],
    Result2 = esp32cam_mock:capture(EdgeParams),
    ?assertMatch({ok, _}, Result2),

    InvalidParams = [{jpeg_quality, 1}],
    Result3 = esp32cam_mock:capture(InvalidParams),
    ?assertMatch({error, _}, Result3),
    Config.

test_has_flash(Config) ->
    ct:comment("Testing has_flash functionality"),

    %% Test has_flash/1 on specific boards
    ?assertEqual(true, esp32cam:has_flash(ai_thinker)),
    ?assertEqual(true, esp32cam:has_flash(m5cam_psram)),
    ?assertEqual(false, esp32cam:has_flash(wrover_kit)),
    ?assertEqual(false, esp32cam:has_flash(esp32s3_xiao)),

    %% Test has_flash/0 (relies on current board initialized)
    %% Switch to ai_thinker
    ok = esp32cam_mock:init([{board, ai_thinker}]),
    ?assertEqual(true, esp32cam:has_flash()),

    %% Switch to wrover_kit
    ok = esp32cam_mock:init([{board, wrover_kit}]),
    ?assertEqual(false, esp32cam:has_flash()),

    Config.

%%====================================================================
%% Error Handling Tests
%%====================================================================

test_invalid_board_config(Config) ->
    ct:comment("Testing invalid board configuration handling"),
    InvalidConfig = [{board, non_existent_board}],
    Result = esp32cam_mock:init(InvalidConfig),
    ?assertMatch({error, _}, Result),
    Config.

test_capture_without_init(Config) ->
    ct:comment("Testing capture without initialization"),
    erase(esp32cam_current_board),
    Result = esp32cam_mock:capture(),
    ?assertEqual({error, bad_state}, Result),
    Config.

test_error_recovery(Config) ->
    ct:comment("Testing error recovery mechanisms"),

    %% Force error state
    esp32cam_mock:set_mock_behavior(always_error),
    ErrorResult = esp32cam_mock:capture(),
    ?assertMatch({error, _}, ErrorResult),

    %% Recover to normal state
    esp32cam_mock:set_mock_behavior(default),
    ok = esp32cam_mock:init(),
    RecoveryResult = esp32cam_mock:capture(),
    ?assertMatch({ok, _}, RecoveryResult),
    Config.

%%====================================================================
%% Performance Tests
%%====================================================================

test_capture_performance(Config) ->
    ct:comment("Testing capture performance"),
    Iterations = proplists:get_value(test_iterations, Config, 10),

    %% Initialize once
    ok = esp32cam_mock:init(),

    %% Measure capture performance
    StartTime = erlang:system_time(microsecond),

    Results = [esp32cam_mock:capture() || _ <- lists:seq(1, Iterations)],

    EndTime = erlang:system_time(microsecond),
    Duration = EndTime - StartTime,

    %% Verify all captures succeeded
    SuccessCount = length([Result || {ok, _} = Result <- Results]),
    ?assert(SuccessCount > 0),

    AvgTime = Duration / Iterations,
    ct:pal(
        "Capture performance: ~p iterations in ~p μs (avg: ~.2f μs/capture)",
        [Iterations, Duration, AvgTime]
    ),

    %% Performance assertion (should be fast in mock mode)

    % Less than 10ms per capture in mock mode
    ?assert(AvgTime < 10000),
    Config.

test_flash_performance(Config) ->
    ct:comment("Testing flash capture performance"),
    ok = esp32cam_mock:init(),
    % Fewer iterations for flash tests
    Iterations = 5,

    StartTime = erlang:system_time(microsecond),

    Results = [
        esp32cam_mock:capture_with_flash([{delay_ms, 10}])
     || _ <- lists:seq(1, Iterations)
    ],

    EndTime = erlang:system_time(microsecond),
    Duration = EndTime - StartTime,

    SuccessCount = length([Result || {ok, _} = Result <- Results]),
    ?assert(SuccessCount > 0),

    AvgTime = Duration / Iterations,
    ct:pal(
        "Flash capture performance: ~p iterations in ~p μs (avg: ~.2f μs/capture)",
        [Iterations, Duration, AvgTime]
    ),
    Config.

test_memory_usage(Config) ->
    ct:comment("Testing memory usage during operations"),

    %% Get initial memory usage
    {_, InitialMemory} = erlang:process_info(self(), memory),

    %% Perform multiple operations
    ok = esp32cam_mock:init(),

    lists:foreach(
        fun(_) ->
            {ok, _} = esp32cam_mock:capture()
        end,
        lists:seq(1, 10)
    ),

    %% Force garbage collection
    erlang:garbage_collect(),

    %% Check final memory usage
    {_, FinalMemory} = erlang:process_info(self(), memory),
    MemoryIncrease = FinalMemory - InitialMemory,

    ct:pal(
        "Memory usage: initial=~p, final=~p, increase=~p bytes",
        [InitialMemory, FinalMemory, MemoryIncrease]
    ),

    %% Memory increase should be reasonable

    % Less than 1MB increase
    ?assert(MemoryIncrease < 1024 * 1024),
    Config.

%%====================================================================
%% Integration Tests
%%====================================================================

test_board_integration(Config) ->
    ct:comment("Testing integration across different board types"),
    BoardConfigs = proplists:get_value(board_configs, Config, [ai_thinker]),

    lists:foreach(
        fun(Board) ->
            ct:pal("Testing board: ~p", [Board]),

            %% Initialize with board
            BoardConfig = [{board, Board}],
            ?assertEqual(ok, esp32cam_mock:init(BoardConfig)),

            %% Test basic capture
            ?assertMatch({ok, _}, esp32cam_mock:capture()),

            %% Test capture with parameters
            Params = [{flash, off}],
            ?assertMatch({ok, _}, esp32cam_mock:capture(Params))
        end,
        BoardConfigs
    ),
    Config.

test_end_to_end_workflow(Config) ->
    ct:comment("Testing complete end-to-end workflow"),

    %% Step 1: Initialize with specific configuration
    InitConfig = [{board, ai_thinker}, {frame_size, vga}, {jpeg_quality, 8}],
    ?assertEqual(ok, esp32cam_mock:init(InitConfig)),

    %% Step 2: Capture multiple images with different settings
    CaptureConfigs = [
        [],
        [{flash, off}],
        [{flash, on}, {flash_delay_ms, 25}]
    ],

    Images = lists:map(
        fun(Params) ->
            {ok, ImageData} = esp32cam_mock:capture(Params),
            ImageData
        end,
        CaptureConfigs
    ),

    %% Step 3: Verify all images were captured
    ?assertEqual(3, length(Images)),
    lists:foreach(
        fun(Image) ->
            ?assert(is_binary(Image)),
            ?assert(byte_size(Image) > 0)
        end,
        Images
    ),

    %% Step 4: Test flash capture
    ?assertMatch({ok, _}, esp32cam_mock:capture_with_flash([{delay_ms, 50}])),

    ct:pal("End-to-end workflow completed successfully"),
    Config.

test_concurrent_operations(Config) ->
    ct:comment("Testing concurrent operations"),

    %% Initialize once
    ok = esp32cam_mock:init(),

    %% Spawn multiple processes to perform captures concurrently
    NumProcesses = 5,
    Parent = self(),

    Pids = [
        spawn_link(fun() ->
            ok = esp32cam_mock:init(),
            Result = esp32cam_mock:capture(),
            Parent ! {capture_result, self(), Result}
        end)
     || _ <- lists:seq(1, NumProcesses)
    ],

    %% Collect results
    Results = [
        receive
            {capture_result, Pid, Result} -> Result
        after 5000 ->
            error(timeout)
        end
     || Pid <- Pids
    ],

    %% Verify results
    SuccessCount = length([Result || {ok, _} = Result <- Results]),
    ?assert(SuccessCount > 0),

    ct:pal("Concurrent operations: ~p/~p successful", [SuccessCount, NumProcesses]),
    Config.

%%====================================================================
%% Helper Functions
%%====================================================================

%% Safe call wrapper to handle NIF errors in test environment
safe_call(Fun) ->
    try
        Fun()
    catch
        throw:nif_error ->
            %% Enable mock mode and retry
            esp32cam_mock:start_mock_mode(),
            Fun();
        _:Error ->
            {error, Error}
    end.

supported_boards() ->
    [
        ai_thinker,
        wrover_kit,
        esp32s3_wroom,
        esp32s3_goouuu,
        esp32s3_xiao,
        m5cam,
        m5cam_wide,
        m5cam_psram
    ].
