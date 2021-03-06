%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2017 Marc Worrell
%% @doc Support for currency exchange rates, automatically fetches rates.

%% Copyright 2017 Marc Worrell
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

-module(mod_exchange_rates).

-mod_author("Marc Worrell <marc@worrell.nl>").
-mod_title("Exchange Rates").
-mod_description("Provide methods to access exchange rates between currencies.").
-mod_depends([mod_tkvstore]).

-behaviour(gen_server).

-define(BASE_CURRENCY, <<"USD">>).

-define(BTC_JSON_URL, "http://api.bitcoincharts.com/v1/weighted_prices.json").
-define(YAHOO_XML_URL, "https://finance.yahoo.com/webservice/v1/symbols/allcurrencies/quote").
-define(ECB_XML_URL, "http://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml").

-define(HTTPC_TIMEOUT, 20000).
-define(HTTPC_TIMEOUT_CONNECT, 10000).

-export([
    start_link/1,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2
    ]).

-export([
    observe_tick_12h/2,
    rates/1,
    rate/2,
    exchange/4,
    update/1,
    base_currency/1,
    fetch/0,
    fetch_ecb/0,
    fetch_btc/0
    ]).

-record(state, {
        site :: atom(),
        rates :: list({binary(), float()})
    }).

-record(rates, {
        base :: binary(),
        rates :: list({binary(), float()})
    }).

-include("zotonic.hrl").

