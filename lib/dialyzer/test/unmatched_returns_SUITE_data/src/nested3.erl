-module(nested3).

-export([t3_1/0, t3_2/0, t3_3/0, t3_4/0, t3_5/0]).

-export([t1/0, t2/0]).

-export([f/2, f2/1]).

t3_1() ->
    case n() of % warning
        Y -> Y
    end,
    case t3:t3_1() of % warning
        d ->
            case _ = n() of
                X -> X
            end
    end,
    ok.

t3_2() ->
    _ = case n() of
        Y -> Y
    end,
    case t3:t3_2() of % warning
        d ->
            case _ = n() of
                X -> X
            end
    end,
    ok.

t3_3() ->
    case n() of
        Y -> _ = Y
    end,
    case t3:t3_3() of % warning
        d ->
            case _ = n() of
                X -> X
            end
    end,
    ok.

t3_4() ->
    case _ = n() of % warning
        Y -> Y
    end,
    case t3:t3_4() of
        d ->
            case _ = n() of
                X -> _ = X
            end
    end,
    ok.

t3_5() ->
    case t3:t3() of
        a ->
            a;
        b ->
            case t3:t3() of
                true ->
                    a;
                false ->
                    _ = {1, 1}
            end
    end,
    ok.

t1() ->
    case foo:bar() of
        true ->
            _ = case fy:foo() of
                    _ -> n()
                end
    end,
    ok.

t2() ->
    case foo:bar() of
        true ->
            self() ! n()
    end,
    ok.

n() ->
    {1, 1}.

f(P, V) ->
    case foo:check(V) of
        ok -> good;
        not_ok -> erlang:send(P, {self(), not_so_good}, [])
    end,
    foo:more().

f2(P) ->
    case foo:bar() of
        1 -> P ! {m, a}
    end,
    foo:more().
