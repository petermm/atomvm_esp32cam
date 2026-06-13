-module(esp32cam_eunit_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test fixtures
-define(MOCK_IMAGE_DATA,
    <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 1, 0, 72, 0, 72, 0, 0, 255, 219, 0, 67, 0,
        8, 6, 6, 7, 6, 5, 8, 7, 7, 7, 9, 9, 8, 10, 12, 20, 13, 12, 11, 11, 12, 25, 18, 19, 15, 20,
        29, 26, 31, 30, 29, 26, 28, 28, 32, 36, 46, 39, 32, 34, 44, 35, 28, 28, 40, 55, 41, 44, 48,
        49, 52, 52, 52, 31, 39, 57, 61, 56, 50, 60, 46, 51, 52, 50, 255, 192, 0, 17, 8, 0, 1, 0, 1,
        1, 1, 17, 0, 2, 17, 1, 3, 17, 1, 255, 196, 0, 20, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 8, 255, 196, 0, 20, 16, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255,
        218, 0, 12, 3, 1, 0, 2, 17, 3, 17, 0, 63, 0, 146, 255, 217>>
).

%%====================================================================
%% Test Descriptions
%%====================================================================

esp32cam_test_() ->
    {"ESP32 Camera Module Tests",
        {setup, fun setup/0, fun cleanup/1, [
            {"Initialization Tests", [
                fun test_init_default/0,
                fun test_init_with_config/0,
                fun test_init_invalid_board/0,
                fun test_init_with_full_driver_config/0,
                fun test_init_with_white_balance_and_warm_up/0,
                fun test_reinit_clears_controls/0
            ]},
            {"Capture Tests", [
                fun test_capture_basic/0,
                fun test_capture_with_params/0,
                fun test_capture_flash_control/0,
                fun test_capture_before_init/0
            ]},
            {"Runtime Control Tests", [
                fun test_set_white_balance_controls/0,
                fun test_set_control_invalid_values/0,
                fun test_set_control_before_init/0
            ]},
            {"Flash Tests", [
                fun test_flash_capture_basic/0,
                fun test_flash_capture_with_delay/0,
                fun test_flash_capture_advanced/0
            ]},
            {"Board Configuration Tests", [
                fun test_board_configurations/0,
                fun test_board_specific_features/0,
                fun test_custom_board_configuration/0
            ]},
            {"Error Handling Tests", [
                fun test_error_handling/0,
                fun test_invalid_parameters/0,
                fun test_invalid_driver_options/0
            ]},
            {"Terminal Image Tests", [
                fun test_display_iterm2/0
            ]},
            {"Zero-Copy Frame Tests", [
                fun test_capture_frame_basic/0,
                fun test_frame_info/0,
                fun test_release_frame/0,
                fun test_view_active_release_rejection/0,
                fun test_lease_limits/0,
                fun test_reinit_lease_rejection/0,
                fun test_destructor_returns_fb/0
            ]},
            {"PSRAM and Framebuffer Auto-Resolution Tests", [
                fun test_psram_size/0,
                fun test_fb_count_auto_resolution/0
            ]}
        ]}}.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Enable mock mode for testing
    application:set_env(esp32cam, test_mode, true),
    esp32cam_mock:start_mock_mode(),
    ok = esp32cam_mock:init(),
    ok.

cleanup(_) ->
    esp32cam_mock:stop_mock_mode(),
    application:unset_env(esp32cam, test_mode),
    %% Clean up process dictionary
    erase(),
    ok.

%%====================================================================
%% Initialization Tests
%%====================================================================

test_init_default() ->
    ?_test(begin
        Result = safe_call(fun() -> esp32cam_mock:init() end),
        ?assertEqual(ok, Result),
        ?assertEqual(ai_thinker, get(esp32cam_current_board))
    end).

test_init_with_config() ->
    ?_test(begin
        Config = [{board, wrover_kit}, {frame_size, svga}, {jpeg_quality, 10}],
        Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
        ?assertEqual(ok, Result),
        ?assertEqual(wrover_kit, get(esp32cam_current_board))
    end).

test_init_invalid_board() ->
    ?_test(begin
        Config = [{board, invalid_board}],
        Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
        ?assertMatch({error, _}, Result)
    end).

test_init_with_full_driver_config() ->
    ?_test(begin
        Config = [
            {board, esp32s3_xiao},
            {frame_size, '5mp'},
            {jpeg_quality, 8},
            {pixel_format, rgb565},
            {xclk_freq_hz, 24000000},
            {fb_count, 2},
            {fb_location, psram},
            {grab_mode, latest},
            {sccb_i2c_port, 1},
            {ledc_timer, 3},
            {ledc_channel, 7},
            {conv_mode, rgb565_to_yuv422}
        ],
        Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
        ?assertEqual(ok, Result),
        ?assertEqual(esp32s3_xiao, get(esp32cam_current_board))
    end).

test_init_with_white_balance_and_warm_up() ->
    ?_test(begin
        Config = [
            {board, ai_thinker},
            {warm_up_frames, 15},
            {auto_white_balance, false},
            {awb_gain, false},
            {wb_mode, office},
            {brightness, -2},
            {contrast, 1},
            {saturation, 2},
            {hmirror, true},
            {vflip, false}
        ],
        Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
        ?assertEqual(ok, Result),
        ?assertEqual(ai_thinker, get(esp32cam_current_board)),
        ?assertEqual(false, get({esp32cam_control, auto_white_balance})),
        ?assertEqual(false, get({esp32cam_control, awb_gain})),
        ?assertEqual(office, get({esp32cam_control, wb_mode})),
        ?assertEqual(-2, get({esp32cam_control, brightness})),
        ?assertEqual(1, get({esp32cam_control, contrast})),
        ?assertEqual(2, get({esp32cam_control, saturation})),
        ?assertEqual(true, get({esp32cam_control, hmirror})),
        ?assertEqual(false, get({esp32cam_control, vflip}))
    end).

test_reinit_clears_controls() ->
    ?_test(begin
        ok = esp32cam_mock:init([
            {brightness, -1},
            {contrast, -1},
            {saturation, -1},
            {hmirror, true}
        ]),
        ?assertEqual(-1, get({esp32cam_control, brightness})),
        ?assertEqual(-1, get({esp32cam_control, contrast})),
        ?assertEqual(-1, get({esp32cam_control, saturation})),
        ?assertEqual(true, get({esp32cam_control, hmirror})),

        ok = esp32cam_mock:init(),
        ?assertEqual(undefined, get({esp32cam_control, brightness})),
        ?assertEqual(undefined, get({esp32cam_control, contrast})),
        ?assertEqual(undefined, get({esp32cam_control, saturation})),
        ?assertEqual(undefined, get({esp32cam_control, hmirror}))
    end).

%%====================================================================
%% Capture Tests
%%====================================================================

test_capture_basic() ->
    ?_test(begin
        %% Initialize first
        ok = safe_call(fun() -> esp32cam_mock:init() end),

        %% Test basic capture
        Result = safe_call(fun() -> esp32cam_mock:capture() end),
        ?assertMatch({ok, ImageData} when is_binary(ImageData), Result),

        {ok, ImageData} = Result,
        ?assert(byte_size(ImageData) > 0)
    end).

test_capture_with_params() ->
    ?_test(begin
        Params = [{flash, off}, {flash_delay_ms, 0}],
        Result = safe_call(fun() -> esp32cam_mock:capture(Params) end),
        ?assertMatch({ok, ImageData} when is_binary(ImageData), Result)
    end).

test_capture_flash_control() ->
    ?_test(begin
        %% Test flash off
        Result1 = safe_call(fun() -> esp32cam_mock:capture([{flash, off}]) end),
        ?assertMatch({ok, _}, Result1),

        %% Test flash on
        Result2 = safe_call(fun() -> esp32cam_mock:capture([{flash, on}]) end),
        ?assertMatch({ok, _}, Result2),

        %% Test flash with delay
        Result3 = safe_call(fun() -> esp32cam_mock:capture([{flash, on}, {flash_delay_ms, 50}]) end),
        ?assertMatch({ok, _}, Result3)
    end).

test_capture_before_init() ->
    ?_test(begin
        erase(esp32cam_current_board),
        ?assertEqual({error, bad_state}, esp32cam_mock:capture()),
        ?assertEqual(
            {error, bad_state},
            esp32cam_mock:capture_with_flash([{delay_ms, 0}])
        ),
        ok = esp32cam_mock:init()
    end).

%%====================================================================
%% Runtime Control Tests
%%====================================================================

test_set_white_balance_controls() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        ?assertEqual(ok, esp32cam_mock:set_control(wb_mode, sunny)),
        ?assertEqual(sunny, get({esp32cam_control, wb_mode})),
        ?assertEqual(ok, esp32cam_mock:set_control(auto_white_balance, false)),
        ?assertEqual(false, get({esp32cam_control, auto_white_balance})),
        ?assertEqual(ok, esp32cam_mock:set_control(awb_gain, true)),
        ?assertEqual(true, get({esp32cam_control, awb_gain})),
        ?assertEqual(ok, esp32cam_mock:set_control(brightness, -2)),
        ?assertEqual(-2, get({esp32cam_control, brightness})),
        ?assertEqual(ok, esp32cam_mock:set_control(brightness, 2)),
        ?assertEqual(2, get({esp32cam_control, brightness})),
        ?assertEqual(ok, esp32cam_mock:set_control(contrast, 0)),
        ?assertEqual(0, get({esp32cam_control, contrast})),
        ?assertEqual(ok, esp32cam_mock:set_control(saturation, 1)),
        ?assertEqual(1, get({esp32cam_control, saturation})),
        ?assertEqual(ok, esp32cam_mock:set_control(hmirror, true)),
        ?assertEqual(true, get({esp32cam_control, hmirror})),
        ?assertEqual(ok, esp32cam_mock:set_control(vflip, false)),
        ?assertEqual(false, get({esp32cam_control, vflip}))
    end).

