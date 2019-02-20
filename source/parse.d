module parse;

import scarpa;
import config : config;
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
alias ParseResult = Tuple!(URL, "url", string, "fname");
alias parseResult = tuple!("url", "fname");

ParseResult url_and_path(const string url, const URL absRooturl) @safe
in{
    // assert(absRooturl.startsWith("http://") || absRooturl.startsWith("https://"), absRooturl);
    assert(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("/"), url);
}
do{
	// string rooturl = absRooturl.toFileName("", false);
    string dst;
    URL src;
    // write full path in case of relative urls
    if(url.startsWith("/")){
        src = URL(absRooturl);
        src.path = url.removeAnchor;
    } else {
        src = url.parseURL;
        src.fragment = "";
    }

	// src = url.cond!(
	// 	  u => u.startsWith("/"), u => absRooturl.cond!(
	// 			a => a.endsWith("/"), a => a[0..$-1] ~ u,
	// 			a => a ~ u), // stripped trailing /
	//       u => u
	// ).removeAnchor;

    // write filename on disk sued on href=...
	dst = toFileName(src, absRooturl, false);
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
        segment = url.path.split('/').filter!(i => i != "").array;
        length = segment.length;
        isRegex = isRgx;
        ur.cond!(
            u => u.startsWith("http://"), { isRelative = false; },
            u => u.startsWith("https://"), { isRelative = false; },
            { isRelative = true; }
        );
        // debug{
        //     writeln("Rule: ", ur, " isRegex: ", isRegex, " isRelative: ", isRelative);
        // }
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

/// ditto
bool checkLevel(const string rhs, const string lhs, const long lev, bool isRegex) @safe
{
    auto rule = URLRule(rhs, lev, isRegex);
    return checkLevel(rule, lhs.parseURL);
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

/// ditto
URLRule findRule(const string src, URLRule[] rules) @safe
{
    return findRule(src.parseURL, rules);
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

bool couldRecur(const string url, const int lev)
{
    auto u = url.parseURL;
    auto rule = findRule(u, config.rules);
    return checkLevel(rule, u, lev);
}
