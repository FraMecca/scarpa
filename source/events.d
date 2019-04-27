module events;

import parse;
import arguments : config;
import logger;
import urllib;
import io;
import scarpa : assertFail;

import sumtype;
import ddash.functional : cond;
import ddash.utils : Expect;
import requests;
import vibe.core.file : FileStream;

import std.stdio : writeln;
import std.conv : to;
import std.typecons : Nullable, No;
import std.uuid;
import std.json;
import std.meta;

enum EventType { // order of execution for BinnedPQ
		   LogEvent = 0,
           ToFileEvent = 1,
           HTMLEvent = 2,
           RequestEvent = 3,
};

alias EventRange = Event[];
alias EventResult = Expect!(EventRange, string);
alias EventSeq = AliasSeq!(LogEvent, RequestEvent, HTMLEvent, ToFileEvent);

struct _Event{
    SumType!EventSeq ev;
    alias ev this;
    this(RequestEvent e) @safe { ev = e; }
    this(HTMLEvent e) @safe { ev = e; }
    this(ToFileEvent e) @safe { ev = e; }
	this(LogEvent e) @safe { ev = e; }

	@property inout string toString() @safe
	{
		return ev.toString;
	}

    const JSONValue toJson() @safe
    {
		enum levelString = `j["level"] = _ev.m_level.match!((int n) => n.to!string,
					 (Asset a) => "asset",
					 (StopRecur a) => "donotrecur");`;

        return ev.match!(
			(inout LogEvent _ev) {
				return assertFail!JSONValue("LogEvent should not be serialized");
			},
            (inout RequestEvent _ev) {
                auto j = JSONValue();
                j["url"] = _ev.url.toString;
                mixin(levelString);
                return j;},
            (inout HTMLEvent _ev) {
                auto j = JSONValue();
                j["url"] = _ev.url.toString;
                mixin(levelString);
                return j;
            },
            (inout ToFileEvent _ev) {
                auto j = JSONValue();
                j["fname"] = _ev.m_fname;
                j["url"] = _ev.url.toString;
                mixin(levelString);
                return j; 
            });
    }

    const parent() @safe
    {
        return ev.match!(
			(const LogEvent _ev) {
				return assertFail!ID("LogEvent should not be serialized");
			},
            (const RequestEvent _ev) => _ev.parent,
            (const HTMLEvent _ev) => _ev.parent,
            (const ToFileEvent _ev) => _ev.parent);
    }

    @property const url() @safe
    {
        return ev.match!(
            (const LogEvent _ev) => _ev.url,
            (const RequestEvent _ev) => _ev.url,
            (const HTMLEvent _ev) => _ev.url,
            (const ToFileEvent _ev) => _ev.url);
    }

    const uuid() @safe
    {
        return ev.match!(
			(const LogEvent _ev) => _ev.uuid,
            (const RequestEvent _ev) => _ev.uuid,
            (const HTMLEvent _ev) => _ev.uuid,
            (const ToFileEvent _ev) => _ev.uuid);
    }

    const EventResult resolve() @safe
    {
		try {
			return typeof(return).expected(ev.match!(
					(inout LogEvent _ev) => _ev.resolve(),
					(inout RequestEvent _ev) => _ev.resolve(),
					(inout HTMLEvent _ev) => _ev.resolve(),
					(inout ToFileEvent _ev) => _ev.resolve()));
		} catch (Exception e) {
            immutable urlh = url.toHumanReadableString;
            debug{
                warning(e.info);
                import std.conv : to;

                return typeof(return).unexpected(e.file ~":"~e.line.to!string~" "~ urlh ~ ": " ~ e.msg);
            } else {
                return typeof(return).unexpected(urlh ~ ": " ~ e.msg);
            }
		}
    }

	auto hashOf() @safe
	{
		return this.uuid.get.toString;
	}

    debug{
    @property const enumType() @safe
    {
        return ev.match!((const LogEvent _ev) => EventType.LogEvent,
                         (const RequestEvent _ev) => EventType.RequestEvent,
                         (const HTMLEvent _ev) => EventType.HTMLEvent,
                         (const ToFileEvent _ev) => EventType.ToFileEvent);
    }

    @property const typeString() @safe
    {
        return ev.match!((const LogEvent _ev) => "LogEvent",
                         (const RequestEvent _ev) => "RequestEvent",
                         (const HTMLEvent _ev) => "HTMLEvent",
                         (const ToFileEvent _ev) => "ToFileEvent");
    }
    }
}

