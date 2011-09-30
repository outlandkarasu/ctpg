module youkei.ctpg;

import std.conv;
import std.traits;
import std.typecons;
import std.typetuple;
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

	immutable(char) opIndex(size_t i)const @safe pure nothrow{
		return str[i];
	}

	typeof(this) opSlice(size_t x, size_t y)const @safe pure nothrow{
		typeof(return) res;
		res.str = str[x..y];
		res.line = line;
		res.column = column;
		for(size_t i; i < x; i++){
			if(str[i] == '\n'){
				res.line++;
				res.column = 1;
			}else{
				res.column++;
			}
		}
		return res;
	}

	bool opEquals(T)(T rhs)const pure @safe nothrow if(is(T == string)){
		return str == rhs;
	}

	size_t length()const pure @safe nothrow @property{
		return str.length;
	}

	dchar decode(ref size_t i)const pure @safe nothrow{
		return .decode(str, i);
	}

	string to()pure @safe nothrow @property{
		return str;
	}

	string str;
	int line = 1;
	int column = 1;
}

debug(ctpg) unittest{
	enum dg = {
		auto s1 = "hoge".s;
		assert(s1 == "hoge");
		assert(s1.line == 1);
		assert(s1.column == 1);
		auto s2 = s1[1..s1.length];
		assert(s2 == "oge");
		assert(s2.line == 1);
		assert(s2.column == 2);
		auto s3 = s2[s2.length..s2.length];
		assert(s3 == "");
		assert(s3.line == 1);
		assert(s3.column == 5);
		auto s4 = "メロスは激怒した。".s;
		auto s5 = s4[3..s4.length];
		assert(s5 == "ロスは激怒した。");
		assert(s5.line == 1);
		assert(s5.column == 4);//TODO: column should be 2
		auto s6 = ("hoge\npiyo".s)[5..9];
		assert(s6 == "piyo");
		assert(s6.line == 2);
		assert(s6.column == 1);
		return true;
	};
	debug(ctpg_ct) static assert(dg());
	dg();
}

struct Result(T){
	bool match;
	T value;
	stringp rest;
	Error error;

	void opAssign(F)(Result!F rhs)pure @safe nothrow if(isAssignable!(T, F)){
		match = rhs.match;
		value = rhs.value;
		rest = rhs.rest;
		error = rhs.error;
	}
}

struct Option(T){
	T value;
	bool some;
	bool opCast(E)()const if(is(E == bool)){
		return some;
	}
}

struct Error{
	invariant(){
		assert(line >= 1);
		assert(column >= 1);
	}