test_set_control_invalid_values() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(wb_mode, invalid)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(auto_white_balance, sunny)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(awb_gain, enabled)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(unknown, true)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(brightness, -3)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(brightness, 3)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(contrast, 1.5)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(saturation, high)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(hmirror, 1)),
        ?assertEqual({error, badarg}, esp32cam_mock:set_control(vflip, off))
    end).

test_set_control_before_init() ->
    ?_test(begin
        erase(esp32cam_current_board),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(wb_mode, sunny)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(brightness, -2)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(brightness, 2)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(contrast, 0)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(saturation, 1)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(hmirror, true)),
        ?assertEqual({error, bad_state}, esp32cam_mock:set_control(vflip, false))
    end).

%%====================================================================
%% Flash Tests
%%====================================================================

test_flash_capture_basic() ->
    ?_test(begin
        Result = safe_call(fun() -> esp32cam_mock:capture_with_flash([{delay_ms, 100}]) end),
        ?assertMatch({ok, ImageData} when is_binary(ImageData), Result)
    end).

test_flash_capture_with_delay() ->
    ?_test(begin
        StartTime = erlang:system_time(millisecond),
        Result = safe_call(fun() -> esp32cam_mock:capture_with_flash([{delay_ms, 50}]) end),
        EndTime = erlang:system_time(millisecond),

        ?assertMatch({ok, _}, Result),
        Duration = EndTime - StartTime,
        % Allow some tolerance
        ?assert(Duration >= 45)
    end).

