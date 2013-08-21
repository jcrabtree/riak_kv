-module(riak_kv_mutator_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-export([mutate_put/2, mutate_get/1]).

functionaltiy_test_() ->
    {foreach, fun() ->
        purge_data_dir(),
        {ok, Pid} = riak_core_metadata_manager:start_link([{data_dir, "test_data"}]),
        Pid
    end,
    fun(Pid) ->
        unlink(Pid),
        exit(Pid, kill),
        Mon = erlang:monitor(process, Pid),
        receive
            {'DOWN', Mon, process, Pid, _Why} ->
                ok
        end,
        purge_data_dir()
    end, [

        fun(_) -> {"register a mutator", fun() ->
            Got = riak_kv_mutator:register(fake_module),
            ?assertEqual(ok, Got)
        end} end,

        fun(_) -> {"retrieve mutators", fun() ->
            ok = riak_kv_mutator:register(fake_module),
            ok = riak_kv_mutator:register(fake_module_2),
            Got = riak_kv_mutator:get(),
            ?assertEqual({ok, [fake_module, fake_module_2]}, Got)
        end} end,

        fun(_) -> {"retrieve an empty list of mutators", fun() ->
            Got = riak_kv_mutator:get(),
            ?assertEqual({ok, []}, Got)
        end} end,

        fun(_) -> {"unregister", fun() ->
            ok = riak_kv_mutator:register(fake_module),
            Got1 = riak_kv_mutator:unregister(fake_module),
            ?assertEqual(ok, Got1),
            Got2 = riak_kv_mutator:get(),
            ?assertEqual({ok, []}, Got2)
        end} end,

        fun(_) -> {"mutate a put", fun() ->
            Object = riak_object:new(<<"bucket">>, <<"key">>, <<"original_data">>, dict:from_list([{<<"mutations">>, 0}])),
            riak_kv_mutator:register(?MODULE),
            Got = riak_kv_mutator:mutate_put(Object, [{<<"bucket_prop">>, <<"bprop">>}]),
            ExpectedVal = <<"mutatedbprop">>,
            ExpectedMetaMutations = 1,
            ?assertEqual(ExpectedVal, riak_object:get_value(Got)),
            ?assertEqual(ExpectedMetaMutations, dict:fetch(<<"mutations">>, riak_object:get_metadata(Got)))
        end} end,

        fun(_) -> {"do not mutate on get if not mutated on put", fun() ->
            Data = <<"original_data">>,
            Object = riak_object:new(<<"bucket">>, <<"key">>, Data, dict:from_list([{<<"mutations">>, 0}])),
            riak_kv_mutator:register(?MODULE),
            Got = riak_kv_mutator:mutate_get(Object),
            ?assertEqual(Data, riak_object:get_value(Got)),
            ?assertEqual(0, dict:fetch(<<"mutations">>, riak_object:get_metadata(Got)))

        end} end,

        fun(_) -> {"mutate a get", fun() ->
            riak_kv_mutator:register(?MODULE),
            Object = riak_object:new(<<"bucket">>, <<"key">>, <<"original_data">>, dict:from_list([{<<"mutations">>, 0}])),
            Object2 = riak_kv_mutator:mutate_put(Object, [{<<"bucket_prop">>, <<"warble">>}]),
            Object3 = riak_kv_mutator:mutate_get(Object2),
            ExpectedVal = <<"mutated">>,
            ExpectedMetaMutations = 2,
            ?assertEqual(ExpectedVal, riak_object:get_value(Object3)),
            ?assertEqual(ExpectedMetaMutations, dict:fetch(<<"mutations">>, riak_object:get_metadata(Object3)))
        end} end

    ]}.

purge_data_dir() ->
    {ok, CWD} = file:get_cwd(),
    DataDir = filename:join(CWD, "test_data"),
    DataFiles = filename:join([DataDir, "*"]),
    [file:delete(File) || File <- filelib:wildcard(DataFiles)],
    file:del_dir(DataDir).

mutate_put(Object, BucketProps) ->
    mutate(Object, BucketProps).

mutate_get(Object) ->
    mutate(Object, []).

mutate(Object, BucketProps) ->
    NewVal = case proplists:get_value(<<"bucket_prop">>, BucketProps) of
        BProp when is_binary(BProp) ->
            <<"mutated", BProp/binary>>;
        _ ->
            <<"mutated">>
    end,
    Meta = riak_object:get_metadata(Object),
    Mutations = case dict:find(<<"mutations">>, Meta) of
        {ok, N} when is_integer(N) ->
            N + 1;
        _ ->
            0
    end,
    Meta2 = dict:store(<<"mutations">>, Mutations, Meta),
    Object2 = riak_object:update_value(Object, NewVal),
    Object3 = riak_object:update_metadata(Object2, Meta2),
    riak_object:apply_updates(Object3).

-endif.