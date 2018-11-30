import sumtype;
import requests;
import arrogant;
import ddash.functional;

import std.stdio;
import std.range;
import std.array;
import std.string;
import std.typecons;
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

enum scopeInvariant = "writeln(this.toString);assert(resolved == false); scope(success) resolved = true;";
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
	Event req = RequestEvent("http://fragal.eu", "fragal.eu");
	list ~= req;

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

struct RequestEvent {

	private immutable string m_url;
	private immutable string m_fname;
	bool resolved = false;

	this(const string url, const string fname) @safe
	{
		m_url = url.endsWith("/") ? url : url ~ "/";
        m_fname = fname;
	}

	Event[] resolve()
	{
		Event[] res;
		mixin(scopeInvariant);
		// fetch request content
		auto content = getContent(m_url);

		Event parser = ParseEvent(content.to!string, m_url, m_fname);
		res ~= parser;
		return res;
	}

    string toString(){ return "RequestEvent(fname: " ~ m_fname ~ ", url: " ~ m_url ~ ")"; }
}

struct ParseEvent {

	private immutable string m_content;
	private immutable string m_rooturl;
	private immutable string m_fname;
	bool resolved = false;

	this(const string content, const string root, const string fname) @safe
	{
        assert(root.endsWith("/"), root);
		m_content = content;
        m_rooturl = root[0 .. $-1];
        m_fname = fname;
	}

	Event[] resolve()
	{
		mixin(scopeInvariant);

		Tuple!(string, "url", string, "fname") parseUrl(const string url){
            string src, dst;
            // write full path in case of relative urls
            src = tuple!("url", "root")(url, m_rooturl).cond!(
                t => t.url.startsWith("/"), t => t.root ~ t.url,
                t => t.url
            );

            enum rootPath = "/tmp/asd/"; // on disk, should be cwd
            // write filename on disk
            dst = tuple!("url", "fpath")(url, rootPath).cond!(
                t => t.url.startsWith("http://"), t => t.fpath ~ t.url.stripLeft("http://"),
                t => t.url.startsWith("https://"), t => t.fpath ~ t.url.stripLeft("https://"),
                t => t.url.startsWith("/"), t => t.fpath ~ t.url.stripLeft("/"),
                t => t.url
            );
            return tuple!("url", "fname")(src, dst);
        }

		Event[] res;

        auto arrogant = Arrogant();
   		auto tree = arrogant.parse(m_content);

		// TODO other tags and js and css
        foreach(ref node; tree.byTagName("a")){
            if(!node["href"].isNull){
                auto tup = parseUrl(node["href"]); // source and destination
                Event e = RequestEvent(tup.url, tup.fname);
                res ~= e;
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }

		// tree.byTagName("a")
		// 	.filter!((e) => !e["href"].isNull)
		// 	.each!((e) => append(e["href"])); // could be tee

        Event e = ToFileEvent(m_content, m_rooturl, m_fname);
        res ~= e;
		return res;
	}

    string toString(){ return "ParseEvent(fname: " ~ m_fname ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}


struct ToFileEvent {

	private immutable string m_content;
    private immutable string m_rooturl;
	private immutable string m_fname;
	bool resolved = false;

	this(const string content, const string url, const string fname) @safe
	{
		m_content = content;
        m_rooturl = url;
        m_fname = fname;
	}

	Event[] resolve()
	{
 		mixin(scopeInvariant);
		Event[] res;

        assert (false);
		// return res; // TODO dbevent
	}

    string toString(){ return "ToFileEvent(fname: " ~ m_fname ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}
