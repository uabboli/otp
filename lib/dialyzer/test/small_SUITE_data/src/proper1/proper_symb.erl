-module(proper_symb).
-export([symb_walk/3]).

symb_walk(VarValues, SymbTerm, HandleInfo) ->
    symb_walk_gen(VarValues, SymbTerm, HandleInfo).

symb_walk_gen(VarValues, SymbTerm, HandleInfo) ->
    SymbWalk = fun(X) -> symb_walk(VarValues, X, HandleInfo) end,
    do_symb_walk_gen(SymbWalk, SymbTerm).

do_symb_walk_gen(SymbWalk, SymbTerm) when is_map(SymbTerm) ->
    M = proper_arith:safe_map(SymbWalk, maps:to_list(SymbTerm)),
    maps:from_list(M).
    %% lists:unzip3(M).
    %% lists:unzip(M).
