%% -------------------------------------
%% QuickCheck properties and generators
%% for the edn grammar
%% -------------------------------------
-module(edn_eqc).

-ifdef(EQC).
-include("edn.hrl").
-include_lib("eqc/include/eqc.hrl").
-include_lib("eunit/include/eunit.hrl").
-import(edn, [ unescape/1, parse/1 ]).

-compile(export_all).

gen_string() ->
    ?LET(Str, list(gen_string_char()),
         ?to_utf8([$", Str, $"])).

gen_string_char() ->
    oneof([?SUCHTHAT(C, utf8_char(), C =/= $" andalso C =/= $\\), gen_escape_char()]).

gen_escape_char() ->
    oneof([<<"\\t">>, <<"\\r">>, <<"\\n">>, <<"\\\"">>]).

%% Borrowed from erlang_protobuffs, generates a valid UTF8 char
utf8_char() ->
    elements([choose(0, 36095),
              choose(57344, 65533),
              choose(65536, 1114111)]).

gen_symbol() ->
    frequency([ {1, gen_leading_slash_symbol()}, {5, gen_normal_symbol()} ]).

gen_leading_slash_symbol() ->
    ?LET(Chars, list(gen_symbol_char()), ?to_utf8([<<"/">>, Chars])).

gen_normal_symbol() ->
    frequency([{2, gen_simple_symbol()},
           {1, gen_trailing_slash_symbol()},
           {2, gen_embedded_slash_symbol()}]).

gen_simple_symbol() ->
    ?LET({H,T},
         {oneof([
                 [ oneof([$., $-]), list(gen_non_numeric_with_punct()) ],
                 list(gen_non_numeric())
                ]),
          list(gen_symbol_char())},
         ?to_utf8([H,T])).

gen_trailing_slash_symbol() ->
    ?LET(Sym, gen_simple_symbol(), ?to_utf8([Sym, $/])).

gen_embedded_slash_symbol() ->
    ?LET({H,T},
         {gen_simple_symbol(), list(gen_symbol_char())},
         ?to_utf8([H, $/, T])).

gen_non_numeric() ->
    oneof([$., $$, $+, $!, $-, $_, $?] ++
          lists:seq($A, $Z) ++
          lists:seq($a, $z)).

gen_non_numeric_with_punct() ->
    oneof([$., $$, $+, $!, $-, $_, $?, $#, $:] ++
          lists:seq($A, $Z) ++
          lists:seq($a, $z)).

gen_symbol_char() ->
    oneof([$., $$, $+, $!, $-, $_, $?, $#, $:] ++
          lists:seq($A, $Z) ++
          lists:seq($a, $z) ++
          lists:seq($0, $9)).

%% Generates 'nil'.
gen_nil() ->
    <<"nil">>.

%% Generates a boolean value, optionally surrounded by whitespace.
gen_bool() ->
    oneof([<<"true">>, <<"false">>]).

%% Generates whitespace.
gen_ws() ->
    ?LET(X,
         list(oneof([9, 10, 11, 12, 13, 32, $,])),
         ?to_utf8(X)).

%% Generates random whitespace around another generator
ws_wrap(Gen) ->
    ?LET({LWS, V, TWS},
         {gen_ws(), Gen, gen_ws()},
         ?to_utf8([LWS, V, TWS])).

%% Elements are generally separated by whitespace. Whitespace is not
%% otherwise significant, nor need redundant whitespace be preserved
%% during transmissions. Commas "," are also considered whitespace,
%% other than within strings.
prop_whitespace() ->
    ?FORALL(Spaces, gen_ws(),
                    ok == ?assertThrow({edn,empty}, parse(Spaces))).

%% true and false should be mapped to booleans.
prop_bool() ->
    ?FORALL(Boolean, ws_wrap(gen_bool()),
            lists:member(parse(Boolean), [true, false])).

%% nil represents nil, null or nothing. It should be read as an object
%% with similar meaning on the target platform.
prop_nil() ->
    ?FORALL(Nil, ws_wrap(gen_nil()),
            nil == parse(Nil)).

prop_unescape() ->
    ?FORALL(Char, gen_escape_char(),
            lists:member(unescape(Char), [<<"\t">>, <<"\r">>, <<"\n">>, <<"\"">>])).

%% Strings are enclosed in "double quotes". May span multiple lines.
%% Standard C/Java escape characters \t \r \n are supported.
prop_string() ->
    ?FORALL(String, ws_wrap(gen_string()),
            is_binary(parse(String))).

% Symbols are used to represent identifiers, and should map to
% something other than strings, if possible.
%
% Symbols begin with a non-numeric character and can contain
% alphanumeric characters and . * + ! - _ ?. If - or . are the first
% character, the second character must be non-numeric. Additionally, :
% # are allowed as constituent characters in symbols but not as the
% first character.
%
% / has special meaning in symbols. It can be used once only in the
% middle of a symbol to separate the prefix (often a namespace) from
% the name, e.g. my-namespace/foo. / by itself is a legal symbol.
prop_symbol() ->
    ?FORALL(Symbol, ws_wrap(non_empty(gen_symbol())),
            is_atom(parse(Symbol))).
-endif.