	string need;
	int line;
	int column;
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
			}else{
				res.error = r.error;
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
				}else{
					res.error = r2.error;
				}
			}else{
				res.error = r1.error;
			}
			return res;
		}
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				auto r = combinateSequence!(
					parseString!("hello"),
					parseString!("world")
				)("helloworld".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value[0] == "hello");
				assert(r.value[1] == "world");
			}
			{
				auto r = combinateSequence!(
					combinateSequence!(
						parseString!("hello"),
						parseString!("world")
					),
					parseString!"!"
				)("helloworld!".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value[0] == "hello");
				assert(r.value[1] == "world");
				assert(r.value[2] == "!");
			}
			{
				auto r = combinateSequence!(
					parseString!("hello"),
					parseString!("world")
				)("hellovvorld".s);
				assert(!r.match);
				assert(r.rest == "");
				assert(r.error.need == q{"world"});
				assert(r.error.line == 1);
				assert(r.error.column == 6);
			}
			{
				auto r = combinateSequence!(
					parseString!("hello"),
					parseString!("world"),
					parseString!("!")
				)("helloworld?".s);
				assert(!r.match);
				assert(r.rest == "");
				assert(r.error.need == q{"!"});
				assert(r.error.line == 1);
				assert(r.error.column == 11);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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
			}else{
				res.error = r1.error;
			}
			auto r2 = combinateChoice!(parsers[1..$])(input);
			if(r2.match){
				res = r2;
				return res;
			}else{
				res.error.need ~= " or " ~ r2.error.need;
			}
			return res;
		}
	}

	debug(ctpg) unittest{
		enum dg = {
			alias combinateChoice!(parseString!"h",parseString!"w") p;
			{
				auto r = p("hw".s);
				assert(r.match);
				assert(r.rest == "w");
				assert(r.value == "h");
			}
			{
				auto r = p("w".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == "w");
			}
			{
				auto r = p("".s);
				assert(!r.match);
				assert(r.rest == "");
				assert(r.error.need == q{"h" or "w"});
				assert(r.error.line == 1);
				assert(r.error.column == 1);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!(ParserType!parser[]) combinateMore(int n, alias parser, alias sep = parseString!"")(stringp input){
		typeof(return) res;
		stringp str = input;
		while(true){
			auto r1 = parser(str);
			if(r1.match){
				res.value = res.value ~ r1.value;
				str = r1.rest;
				auto r2 = sep(str);
				if(r2.match){
					str = r2.rest;
				}else{
					break;
				}
			}else{
				res.error = r1.error;
				break;
			}
		}
		if(res.value.length >= n){
			res.match = true;
			res.rest = str;
		}
		return res;
	}

	template combinateMore0(alias parser, alias sep = parseString!""){
		alias combinateMore!(0, parser, sep) combinateMore0;
	}

	template combinateMore1(alias parser, alias sep = parseString!""){
		alias combinateMore!(1, parser, sep) combinateMore1;
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				alias combinateMore0!(parseString!"w") p;
				{
					auto r = p("wwwwwwwww w".s);
					assert(r.match);
					assert(r.rest == " w");
					assert(r.value.mkString() == "wwwwwwwww");
				}
				{
					auto r = p(" w".s);
					assert(r.match);
					assert(r.rest == " w");
					assert(r.value.mkString == "");
				}
			}
			{
				alias combinateMore1!(parseString!"w") p;
				{
					auto r = p("wwwwwwwww w".s);
					assert(r.match);
					assert(r.rest == " w");
					assert(r.value.mkString() == "wwwwwwwww");
				}
				{
					auto r = p(" w".s);
					assert(!r.match);
					assert(r.rest == "");
					assert(r.error.need == q{"w"});
					assert(r.error.line == 1);
					assert(r.error.column == 1);
				}
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
		enum dg = {
			alias combinateOption!(parseString!"w") p;
			{
				auto r = p("w".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value.some);
				assert(r.value.value == "w");
			}
			{
				auto r = p("".s);
				assert(r.match);
				assert(r.rest == "");
				assert(!r.value.some);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!None combinateNone(alias parser)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			res.match = true;
			res.rest = r.rest;
		}else{
			res.error = r.error;
		}
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				alias combinateSequence!(combinateNone!(parseString!"("), parseString!"w", combinateNone!(parseString!")")) p;
				auto r = p("(w)".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == "w");
			}
			{
				auto r = combinateNone!(parseString!"w")("a".s);
				assert(!r.match);
				assert(r.rest == "");
				assert(r.error.need == q{"w"});
				assert(r.error.line == 1);
				assert(r.error.column == 1);
			}
			{
				alias combinateSequence!(combinateNone!(parseString!"("), parseString!"w", combinateNone!(parseString!")")) p;
				auto r = p("(w}".s);
				assert(!r.match);
				assert(r.rest == "");
				assert(r.error.need == q{")"});
				assert(r.error.line == 1);
				assert(r.error.column == 3);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!None combinateAnd(alias parser)(stringp input){
		typeof(return) res;
		res.rest = input;
		auto r = parser(input);
		res.match = r.match;
		res.error = r.error;
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			alias combinateMore1!(combinateSequence!(parseString!"w", combinateAnd!(parseString!"w"))) p;
			{
				auto r = p("www".s);
				assert(r.match);
				assert(r.rest == "w");
				assert(r.value.mkString() == "ww");
			}
			{
				auto r = p("w".s);
				assert(!r.match);
				assert(r.error.need == q{"w"});
				assert(r.error.line == 1);
				assert(r.error.column == 2);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!None combinateNot(alias parser)(stringp input){
		typeof(return) res;
		res.rest = input;
		res.match = !parser(input).match;
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			alias combinateMore1!(combinateSequence!(parseString!"w", combinateNot!(parseString!"s"))) p;
			auto r = p("wwws".s);
			assert(r.match);
			assert(r.rest == "ws");
			assert(r.value.mkString() == "ww");
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!(ReturnType!(converter)) combinateConvert(alias parser, alias converter)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			res.match = true;
			static if(isTuple!(ParserType!parser)){
				static if(__traits(compiles, converter(r.value.field))){
					res.value = converter(r.value.field);
				}else static if(__traits(compiles, new converter(r.value.field))){
					res.value = new converter(r.value.field);
				}else{
					static assert(false, converter.mangleof ~ " cannot call with argument type " ~ typeof(r.value.field).stringof);
				}
			}else{
				static if(__traits(compiles, converter(r.value))){
					res.value = converter(r.value);
				}else static if(__traits(compiles, new converter(r.value))){
					res.value = new converter(r.value);
				}else{
					static assert(false, converter.mangleof ~ " cannot call with argument type " ~ typeof(r.value).stringof);
				}
			}
			res.rest = r.rest;
		}else{
			res.error = r.error;
		}
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			alias combinateConvert!(
				combinateMore1!(parseString!"w"),
				function(string[] ws)@safe pure nothrow{
					return ws.length;
				}
			) p;
			{
				auto r = p("www".s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == 3);
			}
			{
				auto r = p("a".s);
				assert(!r.match);
				assert(r.error.need == q{"w"});
				assert(r.error.line == 1);
				assert(r.error.column == 1);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!(ParserType!parser) combinateCheck(alias parser, alias checker)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			if(checker(r.value)){
				res = r;
			}else{
				res.error = Error("passing check", input.line, input.column);
			}
		}else{
			res.error = r.error;
		}
		return res;
	}

	debug(ctpg) unittest{
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
			{
				auto r = p("wwwww".s);
				assert(r.match);
				assert(r.value == "wwwww");
				assert(r.rest == "");
			}
			{
				auto r = p("wwww".s);
				assert(!r.match);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string combinateString(alias parser)(stringp input){
		typeof(return) res;
		auto r = parser(input);
		if(r.match){
			res.match = true;
			res.value = flat(r.value);
			res.rest = r.rest;
		}else{
			res.error = r.error;
		}
		return res;
	}
}

/*parsers*/version(all){
	Result!(string) parseString(string str)(stringp input)pure @safe nothrow{
		typeof(return) res;
		if(!str.length){
			res.match = true;
			res.rest = input;
			return res;
		}
		if(input.length >= str.length && input[0..str.length] == str){
			res.match = true;
			res.value = str;
			res.rest = input[str.length..input.length];
			return res;
		}
		res.error = Error('"' ~ str ~ '"', input.line, input.column);
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			auto r = parseString!"hello"("hello world".s);
			assert(r.match);
			assert(r.rest == " world");
			assert(r.value == "hello");
			auto r1 = parseString!"hello"("hllo world".s);
			assert(!r1.match);
			assert(r1.rest == "");
			assert(r1.error.need == "\"hello\"");
			assert(r1.error.line == 1);
			assert(r1.error.column == 1);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string parseCharRange(dchar low, dchar high)(stringp input)pure @safe nothrow{
		typeof(return) res;
		if(input.length > 0){
			size_t i;
			dchar c = input.decode(i);
			if(low <= c && c <= high){
				res.match = true;
				res.value = input[0..i].to;
				res.rest = input[i..input.length];
				return res;
			}
		}
		//res.error = Error("c: '" ~ to!string(low) ~ "' <= c <= '" ~ to!string(high) ~ "'", input.line, input.column);
		return res;
	}

	debug(ctpg) unittest{
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
			assert(r3.rest == "");
			//assert(r3.error.need == "c: '\u0100' <= c <= '\U0010FFFF'");
			//assert(r3.error.line == 1);
			//assert(r3.error.column == 1);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string parseAnyChar(stringp input)pure @safe nothrow{
		typeof(return) res;
		res.rest = input;
		if(input.length > 0){
			size_t i;
			input.decode(i);
			res.match = true;
			res.value = input[0..i].to;
			res.rest = input[i..input.length];
		}else{
			res.error = Error("any char", input.line, input.column);
		}
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			auto r = parseAnyChar("hoge".s);
			assert(r.match);
			assert(r.rest == "oge");
			assert(r.value == "h");
			auto r2 = parseAnyChar("欝だー".s);
			assert(r2.match);
			assert(r2.rest == "だー");
			assert(r2.value == "欝");
			auto r3 = parseAnyChar(r2.rest);
			assert(r3.match);
			assert(r3.rest == "ー");
			assert(r3.value == "だ");
			auto r4 = parseAnyChar(r3.rest);
			assert(r4.match);
			assert(r4.rest == "");
			assert(r4.value == "ー");
			auto r5 = parseAnyChar(r4.rest);
			assert(!r5.match);
			assert(r5.error.need == "any char");
			assert(r5.error.line == 1);
			assert(r5.error.column == 10);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string parseEscapeSequence(stringp input)pure @safe nothrow{
		typeof(return) res;
		if(input.length > 0 && input[0] == '\\'){
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
			return res;
		}else{
			res.error = Error("escape sequence", input.line, input.column);
		}
		return res;
	}

	debug(ctpg) unittest{
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
			assert(r4.error.need == "escape sequence");
			assert(r4.error.line == 1);
			assert(r4.error.column == 1);
			auto r5 = parseEscapeSequence(`\\`.s);
			assert(r5.match);
			assert(r5.rest == "");
			assert(r5.value == `\\`);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string parseSpace(stringp input)pure @safe nothrow{
		typeof(return) res;
		if(input.length > 0 && (input[0] == ' ' || input[0] == '\n' || input[0] == '\t' || input[0] == '\r' || input[0] == '\f')){
			res.match = true;
			res.value = input[0..1].to;
			res.rest = input[1..input.length];
		}else{
			res.error = Error("space", input.line, input.column);
		}
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			auto r = parseSpace("\thoge".s);
			assert(r.match);
			assert(r.rest == "hoge");
			assert(r.value == "\t");
			auto r1 = parseSpace("hoge".s);
			assert(!r1.match);
			assert(r1.rest == "");
			assert(r1.error.need == "space");
			assert(r1.error.line == 1);
			assert(r1.error.column == 1);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	alias combinateNone!(combinateMore0!parseSpace) parseSpaces;

	debug(ctpg) unittest{
		enum dg = {
			auto r1 = parseSpaces("\t \rhoge".s);
			assert(r1.match);
			assert(r1.rest == "hoge");
			auto r2 = parseSpaces("hoge".s);
			assert(r2.match);
			assert(r2.rest == "hoge");
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!None parseEOF(stringp input)pure @safe nothrow{
		typeof(return) res;
		if(input.length == 0){
			res.match = true;
		}else{
			res.error = Error("EOF", input.line, input.column);
		}
		return res;
	}

	debug(ctpg) unittest{
		enum dg = {
			auto r = parseEOF("".s);
			assert(r.match);
			auto r1 = parseEOF("hoge".s);
			assert(!r1.match);
			assert(r1.error.need == "EOF");
			assert(r1.error.line == 1);
			assert(r1.error.column == 1);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	/* parseIdent */ version(all){
		alias combinateString!(
			combinateSequence!(
				combinateChoice!(
					parseString!"_",
					parseCharRange!('a','z'),
					parseCharRange!('A','Z')
				),
				combinateMore0!(
					combinateChoice!(
						parseString!"_",
						parseCharRange!('a','z'),
						parseCharRange!('A','Z'),
						parseCharRange!('0','9')
					)
				)
			)
		) parseIdent;
	}

	/* parseIdentChar */ version(all){
		alias combinateChoice!(
			parseString!"_",
			parseCharRange!('a','z'),
			parseCharRange!('A','Z'),
			parseCharRange!('0','9')
		) parseIdentChar;
	}

	debug(ctpg) unittest{
		enum dg = {
			auto r0 = parseIdent("hoge".s);
			assert(r0.match);
			assert(r0.rest == "");
			assert(r0.value == "hoge");
			auto r1 = parseIdent("_x".s);
			assert(r1.match);
			assert(r1.rest == "");
			assert(r1.value == "_x");
			auto r2 = parseIdent("_0".s);
			assert(r2.match);
			assert(r2.rest == "");
			assert(r2.value == "_0");
			auto r3 = parseIdent("0".s);
			assert(!r3.match);
			assert(r3.rest == "");
			assert(r3.error.line == 1);
			assert(r3.error.column == 1);
			auto r4 = parseIdent("あ".s);
			assert(!r4.match);
			assert(r4.rest == "");
			assert(r4.error.line == 1);
			assert(r4.error.column == 1);
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	/* parseStringLiteral */ version(all){
		alias combinateString!(
			combinateSequence!(
				combinateNone!(parseString!"\""),
				combinateMore0!(
					combinateSequence!(
						combinateNot!(parseString!"\""),
						combinateChoice!(
							parseEscapeSequence,
							parseAnyChar
						)
					)
				),
				combinateNone!(parseString!"\"")
			)
		) parseStringLiteral;
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				auto r = parseStringLiteral(q{"表が怖い噂のソフト"}.s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == "表が怖い噂のソフト");
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	/* parseIntLiteral */ version(all){
		alias combinateChoice!(
			combinateConvert!(
				combinateNone!(parseString!"0"),
				function(){
					return 0;
				}
			),
			combinateConvert!(
				combinateSequence!(
					parseCharRange!('1', '9'),
					combinateMore0!(parseCharRange!('0', '9'))
				),
				function(string ahead, string[] atails){
					int lres = ahead[0] - '0';
					foreach(lchar; atails){
						lres = lres * 10 + lchar[0] - '0';
					}
					return lres;
				}
			)
		) parseIntLiteral;
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				auto r = parseIntLiteral(q{3141}.s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == 3141);
			}
			{
				auto r = parseIntLiteral(q{0}.s);
				assert(r.match);
				assert(r.rest == "");
				assert(r.value == 0);
			}
			{
				auto r = parseIntLiteral("0123".s);
				assert(r.match);
				assert(r.rest == "123");
				assert(r.value == 0);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	debug(ctpg) unittest{
		enum dg = {
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	debug(ctpg) unittest{
		enum dg = {
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}
}

string dpegWithoutMemoize(string file = __FILE__, int line = __LINE__)(string src){
	return makeCompilers!false.parse!(file, line)(src);
}

string dpeg(string file = __FILE__, int line = __LINE__)(string src){
	return makeCompilers!true.parse!(file, line)(src);
}

template getSource(string src){
	enum getSource = makeCompilers!true.defs(src.s);
}

template makeCompilers(bool isMemoize){
	enum prefix = q{
		auto parse(string file = __FILE__, int line = __LINE__)(string input){
			auto res = memoizeInput!root(stringp(input));
			if(res.match){
				return res.value;
			}else{
				if(__ctfe){
					assert(false, file ~ q{: } ~ to!string(line + res.error.line - 1) ~ q{: } ~ to!string(res.error.column) ~ q{: error } ~ res.error.need ~ q{ is needed});
				}else{
					throw new Exception(to!string(res.error.column) ~ q{: error } ~ res.error.need ~ q{ is needed}, file, line + res.error.line - 1);
				}
			}
		}
		bool isMatch(string input){
			return memoizeInput!root(stringp(input)).match;
		}
	};

	string fix(string parser){
		return isMemoize ? "memoizeInput!(" ~ parser ~ ")" : parser;
	}

	auto parse(string file = __FILE__, int line = __LINE__)(string input){
		auto res = defs(stringp(input));
		if(res.match){
			return res.value;
		}else{
			assert(false);
			//assert(false, file ~ q{: } ~ to!string(line + res.error.line - 1) ~ q{: } ~ to!string(res.error.column) ~ q{: error } ~ res.error.need ~ q{ is needed});
		}
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
		dg();
	};

	Result!string convExp(stringp input){
		return combinateConvert!(
			combinateSequence!(
				choiceExp,
				combinateMore0!(
					combinateSequence!(
						parseSpaces,
						combinateNone!(
							parseString!">>"
						),
						parseSpaces,
						combinateChoice!(
							func,
							typeName
						)
					)
				)
			),
			function(string achoiceExp, string[] afuncs){
				string lres = achoiceExp;
				foreach(lfunc; afuncs){
					lres = fix("combinateConvert!(" ~ lres ~ "," ~ lfunc ~ ")");
				}
				return lres;
			}
		)(input);
	}

	debug(ctpg) unittest{
		enum dg = {
			{
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
			}
			{
				auto r = convExp(q{"hello" >> flat >> to!int}.s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(
						r.value ==
						"memoizeInput!(combinateConvert!("
							"memoizeInput!(combinateConvert!("
								"memoizeInput!(parseString!\"hello\"),"
								"flat"
							")),"
							"to!int"
						"))"
					);
				}else{
					assert(
						r.value ==
						"combinateConvert!("
							"combinateConvert!("
								"parseString!\"hello\","
								"flat"
							"),"
							"to!int"
						")"
					);
				}
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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
					case "&":{
						return fix("combinateAnd!(" ~ primaryExp ~ ")");
					}
					case "!":{
						return fix("combinateNot!(" ~ primaryExp ~ ")");
					}
					case "^":{
						return fix("combinateNone!(" ~ primaryExp ~ ")");
					}
					case "":{
						return primaryExp;
					}
				}
			}
		)(input);
	}

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
		enum dg = {
			{
				auto r = literal("\"hello\nworld\"".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseString!\"hello\nworld\")");
				}else{
					assert(r.value == "parseString!\"hello\nworld\"");
				}
			}
			{
				auto r = literal("[a-z]".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseCharRange!('a','z'))");
				}else{
					assert(r.value == "parseCharRange!('a','z')");
				}
			}
			{
				auto r = usefulLit("space_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseSpace)");
				}else{
					assert(r.value == "parseSpace");
				}
			}
			{
				auto r = usefulLit("es".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseEscapeSequence)");
				}else{
					assert(r.value == "parseEscapeSequence");
				}
			}
			{
				auto r = usefulLit("a".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseAnyChar)");
				}else{
					assert(r.value == "parseAnyChar");
				}
			}
			{
				auto r = usefulLit("s".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseSpaces)");
				}else{
					assert(r.value == "parseSpaces");
				}
			}
			{
				auto r = literal("$".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseEOF)");
				}else{
					assert(r.value == "parseEOF");
				}
			}
			{
				auto r = literal("ident_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseIdent)");
				}else{
					assert(r.value == "parseIdent");
				}
			}
			{
				auto r = literal("strLit_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseStringLiteral)");
				}else{
					assert(r.value == "parseStringLiteral");
				}
			}
			{
				auto r = literal("intLit_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseIntLiteral)");
				}else{
					assert(r.value == "parseIntLiteral");
				}
			}
			{
				auto r = literal("表が怖い噂のソフト".s);
				assert(!r.match);
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	Result!string usefulLit(stringp input){
		return combinateConvert!(
			combinateChoice!(
				combinateSequence!(
					parseString!"ident_p",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"strLit_p",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"intLit_p",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"space_p",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"es",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"a",
					combinateNot!parseIdentChar
				),
				combinateSequence!(
					parseString!"s",
					combinateNot!parseIdentChar
				)
			),
			function(string str){
				final switch(str){
					case "ident_p":{
						return fix("parseIdent");
					}
					case "strLit_p":{
						return fix("parseStringLiteral");
					}
					case "intLit_p":{
						return fix("parseIntLiteral");
					}
					case "space_p":{
						return fix("parseSpace");
					}
					case "es":{
						return fix("parseEscapeSequence");
					}
					case "a":{
						return fix("parseAnyChar");
					}
					case "s":{
						return fix("parseSpaces");
					}
				}
			}
		)(input);
	}

	debug(ctpg) unittest{
		enum dg = {
			{
				auto r = usefulLit("space_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseSpace)");
				} else{
					assert(r.value == "parseSpace");
				}
			}
			{
				auto r = usefulLit("es".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseEscapeSequence)");
				}else{
					assert(r.value == "parseEscapeSequence");
				}
			}
			{
				auto r = usefulLit("a".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseAnyChar)");
				}else{
					assert(r.value == "parseAnyChar");
				}
			}
			{
				auto r = usefulLit("s".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseSpaces)");
				}else{
					assert(r.value == "parseSpaces");
				}
			}
			{
				auto r  = usefulLit("ident_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseIdent)");
				}else{
					assert(r.value == "parseIdent");
				}
			}
			{
				auto r = usefulLit("strLit_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseStringLiteral)");
				}else{
					assert(r.value == "parseStringLiteral");
				}
			}
			{
				auto r = usefulLit("intLit_p".s);
				assert(r.match);
				assert(r.rest == "");
				static if(isMemoize){
					assert(r.value == "memoizeInput!(parseIntLiteral)");
				}else{
					assert(r.value == "parseIntLiteral");
				}
			}
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
		dg();
	}

	alias combinateConvert!(id, fix) nonterminal;

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
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
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
		enum dg = {
			auto r = arch("(a(i(u)e)o())".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "(a(i(u)e)o())");
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
		enum dg = {
			auto r = squareArch("[a[i[u]e]o[]]".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "[a[i[u]e]o[]]");
			return true;
		};
		debug(ctpg_ct) static assert(dg());
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

	debug(ctpg) unittest{
		enum dg = {
			auto r = brace("{a{i{u}e}o{}}".s);
			assert(r.match);
			assert(r.rest == "");
			assert(r.value == "{a{i{u}e}o{}}");
			return true;
		};
		debug(ctpg_ct) static assert(dg());
		dg();
	}
}

debug(ctpg) pragma(msg, makeCompilers!true);
debug(ctpg) pragma(msg, makeCompilers!false);

string flat(Arg)(Arg aarg){
	string lres;
	static if(isTuple!Arg || isArray!Arg){
		foreach(larg; aarg){
			lres ~= flat(larg);
		}
	}else{
		lres = to!string(aarg);
	}
	return lres;
}

debug(ctpg) void main(){}

private:

stringp s(string str)pure @safe nothrow{
	return stringp(str);
}

string mkString(string[] strs, string sep = "")pure @safe nothrow{
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
}

debug(ctpg) unittest{
	enum dg = {
		{
			auto r = flat(tuple(1, "hello", tuple(2, "world")));
			assert(r == "1hello2world");
		}
		{
			auto r = flat(tuple([0, 1, 2], "hello", tuple([3, 4, 5], ["wor", "ld!!"]), ["!", "!"]));
			assert(r == "012hello345world!!!!");
		}
		{
			auto r = flat(tuple('表', 'が', '怖', 'い', '噂', 'の', 'ソ', 'フ', 'ト'));
			assert(r == "表が怖い噂のソフト");
		}
		return true;
	};
	debug(ctpg_ct) static assert(dg());
	dg();
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

template flatTuple(arg){
	static if(isTuple!arg){
		alias arg.Types flatTuple;
	}else{
		alias arg flatTuple;
	}
}

template CombinateSequenceImplType(parsers...){
	alias Result!(Tuple!(staticMap!(flatTuple, staticMap!(ParserType, parsers)))) CombinateSequenceImplType;
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
		return Result!(ResultType!R.Types[0])(r.match, r.value[0], r.rest, r.error);
	}else{
		return r;
	}
}

template CommonParserType(parsers...){
	alias CommonType!(staticMap!(ParserType, parsers)) CommonParserType;
}

dchar decode(string str, ref size_t i)@safe pure nothrow{
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

debug(ctpg) public:

unittest{
	struct exp{
		static mixin(dpeg(q{
			int root = addExp $;

			int addExp = mulExp (("+" / "-") addExp)? >> (int lhs, Option!(Tuple!(string, int)) rhs){
				if(rhs.some){
					final switch(rhs.value[0]){
						case "+":{
							return lhs + rhs.value[1];
						}
						case "-":{
							return lhs - rhs.value[1];
						}
					}
				}else{
					return lhs;
				}
			};

			int mulExp = primary (("*" / "/") mulExp)? >> (int lhs, Option!(Tuple!(string, int)) rhs){
				if(rhs.some){
					final switch(rhs.value[0]){
						case "*":{
							return lhs * rhs.value[1];
						}
						case "/":{
							return lhs / rhs.value[1];
						}
					}
				}else{
					return lhs;
				}
			};

			int primary = ^"(" addExp ^")" / intLit_p;
		}));
	}

	assert(exp.parse("5*8+3*20") == 100);
	assert(exp.parse("5*(8+3)*20") == 1100);
	try{
		exp.parse("5*(8+3)20");
	}catch(Exception e){
		assert(e.msg == "8: error EOF is needed");
		assert(e.file == __FILE__);
		assert(e.line == __LINE__-4);
	}

	struct recursive{
		static mixin(dpeg(q{
			None root = A $;
			None A = ^"a" ^A ^"a" / ^"a";
		}));
	}

	assert( recursive.isMatch("a"));
	assert( recursive.isMatch("aaa"));
	assert(!recursive.isMatch("aaaaa"));
	assert( recursive.isMatch("aaaaaaa"));
	assert(!recursive.isMatch("aaaaaaaaa"));
	assert(!recursive.isMatch("aaaaaaaaaaa"));
	assert(!recursive.isMatch("aaaaaaaaaaaaa"));
	assert( recursive.isMatch("aaaaaaaaaaaaaaa"));
}