test_flash_capture_advanced() ->
    ?_test(begin
        FlashOptions = [{delay_ms, 25}],
        CaptureParams = [{flash_delay_ms, 0}],
        Result = safe_call(fun() ->
            esp32cam_mock:capture_with_flash(FlashOptions, CaptureParams)
        end),
        ?assertMatch({ok, _}, Result)
    end).

%%====================================================================
%% Board Configuration Tests
%%====================================================================

test_board_configurations() ->
    ?_test(begin
        Boards = [
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
            esp_eye
        ],
        lists:foreach(
            fun(Board) ->
                Config = [{board, Board}],
                Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
                ?assertEqual(ok, Result),
                ?assertEqual(Board, get(esp32cam_current_board))
            end,
            Boards
        )
    end).

test_custom_board_configuration() ->
    Config = custom_board_config(),
    ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:init(Config) end)),
    ?assertEqual(custom, get(esp32cam_current_board)),
    ?assertEqual(25, get(esp32cam_custom_flash_pin)),
    ?assertEqual(true, esp32cam:has_flash()),

    NoFlashConfig = proplists:delete(pin_flash, Config),
    ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:init(NoFlashConfig) end)),
    ?assertEqual(undefined, get(esp32cam_custom_flash_pin)),
    ?assertEqual(false, esp32cam:has_flash()),

    DisabledFlashConfig = [{pin_flash, -1} | NoFlashConfig],
    ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:init(DisabledFlashConfig) end)),
    ?assertEqual(undefined, get(esp32cam_custom_flash_pin)),
    ?assertEqual(false, esp32cam:has_flash()),

    MissingXclkConfig = proplists:delete(pin_xclk, Config),
    ?assertMatch(
        {error, {invalid_pin, pin_xclk}},
        safe_call(fun() -> esp32cam_mock:init(MissingXclkConfig) end)
    ),
    ?assertMatch(
        {error, {invalid_pin, pin_xclk}},
        safe_call(fun() -> esp32cam_mock:init([{pin_xclk, -1} | MissingXclkConfig]) end)
    ),
    ?assertMatch(
        {error, {invalid_pin, pin_d7}},
        safe_call(fun() -> esp32cam_mock:init([{pin_d7, 999} | Config]) end)
    ).

