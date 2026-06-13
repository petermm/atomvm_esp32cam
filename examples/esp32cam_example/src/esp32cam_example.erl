%%
%% Copyright (c) 2021 fred@dushin.net
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
-module(esp32cam_example).

-export([
    start/0,
    test_custom_ai_thinker/0,
    demo_white_balance_and_warm_up/1,
    demo_runtime_controls/1,
    zero_copy_stress/1,
    zero_copy_stress/2
]).

-define(DEFAULT_ZERO_COPY_ITERATIONS, 100).
-define(ZERO_COPY_PROGRESS_INTERVAL, 10).
-define(ZERO_COPY_DISPLAY_BURST, 5).

start() ->
    io:format("=== Camera Auto-Detection & Demo ===~n"),
    case camera_scanner:scan() of
        {ok, Board} ->
            io:format("Camera board auto-detected and initialized successfully: ~p~n", [Board]),
            case check_initial_capture() of
                {ok, Image} ->
                    maybe_save_to_sdcard(Board, Image);
                error ->
                    ok
            end,
            erlang:garbage_collect(),

            demo_white_balance_and_warm_up(Board),
            erlang:garbage_collect(),

            demo_runtime_controls(Board),
            erlang:garbage_collect(),

            case esp32cam:has_flash(Board) of
                true ->
                    flash_photography_demo(),
                    advanced_flash_demo(Board);
                false ->
                    io:format("Board ~p does not support a flash LED. Skipping flash demos.~n", [
                        Board
                    ])
            end,
            case Board of
                ai_thinker ->
                    test_custom_ai_thinker();
                _ ->
                    ok
            end,
            erlang:garbage_collect(),

            zero_copy_stress(Board),
            erlang:garbage_collect();
        {error, Reason} ->
            io:format("Failed to auto-detect camera board: ~p~n", [Reason])
    end,
    ok.

check_initial_capture() ->
    case esp32cam:capture() of
        {ok, Image} ->
            io:format("Captured initial image. size=~p bytes~n", [erlang:byte_size(Image)]),
            ok = term_image:display(Image),
            {ok, Image};
        {error, CaptureError} ->
            io:format("Failed to capture initial image: ~p~n", [CaptureError]),
            error
    end.

maybe_save_to_sdcard(Board, Image) ->
    io:format("=== SD Card Auto-Detect & Save Demo ===~n"),
    case camera_scanner:mount_sdcard(Board, "/sdcard") of
        {ok, Mounted} ->
            io:format("SD card auto-detected and mounted successfully at /sdcard~n"),
            Filename = "/sdcard/photo.jpg",
            case write_file(Filename, Image) of
                ok ->
                    io:format("Successfully saved captured photo to ~s~n", [Filename]);
                {error, WriteError} ->
                    io:format("Failed to write photo to SD card: ~p~n", [WriteError])
            end,
            ok = camera_scanner:umount_sdcard(Mounted),
            io:format("SD card unmounted successfully.~n");
        {error, no_sdcard_support} ->
            io:format("Board ~p does not support/have an onboard SD card slot.~n", [Board]);
        {error, Reason} ->
            io:format("Failed to mount SD card: ~p~n", [Reason])
    end.

