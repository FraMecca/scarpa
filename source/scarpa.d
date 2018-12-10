module scarpa;

import parse;

import sumtype;
import ddash.functional : cond;
import vibe.core.log;
import std.io;
import requests;

import std.stdio : writeln;
import std.conv : to;
import std.typecons : Nullable;
import std.uuid;

// TODO handle update / existing files

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
    import std.range;
	Event[] list;
	Event req = RequestEvent("http://fragal.eu", "test/");
	list ~= req;

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

struct Base {
	private immutable string m_projdir;
	immutable ID m_parent;
	immutable ID m_uuid;
	bool resolved = false;

	this(const string projdir, const ID parent, const UUID uuid) @safe
	{
        m_projdir = projdir;
        m_parent = parent;
        m_uuid = uuid;
	}

	this(const string projdir, const UUID parent, const UUID uuid) @safe
	{
        m_projdir = projdir;
        m_parent = parent;
        m_uuid = uuid;
	}

    @property const string projdir() @safe { return m_projdir; }
    @property const ID uuid() @safe { return m_uuid; }
    @property const ID parent() @safe { return m_parent; }
}

struct RequestEvent {

	private immutable string m_url;
    Base base;
    alias base this;

	this(const string url, const string projdir, const ID parent = ID()) @safe
	{
        base = Base(projdir, parent, md5UUID(url));
		m_url = url;
	}

	Event[] resolve() @safe
	{
		Event[] res;
		mixin(scopeInvariant);

		requestUrl(m_url).match!(
			(ReceiveAsRange stream) => res.append(ToFileEvent(stream, m_url, projdir, uuid)),
			(string raw) => res.append(HTMLEvent(raw, m_url, projdir, uuid))
			);

		return res;
	}

    string toString() @safe { return "RequestEvent(basedir: " ~ projdir ~ ", url: " ~ m_url ~ ")"; }
}


struct HTMLEvent {

	private immutable string m_content;
	private immutable string m_rooturl;
    Base base;
    alias base this;

	this(const string content, const string root, const string projdir, const UUID parent) @safe
	{
        base = Base(projdir, parent, md5UUID(root ~ content));
		m_content = content;
        m_rooturl = root; // the url of the page requested
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
                res.append(RequestEvent(tup.url, projdir, parent));
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }
		string s = tree.document.innerHTML;
        res.append(ToFileEvent(s, m_rooturl, projdir, parent));
		return res;
	}

    string toString() @safe { return "HTMLEvent(basedir: " ~ projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }
}


struct ToFileEvent
{
	private SumType!(ReceiveAsRange, string) m_content;
    private immutable string m_rooturl;
    private immutable string m_fname;
    Base base;
    alias base this;

	this(T)(T content, const string url, const string projdir, const ID parent) @safe
		if(is(T == string) || is(T == ReceiveAsRange))
	{
		m_content = content;
        m_rooturl = url;
		m_fname = projdir ~ url.toFileName;
        base = Base(projdir, parent, md5UUID(m_fname));
	}

	Event[] resolve() @trusted
	{
        import std.algorithm.iteration : each;
        import std.file : exists, isDir;
        import std.string : representation;
 		mixin(scopeInvariant);
		Event[] res;

        string fname = m_fname.dup;

		logWarn(fname);

		fname.makeDir();

		if(fname.exists) {
			m_fname.cond!(
				f => f.isDir, (f) { fname = handleDirExists(f); },
				{ throw new Exception("Special file"); }
				);
		}

		m_content.match!(
				(string s) {
					auto fp = File(fname, mode!"w");
					fp.write(s.representation);
					},
				(ReceiveAsRange r) {
					auto fp = File(fname, mode!"wb");
					r.each!((e) => fp.write(e));
					// TODO check file type in case of binary
					}
				);
        return res;
	}

    string toString() @safe { return "ToFileEvent(basedir: " ~ projdir ~ ", file: " ~ m_fname ~ " url:" ~ m_rooturl ~ ")"; }
}
