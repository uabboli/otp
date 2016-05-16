-module(nested).

%% Suppressed unmatched returns cannot result in further warnings.

-export([t1/0, t2/0, t3/0, t4/0, t5/0]).

-export([c1/0, c2/0, c3/0, c4/0, c5/0]).

-export([s/0, s2/0, s3/0]).

t1() ->
    case t1:t1() of % warning
        true ->
            n();
        false ->
            _ = n()
    end,
    ok.

t2() ->
    case t2:t2() of
        true ->
            _ = n();
        false ->
            _ = n()
    end,
    ok.

t3() ->
    case t3:t3() of
        true ->
            self() ! n();
        false ->
            self() ! n()
    end,
    ok.

t4() ->
    n(), % warning
    ok.

t5() ->
    case t3:t3() of % warning
        true ->
            n();
        false ->
            n()
    end,
    ok.

c1() ->
    A = ok,
    case c1:c1() of % warning
        {foo, _} ->
            c1:c3(),
            c1:c4(),
            case c1:c2() of
                true ->
                    A;
                false ->
                    c1:c5(),
                    nested_adt:f()
            end;
        _ ->
            ok
    end,
    ok.

c2() ->
    F = case foo:bar() of
            true ->
                fun(X) -> X() end;
            false ->
                fun(Y) -> {Y()} end
        end,
    F(fun n/0), % warning
    ok.

c3() ->
    case foo:bar() of % warning
        true ->
            fun() -> n() end()
    end,
    ok.

c4() ->
    case foo:bar() of
        true ->
            _ = fun() -> n() end()
    end,
    ok.

c5() ->
    F = case foo:bar() of
            true ->
                _ = fun n/0;
            false ->
                _ = fun n/0
        end,
    F(), % warning
    ok.

n() ->
    _ = {1, 1}. % has no effect...

s() ->
    self() ! n(),
    erlang:send(self(), n()),
    ok.

s2() ->
    case s2:s2() of
        true ->
            _ = self() ! n()
    end,
    ok.

s3() ->
    n(), % warning
    n(), % warning
    ok.