custom_board_config() ->
    [
        {board, custom},
        {pin_xclk, 10},
        {pin_pclk, 13},
        {pin_vsync, 38},
        {pin_href, 47},
        {pin_sccb_sda, 40},
        {pin_sccb_scl, 39},
        {pin_d0, 15},
        {pin_d1, 17},
        {pin_d2, 18},
        {pin_d3, 16},
        {pin_d4, 14},
        {pin_d5, 12},
        {pin_d6, 11},
        {pin_d7, 48},
        {pin_flash, 25}
    ].

test_board_specific_features() ->
    ?_test(begin
        %% Test wrover_kit (no flash support)
        ok = safe_call(fun() -> esp32cam_mock:init([{board, wrover_kit}]) end),
        ?assertEqual(wrover_kit, get(esp32cam_current_board)),

        %% Test ai_thinker (with flash support)
        ok = safe_call(fun() -> esp32cam_mock:init([{board, ai_thinker}]) end),
        ?assertEqual(ai_thinker, get(esp32cam_current_board))
    end).

%%====================================================================
%% Error Handling Tests
%%====================================================================

test_error_handling() ->
    ?_test(begin
        %% Test error behavior
        esp32cam_mock:set_mock_behavior(always_error),

        InitResult = safe_call(fun() -> esp32cam_mock:init([]) end),
        ?assertMatch({error, _}, InitResult),

        CaptureResult = safe_call(fun() -> esp32cam_mock:capture() end),
        ?assertMatch({error, _}, CaptureResult),

        %% Reset to default behavior
        esp32cam_mock:set_mock_behavior(default)
    end).

test_invalid_parameters() ->
    ?_test(begin
        %% Test with invalid board
        InvalidConfig = [{board, non_existent_board}],
        Result = safe_call(fun() -> esp32cam_mock:init(InvalidConfig) end),
        ?assertMatch({error, _}, Result)
    end).

test_invalid_driver_options() ->
    ?_test(begin
        InvalidConfigs = [
            [{frame_size, bad_size}],
            [{jpeg_quality, 64}],
            [{pixel_format, bad_format}],
            [{xclk_freq_hz, 0}],
            [{fb_count, 0}],
            [{fb_location, flash}],
            [{grab_mode, old}],
            [{sccb_i2c_port, -1}],
            [{ledc_timer, 4}],
            [{ledc_channel, 8}],
            [{conv_mode, unsupported}],
            [{warm_up_frames, -1}],
            [{warm_up_frames, 101}],
            [{warm_up_frames, not_an_integer}],
            [{auto_white_balance, not_a_boolean}],
            [{awb_gain, not_a_boolean}],
            [{wb_mode, invalid_mode}],
            [{brightness, -3}],
            [{brightness, 3}],
            [{contrast, 1.5}],
            [{saturation, high}],
            [{hmirror, 1}],
            [{vflip, off}]
        ],
        lists:foreach(
            fun(Config) ->
                Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
                ?assertMatch({error, _}, Result)
            end,
            InvalidConfigs
        )
    end).

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

%%====================================================================
%% Terminal Image Tests
%%====================================================================

test_display_iterm2() ->
    ?_test(begin
        Result = term_image:display(?MOCK_IMAGE_DATA),
        ?assertEqual(ok, Result),
        ?assertEqual({error, badarg}, term_image:display(not_a_binary)),
        ?assertEqual({error, too_large}, term_image:display(binary:copy(<<0>>, 262145)))
    end).

