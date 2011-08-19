module youkei.dpegparser;

import std.traits;
import std.typecons;
import std.functional;

ReturnType!fun memoizeInput(alias fun)(stringp input){
    static ReturnType!fun[size_t] memo;
    auto p = cast(size_t)input.str.ptr in memo;
    if(p){
        return *p;
    }
    auto res = fun(input);
    memo[cast(size_t)input.str.ptr] = res;
    return res;
}

alias Tuple!() None;

struct stringp{
    invariant(){
        assert(line >= 0);
        assert(column >= 0);
    }

    const immutable(char) opIndex(size_t i){
        return str[i];
    }

    const typeof(this) opSlice(size_t x, size_t y){
        typeof(return) res;
        res.str = str[x..y];
        res.line = line;
        res.column = column;
        for(size_t i; i < x; i++){
            if(str[i] == '\n'){
                res.line++;
                res.column = 0;
            }else{
                res.column++;
            }
        }
        return res;
    }

    bool opEquals(T)(T rhs)if(is(T == string)){
        return str == rhs;
    }

    @property size_t length(){
        return str.length;
    }

    dchar decode(ref size_t i){
        return .decode(str, i);
    }

    @property string to(){
        return str;
    }

    string str;
    int line;
    int column;
}

struct Result(T){
	bool match;
	T value;
	stringp rest;
	Error error;

	void opAssign(F)(Result!F rhs) if(isAssignable!(T, F)){
		match = rhs.match;
		value = rhs.value;
		rest = rhs.rest;
		error = rhs.error;
	}
}

struct Option(T){
	T value;
	bool some;
	bool opCast(E)() if(is(E == bool)){
		return some;
	}
}

struct Error{
}

