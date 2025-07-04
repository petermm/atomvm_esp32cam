%%
%% Copyright (c) 2026 dushin.net
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
-module(camera_scanner).

-export([scan/0, scan/1]).
-export([get_sdcard_options/1, mount_sdcard/2, umount_sdcard/1, get_spi_port/1]).

-define(ESP32_BOARDS, [
    ai_thinker,
    m5cam_psram,
    m5cam_wide,
    m5cam,
    wrover_kit,
    lilygo_t_camera,
    lilygo_t_camera_plus,
    lilygo_t_journal,
    m5cam_timer,
    esp_eye
]).

-define(ESP32S3_BOARDS, [
    esp32s3_wroom,
    esp32s3_goouuu,
    esp32s3_xiao,
    lilygo_t_camera_s3,
    m5cam_unit_s3_5mp
]).

-define(ALL_BOARDS, ?ESP32_BOARDS ++ ?ESP32S3_BOARDS).

%%-----------------------------------------------------------------------------
%% @returns `{ok, Board}' or `{error, not_found}'
%% @doc     Auto-detect the camera board by trying supported configurations.
%% @end
%%-----------------------------------------------------------------------------
-spec scan() -> {ok, atom()} | {error, not_found}.
scan() ->
    scan([]).

%%-----------------------------------------------------------------------------
%% @param   Config  the base camera configuration
%% @returns `{ok, Board}' or `{error, not_found}'
%% @doc     Auto-detect the camera board using matching SoC configurations.
%% @end
%%-----------------------------------------------------------------------------
-spec scan(Config :: list()) -> {ok, atom()} | {error, not_found}.
scan(Config) ->
    Boards = get_candidate_boards(),
    scan_boards(Config, Boards).

%%-----------------------------------------------------------------------------
%% @param   Board  the camera board type atom
%% @returns `{sdmmc, Opts}' or `{sdspi, SPIBusOpts, SDSPIOpts}' or `{error, Reason}'
%% @doc     Get the SD card configuration options for the specified board.
%% @end
%%-----------------------------------------------------------------------------
-spec get_sdcard_options(Board :: atom()) ->
    {sdmmc, list()} | {sdspi, list(), list()} | {error, term()}.
get_sdcard_options(ai_thinker) ->
    {sdmmc, [{width, 4}]};
get_sdcard_options(wrover_kit) ->
    {sdmmc, [{width, 4}]};
get_sdcard_options(esp32s3_wroom) ->
    {sdmmc, [{width, 1}, {clk, 39}, {cmd, 38}, {d0, 40}]};
get_sdcard_options(esp32s3_goouuu) ->
    {sdmmc, [{width, 1}, {clk, 39}, {cmd, 38}, {d0, 40}]};
get_sdcard_options(esp32s3_xiao) ->
    {sdspi,
        [
            {bus_config, [
                {miso, 8},
                {mosi, 9},
                {sclk, 7}
            ]}
        ],
        [
            {cs, 21}
        ]};
get_sdcard_options(Board) when
    Board =:= m5cam;
    Board =:= m5cam_wide;
    Board =:= m5cam_psram;
    Board =:= lilygo_t_camera_s3;
    Board =:= lilygo_t_camera;
    Board =:= lilygo_t_camera_plus;
    Board =:= lilygo_t_journal;
    Board =:= m5cam_timer;
    Board =:= m5cam_unit_s3_5mp;
    Board =:= esp_eye
->
    {error, no_sdcard_support};
get_sdcard_options(_Board) ->
    {error, unknown_board}.

%%-----------------------------------------------------------------------------
%% @param   Board  the camera board type atom
%% @param   Path   the mount point path (e.g., "/sdcard")
%% @returns `{ok, Mounted}' or `{error, Reason}'
%% @doc     Auto-configure, initialize SPI if necessary, and mount the SD card.
%% @end
%%-----------------------------------------------------------------------------
-spec mount_sdcard(Board :: atom(), Path :: string() | binary()) ->
    {ok, term()} | {error, term()}.
