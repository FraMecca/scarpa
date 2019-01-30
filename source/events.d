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
import std.meta;

enum EventType { // order of execution for BinnedPQ
           ToFileEvent = 0,
           HTMLEvent = 1,
           RequestEvent = 2,
};

alias EventRange = Event[];
alias EventResult = EventRange;
alias EventSeq = AliasSeq!(RequestEvent, HTMLEvent, ToFileEvent);

struct _Event{
    SumType!EventSeq ev;
    alias ev this;
    this(inout RequestEvent e) @safe { ev = e; }
    this(inout HTMLEvent e) @safe { ev = e; }
    this(inout ToFileEvent e) @safe { ev = e; }

	@property inout string toString() @safe
	{
		return ev.toString;
	}

    const JSONValue toJson() @safe
    {
        return ev.match!(
            (RequestEvent _ev) { 
                auto j = JSONValue();
                j["url"] = _ev.m_url;
                return j;},
            (HTMLEvent _ev) { 
                auto j = JSONValue();
                j["url"] = _ev.m_rooturl;
                return j;
            },
            (inout ToFileEvent _ev) {
                auto j = JSONValue();
                j["fname"] = _ev.m_fname;
                j["url"] = _ev.m_rooturl;
                return j;
            });
    }

    const parent() @safe
    {
        return ev.match!(
            (const RequestEvent _ev) => _ev.parent,
            (const HTMLEvent _ev) => _ev.parent,
            (const ToFileEvent _ev) => _ev.parent);
    }

    const uuid() @safe
    {
        return ev.match!(
            (const RequestEvent _ev) => _ev.uuid,
            (const HTMLEvent _ev) => _ev.uuid,
            (const ToFileEvent _ev) => _ev.uuid);
    }

    const resolve() @safe
    {
		log(this.toString);

        return ev.match!(
            (RequestEvent _ev) => _ev.resolve(),
            (HTMLEvent _ev) => _ev.resolve(),
            (const ToFileEvent _ev) => _ev.resolve());
    }

	auto hashOf() @safe
	{
		return this.uuid.get.toString;
	}
}

alias Event = immutable(_Event);

template makeEvent(alias t)
{
    auto makeEvent() {
        immutable e = _Event(t);
        return e;
    }
}

auto firstEvent(string rootUrl)
{
    auto r = RequestEvent(rootUrl);
	Event req = makeEvent!(r);
    return req;
}

alias ID = Nullable!UUID;

private void append(E)(ref EventRange res, E e) @safe
{
    auto ee = makeEvent!(e);
	res ~= ee;
}

struct Base {
	ID parent;
	ID uuid;

	this(const ID parent, const UUID uuid) @safe
	{
        this.parent = parent;
        this.uuid = uuid;
	}

	this(const UUID parent, const UUID uuid) @safe
	{
        this.parent = parent;
        this.uuid = uuid;
	}
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

	const EventResult resolve() @safe
	{
		EventRange res;

		requestUrl(m_url).match!(
			(ReceiveAsRange stream) => res.append(ToFileEvent(stream, m_url, this.uuid)),
			(string raw) => res.append(HTMLEvent(raw, m_url, this.uuid))
			);

		assert(res.length == 1);
		return res;
	}

	@property const string toString() @safe
	{
		return "RequestEvent(basedir: " ~ config.projdir ~ ", url: " ~ m_url ~ ")";
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

	const EventResult resolve() @trusted// TODO safe 
	{
        import arrogant;

		EventRange res;

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

	@property const string toString() @safe
	{
		return "HTMLEvent(basedir: " ~ config.projdir ~ ", rooturl: " ~ m_rooturl ~")";
	}
}

struct ToFileEvent
{
	private SumType!(ReceiveAsRange, string) m_content;
    private string m_rooturl;
    private string m_fname;
    Base base;
    alias base this;

	this(ReceiveAsRange content, const string url, const ID parent) @safe
	{
		m_content = content;
        m_rooturl = url;
		m_fname = config.projdir ~ url.toFileName;
        base = Base(parent, md5UUID(m_fname));
	}

	this(string content, const string url, const ID parent) @safe
    {
            m_content = content;
            m_rooturl = url;
            m_fname = config.projdir ~ url.toFileName;
            base = Base(parent, md5UUID(m_fname));
        }

	const EventResult resolve() @trusted
	{
        import vibe.core.file : openFile, FileMode;
        import std.algorithm.iteration : each;
        import std.file : exists, isDir, isFile;
        import std.string : representation;
		EventRange res;

        string fname = m_fname.dup;

		fname.makeDir();

		if(fname.exists && !fname.isFile) {
			m_fname.cond!(
				f => f.isDir, (f) { fname = handleDirExists(f); },
				{ throw new Exception("Special file"); }
				);
		}

        auto fp = openFile(fname, FileMode.append);
		m_content.match!(
				(const string s) {
					fp.write(s.representation);
					},
				(const ReceiveAsRange cr) {
                    auto r = cast(ReceiveAsRange)cr; // cannot use bcs const
					r.each!((e) => fp.write(e));
					// TODO check file type in case of binary
					}
				);
        return res;
	}

	@property const string toString() @safe
	{
		return "ToFileEvent(basedir: " ~ config.projdir ~ ", file: " ~ m_fname ~ " url:" ~ m_rooturl ~ ")";
	}
}