/*combinators*/version(all){
	UnTuple!(CombinateSequenceImplType!parsers) combinateSequence(parsers...)(stringp input){
		static assert(staticLength!parsers > 0);
		return unTuple(combinateSequenceImpl!parsers(input));
	}

	private CombinateSequenceImplType!parsers combinateSequenceImpl(parsers...)(stringp input){
		typeof(return) res;
		static if(staticLength!parsers == 1){
			auto r = parsers[0](input);
			if(r.match){
				res.match = true;
				static if(isTuple!(ParserType!(parsers[0]))){
					res.value = r.value;
				}else{
					res.value = tuple(r.value);
				}
				res.rest = r.rest;
			}
			return res;
		}else{
			auto r1 = parsers[0](input);
			if(r1.match){
				auto r2 = combinateSequenceImpl!(parsers[1..$])(r1.rest);
				if(r2.match){
					res.match = true;
					static if(isTuple!(ParserType!(parsers[0]))){
						res.value = tuple(r1.value.field, r2.value.field);
					}else{
						res.value = tuple(r1.value, r2.value.field);
					}
					res.rest = r2.rest;
				}
			}
			return res;
		}
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = combinateSequence!(
				parseString!("hello"),
				parseString!("world")
			)("helloworld".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value[0] == "hello");
			assert(r.value[1] == "world");
			auto r2 = combinateSequence!(
				combinateSequence!(
					parseString!("hello"),
					parseString!("world")
				),
				parseString!"!"
			)("helloworld!".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(r2.value[0] == "hello");
			assert(r2.value[1] == "world");
			assert(r2.value[2] == "!");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!(CommonParserType!parsers) combinateChoice(parsers...)(stringp input){
		static assert(staticLength!parsers > 0);
		static if(staticLength!parsers == 1){
			return parsers[0](input);
		}else{
			typeof(return) res;
			auto r1 = parsers[0](input);
			if(r1.match){
				res = r1;
				return res;
			}
			auto r2 = combinateChoice!(parsers[1..$])(input);
			if(r2.match){
				res = r2;
				return res;
			}
			return res;
		}
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateChoice!(parseString!"h",parseString!"w") p;
			auto r1 = p("hw".s);
			assert(r1.match);
			assert(r1.rest == "w");
			assert(r1.value == "h");
			auto r2 = p("w".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(r2.value == "w");
			auto r3 = p("".s);
			assert(!r3.match);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!(ParserType!parser[]) combinateMore(int n, alias parser, alias sep = parseString!"")(stringp input){
		typeof(return) res;
		res.rest = input;
		while(true){
			auto r1 = parser(res.rest);
			if(r1.match){
				res.value = res.value ~ r1.value;
				res.rest = r1.rest;
				auto r2 = sep(r1.rest);
				if(r2.match){
					res.rest = r2.rest;
				}else{
					break;
				}
			}else{
				break;
			}
		}
		if(res.value.length >= n){
			res.match = true;
		}
		return res;
	}

	template combinateMore0(alias parser, alias sep = parseString!""){
		alias combinateMore!(0, parser, sep) combinateMore0;
	}

	template combinateMore1(alias parser, alias sep = parseString!""){
		alias combinateMore!(1, parser, sep) combinateMore1;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateMore!(0, parseString!"w") p;
			auto r1 = p("wwwwwwwww w".s);
			assert(r1.match);
			assert(r1.rest == " w");
			assert(r1.value.mkString() == "wwwwwwwww");
			auto r2 = p(" w".s);
			assert(r2.match);
			assert(r2.rest == " w");
			assert(r2.value.mkString == "");
			alias combinateMore!(1, parseString!"w") p2;
			auto r3 = p2("wwwwwwwww w".s);
			assert(r3.match);
			assert(r3.rest == " w");
			assert(r3.value.mkString() == "wwwwwwwww");
			auto r4 = p2(" w".s);
			assert(!r4.match);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!(Option!(ParserType!parser)) combinateOption(alias parser)(stringp input){
		typeof(return) res;
		res.rest = input;
		res.match = true;
		auto r = parser(input);
		if(r.match){
			res.value.value = r.value;
			res.value.some = true;
			res.rest = r.rest;
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateOption!(parseString!"w") p;
			auto r1 = p("w".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value.some);
			assert(r1.value.value == "w");
			auto r2 = p("".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(!r2.value.some);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!None combinateNone(alias parser)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			res.match = true;
			res.rest = r.rest;
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateSequence!(combinateNone!(parseString!"("), parseString!"w", combinateNone!(parseString!")")) p;
			auto r1 = p("(w)".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value == "w");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!None combinateAnd(alias parser)(stringp input){
		typeof(return) res;
		res.rest = input;
		res.match = parser(input).match;
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateMore!(0, combinateSequence!(parseString!"w", combinateAnd!(parseString!"w"))) p;
			auto r1 = p("www".s);
			assert(r1.match);
			assert(r1.rest == "w");
			assert(r1.value.mkString() == "ww");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!None combinateNot(alias parser)(stringp input){
		typeof(return) res;
		res.rest = input;
		res.match = !parser(input).match;
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateMore!(0, combinateSequence!(parseString!"w", combinateNot!(parseString!"s"))) p;
			auto r1 = p("wwws".s);
			assert(r1.match);
			assert(r1.rest == "ws");
			assert(r1.value.mkString() == "ww");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!(ReturnType!(converter)) combinateConvert(alias parser, alias converter)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			res.match = true;
			static if(isTuple!(ParserType!parser)){
				res.value = converter(r.value.field);
			}else{
				res.value = converter(r.value);
			}
			res.rest = r.rest;
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateConvert!(
				combinateMore!(0, parseString!"w"),
				function(string[] ws){
					return ws.length;
				}
			) p;
			auto r1 = p("www".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value == 3);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!(ParserType!parser) combinateCheck(alias parser, alias checker)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match && checker(r.value)){
			res = r;
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
			alias combinateConvert!(
				combinateCheck!(
					combinateMore!(0, parseString!"w"),
					function(string[] ws){
						return ws.length == 5;
					}
				),
				function(string[] ws){
					return ws.mkString();
				}
			) p;
			auto r1 = p("wwwww".s);
			assert(r1.match);
			assert(r1.value == "wwwww");
			assert(r1.rest == "");
			auto r2 = p("wwww".s);
			assert(!r2.match);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}
}

/*parsers*/version(all){
	Result!(string) parseString(string str)(stringp input){
		typeof(return) res;
		if(!str.length){
			res.match = true;
			res.rest = input;
		}else if(input.length >= str.length && input[0..str.length] == str){
		    res.match = true;
		    res.value = str;
		    res.rest = input[str.length..input.length];
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseString!"hello"("hello world".s);
            assert(r.match);
            assert(r.rest == " world");
            assert(r.value == "hello");
            return true;
        };
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	Result!string parseCharRange(dchar low, dchar high)(stringp input){
		typeof(return) res;
		res.rest = input;
		if(input.length > 0){
		    size_t i;
			dchar c = input.decode(i);
			if(low <= c && c <= high){
				res.match = true;
				res.value = input[0..i].to;
				res.rest = input[i..input.length];
			}
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseCharRange!('a', 'z')("hoge".s);
            assert(r.match);
            assert(r.rest == "oge");
            assert(r.value == "h");
            auto r2 = parseCharRange!('\u0100', '\U0010FFFF')("はろーわーるど".s);
            assert(r2.match);
            assert(r2.rest == "ろーわーるど");
            assert(r2.value == "は");
            auto r3 = parseCharRange!('\u0100', '\U0010FFFF')("hello world".s);
            assert(!r3.match);
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	Result!string parseAnyChar(stringp input){
		typeof(return) res;
		res.rest = input;
		if(input.length > 0){
		    size_t i;
		    input.decode(i);
			res.match = true;
			res.value = input[0..i].to;
			res.rest = input[i..input.length];
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseAnyChar("hoge".s);
            assert(r.match);
            assert(r.rest == "oge");
            assert(r.value == "h");
            auto r2 = parseAnyChar("欝だー".s);
            assert(r2.match);
            assert(r2.rest == "だー");
            assert(r2.value == "欝");
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	Result!string parseEscapeSequence(stringp input){
		typeof(return) res;
		res.rest = input;
		if(input.length > 0){
			if(input[0] == '\\'){
				res.match = true;
				auto c = input[1];
				if(c == 'u'){
					res.value = input[0..6].to;
					res.rest = input[6..input.length];
				}else if(c == 'U'){
					res.value = input[0..10].to;
					res.rest = input[10..input.length];
				}else{
					res.value = input[0..2].to;
					res.rest = input[2..input.length];
				}
			}
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseEscapeSequence(`\"hoge`.s);
            assert(r.match);
            assert(r.rest == "hoge");
            assert(r.value == `\"`);
            auto r2 = parseEscapeSequence("\\U0010FFFF".s);
            assert(r2.match);
            assert(r2.rest == "");
            assert(r2.value == "\\U0010FFFF");
            auto r3 = parseEscapeSequence("\\u10FF".s);
            assert(r3.match);
            assert(r3.rest == "");
            assert(r3.value == "\\u10FF");
            auto r4 = parseEscapeSequence("欝".s);
            assert(!r4.match);
            auto r5 = parseEscapeSequence(`\\`.s);
            assert(r5.match);
            assert(r5.rest == "");
            assert(r5.value == `\\`);
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	Result!string parseSpace(stringp input){
		typeof(return) res;
		if(input.length > 0 && (input[0] == ' ' || input[0] == '\n' || input[0] == '\t' || input[0] == '\r' || input[0] == '\f')){
			res.match = true;
			res.value = input[0..1].to;
			res.rest = input[1..input.length];
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseSpace("\thoge".s);
            assert(r.match);
            assert(r.rest == "hoge");
            assert(r.value == "\t");
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	alias combinateNone!(combinateMore0!parseSpace) parseSpaces;

	debug(dpegparser) unittest{
		enum dg = {
            auto r1 = parseSpaces("\t \rhoge".s);
            assert(r1.match);
            assert(r1.rest == "hoge");
            auto r2 = parseSpaces("hoge".s);
            assert(r2.match);
            assert(r2.rest == "hoge");
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}

	Result!None parseEOF(stringp input){
		typeof(return) res;
		if(input.length == 0){
			res.match = true;
		}
		return res;
	}

	debug(dpegparser) unittest{
		enum dg = {
            auto r = parseEOF("".s);
            assert(r.match);
            return true;
		};
        debug(dpegparser_ct) static assert(dg());
        dg();
	}
}

mixin template dpegWithoutMemoize(string src){
	mixin(makeCompilers!false.defs(src.s).value);
}

mixin template dpeg(string src){
	mixin(makeCompilers!true.defs(src.s).value);
}

template getSource(string src){
	enum getSource = makeCompilers!true.defs(src.s);
}

template makeCompilers(bool isMemoize){
    enum prefix = "auto parse(string input){"
        "auto res = root(stringp(input));"
        "if(res.match){"
            "return res.value;"
        "}else{"
            "if(__ctfe){"
                "assert(false, q{parsing failed});"
            "}else{"
                "throw new Exception(q{parsing failed});"
            "}"
        "}"
    "}";

	string fix(string parser){
		return isMemoize ? "memoizeInput!(" ~ parser ~ ")" : parser;
	}

	Result!string defs(stringp input){
		return combinateConvert!(
			combinateSequence!(
				parseSpaces,
				combinateMore1!(
					def,
					parseSpaces
				),
				parseSpaces,
				parseEOF
			),
			function(string[] defs){
				return prefix ~ defs.mkString();
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			string src = q{
				bool hoge = ^"hello" $ >> {return false;};
				Tuple!piyo hoge2 = hoge* >> {return tuple("foo");};
			};
			auto r = defs(src.s);
			assert(r.match);
			assert(r.rest == "");
			static if(isMemoize){
				assert(
					r.value ==
					prefix ~
					"Result!(bool) hoge(stringp input){"
						"return memoizeInput!(combinateConvert!("
							"memoizeInput!(combinateSequence!("
								"memoizeInput!(combinateNone!("
									"memoizeInput!(parseString!\"hello\")"
								")),"
								"memoizeInput!(parseEOF)"
							")),"
							"function(){"
								"return false;"
							"}"
						"))(input);"
					"}"
					"Result!(Tuple!piyo) hoge2(stringp input){"
						"return memoizeInput!(combinateConvert!("
							"memoizeInput!(combinateMore0!("
								"memoizeInput!(hoge)"
							")),"
							"function(){"
								"return tuple(\"foo\");"
							"}"
						"))(input);"
					"}"
				);
			}else{
				assert(
					r.value ==
					prefix ~
					"Result!(bool) hoge(stringp input){"
						"return combinateConvert!("
							"combinateSequence!("
								"combinateNone!("
									"parseString!\"hello\""
								"),"
								"parseEOF"
							"),"
							"function(){"
								"return false;"
							"}"
						")(input);"
					"}"
					"Result!(Tuple!piyo) hoge2(stringp input){"
						"return combinateConvert!("
							"combinateMore0!("
								"hoge"
							"),"
							"function(){"
								"return tuple(\"foo\");"
							"}"
						")(input);"
					"}"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	};

	Result!string def(stringp input){
		return combinateConvert!(
			combinateSequence!(
				typeName,
				parseSpaces,
				id,
				parseSpaces,
				combinateNone!(
					parseString!"="
				),
				parseSpaces,
				convExp,
				parseSpaces,
				combinateNone!(
					parseString!";"
				)
			),
			function(string type, string name, string convExp){
				return "Result!("~type~") "~name~"(stringp input){"
					"return "~convExp~"(input);"
				"}";
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = def(q{bool hoge = ^"hello" $ >> {return false;};}.s);
			assert(r.match);
			assert(r.rest == "");
			static if(isMemoize){
				assert(
					r.value ==
					"Result!(bool) hoge(stringp input){"
						"return memoizeInput!(combinateConvert!("
							"memoizeInput!(combinateSequence!("
								"memoizeInput!(combinateNone!("
									"memoizeInput!(parseString!\"hello\")"
								")),"
								"memoizeInput!(parseEOF)"
							")),"
							"function(){"
								"return false;"
							"}"
						"))(input);"
					"}"
				);
			}else{
				assert(
					r.value ==
					"Result!(bool) hoge(stringp input){"
						"return combinateConvert!("
							"combinateSequence!("
								"combinateNone!("
									"parseString!\"hello\""
								"),"
								"parseEOF"
							"),"
							"function(){"
								"return false;"
							"}"
						")(input);"
					"}"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	};

	Result!string convExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				choiceExp,
				combinateOption!(
					combinateSequence!(
						parseSpaces,
						combinateNone!(
							parseString!">>"
						),
						parseSpaces,
						func
					)
				)
			),
			function(string choiceExp, Option!string func){
				if(func.some){
					return fix("combinateConvert!("~choiceExp~","~func.value~")");
				}else{
					return choiceExp;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = convExp(q{^"hello" $ >> {return false;}}.s);
			assert(r.match);
			assert(r.rest == "");
			static if(isMemoize){
				assert(
					r.value ==
					"memoizeInput!(combinateConvert!("
						"memoizeInput!(combinateSequence!("
							"memoizeInput!(combinateNone!("
								"memoizeInput!(parseString!\"hello\")"
							")),"
							"memoizeInput!(parseEOF)"
						")),"
						"function(){"
							"return false;"
						"}"
					"))"
				);
			}else{
				assert(
					r.value ==
					"combinateConvert!("
						"combinateSequence!("
							"combinateNone!("
								"parseString!\"hello\""
							"),"
							"parseEOF"
						"),"
						"function(){"
							"return false;"
						"}"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string choiceExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				seqExp,
				combinateMore0!(
					combinateSequence!(
						parseSpaces,
						combinateNone!(
							parseString!"/"
						),
						parseSpaces,
						seqExp
					)
				)
			),
			function(string seqExp, string[] seqExps){
				if(seqExps.length){
					return fix("combinateChoice!("~seqExp~","~seqExps.mkString(",")~")");
				}else{
					return seqExp;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = choiceExp(`^$* / (&(!"a"))?`.s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(
					r1.value ==
					"memoizeInput!(combinateChoice!("
						"memoizeInput!(combinateMore0!("
							"memoizeInput!(combinateNone!("
								"memoizeInput!(parseEOF)"
							"))"
						")),"
						"memoizeInput!(combinateOption!("
							"memoizeInput!(combinateAnd!("
								"memoizeInput!(combinateNot!("
									"memoizeInput!(parseString!\"a\")"
								"))"
							"))"
						"))"
					"))"
				);
			}else{
				assert(
					r1.value ==
					"combinateChoice!("
						"combinateMore0!("
							"combinateNone!("
								"parseEOF"
							")"
						"),"
						"combinateOption!("
							"combinateAnd!("
								"combinateNot!("
									"parseString!\"a\""
								")"
							")"
						")"
					")"
				);
			}
			auto r2 = choiceExp(`^"hello" $`.s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(
					r2.value ==
					"memoizeInput!(combinateSequence!("
						"memoizeInput!(combinateNone!("
							"memoizeInput!(parseString!\"hello\")"
						")),"
						"memoizeInput!(parseEOF)"
					"))"
				);
			}else{
				assert(
					r2.value ==
					"combinateSequence!("
						"combinateNone!("
							"parseString!\"hello\""
						"),"
						"parseEOF"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string seqExp(stringp input){
		return combinateConvert!(
			combinateMore1!(
				optionExp,
				parseSpaces
			),
			function(string[] optionExps){
				if(optionExps.length > 1){
					return fix("combinateSequence!("~optionExps.mkString(",")~")");
				}else{
					return optionExps[0];
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = seqExp("^$* (&(!$))?".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(
					r1.value ==
					"memoizeInput!(combinateSequence!("
						"memoizeInput!(combinateMore0!("
							"memoizeInput!(combinateNone!("
								"memoizeInput!(parseEOF)"
							"))"
						")),"
						"memoizeInput!(combinateOption!("
							"memoizeInput!(combinateAnd!("
								"memoizeInput!(combinateNot!("
									"memoizeInput!(parseEOF)"
								"))"
							"))"
						"))"
					"))"
				);
			}else{
				assert(
					r1.value ==
					"combinateSequence!("
						"combinateMore0!("
							"combinateNone!("
								"parseEOF"
							")"
						"),"
						"combinateOption!("
							"combinateAnd!("
								"combinateNot!("
									"parseEOF"
								")"
							")"
						")"
					")"
				);
			}
			enum r2 = seqExp("^\"hello\" $".s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(
					r2.value ==
					"memoizeInput!(combinateSequence!("
						"memoizeInput!(combinateNone!("
							"memoizeInput!(parseString!\"hello\")"
						")),"
						"memoizeInput!(parseEOF)"
					"))"
				);
			}else{
				assert(
					r2.value ==
					"combinateSequence!("
						"combinateNone!("
							"parseString!\"hello\""
						"),"
						"parseEOF"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string optionExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				postExp,
				parseSpaces,
				combinateOption!(
					combinateNone!(
						parseString!"?"
					)
				)
			),
			function(string convExp, Option!None op){
				if(op.some){
					return fix("combinateOption!("~convExp~")");
				}else{
					return convExp;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = optionExp("(&(!\"hello\"))?".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(
					r1.value ==
					"memoizeInput!(combinateOption!("
						"memoizeInput!(combinateAnd!("
							"memoizeInput!(combinateNot!("
								"memoizeInput!(parseString!\"hello\")"
							"))"
						"))"
					"))"
				);
			}else{
				assert(
					r1.value ==
					"combinateOption!("
						"combinateAnd!("
							"combinateNot!("
								"parseString!\"hello\""
							")"
						")"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string postExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				preExp,
				combinateOption!(
					combinateSequence!(
						combinateChoice!(
							parseString!"+",
							parseString!"*"
						),
						combinateOption!(
							combinateSequence!(
								combinateNone!(
									parseString!"<"
								),
								choiceExp,
								combinateNone!(
									parseString!">"
								)
							)
						)
					)
				)
			),
			function(string preExp, Option!(Tuple!(string, Option!string)) op){
				final switch(op.value[0]){
					case "+":
						if(op.value[1].some){
							return fix("combinateMore1!("~preExp~","~op.value[1].value~")");
						}else{
							return fix("combinateMore1!("~preExp~")");
						}
					case "*":
						if(op.value[1].some){
							return fix("combinateMore0!("~preExp~","~op.value[1].value~")");
						}else{
							return fix("combinateMore0!("~preExp~")");
						}
					case "":
						return preExp;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = postExp("^$*".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(
					r1.value ==
					"memoizeInput!(combinateMore0!("
						"memoizeInput!(combinateNone!("
							"memoizeInput!(parseEOF)"
						"))"
					"))"
				);
			}else{
				assert(
					r1.value ==
					"combinateMore0!("
						"combinateNone!("
							"parseEOF"
						")"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string preExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateOption!(
					combinateChoice!(
						parseString!"&",
						parseString!"^",
						parseString!"!"
					)
				),
				primaryExp
			),
			function(Option!string op, string primaryExp){
				final switch(op.value){
					case "&":
						return fix("combinateAnd!("~primaryExp~")");
					case "!":
						return fix("combinateNot!("~primaryExp~")");
					case "^":
						return fix("combinateNone!("~primaryExp~")");
					case "":
						return primaryExp;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = preExp("^$".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(
					r1.value ==
					"memoizeInput!(combinateNone!("
						"memoizeInput!(parseEOF)"
					"))"
				);
			}else{
				assert(
					r1.value ==
					"combinateNone!("
						"parseEOF"
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string primaryExp(stringp input){
		return combinateChoice!(
			literal,
			nonterminal,
			combinateSequence!(
				combinateNone!(
					parseString!"("
				),
				convExp,
				combinateNone!(
					parseString!")"
				)
			)
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			static if(isMemoize){
				auto r1 = primaryExp("(&(!$)?)".s);
				assert(r1.match);
				assert(r1.rest == "");
				assert(
					r1.value ==
					"memoizeInput!(combinateOption!("
						"memoizeInput!(combinateAnd!("
							"memoizeInput!(combinateNot!("
								"memoizeInput!(parseEOF)"
							"))"
						"))"
					"))"
				);
				auto r2 = primaryExp("int".s);
				assert(r2.match);
				assert(r2.rest == "");
				assert(r2.value == "memoizeInput!(int)");
				auto r3 = primaryExp("select!(true)(\"true\", \"false\")".s);
				assert(r3.match);
				assert(r3.rest == "");
				assert(r3.value == "memoizeInput!(select!(true)(\"true\", \"false\"))");
				auto rn = primaryExp("###縺薙・繧ｳ繝｡繝ｳ繝医・陦ｨ遉ｺ縺輔ｌ縺ｾ縺帙ｓ###".s);
				assert(!rn.match);
			}else{
				auto r1 = primaryExp("(&(!$)?)".s);
				assert(r1.match);
				assert(r1.rest == "");
				assert(
					r1.value ==
					"combinateOption!("
						"combinateAnd!("
							"combinateNot!("
								"parseEOF"
							")"
						")"
					")"
				);
				auto r2 = primaryExp("int".s);
				assert(r2.match);
				assert(r2.rest == "");
				assert(r2.value == "int");
				auto r3 = primaryExp("select!(true)(\"true\", \"false\")".s);
				assert(r3.match);
				assert(r3.rest == "");
				assert(r3.value == "select!(true)(\"true\", \"false\")");
				auto rn = primaryExp("###縺薙・繧ｳ繝｡繝ｳ繝医・陦ｨ遉ｺ縺輔ｌ縺ｾ縺帙ｓ###".s);
				assert(!rn.match);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string literal(stringp input){
		return combinateChoice!(
			rangeLit,
			stringLit,
			eofLit,
			usefulLit
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = literal("\"hello\nworld\"".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(parseString!\"hello\nworld\")");
			}else{
				assert(r1.value == "parseString!\"hello\nworld\"");
			}
			auto r2 = literal("[a-z]".s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(r2.value == "memoizeInput!(parseCharRange!('a','z'))");
			}else{
				assert(r2.value == "parseCharRange!('a','z')");
			}
			auto r3 = usefulLit("@space".s);
			assert(r3.match);
			assert(r3.rest == "");
			static if(isMemoize){
				assert(r3.value == "memoizeInput!(parseSpace)");
			}else{
				assert(r3.value == "parseSpace");
			}
			auto r4 = usefulLit("@es".s);
			assert(r4.match);
			assert(r4.rest == "");
			static if(isMemoize){
				assert(r4.value == "memoizeInput!(parseEscapeSequence)");
			}else{
				assert(r4.value == "parseEscapeSequence");
			}
			auto r5 = usefulLit("@a".s);
			assert(r5.match);
			assert(r5.rest == "");
			static if(isMemoize){
				assert(r5.value == "memoizeInput!(parseAnyChar)");
			}else{
				assert(r5.value == "parseAnyChar");
			}
			auto r6 = usefulLit("@s".s);
			assert(r6.match);
			assert(r6.rest == "");
			static if(isMemoize){
				assert(r6.value == "memoizeInput!(parseSpaces)");
			}else{
				assert(r6.value == "parseSpaces");
			}
			auto r7 = literal("$".s);
			assert(r7.match);
			assert(r7.rest == "");
			static if(isMemoize){
				assert(r7.value == "memoizeInput!(parseEOF)");
			}else{
				assert(r7.value == "parseEOF");
			}
			auto rn = literal("###縺薙・繧ｳ繝｡繝ｳ繝医・陦ｨ遉ｺ縺輔ｌ縺ｾ縺帙ｓ###".s);
			assert(!rn.match);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string stringLit(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateNone!(
					parseString!"\""
				),
				combinateMore0!(
					combinateSequence!(
						combinateNot!(
							parseString!"\""
						),
						combinateChoice!(
							parseEscapeSequence,
							parseAnyChar
						)
					)
				),
				combinateNone!(
					parseString!"\""
				)
			),
			function(string[] strs){
				return fix("parseString!\""~strs.mkString()~"\"");
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = stringLit("\"hello\nworld\" ".s);
			assert(r1.match);
			assert(r1.rest == " ");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(parseString!\"hello\nworld\")");
			}else{
				assert(r1.value == "parseString!\"hello\nworld\"");
			}
			auto r2 = stringLit("aa\"".s);
			assert(!r2.match);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string rangeLit(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateNone!(
					parseString!"["
				),
				combinateMore1!(
					combinateSequence!(
						combinateNot!(
							parseString!"]"
						),
						combinateChoice!(
							charRange,
							oneChar
						)
					)
				),
				combinateNone!(
					parseString!"]"
				)
			),
			function(string[] strs){
				if(strs.length == 1){
					return strs[0];
				}else{
					return fix("combinateChoice!("~strs.mkString(",")~")");
				}
			}
		)(input);
	}

	Result!string charRange(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateChoice!(
					parseEscapeSequence,
					parseAnyChar
				),
				combinateNone!(
					parseString!"-"
				),
				combinateChoice!(
					parseEscapeSequence,
					parseAnyChar
				),
			),
			function(string low, string high){
				return fix("parseCharRange!('"~low~"','"~high~"')");
			}
		)(input);
	}

	Result!string oneChar(stringp input){
		return combinateConvert!(
			combinateChoice!(
				parseEscapeSequence,
				parseAnyChar
			),
			function(string c){
				return fix("parseString!\""~c~"\"");
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = rangeLit("[a-z]".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(parseCharRange!('a','z'))");
			}else{
				assert(r1.value == "parseCharRange!('a','z')");
			}
			auto r2 = rangeLit("[a-zA-Z_]".s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(
					r2.value ==
					"memoizeInput!(combinateChoice!("
						"memoizeInput!(parseCharRange!('a','z')),"
						"memoizeInput!(parseCharRange!('A','Z')),"
						"memoizeInput!(parseString!\"_\")"
					"))"
				);
			}else{
				assert(
					r2.value ==
					"combinateChoice!("
						"parseCharRange!('a','z'),"
						"parseCharRange!('A','Z'),"
						"parseString!\"_\""
					")"
				);
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string eofLit(stringp input){
		return combinateConvert!(
			combinateNone!(
				parseString!"$"
			),
			function{
				return fix("parseEOF");
			}
		)(input);
	}

    debug(dpegparser) unittest{
    	enum dg = {
			auto r1 = eofLit("$".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(parseEOF)");
			}else{
				assert(r1.value == "parseEOF");
			}
			auto r2 = eofLit("#".s);
			assert(!r2.match);
			return true;
    	};
    	debug(dpegparser_ct) static assert(dg());
    	dg();
    }

	Result!string usefulLit(stringp input){
		return combinateConvert!(
			combinateChoice!(
				parseString!"@space",
				parseString!"@es",
				parseString!"@a",
				parseString!"@s",
			),
			function(string str){
				final switch(str){
					case "@space":
						return fix("parseSpace");
					case "@es":
						return fix("parseEscapeSequence");
					case "@a":
						return fix("parseAnyChar");
					case "@s":
						return fix("parseSpaces");
				}
			}
		)(input);
	}

    debug(dpegparser) unittest{
    	enum dg = {
			auto r1 = usefulLit("@space".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(parseSpace)");
			} else{
				assert(r1.value == "parseSpace");
			}
			auto r2 = usefulLit("@es".s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(r2.value == "memoizeInput!(parseEscapeSequence)");
			}else{
				assert(r2.value == "parseEscapeSequence");
			}
			auto r3 = usefulLit("@a".s);
			assert(r3.match);
			assert(r3.rest == "");
			static if(isMemoize){
				assert(r3.value == "memoizeInput!(parseAnyChar)");
			}else{
				assert(r3.value == "parseAnyChar");
			}
			auto r4 = usefulLit("@s".s);
			assert(r4.match);
			assert(r4.rest == "");
			static if(isMemoize){
				assert(r4.value == "memoizeInput!(parseSpaces)");
			}else{
				assert(r4.value == "parseSpaces");
			}
			return true;
    	};
    	debug(dpegparser_ct) static assert(dg());
    	dg();
    }

	Result!string id(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateChoice!(
					parseCharRange!('A','Z'),
					parseCharRange!('a','z'),
					parseString!"_"
				),
				combinateMore0!(
					combinateChoice!(
						parseCharRange!('0','9'),
						parseCharRange!('A','Z'),
						parseCharRange!('a','z'),
						parseString!"_",
						parseString!",",
						parseString!"!",
						arch
					)
				)
			),
			function(string str, string[] strs){
				return str ~ strs.mkString();
			}
		)(input);
	}

    debug(dpegparser) unittest{
    	enum dg = {
			auto r1 = id("int".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value == "int");
			auto r2 = id("select!(true)(\"true\", \"false\")".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(r2.value == "select!(true)(\"true\", \"false\")");
			return true;
    	};
    	debug(dpegparser_ct) static assert(dg());
    	dg();
    }

	alias combinateConvert!(id,function(string id){return fix(id);}) nonterminal;

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = nonterminal("int".s);
			assert(r1.match);
			assert(r1.rest == "");
			static if(isMemoize){
				assert(r1.value == "memoizeInput!(int)");
			}else{
				assert(r1.value == "int");
			}
			auto r2 = nonterminal("select!(true)(\"true\", \"false\")".s);
			assert(r2.match);
			assert(r2.rest == "");
			static if(isMemoize){
				assert(r2.value == "memoizeInput!(select!(true)(\"true\", \"false\"))");
			}else{
				assert(r2.value == "select!(true)(\"true\", \"false\")");
			}
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
    }

	Result!string typeName(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateChoice!(
					parseCharRange!('A','Z'),
					parseCharRange!('a','z'),
					parseString!"_"
				),
				parseSpaces,
				combinateMore0!(
					combinateChoice!(
						parseCharRange!('0','9'),
						parseCharRange!('A','Z'),
						parseCharRange!('a','z'),
						parseString!"_",
						parseString!",",
						parseString!"!",
						arch,
						squareArch
					)
				)
			),
			function(string str, string[] strs){
				return str ~ strs.mkString();
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r1 = typeName("int".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value == "int");
			auto r2 = typeName("Tuple!(string, int)".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(r2.value == "Tuple!(string, int)");
			auto r3 = typeName("int[]".s);
			assert(r3.match);
			assert(r3.rest == "");
			assert(r3.value == "int[]");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string func(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateOption!(
					combinateSequence!(
						arch,
						parseSpaces
					)
				),
				brace
			),
			function(Option!string arch, string brace){
				if(arch.some){
					return "function" ~ arch.value ~ brace;
				}else{
					return "function()" ~ brace;
				}
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = func(
			"(int num, string code){"
				"string res;"
				"foreach(staticNum; 0..num){"
					"foreach(c;code){"
						"if(c == '@'){"
							"res ~= to!string(staticNum);"
						"}else{"
							"res ~= c;"
						"}"
					"}"
				"}"
				"return res;"
			"}".s);
			assert(r.match);
			assert(r.rest == "");
			assert(
				r.value ==
				"function(int num, string code){"
					"string res;"
					"foreach(staticNum; 0..num){"
						"foreach(c;code){"
							"if(c == '@'){"
								"res ~= to!string(staticNum);"
							"}else{"
								"res ~= c;"
							"}"
						"}"
					"}"
					"return res;"
				"}"
			);
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string arch(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateNone!(
					parseString!"("
				),
				combinateMore0!(
					combinateChoice!(
						arch,
						combinateSequence!(
							combinateNot!(
								parseString!")"
							),
							parseAnyChar
						)
					)
				),
				combinateNone!(
					parseString!")"
				)
			),
			function(string[] strs){
				return "("~strs.mkString()~")";
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = arch("(a(i(u)e)o())".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "(a(i(u)e)o())");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string squareArch(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateNone!(
					parseString!"["
				),
				combinateMore0!(
					combinateChoice!(
						squareArch,
						combinateSequence!(
							combinateNot!(
								parseString!"]"
							),
							parseAnyChar
						)
					)
				),
				combinateNone!(
					parseString!"]"
				)
			),
			function (string[] strs){
				return "["~strs.mkString()~"]";
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = squareArch("[a[i[u]e]o[]]".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "[a[i[u]e]o[]]");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}

	Result!string brace(stringp input){
		return combinateConvert!(
			combinateSequence!(
				combinateNone!(
					parseString!"{"
				),
				combinateMore0!(
					combinateChoice!(
						brace,
						combinateSequence!(
							combinateNot!(
								parseString!"}"
							),
							parseAnyChar
						)
					)
				),
				combinateNone!(
					parseString!"}"
				)
			),
			function(string[] strs){
				return "{"~strs.mkString()~"}";
			}
		)(input);
	}

	debug(dpegparser) unittest{
		enum dg = {
			auto r = brace("{a{i{u}e}o{}}".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "{a{i{u}e}o{}}");
			return true;
		};
		debug(dpegparser_ct) static assert(dg());
		dg();
	}
}

debug(dpegparser) pragma(msg, makeCompilers!true);
debug(dpegparser) pragma(msg, makeCompilers!false);

debug(dpegparser) void main(){}

private:

stringp s(string str){
    return stringp(str);
}

string mkString(string[] strs, string sep = ""){
	string res;
	foreach(i, str; strs){
		if(i){
			if(sep.length){
				res ~= sep;
			}
		}
		if(str.length){
			res ~= str;
		}
	}
	return res;
	//cocomadefpsgatacaihituy,hanaidar,na
}

template ResultType(alias R){
	static if(is(R Unused == Result!E, E)){
		alias E ResultType;
	}else{
		static assert(false);
	}
}

template ParserType(alias parser){
	static if(is(ReturnType!parser Unused == Result!(T), T)){
		alias T ParserType;
	}else{
		static assert(false);
	}
}

template CombinateSequenceImplType(parsers...){
	static if(staticLength!parsers == 1){
		static if(isTuple!(ParserType!(parsers[0]))){
			alias Result!(ParserType!(parsers[0])) CombinateSequenceImplType;
		}else{
			alias Result!(Tuple!(ParserType!(parsers[0]))) CombinateSequenceImplType;
		}
	}else{
		static if(isTuple!(ParserType!(parsers[0]))){
			alias Result!(Tuple!(ParserType!(parsers[0]).Types, ResultType!(CombinateSequenceImplType!(parsers[1..$])).Types)) CombinateSequenceImplType;
		}else{
			alias Result!(Tuple!(ParserType!(parsers[0]), ResultType!(CombinateSequenceImplType!(parsers[1..$])).Types)) CombinateSequenceImplType;
		}
	}
}

template UnTuple(E){
	static if(staticLength!(ResultType!E.Types) == 1){
		alias Result!(ResultType!E.Types[0]) UnTuple;
	}else{
		alias E UnTuple;
	}
}

UnTuple!R unTuple(R)(R r){
	static if(staticLength!(ResultType!R.Types) == 1){
		return Result!(ResultType!R.Types[0])(r.match, r.value[0], r.rest);
	}else{
		return r;
	}
}

template CommonParserType(parsers...){
	static if(staticLength!parsers == 1){
		alias ParserType!(parsers[0]) CommonParserType;
	}else{
		alias CommonType!(ParserType!(parsers[0]), CommonParserType!(parsers[1..$])) CommonParserType;
	}
}

dchar decode(string str, ref size_t i){
	dchar res;
	if(!(str[i] & 0b_1000_0000)){
		res = str[i];
		i+=1;
		return res;
	}else if(!(str[i] & 0b_0010_0000)){
		res = str[i] & 0b_0001_1111;
		res <<= 6;
		res |= str[i+1] & 0b_0011_1111;
		i+=2;
		return res;
	}else if(!(str[i] & 0b_0001_0000)){
		res = str[i] & 0b_0000_1111;
		res <<= 6;
		res |= str[i+1] & 0b_0011_1111;
		res <<= 6;
		res |= str[i+2] & 0b_0011_1111;
		i+=3;
		return res;
	}else{
		res = str[i] & 0b_0000_0111;
		res <<= 6;
		res |= str[i+1] & 0b_0011_1111;
		res <<= 6;
		res |= str[i+2] & 0b_0011_1111;
		res <<= 6;
		res |= str[i+3] & 0b_0011_1111;
		i+=4;
		return res;
	}
}

debug(dpegparser) public:

unittest{
    struct exp{
        static mixin dpeg!q{
            int root = addExp;

            int addExp = mulExp (("+" / "-")  addExp)? >> (int lhs, Option!(Tuple!(string, int)) rhs){
                if(rhs.some){
                    final switch(rhs.value[0]){
                        case "+":
                            return lhs + rhs.value[1];
                        case "-":
                            return lhs - rhs.value[1];
                    }
                }else{
                    return lhs;
                }
            };

            int mulExp = primary (("*" / "/")  mulExp)? >> (int lhs, Option!(Tuple!(string, int)) rhs){
                if(rhs.some){
                    final switch(rhs.value[0]){
                        case "*":
                            return lhs * rhs.value[1];
                        case "/":
                            return lhs / rhs.value[1];
                    }
                }else{
                    return lhs;
                }
            };

            int primary = ^"(" addExp ^")" / num;

            int num = [0-9]+ >> (string[] nums){
                int result;
                foreach(i, num;nums){
                    result = result * 10 + (num[0] - '0');
                }
                return result;
            };
        };
    }

    struct recursive{
        static mixin dpeg!q{
            None root = A $;
            None A = ^"a" ^A ^"a" / ^"a";
        };
    }

	assert( exp.parse("5*8+3*20") == 100);
	assert( exp.parse("5*(8+3)*20") == 1100);
	assert( recursive.root("a".s).match);
	assert( recursive.root("aaa".s).match);
	assert(!recursive.root("aaaaa".s).match);
	assert( recursive.root("aaaaaaa".s).match);
	assert(!recursive.root("aaaaaaaaa".s).match);
	assert(!recursive.root("aaaaaaaaaaa".s).match);
	assert(!recursive.root("aaaaaaaaaaaaa".s).match);
    assert( recursive.root("aaaaaaaaaaaaaaa".s).match);
}