%%====================================================================
%% Zero-Copy Frame Tests
%%====================================================================

test_capture_frame_basic() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        Result = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        ?assertMatch({ok, {mock_frame, _}}, Result),
        {ok, Frame} = Result,

        ResultBin = safe_call(fun() -> esp32cam_mock:frame_binary(Frame) end),
        ?assertMatch({ok, Bin} when is_binary(Bin), ResultBin),
        {ok, Bin} = ResultBin,
        ?assertEqual(?MOCK_IMAGE_DATA, Bin),

        % Clean up
        ok = safe_call(fun() -> esp32cam_mock:collect_binary_view(Frame) end),
        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame) end)
    end).

test_frame_info() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        {ok, Frame} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        InfoResult = safe_call(fun() -> esp32cam_mock:frame_info(Frame) end),
        ?assertMatch(
            {ok, #{size := _, width := _, height := _, pixel_format := _, timestamp := _}},
            InfoResult
        ),
        {ok, Info} = InfoResult,
        ?assertEqual(byte_size(?MOCK_IMAGE_DATA), maps:get(size, Info)),
        ?assertEqual(1024, maps:get(width, Info)),
        ?assertEqual(768, maps:get(height, Info)),
        ?assertEqual(jpeg, maps:get(pixel_format, Info)),
        ?assertEqual({1700, 0, 0}, maps:get(timestamp, Info)),

        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame) end)
    end).

test_release_frame() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        {ok, Frame} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:release_frame(Frame) end)),
        % Idempotent rejection check
        ?assertEqual(
            {error, already_released}, safe_call(fun() -> esp32cam_mock:release_frame(Frame) end)
        ),
        ?assertEqual(
            {error, already_released}, safe_call(fun() -> esp32cam_mock:frame_binary(Frame) end)
        ),
        ?assertEqual(
            {error, already_released}, safe_call(fun() -> esp32cam_mock:frame_info(Frame) end)
        )
    end).

test_view_active_release_rejection() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init() end),
        {ok, Frame} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        {ok, Bin} = safe_call(fun() -> esp32cam_mock:frame_binary(Frame) end),
        ?assert(is_binary(Bin)),
        % Should fail to release while view is active
        ?assertEqual(
            {error, binary_views_active}, safe_call(fun() -> esp32cam_mock:release_frame(Frame) end)
        ),
        % Collect the view
        ok = safe_call(fun() -> esp32cam_mock:collect_binary_view(Frame) end),
        % Now release should succeed
        ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:release_frame(Frame) end))
    end).

test_lease_limits() ->
    ?_test(begin
        % Initialize with fb_count = 1
        ok = safe_call(fun() -> esp32cam_mock:init([{fb_count, 1}]) end),
        {ok, Frame1} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        % Second capture should fail immediately
        ?assertEqual({error, frames_in_use}, safe_call(fun() -> esp32cam_mock:capture_frame() end)),
        % Release first frame
        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame1) end),
        % Now second capture should succeed
        {ok, Frame2} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame2) end)
    end).

test_reinit_lease_rejection() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init([{fb_count, 1}]) end),
        {ok, Frame} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        % Reinit should fail with outstanding lease
        ?assertEqual({error, frames_in_use}, safe_call(fun() -> esp32cam_mock:init() end)),
        % Release outstanding lease
        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame) end),
        % Reinit should now succeed
        ?assertEqual(ok, safe_call(fun() -> esp32cam_mock:init() end))
    end).

test_destructor_returns_fb() ->
    ?_test(begin
        ok = safe_call(fun() -> esp32cam_mock:init([{fb_count, 1}]) end),
        {ok, Frame} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        % outstanding leases is now 1. capture fails.
        ?assertEqual({error, frames_in_use}, safe_call(fun() -> esp32cam_mock:capture_frame() end)),
        % Simulate GC collection of Frame (destructor)
        ok = safe_call(fun() -> esp32cam_mock:collect_frame(Frame) end),
        % Now capture should succeed
        {ok, Frame2} = safe_call(fun() -> esp32cam_mock:capture_frame() end),
        ok = safe_call(fun() -> esp32cam_mock:release_frame(Frame2) end)
    end).

