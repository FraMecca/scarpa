module parse;

import scarpa;
import config;
import io;
import url;

import ddash.functional : cond;

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

/**
 * Parse an URL and
 * return a tuple of URL, pathname
 */
alias ParseResult = Tuple!(string, "url", string, "fname");
alias parseResult = tuple!("url", "fname");

ParseResult parseUrl(const string url, const string absRooturl) @safe
in{
    assert(absRooturl.startsWith("http://") || absRooturl.startsWith("https://"), absRooturl);
    assert(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("/"), url);
}
do{
	string rooturl = absRooturl.toFileName("", false);
    assert(rooturl);
    string src, dst;
    // write full path in case of relative urls
	src = url.cond!(
		  u => u.startsWith("/"), u => absRooturl.cond!(
				a => a.endsWith("/"), a => a[0..$-1] ~ u,
				a => a ~ u), // stripped trailing /
	      u => u
	).removeAnchor;

    // write filename on disk
	dst = toFileName(url.removeAnchor, rooturl, false);
    return parseResult(src, dst);
}

unittest{
    // TODO write tests for correct path
	// import std.conv : to;
    // auto p = parseUrl("/about", "http://fragal.eu/");
    // assert(p == parseResult("http://fragal.eu/about", "../fragal.eu/about"), p.to!string);

    // p = parseUrl("http://example.com", "http://fragal.eu/");
    // assert(p == parseResult("http://example.com", "../example.com"), p.to!string);

    // p = parseUrl("http://example.com/about", "http://fragal.eu/");
    // assert(p == parseResult("http://example.com/about", "../example.com/about"), p.to!string);
}

/**
 * Converts an URL to a path on the disk
 */
string toFileName(const string url, const string absRooturl = "", const bool addIndex = true) @safe
in{
    import std.algorithm.searching : canFind;
    assert(!url.canFind('#'), url);
}do
{
	string rooturl, dst;
	if(!absRooturl.empty) {
		rooturl = absRooturl.toFileName("", false);
		if(!rooturl.endsWith("/")) rooturl ~= "/";
	}

	if(addIndex) {
		dst = url.cond!(
			u => u.count("/") == 2, u => u ~ "/index.html",
			u => u.endsWith("/"), u => u ~ "index.html",
			d => d
		);
	} else {
		dst = url;
	}

	dst = dst.cond!(
		  u => u.startsWith("http://"), u => u.stripLeft("http://"),
		  u => u.startsWith("https://"), u => u.stripLeft("https://"),
		  u => u.startsWith("/"), u => rooturl ~ u.stripLeft("/"),
		  u => u
	);

	// TODO add ../ for correct parsing by browsers

	return dst;
}

unittest{
	assert("https://fragal.eu/".toFileName == "fragal.eu/index.html");
	assert("https://fragal.eu".toFileName == "fragal.eu/index.html");
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
    ulong length;
    string[] segment;
    alias url this;

    this(inout string ur, inout long lev) @safe {
        url = ur.parseURL;
        level = lev;
        rgx = regex(url.host);
        segment = url.path.split('/').filter!(i => i != "").array;
        length = segment.length;
    }
}

/**
 * check if a given URL respects the rule given
 */
bool checkLevel(const URLRule rhs, const URL lhs) @safe
{
    import std.regex : matchFirst;

    auto lrg = lhs.path.split('/').filter!(i => i != "");
    long ldiff = lrg.walkLength - rhs.segment.length;

    return
          lhs.host.matchFirst(rhs.rgx) &&
        (rhs.providedPort == 0 || lhs.port == rhs.port) &&
        (lhs.scheme == "http" || lhs.scheme == "https") &&
        ldiff <= rhs.level;
}

/// ditto
bool checkLevel(const string rhs, const string lhs, const long lev) @safe
{
    auto rule = URLRule(rhs, lev);
    return checkLevel(rule, lhs.parseURL);
}

unittest{
    assert(checkLevel("http://fragal.eu/", "http://fragal.eu", 1));
    assert(checkLevel("http://fragal.eu/", "http://fragal.eu/a/b/c", 3));
    assert(!checkLevel("http://fragal.eu/", "http://fragal.eu/a/b/c", 1));
    assert(checkLevel("http://fragal.eu", "http://fragal.eu/", 1));
    assert(checkLevel("fragal.eu", "http://fragal.eu/", 1));
    assert(checkLevel("fragal.eu", "https://fragal.eu/", 1));
    assert(checkLevel("http://fragal.eu", "http://fragal.eu", 1));
    assert(checkLevel("fragal.eu", "http://fragal.eu/", 1));
    assert(checkLevel("http://.*.eu", "fragal.eu", 1));
    assert(checkLevel("http://.*", "fragal.eu", 1));
    assert(!checkLevel("http://.*/", "fragal.eu/git", 0));
    assert(!checkLevel("http://.*.fragal.eu/", "http://fragal.eu/git", 0));
    assert(!checkLevel("http://.*.eu", "fragal.eu/git", 0));
    assert(checkLevel("http://.*.eu", "fragal.eu/git", 1));
    assert(checkLevel("http://.*.fragal.eu", "http://git.fragal.eu", 1));
    assert(checkLevel(".*.fragal.eu", "http://git.fragal.eu", 1));
    assert(checkLevel(".*.*.fragal.eu", "http://a.b.fragal.eu", 1));

    assert(checkLevel("http://fragal.eu:80/", "http://fragal.eu:80", 1));
    assert(!checkLevel("http://fragal.eu:80/", "http://fragal.eu:80/a/b/c", 1));
    assert(checkLevel("http://fragal.eu:80", "http://fragal.eu:80/", 1));
    assert(checkLevel("fragal.eu:80", "http://fragal.eu:80/", 1));
    assert(checkLevel("http://.*.eu:80", "fragal.eu:80", 1));
    assert(checkLevel("http://.*", "fragal.eu:80", 1));
    assert(!checkLevel("http://.*/", "fragal.eu:80/git", 0));
    assert(!checkLevel("http://.*.fragal.eu:80/", "http://fragal.eu:80/git", 0));
    assert(!checkLevel("http://.*.eu:80", "fragal.eu:80/git", 0));
    assert(checkLevel("http://.*.eu:80", "fragal.eu:80/git", 1));
    assert(checkLevel(".*.fragal.eu:80", "http://git.fragal.eu:80", 1));
}
