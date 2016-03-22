-module(type_vars).

-export([t1/0, t2/0, t3/0, t4/0, t5/0]).

t1() ->
    v1({a}, {{b}}).

-spec v1(A, {A}) -> A when A :: tuple(). % cannot be right

v1(_, _) ->
    {a}.

t2() ->
    v2({a, 1}, {a, 2}).

-spec v2(A, A) -> A when A :: {a, _}. % cannot be right

v2(A, A) ->
    A.

t3() ->
    v3({b, 1}, {b, 2}).

-spec v3(B, B) -> B. % cannot be right

v3(B, B) ->
    B.

t4() ->
    v4({a, 3}).

-spec v4(A) -> A when % cannot be right
      A :: {a, _}.

v4({a, _}) ->
    {a, 2}.

t5() ->
    v5(1, 2).

-spec v5(type5(X), type5(X)) -> any().

-type type5(X) :: X.

v5(A, B) ->
    {A, B}.
