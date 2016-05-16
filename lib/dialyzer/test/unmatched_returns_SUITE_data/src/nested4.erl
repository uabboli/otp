-module(nested4).

-export([tr1/0, tr2/0, tr3/0, tr3_1/0, tr4/0, tr5/0, tr6/0, tr7/0, tr8/0]).

tr1() ->
    try t3:t3() of
        a ->
            _C = _B = _A = n();
        c ->
            _A = n()
    catch _:_ ->
            _ = n()
    end,
    ok.

tr2() ->
    try t3:t3() of % warning
        b ->
            _ = _ = foo:foo(),
            n();
        d ->
            case n() of
                X -> X
            end
    catch _:_ ->
            n()
    end,
    ok.

tr3() ->
    try _ = n() % warning
    after n()
    end,
    ok.

tr3_1() ->
    try n() of % warning (?)
        A -> _ = A
    after n()
    end,
    ok.

tr4() ->
    try n() % warning
    after n()
    end,
    ok.

tr5() ->
    try t3:t3() of % warning
        b ->
            1
    catch _:_ ->
            n()
    end,
    ok.

tr6() ->
    try foo:bar() of
        _ -> 1
    after {1, 1}
    end.

tr7() ->
    try t3:t3() of % warning
        b ->
            exit(normal)
    catch _:_ -> {1, 1}
    end,
    ok.

tr8() ->
    try t3:t3() of
        b ->
            exit(normal)
    catch _:_ -> _ = {1, 1}
    end,
    ok.

n() ->
    {1, 1}.
