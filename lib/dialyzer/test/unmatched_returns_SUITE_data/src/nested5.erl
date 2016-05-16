-module(nested5).

-export([r1/0, r2/0, r3/0, r4/0, r5/0]).

r1() ->
    receive % no warning since {1, 1} is subsumed by any()
        X -> X
    after 1 -> n()
    end,
    ok.

r2() ->
    receive % warning
        _ -> n()
    after 1 -> n()
    end,
    ok.

r3() ->
    receive % warning
        _ -> _ = n()
    after 1 -> n()
    end,
    ok.

r4() ->
    receive
        _ -> _ = n()
    after 1 -> _ = n()
    end,
    ok.

r5() ->
    receive % warning
        _ -> n()
    after 1 -> _ = n()
    end,
    ok.

n() ->
    {1, 1}.
