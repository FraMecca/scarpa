module parse;

import scarpa;
import config : config;
import io;
import logger;
import url;

import ddash.functional : cond;
import sumtype : match, SumType;

import std.typecons : Tuple, tuple;
import std.algorithm.searching : startsWith, endsWith;
import std.string : stripLeft, lastIndexOf, count;
import std.range : empty;
import std.regex : Regex, regex;
import std.algorithm : filter;
import std.range: walkLength;
import std.array : split;

/**
 * Module that contains functions related to HTTP, URL schema and HTTP
 */

version(unittest) {
	bool checkLevel(const string rhs, const string lhs, const long lev, bool isRegex) @safe
	{
		auto rule = URLRule(rhs, lev, isRegex);
		return checkLevel(rule, lhs.parseURL);
	}

	string asPathOnDisk(const string url) { return url.parseURL.asPathOnDisk; }

	URLRule findRule(const string src, URLRule[] rules) @safe
	{
		return findRule(src.parseURL, rules);
	}

	string toFileName(const string url, const string src, const bool addIndex = true) @safe
	{
		return toFileName(url.parseURL, src.parseURL);
	}
}


alias ParseResult = Tuple!(URL, "url", string, "fname");
alias parseResult = tuple!("url", "fname");

/**
 * Parse an URL and
 * return a tuple of URL, pathname
 */
ParseResult url_and_path(const string url, const URL absRooturl) @safe
in{
    assert(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("/"), url);
    assert(absRooturl.fragment == "");
}
do{
    string dst;
    URL src;
    // write full path in case of relative urls
    if(url.startsWith("/")){
        src = absRooturl.parseURL;
        src.path = url.removeAnchor;
    } else {
        src = url.removeAnchor.parseURL;
    }

	dst = toFileName(src, absRooturl);
    return parseResult(src, dst);
}

alias segments = (inout string s) => s.split('/').filter!(i => i != "");
/**
 * Converts an URL to a path on the disk
 * relatively to the source that points to the URL
 */
string toFileName(const URL dst, const URL src) @safe
in{
    assert(dst.fragment == "",  dst);
// }out(results){writeln(results);
}do{
    import std.range : walkLength, zip, repeat, take, tee;
    import std.array : array, join;
    import std.algorithm.iteration : map;
    import std.algorithm.searching : countUntil;

    // is it the root of the website?
    if((dst.path == "/" || dst.path.empty)
	   && (src.path == "/" || src.path.empty))
        return "./index.html";
	immutable dstpath = dst.path == "/" ? "" : dst.path;
    bool sameHost = dst.host == src.host;
    immutable srcments = src.path.segments.array; // Could store this in DST struct
    immutable dstments = dstpath.segments.array;

    long len = sameHost ?
        zip(dstments, srcments)
        .map!(t => t[0] == t[1])
        .countUntil(false) :
        // else
        srcments.walkLength + 1;

    len = len == -1 ? 0 : len;
    immutable splitLen = sameHost ? len : 0;
    if(sameHost && srcments.length != 0)
        len = srcments.length - len; // now adjust to remove same subfolders
	if(srcments.length != 0 && srcments[$-1].endsWith(".html"))
		len--;

    immutable goUp = "../".repeat.take(len).join;

    return goUp ~ // file system hierarchy
        (sameHost ? "" : dst.host ~ "/") ~ // host
        dstments[splitLen..$].join("/") ~ // path
		(dstpath == "" ? "index.html" : "") ~
        (dstpath.endsWith("/") ? "/index.html" : ""); // index.html if it is a folder
}

unittest{
	assert(toFileName("https://fragal.eu/a.html", "https://fragal.eu/") == "a.html");
	assert(toFileName("https://fragal.eu/a/b.html", "https://fragal.eu/") == "a/b.html");
	assert(toFileName("https://fragal.eu/b.html", "https://fragal.eu/a") == "../b.html");
	assert(toFileName("https://fragal.eu/b.html", "https://fragal.eu/a/") == "../b.html");
	assert(toFileName("https://fragal.eu/a/c/", "https://fragal.eu/a/b/") == "../c/index.html");
	assert(toFileName("https://fragal.eu/a/c", "https://fragal.eu/a/b/") == "../c");
	assert(toFileName("https://fragal.eu/c/d/", "https://fragal.eu/a/b/") == "../../c/d/index.html");
	assert(toFileName("https://francescomecca.eu/A/c.html", "https://fragal.eu/a/b/") == "../../../francescomecca.eu/A/c.html");
	assert(toFileName("https://fragal.eu/", "https://fragal.eu/") == "./index.html");
	assert(toFileName("https://fragal.eu", "https://fragal.eu/") == "./index.html");
	assert(toFileName("https://fragal.eu/assets/vendor/normalize-css/normalize.css", "https://fragal.eu/2018/10/15/mologna.html") == "../../../assets/vendor/normalize-css/normalize.css");
	assert(toFileName("https://fragal.eu/", "https://fragal.eu/2018/10/15/mologna.html") == "../../../index.html");
}

