import std.stdio;
import sumtype;
import requests;
import arrogant;

import std.range;
import std.array;
import std.string;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.conv : to;

alias Event = SumType!(RequestEvent, ParseEvent, ToFileEvent);

enum scopeInvariant = "assert(resolved == false); scope(success) resolved = true;";
/**
events:
1. request to website
2. parse links -> find links -> to .1
3. translation links -> files
4. save to disk
5. save to db (events on db)
6. print on screen
*/
void main()
{
	Event[] list;
	Event req = RequestEvent("http://fragal.eu");
	list ~= req;

	foreach(rq; list) {
		//req.resolve.each!((ParseEvent r) => r.resolve());
		foreach(r; rq.resolve) {
			r.tryMatch!(
					(ParseEvent q) => list ~= q.resolve,
					(ToFileEvent t) => t.resolve
					);
		}
		list.popFront();
	}
}

struct RequestEvent {

	private immutable string m_url;
	bool resolved = false;

	this(const string url) @safe
	{
		m_url = url;
	}

	Event[] resolve()
	{
		Event[] res;
		mixin(scopeInvariant);
		// fetch request content
		auto content = getContent(m_url);
		//writeln(content);

		Event parser = ParseEvent(content.to!string);
		res ~= parser;
		return res;
	}
}

struct ParseEvent {

	private immutable string m_content;
	bool resolved = false;

	this(const string content) @safe
	{
		m_content = content;
	}

	Event[] resolve()
	{
		mixin(scopeInvariant);

		Event[] res;
		void append(string s)
		{
			Event e = RequestEvent(s);
			res ~= e;
		}

		auto arrogant = Arrogant();
   		auto tree = arrogant.parse(m_content);

		// TODO other tags
		tree.byTagName("a")
			.filter!((e) => !e["href"].isNull)
			.each!((e) => append(e["href"]));

		return res;
	}
}

struct ToFileEvent {

	private immutable string m_content;
	bool resolved = false;

	this(const string content) @safe
	{
		m_content = content;
	}

	Event[] resolve()
	{
 		mixin(scopeInvariant);
		Event[] res;

		void formatURI(/*ref T dst,*/ string uri) // TODO file appender ? iopipe ?
		{
			string rootPath = "/tmp/data/"; // TODO
			auto dst = appender!string;

			if(uri.beginsWith("http://")) {
				dst.put(rootPath ~ uri.stripLeft("http://"));
			} else if(uri.beginsWith("https://")) {
				dst.put(rootPath ~ uri.stripLeft("https://"));
			} else if(uri.beginsWith("/")) {
				dst.put(rootPath ~ uri.stripLeft("/")); // TODO add original folder
			} else {
				dst.put(uri);
			}
			writeln(dst.data);
		}

		m_content.each!(e => formatURI(e["href"]));
		return res; // TODO dbevent
	}
}
