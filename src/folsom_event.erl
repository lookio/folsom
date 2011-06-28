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
%%% File:      folsom_event.erl
%%% @author    joe williams <j@boundary.com>
%%% @doc
%%% @end
%%%------------------------------------------------------------------

-module(folsom_event).

-behaviour(gen_event).

%% API
-export([
         add_handler/2,
         add_handler/3,
         add_handler/4,
         add_handler/5,
         delete_handler/1,
         handler_exists/1,
         notify/1,
         get_handlers/0,
         get_handlers_info/0,
         get_info/1,
         get_values/1,
         get_histogram_sample/1,
         get_history_values/2
        ]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
         handle_info/2, terminate/2, code_change/3]).

-define(EVENTMGR, folsom_event_manager).

-record(metric, {
          name,
          tags = [],
          type,
          history_size
         }).

-include("folsom.hrl").

%%%===================================================================
%%% API
%%%===================================================================

% generic event handling api

add_handler(Type, Name) ->
    maybe_add_handler(Type, Name, handler_exists(Name)).

add_handler(Type, Name, SampleSize) ->
    maybe_add_handler(Type, Name, SampleSize, handler_exists(Name)).

add_handler(Type, Name, SampleType, SampleSize) ->
    maybe_add_handler(Type, Name, SampleType, SampleSize, handler_exists(Name)).

add_handler(Type, Name, SampleType, SampleSize, Alpha) ->
    maybe_add_handler(Type, Name, SampleType, SampleSize, Alpha, handler_exists(Name)).

delete_handler(Name) ->
    gen_event:delete_handler(?EVENTMGR, {?MODULE, Name}, []).

handler_exists(Name) ->
    lists:keymember(Name, 2, gen_event:which_handlers(?EVENTMGR)).

notify(Event) ->
    gen_event:notify(?EVENTMGR, Event).

get_handlers() ->
    [ Handler || {_, Handler} <- gen_event:which_handlers(?EVENTMGR) ].

get_handlers_info() ->
    Handlers = get_handlers(),
    [get_info(Id) || Id <- Handlers].

get_info(Name) ->
    gen_event:call(?EVENTMGR, {?MODULE, Name}, info).

get_values(Name) ->
    {_, Info} = get_info(Name),
    gen_event:call(?EVENTMGR, {?MODULE, Name}, {proplists:get_value(type, Info), Name}).

get_history_values(Name, Count) ->
    gen_event:call(?EVENTMGR, {?MODULE, Name}, {history, {Name, Count}}).

get_histogram_sample(Name) ->
    gen_event:call(?EVENTMGR, {?MODULE, Name}, {histogram_sample, Name}).

% internal functions


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a new event handler is added to an event manager,
%% this function is called to initialize the event handler.
%%
%% @spec init(Args) -> {ok, State}
%% @end
%%--------------------------------------------------------------------