alias Event = immutable(_Event);

/**
 * Construct an immutable Event
 */
template makeEvent(alias t)
{
    auto makeEvent() {
        immutable e = _Event(t);
        return e;
    }
}

/**
 * Construct an immutable event from the root url used for scraping
 */
auto firstEvent(string rootUrl)
{
    auto r = RequestEvent(rootUrl.parseURL, Level(0));
	Event req = makeEvent!(r);
    return req;
}

alias ID = Nullable!UUID;

private void append(E)(ref EventRange res, E e) @safe
{
    auto ee = makeEvent!(e);
	res ~= ee;
}

/**
 * Every event contains a base tuple (parent, uuid)
 * Parent is used to go back the event chain until the last succesful event.
 * The uuid is a unique identifier construct from (url + type(event)).
 */
struct Base {
	ID parent;
	ID uuid;
	immutable URL url;

	this(inout URL url, const ID parent, const UUID uuid) @safe
	{
        this.parent = parent;
        this(url, uuid);
	}

	this(inout URL url, const UUID parent, const UUID uuid) @safe
	{
        this.parent = parent;
        this(url, uuid);
    }

    private this(inout URL url, const UUID uuid) @safe
    {
        this.uuid = uuid;
        this.url = url.toString.parseURL;
	}
}

struct RequestEvent {

    const Level m_level;
    const Base base;
    alias base this;

	this(inout URL url, Level lev, const ID parent = ID()) @safe
	{
        base = Base(url.parseURL, parent, md5UUID(url.toString ~ "REQUEST"));
        m_level = lev;
	}

	/**
	 * Asynchronously gets the content from the URL:
	 * HTML strings are saved in memory while files are saved as temporary files.
	 * Always generate an EventRange of length one.
	 */
	const EventRange resolve() @safe
	{
		EventRange res;
		import std.meta;
		import scarpa;

		auto isAsset = m_level.match!((int n) => false,
									  (Asset a) => true,
									  (StopRecur d) => assertFail!bool);
		try {
			requestUrl(url.toString, isAsset).match!((const FilePayload stream) =>
														res.append(ToFileEvent(stream, url, m_level, this.uuid)),
												   (const HTMLPayload raw) =>
														res.append(HTMLEvent(raw, url, m_level, this.uuid))
												   );
		} catch(Exception e) {
			immutable LogPayload p = ErrorResult(e.msg);
			res.append(LogEvent(url, p));
		}

		assert(res.length == 1);
		return res;
	}

	///
	@property const string toString() @safe
	{
        import std.conv : to;
		return "RequestEvent(basedir: " ~ config.projdir ~ ", url: " ~
            url.toHumanReadableString ~
            " level: "~ m_level.to!string ~ ")";
	}
}

struct HTMLEvent {

	const string m_content;
    const Level m_level;
    const Base base;
    alias base this;

	enum uriKey = ["href", "src", "href", "src",    "src",   "src",   "src"];
	enum tags =   ["a",    "img", "link", "script", "audio", "video", "track"];
	import std.range : zip;
	enum linkTags = zip(uriKey, tags);

	///
	this(const string content, const URL root, Level lev, const UUID parent) @safe
	{
        base = Base(root, parent, md5UUID(root.toString ~ "HTML"));
		m_content = content;
        m_level = lev;
	}

	/**
	 * Parse an HTML string and generate
	 * a Requestevent for every link foundi
	 * plus a ToFileevent to save the content to file.
	 */
	const EventRange resolve() @trusted // trusted until arrogant is @system
	{
        import arrogant;

		EventRange res;
        URLRule currentRule = findRule(url, config.rules);

        string replaceUrl(const string href, const string tag, ref Node node){ 
            auto tup = url_and_path(node[href].get(), url);

            m_level.match!((Asset a) {},
                           (StopRecur d) {},
                           (int n) {
                               immutable level = couldRecur(tup.url, n, currentRule, tag, node); // new level
                                   level.match!((int l){
                                           res.append(RequestEvent(tup.url, level, this.parent));
                                       },
                                   (Asset a){
                                       res.append(RequestEvent(tup.url, level, this.parent));
                                   },
                                   (StopRecur d) {}
                                );
                           });
            return tup.fname;
        }

        bool commentOut(const string tag, ref Node node)
        // out(res){ debug{ writeln(res, " ", tag); }} do
        {
            // there are links such as dns-prefetch
            // that are useful to full fledged browser but
            // dangerous or unused when reading offline
            // such tags are preserved but commented

            if(tag != "link") return false;
            if(node["rel"].isNull) return true;
            immutable rel = node["rel"];
            if(rel != "stylesheet" || rel != "icon") return true;

            return false;
        }

        auto arrogante = Arrogant();
   		auto tree = arrogante.parse(m_content);

		foreach(kv; linkTags){
			auto href = kv[0]; auto tag = kv[1];
			foreach(ref node; tree.byTagName(tag)){
                node[href] = node.cond!(
                    // see function body
                    n => commentOut(tag, n), n => "<!-- " ~ n.innerHTML ~ " -->",
                    // proper url to fetch
                    n => !n[href].isNull && n[href].get.isValidHref, n => replaceUrl(href, tag, n),
                    // do not replace
                    n => n.innerHTML 
                );
			}
		}
		string s = tree.document.innerHTML;
		res.append(ToFileEvent(HTMLPayload(s), url, m_level, this.parent));
		return res;
	}

