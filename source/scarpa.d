module scarpa;

import sumtype;
import ddash.functional;
import vibe.core.log;

import std.stdio : writeln;
import std.range;
import std.conv : to;
import std.uuid;
import std.variant;
import std.typecons;

import parse;

alias ID = Nullable!UUID;
alias Event = SumType!(RequestEvent, ParseEvent, ToFileEvent);
alias resolve = match!(
                       (RequestEvent _ev) => _ev.resolve,
                       (ParseEvent _ev) => _ev.resolve,
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

		// TODO
        //requestUrl(m_url).tryMatch!(
				//(string cont) => res.append(ParseEvent(cont, m_url, m_projdir, m_uuid)),
				//(ubyte[] raw) => res.append(ToFileEvent(raw, m_url, m_projdir, m_uuid))
				//);

		return res;
	}

    string toString() @safe { return "RequestEvent(basedir: " ~ m_projdir ~ ", url: " ~ m_url ~ ")"; }
}

struct ParseEvent {

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
                res.append(RequestEvent(tup.url, m_projdir));
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }

        res.append(ToFileEvent(m_content, m_rooturl, m_projdir, m_parent));
		return res;
	}

    string toString() @safe { return "ParseEvent(basedir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}


struct ToFileEvent
{
	private ubyte[] m_content;
    private immutable string m_rooturl;
	private immutable string m_projdir;
	immutable ID m_parent;
	bool resolved = false;

	this(T)(T content, const string url, const string projdir, const ID parent) @safe
		if(is(T == string) || is(ElementType!T : ubyte))
	{
		static if(is(T == string)) m_content = content.to!(ubyte[]);
		else m_content = content;
        m_rooturl = url;
        m_projdir = projdir;
		m_parent = parent;
	}

	//this(const string content, const string url, const string projdir, const ID parent) @safe
	//{
		////m_content = content;
        //m_rooturl = url;
        //m_projdir = projdir;
		//m_parent = parent;
	//}


	Event[] resolve() @safe
	{
        import std.io;
 		mixin(scopeInvariant);
		Event[] res;
        // auto fp = File(m_projdir, mode!"w");
        // fp.write(m_content.to!(ubyte[]));
        return res;
	}

    string toString() @safe { return "ToFileEvent(basedir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}
