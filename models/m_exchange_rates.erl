%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2017 Marc Worrell
%% @doc Model to fetch the list of currencies and the "base" currency.

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
%% limitations under the License.-module(filter_exchange_rates).
-module(m_exchange_rates).

-export([
    m_find_value/3,
    m_to_list/2,
    m_value/2
    ]).

-include("zotonic.hrl").

m_find_value(rates, #m{value=undefined}, Context) ->
    {ok, Rates} = mod_exchange_rates:rates(Context),
    Rates;
m_find_value(base_currency, #m{value=undefined}, Context) ->
    mod_exchange_rates:base_currency(Context).

m_to_list(#m{}, _Context) ->
    [].

m_value(#m{}, _Context) ->
    undefined.