/**
 * absolute path of a file that need to be written
 * supposing the project directory as root
 * The return does not contain the project directory.
 */
string asPathOnDisk(const URL url) @safe
{
    // is it the root of the website?
    if(url.path == "/" || url.path.empty)
        return url.host ~ "/index.html";

    return url.host ~ url.path ~ (url.path.endsWith("/") ? "index.html" : "");
}

unittest{
    assert("http://fragal.eu".asPathOnDisk == "fragal.eu/index.html");
    assert("http://fragal.eu/".asPathOnDisk == "fragal.eu/index.html");
    assert("http://fragal.eu/index.html".asPathOnDisk == "fragal.eu/index.html");
    assert("http://fragal.eu/a.html".asPathOnDisk == "fragal.eu/a.html");
    assert("http://fragal.eu/a/b.html".asPathOnDisk == "fragal.eu/a/b.html");
    assert("http://fragal.eu/a/b".asPathOnDisk == "fragal.eu/a/b");
    assert("http://fragal.eu/a/b/".asPathOnDisk == "fragal.eu/a/b/index.html");
}

/**
 * The anchor character '#' is correctly parsed by
 * the html library while effectively being
 * the same html page referring to one of its div.
 * This function strips the '#'
 */
string removeAnchor(const string src) @safe
{
    auto idx = src.lastIndexOf('#');
    if(idx < 0) return src;
    else return src[0 .. idx];
}

unittest{
    assert("http://example.com/p#anchor".removeAnchor == "http://example.com/p");
    assert("http://example.com/p#anchor/".removeAnchor == "http://example.com/p");
    assert("http://example.com/#anchor".removeAnchor == "http://example.com/");
    assert("#anchor".removeAnchor == "");
    assert("#".removeAnchor == "");
}

/**
   Different value checks for valid href url
*/
bool isValidHref(const string href) @safe
{
    return href.cond!(
        h => h.removeAnchor == "", false,
        h => h.startsWith("/"), true,
        h => h.startsWith("http://"), true,
        h => h.startsWith("https://"), true,
        false
    );
}

/**
 * Parse the HTTP headers
 * and return true if we are dealing with an HTML file
 */
bool isHTMLFile(string[string] headers) @safe
{
	return /*"content-length" in headers &&*/ // TODO investigate
			//headers["content-length"].to!ulong < config.maxResSize &&
		    "content-type" in headers &&
			(headers["content-type"] == "text/html" ||
			headers["content-type"].startsWith("text/html;"));
}

/**
 * Parse the header of a file on disk using libmagic
 * and return true if we are dealing with an HTML file
 */
bool isHTMLFile(Path path) @safe
{
    import magic;
	return path.toString.magicType.startsWith("text/html");
}

/**
 * Convenience struct for values that must be computed every time
 */
struct URLRule{
    import std.array : array;

    URL url;
    long level;
    Regex!char rgx;
    bool isRegex;
    bool isRelative; // url does not start with http[s]
    ulong length;
    string[] segment;
    alias url this;

    this(inout string ur, inout long lev, bool isRgx) @safe {
        import std.string : startsWith;
        url = ur.parseURL;
        level = lev;
        rgx = regex(url.host);
        segment = url.path.segments.array;
        length = segment.length;
        isRegex = isRgx;
        ur.cond!(
            u => u.startsWith("http://"), { isRelative = false; },
            u => u.startsWith("https://"), { isRelative = false; },
            { isRelative = true; }
        );
    }

    bool matches(const URL url) @safe
    {
        import std.regex : matchFirst;
        return ((isRegex && url.host.matchFirst(this.rgx)) || url.host == this.host) &&
            (isRelative || (url.scheme == this.scheme && this.port == url.port));
    }
}

/**
 * check if a given URL respects the rule given
 */
bool checkLevel(const URLRule rhs, const URL lhs, int currentLev = 0) @safe
{
    import std.regex : matchFirst;

    auto lrg = lhs.path.split('/').filter!(i => i != ""); // skips http[s]
    long ldiff = lrg.walkLength - rhs.segment.length;

    return
        (!rhs.isRegex || lhs.host.matchFirst(rhs.rgx)) &&
        (rhs.providedPort == 0 || lhs.port == rhs.port) &&
        (lhs.scheme == "http" || lhs.scheme == "https") &&
        ldiff <= rhs.level - currentLev;
}

