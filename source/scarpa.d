module scarpa;

import sumtype;
import ddash.functional;
import vibe.core.log;
import std.io;
import requests;

import std.stdio : writeln;
import std.range;
import std.conv : to;
import std.uuid;
import std.variant;
import std.typecons;

import parse;

alias ID = Nullable!UUID;
alias Event = SumType!(RequestEvent, HTMLEvent, ToFileEvent);
alias resolve = match!(
                       (RequestEvent _ev) => _ev.resolve,
                       (HTMLEvent _ev) => _ev.resolve,
                       (ToFileEvent _ev) => _ev.resolve,
                       );

private void append(E)(ref Event[] res, E e) @safe
{
	Event ee = e;
	res ~= ee;
}

enum scopeInvariant = "logInfo(this.toString);assert(resolved == false); scope(success) resolved = true;";
/**
events:
1. request to website
2. parse links -> find links -> to .1
3. translation links -> files
4. save to disk
*/
void main()
{
	Event[] list;
	Event req = RequestEvent("http://fragal.eu", "test/");
	list ~= req;

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

struct RequestEvent {

	private immutable string m_url;
	private immutable string m_projdir;
	immutable ID m_uuid;
	immutable ID m_parent;
	bool resolved = false;

	this(const string url, const string projdir, const ID parent = ID()) @safe
	{
		m_url = url;
        m_projdir = projdir;
		m_uuid = md5UUID(url);
		m_parent = parent;
	}

	Event[] resolve() @safe
	{
		Event[] res;
		mixin(scopeInvariant);

		requestUrl(m_url).match!(
			(ReceiveAsRange stream) => res.append(ToFileEvent(stream, m_url, m_projdir, m_uuid)),
			(string raw) => res.append(HTMLEvent(raw, m_url, m_projdir, m_uuid))
			);

		return res;
	}

    string toString() @safe { return "RequestEvent(basedir: " ~ m_projdir ~ ", url: " ~ m_url ~ ")"; }
}

struct HTMLEvent {

	private immutable string m_content;
	private immutable string m_rooturl;
	private immutable string m_projdir;
	immutable ID m_parent;
	bool resolved = false;

	this(const string content, const string root, const string projdir, const UUID parent) @safe
	{
		m_content = content;
        m_rooturl = root; // the url of the page requested
        m_projdir = projdir;
		m_parent = parent;
	}

	Event[] resolve() @trusted// TODO safe 
	{
        import arrogant;
		mixin(scopeInvariant);

		Event[] res;

        auto arrogante = Arrogant();
   		auto tree = arrogante.parse(m_content);

		// TODO other tags and js and css
        foreach(ref node; tree.byTagName("a")){
            if(!node["href"].isNull){
                auto tup = parseUrl(node["href"].get(), m_rooturl);
                res.append(RequestEvent(tup.url, m_projdir, m_parent));
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }
		string s = tree.document.innerHTML;
        res.append(ToFileEvent(s, m_rooturl, m_projdir, m_parent));
		return res;
	}

    string toString() @safe { return "HTMLEvent(basedir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}


struct ToFileEvent
{
	private SumType!(ReceiveAsRange, string) m_content;
    private immutable string m_rooturl;
	private immutable string m_projdir;
	immutable ID m_parent;
	bool resolved = false;

	this(T)(T content, const string url, const string projdir, const ID parent) @safe
		if(is(T == string) || is(T == ReceiveAsRange))
	{
		m_content = content;
        m_rooturl = url;
        m_projdir = projdir;
		m_parent = parent;
	}

	Event[] resolve() @trusted
	{
 		mixin(scopeInvariant);
		Event[] res;

		string fname = m_projdir ~ m_rooturl.toFileName();
		logWarn(fname);
		m_content.match!(
				(string s) {
						auto fp = File(fname, mode!"w");
						fp.write(s.to!(ubyte[]));
					},
				(ReceiveAsRange r) {
						import std.algorithm.iteration;
						auto fp = File(fname, mode!"wb");
						r.each!((e) => fp.write(e));
					// TODO check file type in case of binary
					}
				);
        return res;
	}

    string toString() @safe { return "ToFileEvent(basedir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}