%% Counter
init([counter, Name]) ->
    folsom_metrics_counter:new(Name),
    {ok, #metric{name = Name, type = counter}};
%% Gauge
init([gauge, Name]) ->
    folsom_metrics_gauge:new(Name),
    {ok, #metric{name = Name, type = gauge}};
%% Histogram
init([histogram, Name]) ->
    folsom_metrics_histogram:new(Name),
    {ok, #metric{name = Name, type = histogram}};
init([histogram, Name, SampleType]) ->
    folsom_metrics_histogram:new(Name, SampleType),
    {ok, #metric{name = Name, type = histogram}};
init([histogram, Name, SampleType, SampleSize]) ->
    folsom_metrics_histogram:new(Name, SampleType, SampleSize),
    {ok, #metric{name = Name, type = histogram}};
init([histogram, Name, SampleType, SampleSize, Alpha]) ->
    folsom_metrics_histogram:new(Name, SampleType, SampleSize, Alpha),
    {ok, #metric{name = Name, type = histogram}};
%% History
init([history, Name, SampleSize]) ->
    folsom_metrics_history:new(Name),
    {ok, #metric{name = Name, type = history, history_size = SampleSize}};
%% Meter
init([meter, Name]) ->
    {ok, _} = timer:send_interval(?DEFAULT_INTERVAL, {meter_tick, Name}),
    folsom_metrics_meter:new(Name),
    {ok, #metric{name = Name, type = meter}};
%% Meter Reader
init([meter_reader, Name]) ->
    {ok, _} = timer:send_interval(?DEFAULT_INTERVAL, {meter_reader_tick, Name}),
    folsom_metrics_meter_reader:new(Name),
    {ok, #metric{name = Name, type = meter_reader}}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @spec handle_event(Event, State) ->
%%                          {ok, State} |
%%                          {swap_handler, Args1, State1, Mod2, Args2} |
%%                          remove_handler
%% @end
%%--------------------------------------------------------------------

%% Bulk update to cut down on message passing
handle_event({Name, Values}, #metric{name = Name, type = Type} = State) when is_list(Values) ->
    bulk_update_metric(Type, Name, Values, State),
    {ok, State};
handle_event({Name, {inc, Value}}, #metric{name = Name1, type = counter} = State) when Name == Name1 ->
    folsom_metrics_counter:inc(Name, Value),
    {ok, State};
%% Counter Decrement
handle_event({Name, {dec, Value}}, #metric{name = Name1, type = counter} = State) when Name == Name1 ->
    folsom_metrics_counter:dec(Name, Value),
    {ok, State};
%% Gauge
handle_event({Name, Value}, #metric{name = Name1, type = gauge} = State) when Name == Name1 ->
    folsom_metrics_gauge:update(Name, Value),
    {ok, State};
%% Histogram
handle_event({Name, Value}, #metric{name = Name1, type = histogram} = State) when Name == Name1 ->
    folsom_metrics_histogram:update(Name, Value),
    {ok, State};
%% History
handle_event({Name, Value}, #metric{name = Name1, type = history, history_size = HistorySize} = State) when Name == Name1 ->
    folsom_metrics_history:update(Name, HistorySize, Value),
    {ok, State};
%% Meter
handle_event({Name, Value}, #metric{name = Name1, type = meter} = State) when Name == Name1 ->
    folsom_metrics_meter:mark(Name, Value),
    {ok, State};
%% Meter Reader
handle_event({Name, Value}, #metric{name = Name1, type = meter_reader} = State) when Name == Name1 ->
    folsom_metrics_meter_reader:mark(Name, Value),
    {ok, State};
handle_event(_, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @spec handle_call(Request, State) ->
%%                   {ok, Reply, State} |
%%                   {swap_handler, Reply, Args1, State1, Mod2, Args2} |
%%                   {remove_handler, Reply}
%% @end
%%--------------------------------------------------------------------
handle_call(info, #metric{name = Name, type = Type} = State) ->
    {ok, {Name, [{type, Type}]}, State};
%% Counter
handle_call({counter, Name}, State) ->
    Values = folsom_metrics_counter:get_value(Name),
    {ok, Values, State};
%% Gauge
handle_call({gauge, Name}, State) ->
    Values = folsom_metrics_gauge:get_value(Name),
    {ok, Values, State};
%% Histogram
handle_call({histogram, Name}, State) ->
    Values = folsom_metrics_histogram:get_values(Name),
    Stats = folsom_statistics:get_statistics(Values),
    {ok, Stats, State};
handle_call({histogram_sample, Name}, State) ->
    Values = folsom_metrics_histogram:get_values(Name),
    {ok, Values, State};
%% History
handle_call({history, {Name, Count}}, State) ->
    Values = folsom_metrics_history:get_events(Name, Count),
    {ok, Values, State};
handle_call({history, Name}, State) ->
    Values = folsom_metrics_history:get_events(Name),
    {ok, Values, State};
%% Meter
handle_call({meter, Name}, State) ->
    Values = folsom_metrics_meter:get_values(Name),
    {ok, Values, State};
%% Meter Reader
handle_call({meter_reader, Name}, State) ->
    Values = folsom_metrics_meter_reader:get_values(Name),
    {ok, Values, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for each installed event handler when
%% an event manager receives any other message than an event or a
%% synchronous request (or a system message).
%%
%% @spec handle_info(Info, State) ->
%%                         {ok, State} |
%%                         {swap_handler, Args1, State1, Mod2, Args2} |
%%                         remove_handler
%% @end
%%--------------------------------------------------------------------
handle_info({meter_tick, Name}, #metric{name = Name1} = State) when Name == Name1->
    folsom_metrics_meter:tick(Name),
    {ok, State};
handle_info({meter_reader_tick, Name}, #metric{name = Name1} = State) when Name == Name1->
    folsom_metrics_meter_reader:tick(Name),
    {ok, State};
handle_info(_Info, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event handler is deleted from an event manager, this
%% function is called. It should be the opposite of Module:init/1 and
%% do any necessary cleaning up.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_, #metric{name = Name, type = counter}) ->
    ets:delete(?COUNTER_TABLE, Name),
    ok;
terminate(_, #metric{name = Name, type = gauge}) ->
    ets:delete(?GAUGE_TABLE, Name),
    ok;
terminate(_, #metric{name = Name, type = histogram}) ->
    ets:delete(?HISTOGRAM_TABLE, Name),
    ok;
terminate(_, #metric{name = Name, type = history}) ->
    ets:delete(Name),
    ets:delete(?HISTORY_TABLE, Name),
    ok;
terminate(_, #metric{name = Name, type = meter}) ->
    ets:delete(?METER_TABLE, Name),
    ok;
terminate(_, #metric{name = Name, type = meter_reader}) ->
    ets:delete(?METER_READER_TABLE, Name),
    ok;
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

maybe_add_handler(Type, Name, false) ->
    gen_event:add_handler(?EVENTMGR, {?MODULE, Name}, [Type, Name]);
maybe_add_handler(_, Name, true) ->
    {metric_already_exists, Name}.

maybe_add_handler(Type, Name, SampleSize, false) ->
    gen_event:add_handler(?EVENTMGR, {?MODULE, Name}, [Type, Name, SampleSize]);
maybe_add_handler(_, Name, _, true) ->
    {metric_already_exists, Name}.

maybe_add_handler(Type, Name, SampleType, SampleSize, false) ->
    gen_event:add_handler(?EVENTMGR, {?MODULE, Name}, [Type, Name, SampleType, SampleSize]);
maybe_add_handler(_, Name, _, _, true) ->
    {metric_already_exists, Name}.

maybe_add_handler(Type, Name, SampleType, SampleSize, Alpha, false) ->
    gen_event:add_handler(?EVENTMGR, {?MODULE, Name}, [Type, Name, SampleType, SampleSize, Alpha]);
maybe_add_handler(_, Name, _, _, _, true) ->
    {metric_already_exists, Name}.

bulk_update_metric(counter, Name, Values, _State) ->
    update_counter(Name, Values);
bulk_update_metric(gauge, Name, Values, _State) ->
    [folsom_metrics_gauge:update(Name, Value) || Value <- Values],
    ok;
bulk_update_metric(histogram, Name, Values, _State) ->
    [folsom_metrics_histogram:update(Name, Value) || Value <- Values],
    ok;
bulk_update_metric(history, Name, Values, #metric{history_size = HistorySize}) ->
    [folsom_metrics_history:update(Name, HistorySize, Value) || Value <- Values],
    ok;
bulk_update_metric(meter, Name, Values, _State) ->
    [folsom_metrics_meter:mark(Name, Value) || Value <- Values],
    ok;
bulk_update_metric(meter_reader, Name, Values, _State) ->
    [folsom_metrics_meter_reader:mark(Name, Value) || Value <- Values],
    ok;
bulk_update_metric(_, _Name, _Values, _State) ->
    ok.



update_counter(_Name, []) ->
    ok;
update_counter(Name, [{inc, Value}|T]) ->
    folsom_metrics_counter:inc(Name, Value),
    update_counter(Name, T);
update_counter(Name, [{dec, Value}|T]) ->
    folsom_metrics_counter:dec(Name, Value),
    update_counter(Name, T).