unittest{
	assert(checkLevel("http://fragal.eu/", "http://fragal.eu", 1, false));
    assert(checkLevel("http://fragal.eu/", "http://fragal.eu/a/b/c", 3, false));
    assert(!checkLevel("http://fragal.eu/", "http://fragal.eu/a/b/c", 1, false));
    assert(checkLevel("http://fragal.eu", "http://fragal.eu/", 1, false));
    assert(checkLevel("fragal.eu", "http://fragal.eu/", 1, false));
    assert(checkLevel("fragal.eu", "https://fragal.eu/", 1, false));
    assert(checkLevel("http://fragal.eu", "http://fragal.eu", 1, false));
    assert(checkLevel("fragal.eu", "http://fragal.eu/", 1, false));
    assert(checkLevel("http://.*.eu", "fragal.eu", 1, true));
    assert(checkLevel("http://.*", "fragal.eu", 1, true));
    assert(!checkLevel("http://.*/", "fragal.eu/git", 0, true));
    assert(!checkLevel("http://.*.fragal.eu/", "http://fragal.eu/git", 0, true));
    assert(!checkLevel("http://.*.eu", "fragal.eu/git", 0, true));
    assert(checkLevel("http://.*.eu", "fragal.eu/git", 1, true));
    assert(checkLevel("http://.*.fragal.eu", "http://git.fragal.eu", 1, true));
    assert(checkLevel(".*.fragal.eu", "http://git.fragal.eu", 1, true));
    assert(checkLevel(".*.*.fragal.eu", "http://a.b.fragal.eu", 1, true));

    assert(checkLevel("http://fragal.eu:80/", "http://fragal.eu:80", 1, false));
    assert(!checkLevel("http://fragal.eu:80/", "http://fragal.eu:80/a/b/c", 1, false));
    assert(checkLevel("http://fragal.eu:80", "http://fragal.eu:80/", 1, false));
    assert(checkLevel("fragal.eu:80", "http://fragal.eu:80/", 1, false));
    assert(checkLevel("http://.*.eu:80", "fragal.eu:80", 1, true));
    assert(checkLevel("http://.*", "fragal.eu:80", 1, true));
    assert(!checkLevel("http://.*/", "fragal.eu:80/git", 0, true));
    assert(!checkLevel("http://.*.fragal.eu:80/", "http://fragal.eu:80/git", 0, true));
    assert(!checkLevel("http://.*.eu:80", "fragal.eu:80/git", 0, true));
    assert(checkLevel("http://.*.eu:80", "fragal.eu:80/git", 1, true));
    assert(checkLevel(".*.fragal.eu:80", "http://git.fragal.eu:80", 1, true));
}

/**
 * O(n) find the rule that matches the url given,
 * does not check if the rule is respected
 */
URLRule findRule(const URL src, URLRule[] rules) @safe
{
    import std.algorithm.iteration : filter;
    import std.range : takeOne;
    return rules.filter!(rule => rule.matches(src)).takeOne.front;
}

unittest{

    URLRule[] rules;
    rules ~= URLRule("fragal.eu", 2, false);
    rules ~= URLRule("https://.*.fragal.eu", 1, true);
    rules ~= URLRule(".*.fragal.eu", 0, true);
    rules ~= URLRule(".*", 0, true);
    assert(findRule("http://fragal.eu/a/b", rules) == rules[0]);
    assert(findRule("https://fragal.eu/a/b", rules) == rules[0]);
    assert(findRule("http://a.fragal.eu/a/b", rules) == rules[2]);
    assert(findRule("https://a.fragal.eu/a/b", rules) == rules[1]);
    assert(findRule("https://francescomecca.eu", rules) == rules[$-1]);
}

struct StopRecur {};
struct Asset {};
alias Level = SumType!(int, StopRecur, Asset); /// Possible return values for couldRecur
/**
 * compare an url against the rule specified for it
 * and return the level of recursion if it passes
 * Levels start from 0
 * but on config file they are specified starting from 1
 */
import arrogant : Node;
Level couldRecur(const URL url, const int lev, const URLRule current, const string tag, Node node)
{
	typeof(return) ret;
	if(tag == "script" ||
	   tag == "img" ||
	   (tag == "link" && node["rel"] == "stylesheet")){
		ret = Asset();
	} else {
		// check level by connections, not path
		auto rule = findRule(url, config.rules);
		int level = rule == current ? lev + 1 : 1;
		if(rule.level >= level) ret = level;
		else ret = StopRecur();
		// ret =  checkLevel(rule, url, level) ? Level(level) : Level(StopRecur());
		// TODO decide if byPath or byRequests. Config file maybe
	}

	return ret;
}
