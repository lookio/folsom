%%%
%%% Copyright 2011, Boundary
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%


%%%-------------------------------------------------------------------
%%% File:      folsom_metrics_resource.erl
%%% @author    joe williams <j@boundary.com>
%%% @doc
%%% http end point that produces metrics collected from event handlers
%%% @end
%%%------------------------------------------------------------------

-module(folsom_metrics_resource).

-export([init/1,
         content_types_provided/2,
         to_json/2,
         allowed_methods/2,
         resource_exists/2
         ]).

-include("folsom.hrl").
-include_lib("webmachine/include/webmachine.hrl").

-record(state, {
          key
         }).

init(_) -> {ok, #state{key = undefined}}.

content_types_provided(ReqData, Context) ->
    {[{"application/json", to_json}], ReqData, Context}.

allowed_methods(ReqData, Context) ->
    {['GET'], ReqData, Context}.

resource_exists(ReqData, Context) ->
    resource_exists(wrq:path_info(id, ReqData), ReqData, Context).

to_json(ReqData, Context = #state{key = Id}) ->
    Info = wrq:get_qs_value("info", undefined, ReqData),
    Result = get_request(Id, Info),
    {mochijson2:encode(Result), ReqData, Context}.

% internal fuctions

resource_exists(undefined, ReqData, Context) ->
    {true, ReqData, Context};
resource_exists(Id, ReqData, Context) ->
    case metric_exists(Id) of
        {true, Key} ->
            {true, ReqData, Context#state{key = Key}};
        {false, _} ->
            {false, ReqData, Context}
    end.

get_request(undefined, undefined) ->
    folsom_metrics:get_metrics();
get_request(Id, undefined) ->
    [{value, folsom_metrics:get_metric_value(Id)}];
get_request(undefined, "true") ->
    folsom_metrics:get_metrics_info().

% @doc Return true if metric with key `Id' exists, false otherwise
%
% Searches for a metric with `Id' stored as a binary first and falls
% back to looking for an existing atom if no matching binary key was
% found.
metric_exists(Id) when is_list(Id) ->
    metric_exists(list_to_binary(Id));
metric_exists(Id) when is_binary(Id) ->
    case folsom_metrics:metric_exists(Id) of
        true  -> {true, Id};
        false ->
            try
                metric_exists(erlang:binary_to_existing_atom(Id, utf8))
            catch
                error:badarg -> {false, Id}
            end
    end;
metric_exists(Id) when is_atom(Id) ->
    {folsom_metrics:metric_exists(Id), Id}.
