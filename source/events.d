module events;

import parse;
import config : config;
import logger;

import sumtype;
import ddash.functional : cond;
import std.io;
import requests;
// import stdx.data.json;

import std.stdio : writeln;
import std.conv : to;
import std.typecons : Nullable;
import std.uuid;
import std.json;

enum scopeInvariant = "log(this.toString);
						assert(this.resolved == false);
						scope(success) this.resolved = true;";

alias ID = Nullable!UUID;
alias Event = SumType!(RequestEvent, HTMLEvent, ToFileEvent);
alias resolve = match!(
                       (RequestEvent _ev) => _ev.resolve,
                       (HTMLEvent _ev) => _ev.resolve,
                       (ToFileEvent _ev) => _ev.resolve,
                       );

alias uuid = match!(
                       (RequestEvent _ev) => _ev.uuid,
                       (HTMLEvent _ev) => _ev.uuid,
                       (ToFileEvent _ev) => _ev.uuid,
                       );

alias resolved = match!(
                       (RequestEvent _ev) => _ev.resolved,
                       (HTMLEvent _ev) => _ev.resolved,
                       (ToFileEvent _ev) => _ev.resolved,
                       );

alias toJson = match!(
                       (RequestEvent _ev) => _ev.toJson,
                       (HTMLEvent _ev) => _ev.toJson,
                       (ToFileEvent _ev) => _ev.toJson,
                       );

alias parent = match!(
                       (RequestEvent _ev) => _ev.parent,
                       (HTMLEvent _ev) => _ev.parent,
                       (ToFileEvent _ev) => _ev.parent,
                       );

private void append(E)(ref Event[] res, E e) @safe
{
	Event ee = e;
	res ~= ee;
}

struct Base {
	ID m_parent;
	ID m_uuid;
	bool resolved = false;

	this(const ID parent, const UUID uuid) @safe
	{
        m_parent = parent;
        m_uuid = uuid;
	}

	this(const UUID parent, const UUID uuid) @safe
	{
        m_parent = parent;
        m_uuid = uuid;
	}

    @property const ID uuid() @safe { return m_uuid; }
    @property const ID parent() @safe { return m_parent; }
}

struct RequestEvent {

	private string m_url;
    Base base;
    alias base this;
	bool requestOver = false;

	this(const string url, const ID parent = ID()) @safe
	{
        base = Base(parent, md5UUID(url));
		m_url = url;
	}

	Event[] resolve() @safe
	{
		Event[] res;
		mixin(scopeInvariant);

		requestUrl(m_url).match!(
			(ReceiveAsRange stream) => res.append(ToFileEvent(stream, m_url, this.uuid)),
			(string raw) => res.append(HTMLEvent(raw, m_url, this.uuid))
			);

		assert(res.length == 1);
		return res;
	}

    string toString() @safe { return "RequestEvent(basedir: " ~ config.projdir ~ ", url: " ~ m_url ~ ")"; }

    @property JSONValue toJson() @safe
    {
        auto j = JSONValue();
        j["url"] = m_url;
        return j;
    }
}


struct HTMLEvent {

	private string m_content;
	private string m_rooturl;
    Base base;
    alias base this;

	this(const string content, const string root, const UUID parent) @safe
	{
        base = Base(parent, md5UUID(root ~ content));
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
            if(!node["href"].isNull && node["href"].get.isValidHref){
                auto tup = parseUrl(node["href"].get(), m_rooturl);
                res.append(RequestEvent(tup.url, this.parent));
                node["href"] = tup.fname; // replace with a filename on disk
            }
        }
		string s = tree.document.innerHTML;
        res.append(ToFileEvent(s, m_rooturl, this.parent));
		return res;
	}

    string toString() @safe { return "HTMLEvent(basedir: " ~ config.projdir ~ ", rooturl: " ~ m_rooturl ~ ")"; }

    @property JSONValue toJson() @safe
    {
        auto j = JSONValue();
        j["url"] = m_rooturl;
        return j;
    }
}


struct ToFileEvent
{
	private SumType!(ReceiveAsRange, string) m_content;
    private string m_rooturl;
    private string m_fname;
    Base base;
    alias base this;

	this(T)(T content, const string url, const ID parent) @safe
		if(is(T == string) || is(T == ReceiveAsRange))
	{
		m_content = content;
        m_rooturl = url;
		m_fname = config.projdir ~ url.toFileName;
        base = Base(parent, md5UUID(m_fname));
	}

	Event[] resolve() @trusted
	{
        import std.algorithm.iteration : each;
        import std.file : exists, isDir, isFile;
        import std.string : representation;
 		mixin(scopeInvariant);
		Event[] res;

        string fname = m_fname.dup;

		warning(fname);

		fname.makeDir();

		if(fname.exists && !fname.isFile) {
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

    string toString() @safe { return "ToFileEvent(basedir: " ~ config.projdir ~ ", file: " ~ m_fname ~ " url:" ~ m_rooturl ~ ")"; }

    @property JSONValue toJson() @safe
    {
        auto j = JSONValue();
        j["url"] = m_rooturl;
        j["fname"] = m_fname;
        return j;
    }
}