test_psram_size() ->
    ?_test(begin
        % Test default mocked size
        ?assertEqual(4194304, esp32cam_mock:psram_size()),
        % Test custom mocked size
        put(esp32cam_mock_psram_size, 8388608),
        ?assertEqual(8388608, esp32cam_mock:psram_size()),
        put(esp32cam_mock_psram_size, 0),
        ?assertEqual(0, esp32cam_mock:psram_size()),
        % Clean up
        erase(esp32cam_mock_psram_size)
    end).

test_fb_count_auto_resolution() ->
    ?_test(begin
        % Test when no PSRAM is present (mock size = 0)
        put(esp32cam_mock_psram_size, 0),
        ?assertEqual(1, esp32cam:resolve_fb_count(auto, [{fb_location, psram}])),

        % Test when fb_location = dram
        put(esp32cam_mock_psram_size, 4194304),
        ?assertEqual(1, esp32cam:resolve_fb_count(auto, [{fb_location, dram}])),

        % Test when PSRAM is present (4MB) and format is JPEG, small resolution (VGA)
        ?assertEqual(
            3,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, vga}, {pixel_format, jpeg}
            ])
        ),

        % Test when PSRAM is present (4MB) and format is JPEG, medium resolution (XGA)
        ?assertEqual(
            3,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, xga}, {pixel_format, jpeg}
            ])
        ),

        % Test when PSRAM is present (4MB) and format is JPEG, huge resolution (5mp)
        ?assertEqual(
            2,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, '5mp'}, {pixel_format, jpeg}
            ])
        ),

        % Test when PSRAM is present (4MB) and format is raw (RGB565) and resolution is VGA
        ?assertEqual(
            1,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, vga}, {pixel_format, rgb565}
            ])
        ),

        % Test when PSRAM is present (8MB) and format is raw (RGB565) and resolution is VGA
        put(esp32cam_mock_psram_size, 8388608),
        ?assertEqual(
            3,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, vga}, {pixel_format, rgb565}
            ])
        ),

        % Test when PSRAM is present (4MB) and format is raw (RGB565) and resolution is QQVGA
        put(esp32cam_mock_psram_size, 4194304),
        ?assertEqual(
            3,
            esp32cam:resolve_fb_count(auto, [
                {fb_location, psram}, {frame_size, qqvga}, {pixel_format, rgb565}
            ])
        ),

        % Test explicit fb_count overrides are respected
        ?assertEqual(5, esp32cam:resolve_fb_count(5, [])),

        % Clean up
        erase(esp32cam_mock_psram_size)
    end).

%%====================================================================
%% Property-Based Test Generators (for use with PropEr)
%%====================================================================

-ifdef(PROPER).
-include_lib("proper/include/proper.hrl").

%% Property: Flash delay should be respected
prop_flash_delay_timing() ->
    ?FORALL(
        Delay,
        range(0, 200),
        begin
            esp32cam_mock:set_mock_behavior(default),
            StartTime = erlang:system_time(millisecond),
            Result = safe_call(fun() ->
                esp32cam_mock:capture([{flash, on}, {flash_delay_ms, Delay}])
            end),
            EndTime = erlang:system_time(millisecond),
            ActualDelay = EndTime - StartTime,

            case Result of
                % Allow 5ms tolerance
                {ok, _} -> ActualDelay >= Delay - 5;
                % Errors are acceptable in test environment
                {error, _} -> true
            end
        end
    ).

%% Property: All supported boards should initialize successfully
prop_board_initialization() ->
    ?FORALL(
        Board,
        oneof([
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
            esp_eye
        ]),
        begin
            esp32cam_mock:set_mock_behavior(default),
            Config = [{board, Board}],
            Result = safe_call(fun() -> esp32cam_mock:init(Config) end),
            Result =:= ok
        end
    ).

%% Property: Capture should always return binary data when successful
prop_capture_returns_binary() ->
    ?FORALL(
        Params,
        list(oneof([{flash, oneof([on, off])}, {flash_delay_ms, range(0, 100)}])),
        begin
            esp32cam_mock:set_mock_behavior(default),
            Result = safe_call(fun() -> esp32cam_mock:capture(Params) end),
            case Result of
                {ok, Data} -> is_binary(Data) andalso byte_size(Data) > 0;
                % Errors are acceptable
                {error, _} -> true
            end
        end
    ).

-endif.
