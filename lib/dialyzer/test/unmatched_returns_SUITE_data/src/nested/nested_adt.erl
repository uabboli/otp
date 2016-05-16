-module(nested_adt).

-export([f/0]).

%-spec f() -> 'ok' | {error, _}.

f() ->
    case foo:bar() of
        true -> ok;
        Else -> {error, Else}
    end.
