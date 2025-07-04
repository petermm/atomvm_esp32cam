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
%% Display inline images in terminals supporting the iTerm2 graphics protocol.
%%
%% Usage:
%%   term_image:display(ImageBinary)

-module(term_image).

-export([display/1]).

%% ============================================================
%% Public API
%% ============================================================

%% Display with default options.
-spec display(binary()) -> ok | {error, badarg | too_large}.
display(Image) ->
    display_image(Image).

display_image(Image) when is_binary(Image), byte_size(Image) =< 262144 ->
    B64 = base64:encode(Image),
    io:put_chars("\n"),
    io:put_chars("\n"),
    io:put_chars("\e]1337;File=size="),
    io:put_chars(integer_to_binary(byte_size(Image))),
    io:put_chars(";inline=1:"),
    io:put_chars(B64),
    io:put_chars(<<7, 10>>);
display_image(Image) when is_binary(Image) ->
    {error, too_large};
display_image(_) ->
    {error, badarg}.
