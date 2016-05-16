-module(nested2).

-export([t3/0]).

t3() ->
    A = 4,
    case t3:t3() of
        true ->
            _ = m1:f1(),
            n(), % warning
            _ = n();
        false ->
            n(), % warning
            {1, _} = n();
        ett ->
            m3:f3(),
            _B = _A = n();
        fyra ->
            {1, _} = n();
        fem ->
            {1, _} = {1, 1};
        sex ->
            {1, _} = {1, A};
        a ->
            _C = _B = _A = n();
        b ->
            _ = _ = m1:f1(),
            _ = _ = n();
        c ->
            _A = n()
    end,
    ok.

n() ->
    {1, 1}.
