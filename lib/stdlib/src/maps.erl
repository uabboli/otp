%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2013-2016. All Rights Reserved.
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
%% %CopyrightEnd%
%%

-module(maps).

-export([get/3, filter/2,fold/3,
         map/2, size/1,
         update_with/3, update_with/4,
         without/2, with/2]).

%% BIFs
-export([get/2, find/2, from_list/1,
         is_key/2, keys/1, merge/2,
         new/0, put/3, remove/2, take/2,
         to_list/1, update/3, values/1]).

%% Shadowed by erl_bif_types: maps:get/2
-spec get(Key, Map :: #{Key => Value}) -> Value.

get(_,_) -> erlang:nif_error(undef).


-spec find(Key :: term(), Map :: #{_ => Value}) -> {ok, Value} | 'error'.

find(_,_) -> erlang:nif_error(undef).

%% Shadowed by erl_bif_types: maps:from_list/1
-spec from_list(List :: [{Key, Value}]) -> #{Key => Value}.

from_list(_) -> erlang:nif_error(undef).


%% Shadowed by erl_bif_types: maps:is_key/2
-spec is_key(Key :: term(), Map :: map()) -> boolean().

is_key(_,_) -> erlang:nif_error(undef).


-spec keys(Map :: #{Key => _}) -> [Key].

keys(_) -> erlang:nif_error(undef).


%% Shadowed by erl_bif_types: maps:merge/2
-spec merge(Map1 :: #{Key1 => Value1}, Map2 :: #{Key2 => Value2}) ->
                   Map3 :: #{Key1 | Key2 => Value1 | Value2}.

merge(_,_) -> erlang:nif_error(undef).



-spec new() -> map().

new() -> erlang:nif_error(undef).


%% Shadowed by erl_bif_types: maps:put/3
-spec put(Key, Value, Map1 :: #{Key1 => Value1}) ->
                 Map2 :: #{Key1 | Key => Value1 | Value}.

put(_,_,_) -> erlang:nif_error(undef).


-spec remove(Key :: term(), Map1 :: #{Key => Value}) ->
                    Map2 :: #{Key => Value}.

remove(_,_) -> erlang:nif_error(undef).

-spec take(Key :: term(), Map1 :: #{Key => Value}) ->
                  {Value, Map2 :: #{Key => Value}} | 'error'.

take(_,_) -> erlang:nif_error(undef).

%% Shadowed by erl_bif_types: maps:to_list/1
-spec to_list(Map :: #{Key => Value}) -> [{Key,Value}].

to_list(_) -> erlang:nif_error(undef).


%% Shadowed by erl_bif_types: maps:update/3
-spec update(Key, Value, Map1 :: #{Key => Value1}) ->
                    Map2 :: #{Key => Value1 | Value}.

update(_,_,_) -> erlang:nif_error(undef).


-spec values(Map :: #{_ => Value}) -> [Value].

values(_) -> erlang:nif_error(undef).

%% End of BIFs

-spec update_with(Key, Fun, Map1 :: #{Key => Value1}) -> #{Key => Value2} when
      Fun :: fun((Value1) -> Value2).

update_with(Key,Fun,Map) when is_function(Fun,1), is_map(Map) ->
    try maps:get(Key,Map) of
        Val -> maps:update(Key,Fun(Val),Map)
    catch
        error:{badkey,_} ->
            erlang:error({badkey,Key},[Key,Fun,Map])
    end;
update_with(Key,Fun,Map) ->
    erlang:error(error_type(Map),[Key,Fun,Map]).


-spec update_with(Key, Fun, Init, Map1 :: #{Key1 => Value1}) ->
                         #{Key1 | Key => Value1 | Value2 | Init} when
      Fun :: fun((Value1) -> Value2).

update_with(Key,Fun,Init,Map) when is_function(Fun,1), is_map(Map) ->
    case maps:find(Key,Map) of
        {ok,Val} -> maps:update(Key,Fun(Val),Map);
        error -> maps:put(Key,Init,Map)
    end;
update_with(Key,Fun,Init,Map) ->
    erlang:error(error_type(Map),[Key,Fun,Init,Map]).


-spec get(Key, Map :: #{Key => Value}, Default) -> Value | Default.

get(Key,Map,Default) when is_map(Map) ->
    case maps:find(Key, Map) of
        {ok, Value} ->
            Value;
        error ->
            Default
    end;
get(Key,Map,Default) ->
    erlang:error({badmap,Map},[Key,Map,Default]).


-spec filter(Pred, Map1 :: #{Key => Value}) -> Map2 :: #{Key => Value} when
      Pred :: fun((Key, Value) -> boolean()).

filter(Pred,Map) when is_function(Pred,2), is_map(Map) ->
    maps:from_list([{K,V}||{K,V}<-maps:to_list(Map),Pred(K,V)]);
filter(Pred,Map) ->
    erlang:error(error_type(Map),[Pred,Map]).


-spec fold(Fun, Init :: Acc, Map :: #{K => V}) -> AccOut when
    Fun :: fun((K, V, AccIn :: Acc) -> AccOut).

fold(Fun,Init,Map) when is_function(Fun,3), is_map(Map) ->
    lists:foldl(fun({K,V},A) -> Fun(K,V,A) end,Init,maps:to_list(Map));
fold(Fun,Init,Map) ->
    erlang:error(error_type(Map),[Fun,Init,Map]).

-spec map(Fun, Map1 :: #{K => V1}) -> Map2 :: #{K => V2} when
    Fun :: fun((K, V1) -> V2).

map(Fun,Map) when is_function(Fun, 2), is_map(Map) ->
    maps:from_list([{K,Fun(K,V)}||{K,V}<-maps:to_list(Map)]);
map(Fun,Map) ->
    erlang:error(error_type(Map),[Fun,Map]).


-spec size(Map :: map()) -> non_neg_integer().

size(Map) when is_map(Map) ->
    erlang:map_size(Map);
size(Val) ->
    erlang:error({badmap,Val},[Val]).


-spec without(Ks :: [term()], Map1 :: #{Key => Value}) ->
                     Map2 :: #{Key => Value}.

without(Ks,M) when is_list(Ks), is_map(M) ->
    lists:foldl(fun(K, M1) -> ?MODULE:remove(K, M1) end, M, Ks);
without(Ks,M) ->
    erlang:error(error_type(M),[Ks,M]).


-spec with(Ks :: [K], Map1 :: #{_ => Value}) -> Map2 :: #{K => Value}.

with(Ks,Map1) when is_list(Ks), is_map(Map1) ->
    Fun = fun(K, List) ->
      case ?MODULE:find(K, Map1) of
          {ok, V} ->
              [{K, V} | List];
          error ->
              List
      end
    end,
    ?MODULE:from_list(lists:foldl(Fun, [], Ks));
with(Ks,M) ->
    erlang:error(error_type(M),[Ks,M]).


error_type(M) when is_map(M) -> badarg;
error_type(V) -> {badmap, V}.
