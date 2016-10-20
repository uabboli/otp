-module(proper_symb).
-export([symb_walk/3]).

symb_walk(VarValues, SymbTerm, HandleInfo) ->
    symb_walk_gen(VarValues, SymbTerm, HandleInfo).

symb_walk_gen(VarValues, SymbTerm, HandleInfo) ->
    SymbWalk = fun(X) -> symb_walk(VarValues, X, HandleInfo) end,
    maps:from_list(proper_arith:safe_map(SymbWalk, maps:to_list(SymbTerm))).
