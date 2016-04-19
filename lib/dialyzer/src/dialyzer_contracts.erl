%% -*- erlang-indent-level: 2 -*-
%%-----------------------------------------------------------------------
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2016. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

-module(dialyzer_contracts).

-export([check_contract/2,
	 check_contracts/4,
	 contracts_without_fun/3,
	 contract_to_string/1,
	 get_invalid_contract_warnings/4,
	 get_contract_args/1,
	 get_contract_return/1,
	 get_contract_return/2,
	 %% get_contract_signature/1,
	 is_overloaded/1,
	 process_contract_remote_types/1,
	 store_tmp_contract/5]).

-export_type([file_contract/0, plt_contracts/0]).

%%-----------------------------------------------------------------------

-include("dialyzer.hrl").

%%-----------------------------------------------------------------------
%% Types used in other parts of the system below
%%-----------------------------------------------------------------------

-type file_contract() :: {file_line(), #contract{}, Extra :: [_]}.

-type plt_contracts() :: orddict:orddict(mfa(), #contract{}).

%%-----------------------------------------------------------------------
%% Internal record for contracts whose components have not been processed
%% to expand records and/or remote types that they might contain.
%%-----------------------------------------------------------------------

-type cache() :: ets:tid().
-type tmp_contract_fun() ::
        fun((sets:set(mfa()), types(), cache()) -> contract_pair()).

-record(tmp_contract, {contract_funs = [] :: [tmp_contract_fun()],
		       forms	     = [] :: [{_, _}]}).

%%-----------------------------------------------------------------------

%%-define(DEBUG, true).

-ifdef(DEBUG).
-define(debug(X__, Y__), io:format(X__, Y__)).
-else.
-define(debug(X__, Y__), ok).
-endif.

%%-----------------------------------------------------------------------

-spec get_contract_return(#contract{}) -> erl_types:erl_type().

get_contract_return(#contract{contracts = Cs, args = GenArgs}) ->
  process_contracts(Cs, GenArgs).

-spec get_contract_return(#contract{}, [erl_types:erl_type()]) -> erl_types:erl_type().

get_contract_return(#contract{contracts = Cs}, Args) ->
  process_contracts(Cs, Args).

-spec get_contract_args(#contract{}) -> [erl_types:erl_type()].

get_contract_args(#contract{args = Args}) ->
  Args.

-spec get_contract_signature(#contract{}) -> erl_types:erl_type().

get_contract_signature(#contract{contracts = Cs, args = GeneralDomain}) ->
  Range = process_contracts(Cs, GeneralDomain),
  erl_types:t_fun(GeneralDomain, Range).

-spec is_overloaded(#contract{}) -> boolean().

is_overloaded(#contract{contracts = Cs}) ->
  case Cs of
    [_] -> true;
    [_,_|_] -> false
  end.

-spec contract_to_string(#contract{}) -> string().

contract_to_string(#contract{forms = Forms}) ->
  contract_to_string_1(Forms).

contract_to_string_1([{Contract, []}]) ->
  strip_fun(erl_types:t_form_to_string(Contract));
contract_to_string_1([{Contract, []}|Rest]) ->
  strip_fun(erl_types:t_form_to_string(Contract)) ++ "\n    ; "
    ++ contract_to_string_1(Rest);
contract_to_string_1([{Contract, Constraints}]) ->
  strip_fun(erl_types:t_form_to_string(Contract)) ++ " when "
    ++ constraints_to_string(Constraints);
contract_to_string_1([{Contract, Constraints}|Rest]) ->
  strip_fun(erl_types:t_form_to_string(Contract)) ++ " when "
    ++ constraints_to_string(Constraints) ++ ";" ++
    contract_to_string_1(Rest).

strip_fun("fun(" ++ String) ->
  butlast(String).

butlast([]) -> [];
butlast([_]) -> [];
butlast([H|T]) -> [H|butlast(T)].

constraints_to_string([]) ->
  "";
constraints_to_string([{type, _, constraint, [{atom, _, What}, Types]}|Rest]) ->
  S = constraint_to_string(What, Types),
  case Rest of
    [] -> S;
    _ -> S ++ ", " ++ constraints_to_string(Rest)
  end.

constraint_to_string(is_subtype, [{var, _, Var}, T]) ->
  atom_to_list(Var) ++ " :: " ++ erl_types:t_form_to_string(T);
constraint_to_string(What, Types) ->
  atom_to_list(What) ++ "("
    ++ sequence([erl_types:t_form_to_string(T) || T <- Types], ",")
    ++ ")".

sequence([], _Delimiter) -> "";
sequence([H], _Delimiter) -> H;
sequence([H|T], Delimiter) -> H ++ Delimiter ++ sequence(T, Delimiter).

-spec process_contract_remote_types(dialyzer_codeserver:codeserver()) ->
	  dialyzer_codeserver:codeserver().

process_contract_remote_types(CodeServer) ->
  {TmpContractDict, TmpCallbackDict} =
    dialyzer_codeserver:get_temp_contracts(CodeServer),
  ExpTypes = dialyzer_codeserver:get_exported_types(CodeServer),
  RecordDict = dialyzer_codeserver:get_records(CodeServer),
  ContractFun =
    fun({{_M, _F, _A}=MFA, {File, TmpContract, Xtra}}, C0) ->
        #tmp_contract{contract_funs = CFuns, forms = Forms} = TmpContract,
        {NewCs, C2} = lists:mapfoldl(fun(CFun, C1) ->
                                         CFun(ExpTypes, RecordDict, C1)
                                     end, C0, CFuns),
        Args = general_domain(NewCs),
        Contract = #contract{contracts = NewCs, args = Args, forms = Forms},
        {{MFA, {File, Contract, Xtra}}, C2}
    end,
  ModuleFun =
    fun({ModuleName, ContractDict}, C3) ->
        {NewContractList, C4} =
          lists:mapfoldl(ContractFun, C3, dict:to_list(ContractDict)),
        {{ModuleName, dict:from_list(NewContractList)}, C4}
    end,
  Cache = erl_types:cache__new(),
  {NewContractList, C5} =
    lists:mapfoldl(ModuleFun, Cache, dict:to_list(TmpContractDict)),
  {NewCallbackList, _C6} =
    lists:mapfoldl(ModuleFun, C5, dict:to_list(TmpCallbackDict)),
  NewContractDict = dict:from_list(NewContractList),
  NewCallbackDict = dict:from_list(NewCallbackList),
  dialyzer_codeserver:finalize_contracts(NewContractDict, NewCallbackDict,
                                         CodeServer).

-type opaques_fun() :: fun((module()) -> [erl_types:erl_type()]).

-type fun_types() :: dict:dict(label(), erl_types:type_table()).

-spec check_contracts([{mfa(), file_contract()}],
		      dialyzer_callgraph:callgraph(), fun_types(),
                      opaques_fun()) -> plt_contracts().

check_contracts(Contracts, Callgraph, FunTypes, FindOpaques) ->
  FoldFun =
    fun(Label, Type, NewContracts) ->
	case dialyzer_callgraph:lookup_name(Label, Callgraph) of
	  {ok, {M,F,A} = MFA} ->
	    case orddict:find(MFA, Contracts) of
	      {ok, {_FileLine, Contract, _Xtra}} ->
                Opaques = FindOpaques(M),
		case check_contract(Contract, Type, Opaques) of
		  ok ->
		    case erl_bif_types:is_known(M, F, A) of
		      true ->
			%% Disregard the contracts since
			%% this is a known function.
			NewContracts;
		      false ->
			[{MFA, Contract}|NewContracts]
		    end;
		  {error, _Error} -> NewContracts
		end;
	      error -> NewContracts
	    end;
	  error -> NewContracts
	end
    end,
  dict:fold(FoldFun, [], FunTypes).

%% Checks all components of a contract
-spec check_contract(#contract{}, erl_types:erl_type()) -> 'ok' | {'error', term()}.

check_contract(Contract, SuccType) ->
  check_contract(Contract, SuccType, 'universe').

check_contract(#contract{contracts = Contracts}, SuccType, Opaques) ->
  try
    Contracts1 = [{Contract, insert_constraints(Constraints)}
		  || {_Orig, {Contract, Constraints}} <- Contracts],
    Contracts2 = [erl_types:t_subst(Contract, Map)
		  || {Contract, Map} <- Contracts1],
    GenDomains = [erl_types:t_fun_args(C) || C <- Contracts2],
    case check_domains(GenDomains) of
      error ->
	{error, {overlapping_contract, []}};
      ok ->
	InfList = [erl_types:t_inf(Contract, SuccType, Opaques)
		   || Contract <- Contracts2],
	case check_contract_inf_list(InfList, SuccType, Opaques) of
	  {error, _} = Invalid -> Invalid;
	  ok -> check_extraneous(Contracts2, SuccType)
	end
    end
  catch
    throw:{error, _} = Error -> Error
  end.

check_domains([_]) -> ok;
check_domains([Dom|Doms]) ->
  Fun = fun(D) ->
	    erl_types:any_none_or_unit(erl_types:t_inf_lists(Dom, D))
	end,
  case lists:all(Fun, Doms) of
    true -> check_domains(Doms);
    false -> error
  end.

%% Allow a contract if one of the overloaded contracts is possible.
%% We used to be more strict, e.g., all overloaded contracts had to be
%% possible.
check_contract_inf_list([FunType|Left], SuccType, Opaques) ->
  FunArgs = erl_types:t_fun_args(FunType),
  case lists:any(fun erl_types:t_is_none_or_unit/1, FunArgs) of
    true -> check_contract_inf_list(Left, SuccType, Opaques);
    false ->
      STRange = erl_types:t_fun_range(SuccType),
      case erl_types:t_is_none_or_unit(STRange) of
	true -> ok;
	false ->
	  Range = erl_types:t_fun_range(FunType),
	  case erl_types:t_is_none(erl_types:t_inf(STRange, Range)) of
	    true -> check_contract_inf_list(Left, SuccType, Opaques);
	    false -> ok
	  end
      end
  end;
check_contract_inf_list([], _SuccType, _Opaques) ->
  {error, invalid_contract}.

check_extraneous([], _SuccType) -> ok;
check_extraneous([C|Cs], SuccType) ->
  case check_extraneous_1(C, SuccType) of
    ok -> check_extraneous(Cs, SuccType);
    Error -> Error
  end.

check_extraneous_1(Contract, SuccType) ->
  CRng = erl_types:t_fun_range(Contract),
  CRngs = erl_types:t_elements(CRng),
  STRng = erl_types:t_fun_range(SuccType),
  ?debug("CR = ~p\nSR = ~p\n", [CRngs, STRng]),
  case [CR || CR <- CRngs,
              erl_types:t_is_none(erl_types:t_inf(CR, STRng))] of
    [] ->
      case bad_extraneous_list(CRng, STRng)
	orelse bad_extraneous_map(CRng, STRng)
      of
	true -> {error, invalid_contract};
	false -> ok
      end;
    CRs -> {error, {extra_range, erl_types:t_sup(CRs), STRng}}
  end.

bad_extraneous_list(CRng, STRng) ->
  CRngList = list_part(CRng),
  STRngList = list_part(STRng),
  case is_not_nil_list(CRngList) andalso is_not_nil_list(STRngList) of
    false -> false;
    true ->
      CRngElements = erl_types:t_list_elements(CRngList),
      STRngElements = erl_types:t_list_elements(STRngList),
      Inf = erl_types:t_inf(CRngElements, STRngElements),
      erl_types:t_is_none(Inf)
  end.

list_part(Type) ->
  erl_types:t_inf(erl_types:t_list(), Type).

is_not_nil_list(Type) ->
  erl_types:t_is_list(Type) andalso not erl_types:t_is_nil(Type).

bad_extraneous_map(CRng, STRng) ->
  CRngMap = map_part(CRng),
  STRngMap = map_part(STRng),
  (not is_empty_map(CRngMap)) andalso (not is_empty_map(STRngMap))
    andalso is_empty_map(erl_types:t_inf(CRngMap, STRngMap)).

map_part(Type) ->
  erl_types:t_inf(erl_types:t_map(), Type).

is_empty_map(Type) ->
  erl_types:t_is_equal(Type, erl_types:t_from_term(#{})).

%% This is the heart of the "range function"
-spec process_contracts([contract_pairs()], [erl_types:erl_type()]) ->
                           erl_types:erl_type().

process_contracts(OverContracts, Args) ->
  process_contracts(OverContracts, Args, erl_types:t_none()).

process_contracts([OverContract|Left], Args, AccRange) ->
  NewAccRange =
    case process_contract(OverContract, Args) of
      error -> AccRange;
      {ok, Range} -> erl_types:t_sup(AccRange, Range)
    end,
  process_contracts(Left, Args, NewAccRange);
process_contracts([], _Args, AccRange) ->
  AccRange.

-spec process_contract(contract_pairs(), [erl_types:erl_type()]) ->
                          'error' | {'ok', erl_types:erl_type()}.

process_contract(ContractPairs, CallTypes0) ->
  {{OrigContract, OrigConstraints},
   {Contract, Constraints}} = ContractPairs,
  CallTypesFun = erl_types:t_fun(CallTypes0, erl_types:t_any()),
  ContArgsFun = erl_types:t_fun(erl_types:t_fun_args(Contract),
				erl_types:t_any()),
  OrigContArgsFun = erl_types:t_fun(erl_types:t_fun_args(OrigContract),
                                    erl_types:t_any()),
  case solve_constraints(ContArgsFun, OrigContArgsFun,
                         CallTypesFun, Constraints, OrigConstraints) of
    {ok, VarMap} ->
      Range = erl_types:t_fun_range(Contract),
      NewRange = erl_types:t_subst(Range, VarMap),
      OrigRange = erl_types:t_fun_range(OrigContract),
      OrigNewRange = erl_types:t_subst(OrigRange, VarMap),
      FinalRange = erl_types:t_inf(NewRange, OrigNewRange),
      ?debug("Range: ~s\n", [erl_types:t_to_string(Range)]),
      ?debug("NewRange: ~s\n", [erl_types:t_to_string(NewRange)]),
      ?debug("OrigRange: ~s\n", [erl_types:t_to_string(OrigRange)]),
      ?debug("OrigNewRange: ~s\n", [erl_types:t_to_string(OrigNewRange)]),
      ?debug("FinalRange: ~s\n", [erl_types:t_to_string(FinalRange)]),
      {ok, FinalRange};
    error -> error
  end.

%% This treats the "when" constraints. It will be extended, we hope.
solve_constraints(Contract, OrigContract, Call,
                  Constraints, OrigConstraints) ->
  ?debug("Instance:\n  Contract:  ~s\n  OrigContract:  ~s\n  Arguments: ~s\n",
	 [erl_types:t_to_string(Contract),
	  erl_types:t_to_string(OrigContract),
	  erl_types:t_to_string(Call)]),
  pp_constraints("  Constraints", Constraints),
  pp_constraints("  OrigConstraints", OrigConstraints),

  %% The original contract has type variables that substitutions have
  %% replaced with types without variables. The extra constraints
  %% generated from the original contract compensate for the lost
  %% "sameness" caused by the substitutions.
  Inf = erl_types:t_inf(Contract, Call),
  OrigArgVarTypes =
    erl_types:t_assign_variables_to_subtype(OrigContract, Inf),
  pp_list("OrigArgVarTypes", OrigArgVarTypes),

  ArgCs = [{sub, T1, T2} || {T1, T2} <- OrigArgVarTypes],
  OrigCs = collect_constraints(OrigConstraints),
  Cs = collect_constraints(Constraints),
  Eqs = lists:usort(ArgCs ++ Cs ++ OrigCs),
  {ok, VarMap} = solve_eqs(Eqs),

  OrigInfList = inf_lists_from_args(OrigContract, Call, VarMap),
  case erl_types:any_none_or_unit(OrigInfList) of
    true ->  error;
    false -> {ok, VarMap}
  end.

inf_lists_from_args(Contract, Call, VarMap) ->
  CArgs = erl_types:t_fun_args(Contract),
  Args = [erl_types:t_subst(A, VarMap) || A <- CArgs],
  erl_types:t_inf_lists(Args, erl_types:t_fun_args(Call)).

solve_eqs(L) ->
  pp_eqs("EQ", L),
  solve_it(L, maps:new()).

solve_it(L, VarMap) ->
  case solve(L, VarMap) of
    VarMap ->
      pp_map("Solved", VarMap),
      {ok, VarMap};
    VarMap1 ->
      solve_it(L, VarMap1)
  end.

solve([], VarMap) ->
  VarMap;
solve([{Op, V, T}|L], VarMap) ->
  VarMap1 = solve_one(Op, V, T, VarMap),
  solve(L, VarMap1).

solve_one(Op, V, T, VarMap) ->
  T1 = look_up(V, VarMap),
  %% Take care of sameness of type variables:
  VarTypes = erl_types:t_assign_variables_to_subtype(T, T1),
  pp_list("VarTypes", [VarTypes]),
  F = dialyzer_utils:family(VarTypes),
  L = [{erl_types:t_var_name(Var), erl_types:t_inf(Types)} ||
        {Var, Types} <- F, length(Types) > 1],
  VarMap1 = enter_type_list(L, VarMap),
  T2 = look_up(T, VarMap1),
  Inf = erl_types:t_inf(T1, T2),
  ?debug("Solving: ~s :: ~s ~w ~s :: ~s\n\tInf: ~s\n",
	 [erl_types:t_to_string(V), erl_types:t_to_string(T1), Op,
	  erl_types:t_to_string(T), erl_types:t_to_string(T2),
          erl_types:t_to_string(Inf)]),
  case solve_one1(Op, V, Inf, VarMap) of
    error ->
      enter_type(erl_types:t_var_name(V), erl_types:t_none(), VarMap);
    {ok, VarMap2} ->
      VarMap2
  end.

solve_one1(sub, V, Inf, VarMap) ->
  case erl_types:t_is_none(Inf) of
    true -> error;
    false ->
      try erl_types:t_unify(V, Inf) of
        {_, List} ->
          {ok, enter_type_list(List, VarMap)}
      catch
        throw:{mismatch, _T1, _T2} ->
          ?debug("Mismatch between ~s and ~s\n",
                 [erl_types:t_to_string(_T1), erl_types:t_to_string(_T2)]),
          error
      end
  end.

enter_type_list([], VarMap) ->
  VarMap;
enter_type_list([{K, V}|L], VarMap) ->
  VarMap1 = enter_type(K, V, VarMap),
  enter_type_list(L, VarMap1).

enter_type(Key, Val, VarMap) ->
  ?debug("Entering ~s :: ~s\n", [erl_types:t_to_string(erl_types:t_var(Key)),
                                 erl_types:t_to_string(Val)]),
  case maps:find(Key, VarMap) of
    {ok, Value} ->
      case erl_types:t_is_equal(Value, Val) of
        true -> VarMap;
        false -> store(Key, Val, VarMap)
      end;
    error ->
      case erl_types:t_is_any(Val) of
        true -> VarMap;
        false -> store(Key, Val, VarMap)
      end
  end.

store(Key, Val, VarMap) ->
  ?debug("Storing ~w :: ~s\n", [Key, erl_types:t_to_string(Val)]),
  maps:put(Key, Val, VarMap).

look_up(Id, VarMap) ->
  erl_types:t_subst(Id, VarMap).

-ifdef(DEBUG).
pp_constraints(T, []) ->
  io:format("~s: empty\n", [T]);
pp_constraints(T, Cs) ->
  io:format("~s:\n", [T]),
  _ = [io:format("    ~s :: ~s\n", [erl_types:t_to_string(T1),
                                    erl_types:t_to_string(T2)]) ||
        {subtype, T1, T2} <- Cs],
    ok.

pp_map(T, Map) ->
  L = [{erl_types:t_var(V), Type} ||
        {V, Type} <- lists:sort(maps:to_list(D))],
  pp_list(T, L).

pp_list(T, []) ->
  io:format("<~s>: empty\n", [T]);
pp_list(T, L) ->
  io:format("<~s>\n", [T]),
  _ = [io:format("    ~s: ~s\n", [erl_types:t_to_string(V),
                                  erl_types:t_to_string(Type)]) ||
        {V, Type} <- lists:sort(L)],
  io:format("</~s>\n", [T]),
  ok.

pp_eqs(_T, []) ->
  ok;
pp_eqs(T, L) ->
  io:format("<~s>\n", [T]),
  _ = [io:format(" ~s ~w ~s\n",
                 [erl_types:t_to_string(T1), Op, erl_types:t_to_string(T2)]) ||
        {Op, T1, T2} <- lists:sort(L)],
  io:format("</~s>\n", [T]),
  ok.
-else.
pp_constraints(_, _) -> ok.

pp_map(_, _) -> ok.

pp_list(_, _) -> ok.

pp_eqs(_, _) -> ok.
-endif.

-type contracts() :: dict:dict(mfa(),dialyzer_contracts:file_contract()).

%% Checks the contracts for functions that are not implemented
-spec contracts_without_fun(contracts(), [_], dialyzer_callgraph:callgraph()) ->
        [raw_warning()].

contracts_without_fun(Contracts, AllFuns0, Callgraph) ->
  AllFuns1 = [{dialyzer_callgraph:lookup_name(Label, Callgraph), Arity}
	      || {Label, Arity} <- AllFuns0],
  AllFuns2 = [{M, F, A} || {{ok, {M, F, _}}, A} <- AllFuns1],
  AllContractMFAs = dict:fetch_keys(Contracts),
  ErrorContractMFAs = AllContractMFAs -- AllFuns2,
  [warn_spec_missing_fun(MFA, Contracts) || MFA <- ErrorContractMFAs].

warn_spec_missing_fun({M, F, A} = MFA, Contracts) ->
  {{File, Line}, _Contract, _Xtra} = dict:fetch(MFA, Contracts),
  WarningInfo = {File, Line, MFA},
  {?WARN_CONTRACT_SYNTAX, WarningInfo, {spec_missing_fun, [M, F, A]}}.

collect_constraints(L) ->
  collect_constraints(L, []).

collect_constraints([{subtype, Type1, Type2}|Left], L) ->
  case erl_types:t_is_var(Type1) of
    true -> collect_constraints(Left, [{sub, Type1, Type2}|L]);
    false ->
      %% A lot of things should change to add supertypes
      throw({error, io_lib:format("First argument of is_subtype constraint "
				  "must be a type variable: ~p\n", [Type1])})
  end;
collect_constraints([], L) -> L.

%% This treats the "when" constraints. It will be extended, we hope.
insert_constraints(Constraints) ->
  insert_constraints(Constraints, maps:new()).

insert_constraints([{subtype, Type1, Type2}|Left], Map) ->
  case erl_types:t_is_var(Type1) of
    true ->
      Name = erl_types:t_var_name(Type1),
      Map1 = case maps:find(Name, Map) of
               error ->
                 maps:put(Name, Type2, Map);
               {ok, VarType} ->
                 maps:put(Name, erl_types:t_inf(VarType, Type2), Map)
             end,
      insert_constraints(Left, Map1);
    false ->
      %% A lot of things should change to add supertypes
      throw({error, io_lib:format("First argument of is_subtype constraint "
				  "must be a type variable: ~p\n", [Type1])})
  end;
insert_constraints([], Map) -> Map.

-type types() :: erl_types:type_table().

-type spec_data() :: {TypeSpec :: [_], Xtra:: [_]}.

-spec store_tmp_contract(mfa(), file_line(), spec_data(), contracts(), types()) ->
        contracts().

store_tmp_contract(MFA, FileLine, {TypeSpec, Xtra}, SpecDict, _RecordsDict) ->
  %% io:format("contract from form: ~p\n", [TypeSpec]),
  TmpContract = contract_from_form(TypeSpec, MFA, FileLine),
  %% io:format("contract: ~p\n", [TmpContract]),
  dict:store(MFA, {FileLine, TmpContract, Xtra}, SpecDict).

contract_from_form(Forms, MFA, FileLine) ->
  {CFuns, Forms1} = contract_from_form(Forms, MFA, FileLine, [], []),
  #tmp_contract{contract_funs = CFuns, forms = Forms1}.

contract_from_form([{type, _, 'fun', [_, _]} = Form | Left], MFA,
		   FileLine, TypeAcc, FormAcc) ->
  TypeFun =
    fun(ExpTypes, AllRecords, Cache) ->
	{NewType, NewCache} =
	  try
            from_form_with_check(Form, ExpTypes, MFA, AllRecords, Cache)
	  catch
	    throw:{error, Msg} ->
	      {File, Line} = FileLine,
	      NewMsg = io_lib:format("~s:~p: ~s", [filename:basename(File),
                                                   Line, Msg]),
	      throw({error, NewMsg})
	  end,
	{{{NewType, []}, {NewType, []}}, NewCache}
    end,
  NewTypeAcc = [TypeFun | TypeAcc],
  NewFormAcc = [{Form, []} | FormAcc],
  contract_from_form(Left, MFA, FileLine, NewTypeAcc, NewFormAcc);
contract_from_form([{type, _L1, bounded_fun,
		     [{type, _L2, 'fun', [_, _]} = Form, Constr]}| Left],
		   MFA, FileLine, TypeAcc, FormAcc) ->
  TypeFun =
    fun(ExpTypes, AllRecords, Cache) ->
        {Init, Cache1} =
          set_up_constraints(Constr, MFA, ExpTypes, AllRecords, Cache),
        {OrigType, Cache2} =
          from_form_with_check(Form, ExpTypes, MFA, AllRecords, Cache1),
	{Constr1, VarTab, Cache3} =
	  constraints_fixpoint(Init, MFA, ExpTypes, AllRecords, Cache2),
        {OrigConstr, Cache4} =
          constraints_to_subs(Init, MFA, ExpTypes, AllRecords, maps:new(),
                              Cache3, []),
        {NewType, NewCache} =
          from_form_with_check(Form, ExpTypes, MFA, AllRecords,
                               VarTab, Cache4),
	{{{OrigType, OrigConstr}, {NewType, Constr1}}, NewCache}
    end,
  NewTypeAcc = [TypeFun | TypeAcc],
  NewFormAcc = [{Form, Constr} | FormAcc],
  contract_from_form(Left, MFA, FileLine, NewTypeAcc, NewFormAcc);
contract_from_form([], _MFA, _FileLine, TypeAcc, FormAcc) ->
  {lists:reverse(TypeAcc), lists:reverse(FormAcc)}.

set_up_constraints(Constrs, MFA, ExpTypes, AllRecords, Cache) ->
  {Init0, NewCache} =
    initialize_constraints(Constrs, MFA, ExpTypes, AllRecords, Cache, []),
  {remove_cycles(Init0), NewCache}.

initialize_constraints([], _MFA, _ExpTypes, _AllRecords, Cache, Acc) ->
  {Acc, Cache};
initialize_constraints([Constr|Rest], MFA, ExpTypes, AllRecords,
                       Cache, Acc) ->
  case Constr of
    {type, _, constraint, [{atom, _, is_subtype}, [Type1, Type2]]} ->
      VarTable = erl_types:var_table__new(),
      {T1, NewCache} =
        final_form(Type1, ExpTypes, MFA, AllRecords, VarTable, Cache),
      Entry = {T1, Type2},
      initialize_constraints(Rest, MFA, ExpTypes, AllRecords,
                             NewCache, [Entry|Acc]);
    {type, _, constraint, [{atom,_,Name}, List]} ->
      N = length(List),
      throw({error,
	     io_lib:format("Unsupported type guard ~w/~w\n", [Name, N])})
  end.

constraints_fixpoint(Constrs, MFA, ExpTypes, AllRecords, Cache) ->
  VarTable = erl_types:var_table__new(),
  {VarTab, NewCache} =
    constraints_to_dict(Constrs, MFA, ExpTypes, AllRecords, VarTable, Cache),
  constraints_fixpoint(VarTab, MFA, Constrs, ExpTypes, AllRecords, NewCache).

constraints_fixpoint(OldVarTab, MFA, Constrs, ExpTypes, AllRecords, Cache) ->
  {NewVarTab, NewCache} =
    constraints_to_dict(Constrs, MFA, ExpTypes, AllRecords,
                        OldVarTab, Cache),
  case NewVarTab of
    OldVarTab ->
      Fun =
	fun(Key, Value, Acc) ->
	    [{subtype, erl_types:t_var(Key), Value}|Acc]
	end,
      FinalConstrs = maps:fold(Fun, [], NewVarTab),
      {FinalConstrs, NewVarTab, NewCache};
    _Other ->
      constraints_fixpoint(NewVarTab, MFA, Constrs, ExpTypes,
                           AllRecords, NewCache)
  end.

final_form(Form, ExpTypes, MFA, AllRecords, VarTable, Cache) ->
  from_form_with_check(Form, ExpTypes, MFA, AllRecords, VarTable, Cache).

from_form_with_check(Form, ExpTypes, MFA, AllRecords, Cache) ->
  VarTable = erl_types:var_table__new(),
  from_form_with_check(Form, ExpTypes, MFA, AllRecords, VarTable, Cache).

from_form_with_check(Form, ExpTypes, MFA, AllRecords, VarTable, Cache) ->
  Site = {spec, MFA},
  C1 = erl_types:t_check_record_fields(Form, ExpTypes, Site, AllRecords,
                                       VarTable, Cache),
  erl_types:t_from_form(Form, ExpTypes, Site, AllRecords, VarTable, C1).

constraints_to_dict(Constrs, MFA, ExpTypes, AllRecords, VarTab, Cache) ->
  {Subtypes, NewCache} = constraints_to_subs(Constrs, MFA, ExpTypes,
                                             AllRecords, VarTab, Cache, []),
  {insert_constraints(Subtypes), NewCache}.

constraints_to_subs([], _MFA, _ExpTypes, _AllRecords, _VarTab, Cache, Acc) ->
  {Acc, Cache};
constraints_to_subs([C|Rest], MFA, ExpTypes, AllRecords,
                    VarTab, Cache, Acc) ->
  {T1, Form2} = C,
  {T2, NewCache} =
    final_form(Form2, ExpTypes, MFA, AllRecords, VarTab, Cache),
  NewAcc = [{subtype, T1, T2}|Acc],
  constraints_to_subs(Rest, MFA, ExpTypes, AllRecords,
                      VarTab, NewCache, NewAcc).

%% Replaces variables with '_' when necessary to break up cycles among
%% the constraints.

remove_cycles(Constrs0) ->
  Uses = find_uses(Constrs0),
  G = digraph:new(),
  Vs0 = [V || {V, _} <- Uses] ++ [V || {_, V} <- Uses],
  Vs = lists:usort(Vs0),
  lists:foreach(fun(V) -> _ = digraph:add_vertex(G, V) end, Vs),
  lists:foreach(fun({From, To}) ->
                    _ = digraph:add_edge(G, {From, To}, From, To, [])
                end, Uses),
  ok = remove_cycles(G, Vs),
  ToRemove = ordsets:subtract(ordsets:from_list(Uses),
                              ordsets:from_list(digraph:edges(G))),
  Constrs = remove_uses(ToRemove, Constrs0),
  digraph:delete(G),
  Constrs.

find_uses([{Var, Form}|Constrs]) ->
  UsedVars = form_vars(Form, []),
  VarName = erl_types:t_var_name(Var),
  [{VarName, UsedVar} || UsedVar <- UsedVars] ++ find_uses(Constrs);
find_uses([]) ->
  [].

form_vars({var, _, '_'}, Vs) -> Vs;
form_vars({var, _, V}, Vs) -> [V|Vs];
form_vars(T, Vs) when is_tuple(T) ->
  form_vars(tuple_to_list(T), Vs);
form_vars([E|Es], Vs) ->
  form_vars(Es, form_vars(E, Vs));
form_vars(_, Vs) -> Vs.

remove_cycles(G, Vs) ->
  NumberOfEdges = digraph:no_edges(G),
  lists:foreach(fun(V) ->
                        case digraph:get_cycle(G, V) of
                          false -> true;
                          [V] -> digraph:del_edge(G, {V, V});
                          [V, V1|_] -> digraph:del_edge(G, {V, V1})
                        end
                    end, Vs),
  case digraph:no_edges(G) =:= NumberOfEdges of
    true -> ok;
    false -> remove_cycles(G, Vs)
  end.

remove_uses([], Constrs) -> Constrs;
remove_uses([{Var, Use}|ToRemove], Constrs0) ->
  Constrs = remove_uses(Var, Use, Constrs0),
  remove_uses(ToRemove, Constrs).

remove_uses(_Var, _Use, []) -> [];
remove_uses(Var, Use, [Constr|Constrs]) ->
  {V, Form} = Constr,
  NewConstr = case erl_types:t_var_name(V) =:= Var of
                true ->
                  {V, remove_use(Form, Use)};
                false ->
                  Constr
              end,
  [NewConstr|remove_uses(Var, Use, Constrs)].

remove_use({var, L, V}, V) -> {var, L, '_'};
remove_use(T, V) when is_tuple(T) ->
  list_to_tuple(remove_use(tuple_to_list(T), V));
remove_use([E|Es], V) ->
  [remove_use(E, V)|remove_use(Es, V)];
remove_use(T, _V) -> T.

%% Gets the most general domain of a list of domains of all
%% the overloaded contracts

general_domain(List) ->
  general_domain(List, erl_types:t_none()).

general_domain([{{_OrigSig, _OrigCs}, {Sig, Constraints}}|Left], AccSig) ->
  Map = insert_constraints(Constraints),
  Sig1 = erl_types:t_subst(Sig, Map),
  general_domain(Left, erl_types:t_sup(AccSig, Sig1));
general_domain([], AccSig) ->
  %% Get rid of all variables in the domain.
  AccSig1 = erl_types:subst_all_vars_to_any(AccSig),
  erl_types:t_fun_args(AccSig1).

-spec get_invalid_contract_warnings([module()],
                                    dialyzer_codeserver:codeserver(),
                                    dialyzer_plt:plt(),
                                    opaques_fun()) -> [raw_warning()].

get_invalid_contract_warnings(Modules, CodeServer, Plt, FindOpaques) ->
  get_invalid_contract_warnings_modules(Modules, CodeServer, Plt, FindOpaques, []).

get_invalid_contract_warnings_modules([Mod|Mods], CodeServer, Plt, FindOpaques, Acc) ->
  Contracts1 = dialyzer_codeserver:lookup_mod_contracts(Mod, CodeServer),
  Contracts2 = dict:to_list(Contracts1),
  Records = dialyzer_codeserver:lookup_mod_records(Mod, CodeServer),
  NewAcc = get_invalid_contract_warnings_funs(Contracts2, Plt, Records, FindOpaques, Acc),
  get_invalid_contract_warnings_modules(Mods, CodeServer, Plt, FindOpaques, NewAcc);
get_invalid_contract_warnings_modules([], _CodeServer, _Plt, _FindOpaques, Acc) ->
  Acc.

get_invalid_contract_warnings_funs([{MFA, {FileLine, Contract, _Xtra}}|Left],
				   Plt, RecDict, FindOpaques, Acc) ->
  case dialyzer_plt:lookup(Plt, MFA) of
    none ->
      %% This must be a contract for a non-available function. Just accept it.
      get_invalid_contract_warnings_funs(Left, Plt, RecDict, FindOpaques, Acc);
    {value, {Ret, Args}} ->
      Sig = erl_types:t_fun(Args, Ret),
      {M, _F, _A} = MFA,
      %% io:format("MFA ~p~n", [MFA]),
      Opaques = FindOpaques(M),
      {File, Line} = FileLine,
      WarningInfo = {File, Line, MFA},
      NewAcc =
	case check_contract(Contract, Sig, Opaques) of
	  {error, invalid_contract} ->
	    [invalid_contract_warning(MFA, WarningInfo, Sig, RecDict)|Acc];
	  {error, {overlapping_contract, []}} ->
	    [overlapping_contract_warning(MFA, WarningInfo)|Acc];
	  {error, {extra_range, ExtraRanges, STRange}} ->
	    Warn =
	      case t_from_forms_without_remote(Contract#contract.forms,
					       MFA, RecDict) of
		{ok, NoRemoteType} ->
		  CRet = erl_types:t_fun_range(NoRemoteType),
		  erl_types:t_is_subtype(ExtraRanges, CRet);
		unsupported ->
		  true
	      end,
	    case Warn of
	      true ->
		[extra_range_warning(MFA, WarningInfo, ExtraRanges, STRange)|Acc];
	      false ->
		Acc
	    end;
	  {error, Msg} ->
	    [{?WARN_CONTRACT_SYNTAX, WarningInfo, Msg}|Acc];
	  ok ->
	    {M, F, A} = MFA,
	    CSig0 = get_contract_signature(Contract),
	    CSig = erl_types:subst_all_vars_to_any(CSig0),
	    case erl_bif_types:is_known(M, F, A) of
	      true ->
		%% This is strictly for contracts of functions also in
		%% erl_bif_types
		BifArgs = erl_bif_types:arg_types(M, F, A),
		BifRet = erl_bif_types:type(M, F, A),
		BifSig = erl_types:t_fun(BifArgs, BifRet),
		case check_contract(Contract, BifSig, Opaques) of
		  {error, _} ->
		    [invalid_contract_warning(MFA, WarningInfo, BifSig, RecDict)
		     |Acc];
		  ok ->
		    picky_contract_check(CSig, BifSig, MFA, WarningInfo,
					 Contract, RecDict, Acc)
		end;
	      false ->
		picky_contract_check(CSig, Sig, MFA, WarningInfo, Contract,
				     RecDict, Acc)
	    end
	end,
      get_invalid_contract_warnings_funs(Left, Plt, RecDict, FindOpaques, NewAcc)
  end;
get_invalid_contract_warnings_funs([], _Plt, _RecDict, _FindOpaques, Acc) ->
  Acc.

invalid_contract_warning({M, F, A}, WarningInfo, SuccType, RecDict) ->
  SuccTypeStr = dialyzer_utils:format_sig(SuccType, RecDict),
  {?WARN_CONTRACT_TYPES, WarningInfo, {invalid_contract, [M, F, A, SuccTypeStr]}}.

overlapping_contract_warning({M, F, A}, WarningInfo) ->
  {?WARN_CONTRACT_TYPES, WarningInfo, {overlapping_contract, [M, F, A]}}.

extra_range_warning({M, F, A}, WarningInfo, ExtraRanges, STRange) ->
  ERangesStr = erl_types:t_to_string(ExtraRanges),
  STRangeStr = erl_types:t_to_string(STRange),
  {?WARN_CONTRACT_SUPERTYPE, WarningInfo,
   {extra_range, [M, F, A, ERangesStr, STRangeStr]}}.

picky_contract_check(CSig0, Sig0, MFA, WarningInfo, Contract, RecDict, Acc) ->
  CSig = erl_types:t_abstract_records(CSig0, RecDict),
  Sig = erl_types:t_abstract_records(Sig0, RecDict),
  case erl_types:t_is_equal(CSig, Sig) of
    true -> Acc;
    false ->
      case (erl_types:t_is_none(erl_types:t_fun_range(Sig)) andalso
	    erl_types:t_is_unit(erl_types:t_fun_range(CSig))) of
	true -> Acc;
	false ->
	  case extra_contract_warning(MFA, WarningInfo, Contract,
				      CSig0, Sig0, RecDict) of
	    no_warning -> Acc;
	    {warning, Warning} -> [Warning|Acc]
	  end
      end
  end.

extra_contract_warning(MFA, WarningInfo, Contract, CSig, Sig, RecDict) ->
  {IsRemoteTypesRelated, SubtypeRelation} =
    is_remote_types_related(Contract, CSig, Sig, MFA, RecDict),
  case IsRemoteTypesRelated of
    true ->
      no_warning;
    false ->
      {M, F, A} = MFA,
      SigString = lists:flatten(dialyzer_utils:format_sig(Sig, RecDict)),
      ContractString = contract_to_string(Contract),
      {Tag, Msg} =
	case SubtypeRelation of
	  contract_is_subtype ->
	    {?WARN_CONTRACT_SUBTYPE,
	     {contract_subtype, [M, F, A, ContractString, SigString]}};
	  contract_is_supertype ->
	    {?WARN_CONTRACT_SUPERTYPE,
	     {contract_supertype, [M, F, A, ContractString, SigString]}};
	  neither ->
	    {?WARN_CONTRACT_NOT_EQUAL,
	     {contract_diff, [M, F, A, ContractString, SigString]}}
	end,
      {warning, {Tag, WarningInfo, Msg}}
  end.

is_remote_types_related(Contract, CSig, Sig, MFA, RecDict) ->
  case erl_types:t_is_subtype(CSig, Sig) of
    true ->
      {false, contract_is_subtype};
    false ->
      case erl_types:t_is_subtype(Sig, CSig) of
	true ->
	  case t_from_forms_without_remote(Contract#contract.forms, MFA,
                                           RecDict) of
	    {ok, NoRemoteTypeSig} ->
	      case blame_remote(CSig, NoRemoteTypeSig, Sig) of
		true ->
		  {true, neither};
		false ->
		  {false, contract_is_supertype}
	      end;
	    unsupported ->
	      {false, contract_is_supertype}
	  end;
	false ->
	  {false, neither}
      end
  end.

t_from_forms_without_remote([{FType, []}], MFA, RecDict) ->
  Site = {spec, MFA},
  {Type1, _} = erl_types:t_from_form_without_remote(FType, Site, RecDict),
  {ok, erl_types:subst_all_vars_to_any(Type1)};
t_from_forms_without_remote([{_FType, _Constrs}], _MFA, _RecDict) ->
  %% 'When' constraints
  unsupported;
t_from_forms_without_remote(_Forms, _MFA, _RecDict) ->
  %% Lots of forms
  unsupported.

blame_remote(ContractSig, NoRemoteContractSig, Sig) ->
  CArgs  = erl_types:t_fun_args(ContractSig),
  CRange = erl_types:t_fun_range(ContractSig),
  NRArgs = erl_types:t_fun_args(NoRemoteContractSig),
  NRRange = erl_types:t_fun_range(NoRemoteContractSig),
  SArgs = erl_types:t_fun_args(Sig),
  SRange = erl_types:t_fun_range(Sig),
  blame_remote_list([CRange|CArgs], [NRRange|NRArgs], [SRange|SArgs]).

blame_remote_list([], [], []) ->
  true;
blame_remote_list([CArg|CArgs], [NRArg|NRArgs], [SArg|SArgs]) ->
  case erl_types:t_is_equal(CArg, NRArg) of
    true ->
      case not erl_types:t_is_equal(CArg, SArg) of
	true  -> false;
	false -> blame_remote_list(CArgs, NRArgs, SArgs)
      end;
    false ->
      case erl_types:t_is_subtype(SArg, NRArg)
	andalso not erl_types:t_is_subtype(NRArg, SArg) of
	true  -> false;
	false -> blame_remote_list(CArgs, NRArgs, SArgs)
      end
  end.
