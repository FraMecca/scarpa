module scarpa;

import sumtype;
import ddash.functional;

import std.stdio : writeln;
import std.range;
import std.conv : to;

import parse;

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
*/
void main()
{
	Event[] list;
	Event req = RequestEvent("http://fragal.eu/cv.pdf", "test/");
	list ~= req;

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

struct RequestEvent {

	private immutable string m_url;
	private immutable string m_projdir;
	bool resolved = false;

	this(const string url, const string projdir) @safe
	{
		m_url = url;
        m_projdir = projdir;
	}

	Event[] resolve() @safe
	{
		Event[] res;
		mixin(scopeInvariant);
		// fetch request content
        Event ev = requestUrl(m_url, m_projdir);
		res ~= ev;
		return res;
	}

    string toString() @safe { return "RequestEvent(rootdir: " ~ m_projdir ~ ", url: " ~ m_url ~ ")"; }
}

struct ParseEvent {

	private immutable string m_content;
	private immutable string m_rooturl;
	private immutable string m_projdir;
	bool resolved = false;

	this(const string content, const string root, const string projdir) @safe
	{
		m_content = content;
        m_rooturl = root; // the url of the page requested
        m_projdir = projdir;
	}

	Event[] resolve() @trusted// TODO safe 
	{
        import arrogant;
		mixin(scopeInvariant);

		Event[] res;

        auto arrogantt = Arrogant();
   		auto tree = arrogantt.parse(m_content);

		// TODO other tags and js and css
        foreach(ref node; tree.byTagName("a")){
            if(!node["href"].isNull){
                auto tup = parseUrl(node["href"].get(), m_rooturl);
                Event e = RequestEvent(tup.url, m_projdir);
                res ~= e;
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }

        Event e = ToFileEvent(m_content, m_rooturl, m_projdir);
        res ~= e;
		return res;
	}

    string toString() @safe { return "ParseEvent(project dir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}


struct ToFileEvent {

	private immutable string m_content;
    private immutable string m_rooturl;
	private immutable string m_projdir;
	bool resolved = false;

	this(const string content, const string url, const string projdir) @safe
	{
		m_content = content;
        m_rooturl = url;
        m_projdir = projdir;
	}

	this(const ubyte[] content, const string url, const string projdir) @safe
	{
        assert(false);
        // m_rooturl = url;
        // m_projdir = projdir;
	}

	Event[] resolve() @safe
	{
        import std.io;
 		mixin(scopeInvariant);
		Event[] res;
        // auto fp = File(m_projdir, mode!"w");
        // fp.write(m_content.to!(ubyte[]));
        return res;
	}

    string toString() @safe { return "ToFileEvent(projdir: " ~ m_projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}
