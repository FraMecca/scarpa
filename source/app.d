import sumtype;
import requests;
import arrogant;
import ddash.functional;

import std.stdio;
import std.range;
import std.array;
import std.string;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.conv : to;

alias Event = SumType!(RequestEvent, ParseEvent, ToFileEvent);
alias resolve = match!(
                       (RequestEvent _ev) => _ev.resolve,
                       (ParseEvent _ev) => _ev.resolve,
                       (ToFileEvent _ev) => _ev.resolve,
                       );

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

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

struct RequestEvent {

	private immutable string m_url;
	bool resolved = false;

	this(const string url) @safe
	{
		m_url = url.endsWith("/") ? url : url ~ "/";
	}

	Event[] resolve()
	{
		Event[] res;
		mixin(scopeInvariant);
		// fetch request content
		auto content = getContent(m_url);
		//writeln(content);

		Event parser = ParseEvent(content.to!string, m_url);
		res ~= parser;
		return res;
	}
}

struct ParseEvent {

	private immutable string m_content;
	private immutable string m_rooturl;
	bool resolved = false;

	this(const string content, const string root) @safe
	{
        assert(root.endsWith("/"), root);
		m_content = content;
        m_rooturl = root[0 .. $-1];
	}

	Event[] resolve()
	{
		mixin(scopeInvariant);

		Event[] res;
		void append(const string src){
            if(src.startsWith("/")){
                Event e = RequestEvent(m_rooturl ~ src);
                res ~= e;
            }
            else{
                Event e = RequestEvent(src);
                res ~= e;
            }
        }

        auto arrogant = Arrogant();
   		auto tree = arrogant.parse(m_content);

		// TODO other tags
		tree.byTagName("a")
			.filter!((e) => !e["href"].isNull)
			.each!((e) => append(e["href"])); // could be tee

        foreach(ref e; tree.byTagName("a")){
            e.formatUri; // CAN'T replace occurences TODO
        }
        Event e = ToFileEvent(m_content, m_rooturl);
        res ~= e;
		return res;
	}
}
void formatUri(/*ref T dst,*/ ref Node uri) // TODO file appender ? iopipe ?
{
    if(e["href"].isNull)
        return

    enum rootPath = "/tmp/data/"; // TODO
    // auto dst = appender!string;
    // dst.put(uri.cond!(
    uri["href"] = uri["href"].cond!(
          u => u.startsWith("http://"), u => rootPath ~ u.stripLeft("http://"),
          u => u.startsWith("https://"), u => rootPath ~ u.stripLeft("https://"),
          u => u.startsWith("/"), u => rootPath ~ u.stripLeft("/"),
          u => u
    );
    writeln(uri["href"] ~ "asd");
}


struct ToFileEvent {

	private immutable string m_content;
    private immutable string m_rooturl;
	bool resolved = false;

	this(const string content, const string url) @safe
	{
		m_content = content;
        m_rooturl = url;
	}

	Event[] resolve()
	{
        writeln(this);
 		mixin(scopeInvariant);
		Event[] res;

        assert (false);
		// return res; // TODO dbevent
	}
}