	///
	@property const string toString() @safe
	{
		return "HTMLEvent(basedir: " ~ config.projdir ~ ", rooturl: " ~
            url.toHumanReadableString ~")";
	}
}

struct ToFileEvent
{
	const FileContent m_content;
    const string m_fname;
    const Level m_level;
    Base base;
    alias base this;

    private this(const URL uurl, Level level, const ID parent) @safe
    {
        m_level = level;
		m_fname = config.projdir ~ uurl.asPathOnDisk;
        base = Base(uurl.parseURL, parent, md5UUID(m_fname ~ "FILE"));
        info(m_fname, " ", base.uuid);
    }

    ///
    this(const FilePayload content, const URL uurl, Level level, const ID parent) @trusted
	{
		m_content = content;
        this(uurl, level, parent);
    }

    ///
	this(const HTMLPayload content, const URL uurl, Level level, const ID parent) @safe
    {
        m_content = content;
        this(uurl, level, parent);
    }

    /**
	 * Generate the appropriate folder structure and save the file.
	 * Could check if the file is an HTML and could generate an HTML event.
	 */
	const EventRange resolve() @trusted
	{
		EventRange res;

        auto fname = Path(m_fname);
		fname.parentPath.makeDirRecursive();
        debug{
            if(fname.fileExists){
                info("[D] File exists: ", fname);
                return res;
            }
        } else {
            assert(!fname.fileExists, "file should not exists already");
        }

        // write file to disk
        immutable fsize = fname.writeToFile(m_content);
        m_content.match!(
            (const HTMLPayload s) {},
            (const FilePayload r) {
                if(config.checkFileAfterSave && isHTMLFile(fname)){
                    string content = readFromFile(fname);
                    res.append(HTMLEvent(content, url, m_level, uuid));
                }
            }
        );
        immutable LogPayload p = FileResult(m_fname, fsize);
        res.append(LogEvent(url, p));

        return res;
	}

	@property const string toString() @safe
	{
		return "ToFileEvent(basedir: " ~ config.projdir ~ ", file: " ~ m_fname ~
            " url:" ~ url.toHumanReadableString ~ ")";
	}
}

alias ErrorCode = string;

struct FileResult {
    const string name;
	const ulong size;
}

struct ErrorResult {
	const ErrorCode code;
}

alias LogPayload = SumType!(FileResult, ErrorResult);

struct LogEvent {
	import std.datetime.systime : SysTime, Clock;
	import std.conv : to;

	const SysTime m_reqTime;
	const LogPayload m_payload;
    const Base base;
    alias base this;


	this(const URL requrl, const LogPayload payload) @safe
	{
		m_reqTime = Clock.currTime();
		m_payload = payload;
        base = Base(requrl, ID(), md5UUID(m_reqTime.toSimpleString() ~ requrl.toString ~ "LOG"));

		// DATE TIME URL FILENAME:FILESIZE
		// DATE TIME URL ERROR
		string res = m_payload.match!(
					(FileResult f) => "[S] ",
					(ErrorResult e) => "[E] "
					)
	    	~ m_reqTime.toSimpleString()
			~ " "
			~ m_payload.match!(
					(FileResult f) => f.name ~ ":" ~ f.size.to!string,
					(ErrorResult e) => "\"" ~ e.code.to!string ~ "\""
					)
			~ " "
			~ url.toString;

		// log to logPath
		info(res);

	}

	/// empty since no priority
	const EventRange resolve() @safe
	{
		typeof(return) r;
		return r;
	}

}