mount_sdcard(Board, Path) ->
    case get_sdcard_options(Board) of
        {sdmmc, Opts} ->
            case safe_mount("sdmmc", Path, fat, Opts) of
                {ok, MountedFS} -> {ok, MountedFS};
                {error, Reason} -> {error, Reason}
            end;
        {sdspi, SPIBusOpts, SDSPIOpts} ->
            try
                SPIPort = safe_spi_open(SPIBusOpts),
                Opts = [{spi_host, SPIPort} | SDSPIOpts],
                case safe_mount("sdspi", Path, fat, Opts) of
                    {ok, MountedFS} ->
                        {ok, {MountedFS, SPIPort}};
                    {error, ErrReason} ->
                        safe_spi_close(SPIPort),
                        {error, ErrReason}
                end
            catch
                ErrType:ErrData ->
                    {error, {spi_init_failed, {ErrType, ErrData}}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%-----------------------------------------------------------------------------
%% @param   Mounted  the mounted filesystem reference (either MountedFS or {MountedFS, SPIPort})
%% @returns `ok' or `{error, Reason}'
%% @doc     Unmount the SD card and close the associated SPI bus port if opened.
%% @end
%%-----------------------------------------------------------------------------
-spec umount_sdcard(Mounted :: term()) -> ok | {error, term()}.
umount_sdcard({MountedFS, SPIPort}) ->
    Res = safe_umount(MountedFS),
    safe_spi_close(SPIPort),
    Res;
umount_sdcard(MountedFS) ->
    safe_umount(MountedFS).

%%-----------------------------------------------------------------------------
%% @param   Mounted  the mounted filesystem reference
%% @returns `{ok, SPIPort}' or `{error, no_spi_port}'
%% @doc     Get the SPI port reference from the mounted SD card resource if active.
%% @end
%%-----------------------------------------------------------------------------
-spec get_spi_port(Mounted :: term()) -> {ok, port()} | {error, no_spi_port}.
get_spi_port({_MountedFS, SPIPort}) ->
    case is_port(SPIPort) of
        true -> {ok, SPIPort};
        false -> {error, no_spi_port}
    end;
get_spi_port(_) ->
    {error, no_spi_port}.

%%-----------------------------------------------------------------------------
%% Internal functions
%%-----------------------------------------------------------------------------

scan_boards(_Config, []) ->
    {error, not_found};
scan_boards(Config, [Board | Rest]) ->
    case init_cam([{board, Board} | Config]) of
        ok ->
            {ok, Board};
        {error, _Reason} ->
            scan_boards(Config, Rest)
    end.

init_cam(Config) ->
    try
        esp32cam:init(Config)
    catch
        throw:nif_error ->
            esp32cam_mock:init(Config);
        error:undef ->
            esp32cam_mock:init(Config)
    end.

get_candidate_boards() ->
    case get_chip_model() of
        esp32 -> ?ESP32_BOARDS;
        esp32_s3 -> ?ESP32S3_BOARDS;
        _ -> ?ALL_BOARDS
    end.

get_chip_model() ->
    try erlang:system_info(esp32_chip_info) of
        #{model := Model} -> Model;
        _ -> unknown
    catch
        _:_ -> unknown
    end.

%%-----------------------------------------------------------------------------
%% Safe platform call wrappers with test mocks
%%-----------------------------------------------------------------------------

safe_spi_open(SPIBusOpts) ->
    try
        spi:open(SPIBusOpts)
    catch
        error:undef ->
            %% Host testing mock port
            try
                open_port({spawn, "true"}, [binary])
            catch
                _:_ ->
                    %% Fallback if spawn true fails
                    erlang:make_ref()
            end
    end.

safe_spi_close(SPIPort) ->
    try
        case is_port(SPIPort) of
            true -> port_close(SPIPort);
            false -> ok
        end
    catch
        error:undef ->
            ok;
        error:badarg ->
            ok
    end.

safe_mount(Source, Path, FS, Opts) ->
    try
        esp:mount(Source, Path, FS, Opts)
    catch
        error:undef ->
            {ok, mock_mounted_fs}
    end.

safe_umount(MountedFS) ->
    try
        esp:umount(MountedFS)
    catch
        error:undef ->
            ok
    end.
