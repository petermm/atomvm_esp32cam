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
-module(esp32cam_mjpeg).

-export([start/1, start/2]).

-define(DEFAULT_PORT, 8080).
-define(BOUNDARY, "mjpeg_boundary").

%%-----------------------------------------------------------------------------
%% @doc     Start the MJPEG HTTP streaming server on default port 8080.
%% @end
%%-----------------------------------------------------------------------------
start(Board) ->
    start(Board, ?DEFAULT_PORT).

%%-----------------------------------------------------------------------------
%% @doc     Start the MJPEG HTTP streaming server on a specified port.
%% @end
%%-----------------------------------------------------------------------------
start(Board, Port) when is_integer(Port) ->
    io:format("=== Starting Zero-Copy MJPEG Streaming Server on Port ~p ===~n", [Port]),
    Config = [
        {board, Board},
        {frame_size, vga},
        {jpeg_quality, 12},
        {fb_count, auto},       % Dynamically selects double/triple buffering
        {fb_location, psram},
        {grab_mode, latest}
    ],
    case esp32cam:init(Config) of
        ok ->
            case gen_tcp:listen(Port, [binary, {active, false}, {reuseaddr, true}]) of
                {ok, ListenSocket} ->
                    io:format("Listening for HTTP connections...~n"),
                    accept_loop(ListenSocket);
                {error, Reason} ->
                    io:format("Failed to listen on port ~p: ~p~n", [Port, Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            io:format("Failed to initialize camera driver: ~p~n", [Reason]),
            {error, Reason}
    end.

%%-----------------------------------------------------------------------------
%% Internal Functions
%%-----------------------------------------------------------------------------

accept_loop(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, ClientSocket} ->
            io:format("Client connected! Spawning streaming handler.~n"),
            spawn(fun() -> handle_client(ClientSocket) end),
            accept_loop(ListenSocket);
        {error, Reason} ->
            io:format("TCP accept error: ~p~n", [Reason]),
            accept_loop(ListenSocket)
    end.

handle_client(Socket) ->
    % Read HTTP request headers (wait up to 5 seconds)
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Request} ->
            io:format("Received Request:~n~s~n", [Request]),
            % Send HTTP multipart mixed-replace headers
            Headers = [
                "HTTP/1.1 200 OK\r\n",
                "Content-Type: multipart/x-mixed-replace; boundary=", ?BOUNDARY, "\r\n",
                "Connection: keep-alive\r\n\r\n"
            ],
            case gen_tcp:send(Socket, Headers) of
                ok ->
                    io:format("Starting video frame stream...~n"),
                    stream_loop(Socket);
                {error, SendError} ->
                    io:format("Failed to send HTTP response headers: ~p~n", [SendError]),
                    gen_tcp:close(Socket)
            end;
        {error, RecvError} ->
            io:format("Failed to read HTTP request: ~p~n", [RecvError]),
            gen_tcp:close(Socket)
    end.

stream_loop(Socket) ->
    % Lease a camera framebuffer resource (zero-copy)
    case esp32cam:capture_frame() of
        {ok, Frame} ->
            % Get zero-copy binary view over the frame data
            case esp32cam:frame_binary(Frame) of
                {ok, Binary} ->
                    PartHeader = [
                        "--", ?BOUNDARY, "\r\n",
                        "Content-Type: image/jpeg\r\n",
                        "Content-Length: ", integer_to_list(byte_size(Binary)), "\r\n\r\n"
                    ],
                    % Send part header, binary view, and trailing boundary CRLF
                    case gen_tcp:send(Socket, [PartHeader, Binary, <<"\r\n">>]) of
                        ok ->
                            % Release the frame buffer immediately back to the driver
                            ok = esp32cam:release_frame(Frame),
                            % Yield slightly to match standard frame rate (approx. 25-30 FPS)
                            timer:sleep(35),
                            stream_loop(Socket);
                        {error, Closed} ->
                            io:format("Client connection closed: ~p~n", [Closed]),
                            ok = esp32cam:release_frame(Frame),
                            gen_tcp:close(Socket)
                    end;
                {error, BinaryErr} ->
                    io:format("Failed to create frame binary: ~p~n", [BinaryErr]),
                    ok = esp32cam:release_frame(Frame),
                    gen_tcp:close(Socket)
            end;
        {error, CaptureErr} ->
            io:format("Capture frame failed: ~p~n", [CaptureErr]),
            % Retry after short pause if capture fails temporarily
            timer:sleep(100),
            stream_loop(Socket)
    end.
