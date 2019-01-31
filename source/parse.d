module parse;

import scarpa;
import config;

import ddash.functional : cond;
import sumtype;

import std.typecons : Tuple, tuple;
import std.algorithm.searching : startsWith, endsWith;
import std.string : stripLeft, lastIndexOf, count;
import std.range : empty;

/**
 * Module that contains functions related to HTTP, URL schema and HTTP
 */

/**
 * Parse an URL and
 * return a tuple of URL, pathname
 */
alias ParseResult = Tuple!(string, "url", string, "fname");
alias parseResult = tuple!("url", "fname");

ParseResult parseUrl(const string url, const string absRooturl)
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
	import std.conv : to;
    auto p = parseUrl("/about", "http://fragal.eu/");
    assert(p == parseResult("http://fragal.eu/about", "../fragal.eu/about"), p.to!string);

    p = parseUrl("http://example.com", "http://fragal.eu/");
    assert(p == parseResult("http://example.com", "../example.com"), p.to!string);

    p = parseUrl("http://example.com/about", "http://fragal.eu/");
    assert(p == parseResult("http://example.com/about", "../example.com/about"), p.to!string);
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
bool isValidHref(const string href)
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
