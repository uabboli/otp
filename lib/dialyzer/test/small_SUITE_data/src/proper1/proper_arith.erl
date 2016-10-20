-module(proper_arith).

-export([safe_map/2]).

-spec safe_map(fun((T) -> S), [T]) -> [S].
safe_map(Fun, List) ->
    safe_map_tr(Fun, List, []).

safe_map_tr(_Fun, [], AccList) ->
    AccList;
safe_map_tr(Fun, [Head | Tail], AccList) ->
    safe_map_tr(Fun, Tail, [Fun(Head) | AccList]).