write_file(Path, Data) ->
    case atomvm:posix_open(Path, [o_wronly, o_creat, o_trunc], 8#644) of
        {ok, Fd} ->
            case atomvm:posix_write(Fd, Data) of
                {ok, _Len} ->
                    atomvm:posix_close(Fd);
                Error ->
                    _ = atomvm:posix_close(Fd),
                    Error
            end;
        Error ->
            Error
    end.

flash_photography_demo() ->
    io:format("=== Flash Photography Demo ===~n"),

    capture_demo("Normal image", [{flash, off}]),
    erlang:garbage_collect(),

    capture_demo("Flash image", [{flash, on}]),
    erlang:garbage_collect(),

    capture_demo("Delayed flash image", [{flash, on}, {flash_delay_ms, 100}]),
    erlang:garbage_collect().

advanced_flash_demo(Board) ->
    io:format("=== Advanced Flash Demo ===~n"),

    capture_with_flash_demo("Advanced flash (50ms delay)", [{delay_ms, 50}]),
    erlang:garbage_collect(),

    % Configure image quality with init/1 before flash capture
    ok = esp32cam:init([{board, Board}, {frame_size, xga}, {jpeg_quality, 5}]),

    capture_with_flash_demo("High quality flash", [{delay_ms, 100}]),
    erlang:garbage_collect(),

    % Multiple flash captures with different timings
    flash_sequence().

flash_sequence() ->
    io:format("=== Flash Sequence Demo ===~n"),
    Configs = [
        % Immediate flash
        {1, 0, [{delay_ms, 0}]},
        % Short delay
        {2, 25, [{delay_ms, 25}]},
        % Medium delay
        {3, 50, [{delay_ms, 50}]},
        % Longer delay
        {4, 100, [{delay_ms, 100}]}
    ],
    run_flash_sequence(Configs).

run_flash_sequence([]) ->
    ok;
run_flash_sequence([{Index, DelayMs, Config} | Rest]) ->
    capture_sequence_demo(Index, DelayMs, Config),
    erlang:garbage_collect(),
    run_flash_sequence(Rest).

capture_demo(Label, Params) ->
    case esp32cam:capture(Params) of
        {ok, Image} ->
            io:format("~s: ~p bytes~n", [Label, erlang:byte_size(Image)]);
        {error, Reason} ->
            io:format("~s failed: ~p~n", [Label, Reason])
    end.

capture_with_flash_demo(Label, FlashOptions) ->
    case esp32cam:capture_with_flash(FlashOptions) of
        {ok, Image} ->
            io:format("~s: ~p bytes~n", [Label, erlang:byte_size(Image)]);
        {error, Reason} ->
            io:format("~s failed: ~p~n", [Label, Reason])
    end.

capture_sequence_demo(Index, DelayMs, Config) ->
    case esp32cam:capture_with_flash(Config) of
        {ok, Image} ->
            io:format(
                "Flash sequence ~p (~pms delay): ~p bytes~n",
                [Index, DelayMs, erlang:byte_size(Image)]
            );
        {error, Reason} ->
            io:format(
                "Flash sequence ~p (~pms delay) failed: ~p~n",
                [Index, DelayMs, Reason]
            )
    end.

test_custom_ai_thinker() ->
    io:format("=== Custom AI-Thinker Board Config Demo ===~n"),
    Config = [
        {board, custom},
        {pin_pwdn, 32},
        {pin_reset, -1},
        {pin_xclk, 0},
        {pin_sccb_sda, 26},
        {pin_sccb_scl, 27},
        {pin_d7, 35},
        {pin_d6, 34},
        {pin_d5, 39},
        {pin_d4, 36},
        {pin_d3, 21},
        {pin_d2, 19},
        {pin_d1, 18},
        {pin_d0, 5},
        {pin_vsync, 25},
        {pin_href, 23},
        {pin_pclk, 22},
        {pin_flash, 4},
        {frame_size, xga},
        {jpeg_quality, 12}
    ],
    case esp32cam:init(Config) of
        ok ->
            io:format("Custom board initialized successfully.~n"),
            case esp32cam:capture() of
                {ok, Image} ->
                    io:format("Captured custom image. size=~p bytes~n", [erlang:byte_size(Image)]),
                    ok = term_image:display(Image),
                    case esp32cam:has_flash() of
                        true ->
                            io:format("Triggering flash photo on custom board...~n"),
                            case esp32cam:capture([{flash, on}, {flash_delay_ms, 50}]) of
                                {ok, FlashImage} ->
                                    io:format("Captured custom flash image. size=~p bytes~n", [
                                        erlang:byte_size(FlashImage)
                                    ]),
                                    ok;
                                {error, FlashErr} ->
                                    io:format("Custom flash capture failed: ~p~n", [FlashErr]),
                                    error
                            end;
                        false ->
                            ok
                    end,
                    ok;
                {error, Reason} ->
                    io:format("Failed to capture image on custom board: ~p~n", [Reason]),
                    error
            end;
        {error, Reason} ->
            io:format("Failed to initialize custom board: ~p~n", [Reason]),
            error
    end.

demo_white_balance_and_warm_up(Board) ->
    io:format("=== White Balance & Warm-Up Demo ===~n"),
    Config = [
        {board, Board},
        {frame_size, vga},
        {jpeg_quality, 10},
        {warm_up_frames, 15},
        {auto_white_balance, true},
        {wb_mode, sunny}
    ],
    io:format("Initializing with warm_up_frames=15, auto_white_balance=true, wb_mode=sunny...~n"),
    case esp32cam:init(Config) of
        ok ->
            io:format("Camera initialized with custom white balance settings.~n"),
            case esp32cam:capture() of
                {ok, Image} ->
                    io:format("Captured custom white balance image: ~p bytes~n", [
                        erlang:byte_size(Image)
                    ]),
                    ok = term_image:display(Image),
                    ok;
                {error, Reason} ->
                    io:format("Failed to capture image: ~p~n", [Reason])
            end;
        {error, Reason} ->
            io:format("Failed to initialize camera: ~p~n", [Reason])
    end.

demo_runtime_controls(Board) ->
    io:format("=== Runtime Camera Controls Demo ===~n"),
    Config = [
        {board, Board},
        {frame_size, vga},
        {jpeg_quality, 10},
        {brightness, 1},
        {hmirror, true}
    ],
    io:format("Initializing camera with brightness=1, hmirror=true...~n"),
    case esp32cam:init(Config) of
        ok ->
            io:format("Camera initialized with initial controls.~n"),
            case esp32cam:capture() of
                {ok, Image1} ->
                    io:format("Captured image 1 (brightness=1, hmirror=true): ~p bytes~n", [
                        erlang:byte_size(Image1)
                    ]),
                    ok = term_image:display(Image1);
                {error, Reason1} ->
                    io:format("Failed to capture image 1: ~p~n", [Reason1])
            end,

            io:format("Changing contrast to 2 and hmirror to false at runtime...~n"),
            _ = maybe_set_control(contrast, 2),
            _ = maybe_set_control(hmirror, false),

            case esp32cam:capture() of
                {ok, Image2} ->
                    io:format("Captured image 2 (contrast=2, hmirror=false): ~p bytes~n", [
                        erlang:byte_size(Image2)
                    ]),
                    ok = term_image:display(Image2);
                {error, Reason2} ->
                    io:format("Failed to capture image 2: ~p~n", [Reason2])
            end,

            _ = maybe_set_control(brightness, 0),
            _ = maybe_set_control(contrast, 0),
            ok;
        {error, Reason} ->
            io:format("Failed to initialize camera for controls demo: ~p~n", [Reason])
    end.

maybe_set_control(Control, Value) ->
    case esp32cam:set_control(Control, Value) of
        ok ->
            ok;
        {error, Reason} ->
            io:format("control ~p=~p unsupported/failed: ~p~n", [Control, Value, Reason]),
            ok
    end.

%% Run this explicitly after the normal demo has identified the board:
%%
%%     esp32cam_example:zero_copy_stress(ai_thinker, 1000).
%%
%% The test returns {error, Reason} on the first broken lifecycle invariant.
zero_copy_stress(Board) ->
    zero_copy_stress(Board, ?DEFAULT_ZERO_COPY_ITERATIONS).

zero_copy_stress(Board, Iterations) when is_integer(Iterations), Iterations > 0 ->
    io:format("=== Zero-Copy Frame Stress Test (~p iterations) ===~n", [Iterations]),
    Config = [
        {board, Board},
        {frame_size, vga},
        {jpeg_quality, 12},
        {fb_count, 2},
        {fb_location, psram},
        {grab_mode, latest}
    ],
    case esp32cam:init(Config) of
        ok ->
            BaselineBinaryMemory = erlang:memory(binary),
            io:format("Initial binary memory: ~p bytes~n", [BaselineBinaryMemory]),
            case zero_copy_preflight(Config) of
                ok ->
                    case zero_copy_display_burst(1, ?ZERO_COPY_DISPLAY_BURST) of
                        ok ->
                            case zero_copy_loop(1, Iterations, BaselineBinaryMemory) of
                                ok ->
                                    erlang:garbage_collect(),
                                    FinalBinaryMemory = erlang:memory(binary),
                                    io:format(
                                        "Zero-copy stress passed. binary memory: ~p -> ~p bytes~n",
                                        [BaselineBinaryMemory, FinalBinaryMemory]
                                    ),
                                    ok;
                                Error ->
                                    Error
                            end;
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        {error, Reason} ->
            stress_error(init, Reason)
    end;
zero_copy_stress(_Board, Iterations) ->
    {error, {invalid_iterations, Iterations}}.

zero_copy_preflight(Config) ->
    case capture_two_frames() of
        {ok, Frame1, Frame2} ->
            ThirdCapture = esp32cam:capture_frame(),
            case ThirdCapture of
                {error, frames_in_use} ->
                    case esp32cam:init(Config) of
                        {error, frames_in_use} ->
                            release_two_frames(Frame1, Frame2);
                        OtherInitResult ->
                            _ = esp32cam:release_frame(Frame1),
                            _ = esp32cam:release_frame(Frame2),
                            stress_error(reinit_with_leases, OtherInitResult)
                    end;
                OtherCaptureResult ->
                    _ = esp32cam:release_frame(Frame1),
                    _ = esp32cam:release_frame(Frame2),
                    stress_error(lease_limit, OtherCaptureResult)
            end;
        Error ->
            Error
    end.

capture_two_frames() ->
    case esp32cam:capture_frame() of
        {ok, Frame1} ->
            case esp32cam:capture_frame() of
                {ok, Frame2} ->
                    {ok, Frame1, Frame2};
                {error, Reason} ->
                    _ = esp32cam:release_frame(Frame1),
                    stress_error(second_lease, Reason)
            end;
        {error, Reason} ->
            stress_error(first_lease, Reason)
    end.

release_two_frames(Frame1, Frame2) ->
    case esp32cam:release_frame(Frame1) of
        ok ->
            case esp32cam:release_frame(Frame2) of
                ok -> ok;
                {error, Reason} -> stress_error(release_second_lease, Reason)
            end;
        {error, Reason} ->
            _ = esp32cam:release_frame(Frame2),
            stress_error(release_first_lease, Reason)
    end.

zero_copy_loop(Iteration, Iterations, _BaselineBinaryMemory) when Iteration > Iterations ->
    ok;
zero_copy_loop(Iteration, Iterations, BaselineBinaryMemory) ->
    case zero_copy_iteration(Iteration) of
        ok ->
            case Iteration rem ?ZERO_COPY_PROGRESS_INTERVAL of
                0 ->
                    CurrentBinaryMemory = erlang:memory(binary),
                    io:format(
                        "zero-copy iteration ~p/~p, binary memory=~p bytes (delta=~p)~n",
                        [
                            Iteration,
                            Iterations,
                            CurrentBinaryMemory,
                            CurrentBinaryMemory - BaselineBinaryMemory
                        ]
                    );
                _ ->
                    ok
            end,
            zero_copy_loop(Iteration + 1, Iterations, BaselineBinaryMemory);
        Error ->
            Error
    end.

zero_copy_iteration(Iteration) ->
    case esp32cam:capture_frame() of
        {ok, Frame} ->
            case esp32cam:frame_info(Frame) of
                {ok, #{size := Size}} when is_integer(Size), Size > 0 ->
                    case inspect_live_binary_view(Frame, Size) of
                        ok ->
                            erlang:garbage_collect(),
                            case esp32cam:release_frame(Frame) of
                                ok ->
                                    maybe_test_gc_fallback(Iteration);
                                {error, Reason} ->
                                    stress_error({release_after_view_gc, Iteration}, Reason)
                            end;
                        Error ->
                            Error
                    end;
                OtherInfoResult ->
                    _ = esp32cam:release_frame(Frame),
                    stress_error({frame_info, Iteration}, OtherInfoResult)
            end;
        {error, Reason} ->
            stress_error({capture, Iteration}, Reason)
    end.

zero_copy_display_burst(Index, Count) when Index > Count ->
    ok;
zero_copy_display_burst(Index, Count) ->
    case esp32cam:capture_frame() of
        {ok, Frame} ->
            io:format("Displaying zero-copy frame ~p/~p...~n", [Index, Count]),
            DisplayResult = term_image:display(Frame),
            ReleaseResult = esp32cam:release_frame(Frame),
            case {DisplayResult, ReleaseResult} of
                {ok, ok} ->
                    zero_copy_display_burst(Index + 1, Count);
                {{error, Reason}, _} ->
                    stress_error({display_burst, Index}, Reason);
                {ok, {error, Reason}} ->
                    stress_error({display_burst_release, Index}, Reason)
            end;
        {error, Reason} ->
            stress_error({display_burst_capture, Index}, Reason)
    end.

inspect_live_binary_view(Frame, ExpectedSize) ->
    case esp32cam:frame_binary(Frame) of
        {ok, Binary} when is_binary(Binary), byte_size(Binary) =:= ExpectedSize ->
            case esp32cam:release_frame(Frame) of
                {error, binary_views_active} ->
                    ok;
                OtherReleaseResult ->
                    stress_error(release_with_live_binary, OtherReleaseResult)
            end;
        {ok, Binary} when is_binary(Binary) ->
            stress_error(binary_size, {expected, ExpectedSize, got, byte_size(Binary)});
        OtherBinaryResult ->
            stress_error(frame_binary, OtherBinaryResult)
    end.

maybe_test_gc_fallback(Iteration) when Iteration rem ?ZERO_COPY_PROGRESS_INTERVAL =:= 0 ->
    case capture_and_drop_two_frames() of
        ok ->
            erlang:garbage_collect(),
            case capture_two_frames() of
                {ok, Frame1, Frame2} ->
                    release_two_frames(Frame1, Frame2);
                Error ->
                    stress_error({gc_fallback, Iteration}, Error)
            end;
        Error ->
            stress_error({gc_fallback_setup, Iteration}, Error)
    end;
maybe_test_gc_fallback(_Iteration) ->
    ok.

capture_and_drop_two_frames() ->
    case capture_two_frames() of
        {ok, _Frame1, _Frame2} ->
            ok;
        Error ->
            Error
    end.

stress_error(Stage, Reason) ->
    Error = {error, {zero_copy_stress, Stage, Reason}},
    io:format("Zero-copy stress failed: ~p~n", [Error]),
    Error.