%% @doc Update the exchange rates.
-spec observe_tick_12h(tick_12h, #context{}) -> ok.
observe_tick_12h(_tick, Context) ->
    update(Context).

-spec update(#context{}) -> ok.
update(Context) ->
    Name = z_utils:name_for_host(?MODULE, Context),
    gen_server:cast(Name, update).

-spec base_currency(#context{}) -> binary().
base_currency(_Context) ->
    ?BASE_CURRENCY.

-spec rates(#context{}) -> {ok, list()} | {error, term()}.
rates(Context) ->
    Name = z_utils:name_for_host(?MODULE, Context),
    gen_server:call(Name, rates).

-spec rate1(binary(), #context{}) -> {ok, float()} | {error, term()}.
rate(Currency, Context) ->
    rate1(z_string:to_upper(z_convert:to_binary(Currency)), Context).

rate1(<<"BTC">>, Context) -> rate1(<<"XBT">>, Context);
rate1(Currency, Context) ->
    case base_currency(Context) of
        Currency -> {ok, 1.0};
        _ ->
            Name = z_utils:name_for_host(?MODULE, Context),
            gen_server:call(Name, {rate, Currency})
    end.

-spec exchange(float()|integer(), binary(), binary(), #context{}) -> {ok, float()} | {error, term()}.
exchange(_Amount, undefined, _To, _Context) ->
    {error, currency_from};
exchange(_Amount, _From, undefined, _Context) ->
    {error, currency_to};
exchange(Amount, From, From, _Context) ->
    {ok, z_convert:to_float(Amount)};
exchange(Amount, From, To, Context) ->
    Amount1 = z_convert:to_float(Amount),
    FromRate = mod_exchange_rates:rate(From, Context),
    ToRate = mod_exchange_rates:rate(To, Context),
    case {FromRate, ToRate} of
        {{ok, FR}, {ok, TR}} when FR > 0.0 ->
            {ok, round_currency(To, Amount1 / FR * TR)};
        {{error, _}, _} ->
            {error, currency_from};
        {_, {error, _}} ->
            {error, currency_to}
    end.

%% @doc Round an amount to the number of expected digits for that currency.
round_currency(Currency, Amount) ->
    case exponent(z_string:to_upper(z_convert:to_binary(Currency))) of
        0 -> round(Amount);
        N ->
            Exp = exp(N),
            round(Amount * Exp) / Exp
    end.

exp(N) -> exp(N,1).

exp(0, Acc) -> Acc;
exp(N, Acc) -> exp(N-1, 10*Acc).

% See https://en.wikipedia.org/wiki/ISO_4217
exponent(<<"BHD">>) -> 3;
exponent(<<"BIF">>) -> 0;
exponent(<<"BYR">>) -> 0;
exponent(<<"CLF">>) -> 4;
exponent(<<"CLP">>) -> 0;
exponent(<<"CVE">>) -> 0;
exponent(<<"DJF">>) -> 0;
exponent(<<"GNF">>) -> 0;
exponent(<<"IQD">>) -> 3;
exponent(<<"ISK">>) -> 0;
exponent(<<"JOD">>) -> 3;
exponent(<<"JPY">>) -> 0;
exponent(<<"KMF">>) -> 0;
exponent(<<"KRW">>) -> 0;
exponent(<<"KWD">>) -> 3;
exponent(<<"MGA">>) -> 1;
exponent(<<"MRO">>) -> 1;
exponent(<<"OMR">>) -> 3;
exponent(<<"PYG">>) -> 0;
exponent(<<"RWF">>) -> 0;
exponent(<<"TND">>) -> 3;
exponent(<<"UGX">>) -> 0;
exponent(<<"UYI">>) -> 0;
exponent(<<"VND">>) -> 0;
exponent(<<"VUV">>) -> 0;
exponent(<<"XAF">>) -> 0;
exponent(<<"XOF">>) -> 0;
exponent(<<"XPF">>) -> 0;
exponent(<<"XBT">>) -> 8; % Bitcoin new
exponent(<<"BTC">>) -> 8; % Bitcoin old
exponent(_) -> 2.


%% @doc Start the gen_server
-spec start_link(list()) -> {ok, pid()} | {error, term()}.
start_link(Args) when is_list(Args) ->
    {context, Context} = proplists:lookup(context, Args),
    Name = z_utils:name_for_host(?MODULE, Context),
    gen_server:start_link({local, Name}, ?MODULE, Args, []).


%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init(list()) -> {ok, #state{}}.
init(Args) ->
    {context, Context} = proplists:lookup(context, Args),
    z_context:lager_md(Context),
    gen_server:cast(self(), update),
    {ok, #state{
        site = z_context:site(Context),
        rates = []
    }}.

handle_call({rate, Currency}, _From, #state{rates=Rates} = State) ->
    case proplists:get_value(Currency, Rates) of
        undefined ->
            {reply, {error, unknown_currency}, State};
        Rate ->
            {reply, {ok, Rate}, State}
    end;
handle_call(rates, _From, #state{rates=Rates} = State) ->
    {reply, {ok, Rates}, State};
handle_call(_, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(update, State) ->
    Self = self(),
    erlang:spawn_link(
        fun() ->
            Fetched = fetch(),
            Self ! {new_rates, Fetched}
        end),
    {noreply, State};
handle_cast(_, State) ->
    {noreply, State}.

handle_info({new_rates, FetchedRates}, #state{rates = OldRates, site = Site} = State) ->
    Context = z_context:new(Site),
    StoredRates = case z_notifier:first(#tkvstore_get{type=?MODULE, key=rates}, Context) of
        #rates{base = ?BASE_CURRENCY, rates = Rs} -> Rs;
        _ -> []
    end,
    StoredRates1 = merge(lists:sort(StoredRates), lists:sort(OldRates)),
    NewRates = merge(lists:sort(FetchedRates), StoredRates1),
    z_notifier:first(
        #tkvstore_put{
            type = ?MODULE,
            key = rates,
            value = #rates{base = ?BASE_CURRENCY, rates = NewRates}
        },
        Context),
    {noreply, State#state{rates = NewRates}};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_Version, State, _Extra) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

merge(As, Bs) ->
    merge(dedup(As), dedup(Bs), []).

dedup(As) ->
    dedup(As, []).

dedup([], Acc) -> lists:reverse(Acc);
dedup([{A,_}=X,{A,_}|As], Acc) -> dedup([X|As], Acc);
dedup([A|As], Acc) -> dedup(As, [A|Acc]).

merge([], [], Acc) ->
    lists:reverse(Acc);
merge([], Bs, Acc) ->
    lists:reverse(Acc, Bs);
merge(As, [], Acc) ->
    lists:reverse(Acc, As);
merge([{A,_}|_] = As,[{A,_}|Bs], Acc) ->
    merge(As, Bs, Acc);
merge([{A,_}|_] = As,[{B,_}=X|Bs], Acc) when A > B ->
    merge(As, Bs, [X|Acc]);
merge([{A,_}=X|As], [{B,_}|_] = Bs, Acc) when A < B ->
    merge(As, Bs, [X|Acc]).


fetch() ->
    BTC = fetch_btc(),
    Cs = fetch_ecb(), % returns in EUR, only use Yahoo data for now
    lists:sort(Cs) ++ BTC ++ [{?BASE_CURRENCY, 1.0}].

fetch_ecb() ->
    fetch_ecb_data(z_url_fetch:fetch(?ECB_XML_URL, [])).

fetch_ecb_data({ok, {_FinalUrl, _Hs, Size, <<"<?xml ", _/binary>> = XML}}) when Size > 0 ->
    case mochiweb_html:parse(XML) of
        {<<"gesmes:Envelope">>, _Args, EnvelopeNodes} ->
            {value, {<<"Cube">>, _, Cubes}} = lists:keysearch(<<"Cube">>, 1, EnvelopeNodes),
            {value, {<<"Cube">>, _, Cube}} = lists:keysearch(<<"Cube">>, 1, Cubes),
            Rates = lists:foldl(
                fun
                    ({<<"Cube">>, Args, _}, Acc) ->
                        {<<"currency">>, Currency} = proplists:lookup(<<"currency">>, Args),
                        {<<"rate">>, Rate} = proplists:lookup(<<"rate">>, Args),
                        [ {Currency, z_convert:to_float(Rate)} | Acc ];
                    (_, Acc) ->
                        Acc
                end,
                [],
                Cube),
            case proplists:get_value(?BASE_CURRENCY, Rates) of
                undefined -> [];
                Rate when is_float(Rate) ->
                    lists:map(
                        fun({C, R}) ->
                            {C, R / Rate}
                        end,
                        [{<<"EUR">>, 1.0} | Rates])
            end;
        _ ->
            ecb_xml_error(XML)
    end;
fetch_ecb_data(Other) ->
    lager:warning("Fetch of ECB data at ~p returned ~p",
            [?ECB_XML_URL, Other]),
    [].

ecb_xml_error(XML) ->
    lager:warning("Unexpected XML structure in ECB data ~p", [XML]),
    [].


% BTC 
fetch_btc() ->
    fetch_btc_data(z_url_fetch:fetch(?BTC_JSON_URL, [])).

fetch_btc_data({ok, {_FinalUrl, _Hs, Size, <<"{", _/binary>> = JSON}}) when Size > 0 ->
    {struct, Currencies} = mochijson:binary_decode(JSON),
    case proplists:get_value(?BASE_CURRENCY, Currencies) of
        undefined -> [];
        {struct, Rates} ->
            case proplists:lookup(<<"24h">>, Rates) of
                none ->
                    lager:info("[mod_exchange_rates] No 24h key in BTC rates: ~p", [Rates]),
                    [];
                {<<"24h">>, Rate} ->
                    [{<<"XBT">>, 1.0 / z_convert:to_float(Rate)}]
            end
    end;
fetch_btc_data(Other) ->
    lager:warning("Fetch of BTC (XBT) data at ~p returned ~p",
            [?BTC_JSON_URL, Other]),
    [].
