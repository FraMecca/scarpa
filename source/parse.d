module parse;

import scarpa;
import config : config;

import vibe.core.log;
import requests;
import ddash.functional;
import sumtype;

import std.string;
import std.typecons;
import std.variant;

alias ParseResult = Tuple!(string, "url", string, "fname");
alias parseResult = tuple!("url", "fname");
ParseResult parseUrl(const string url, const string absRooturl)
in{
    assert(absRooturl.startsWith("http://") || absRooturl.startsWith("https://"), absRooturl);
    assert(url.startsWith("http://") || url.startsWith("https://") || url.startsWith("/"), url);
}
do{

    //string rooturl = absRooturl.cond!(
          //u => u.startsWith("http://"), u => u.stripLeft("http://"),
          //u => u.startsWith("https://"), u => u.stripLeft("https://"),
          //"");
	string rooturl = absRooturl.toFileName("", false);
    assert(rooturl);
    string src, dst;
    // write full path in case of relative urls
	src = url.cond!(
		  u => u.startsWith("/"), u => absRooturl.cond!(
				a => a.endsWith("/"), a => a[0..$-1] ~ u,
				a => a ~ u), // stripped trailing /
	      u => u
	);

    // write filename on disk
	dst = toFileName(url, rooturl, false);
    return parseResult(src, dst);
}

string toFileName(const string url, const string absRooturl = "", const bool addIndex = true) @safe
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

	return dst;
}

unittest{
	import std.conv : to;
    auto p = parseUrl("/about", "http://fragal.eu/");
    assert(p == parseResult("http://fragal.eu/about", "fragal.eu/about"), p.to!string);

    p = parseUrl("http://example.com", "http://fragal.eu/");
    assert(p == parseResult("http://example.com", "example.com"), p.to!string);

    p = parseUrl("http://example.com/about", "http://fragal.eu/");
    assert(p == parseResult("http://example.com/about", "example.com/about"), p.to!string);

	assert("https://fragal.eu/".toFileName == "fragal.eu/index.html");
	assert("https://fragal.eu".toFileName == "fragal.eu/index.html");
}

private bool isHTMLFile(string[string] headers)
{
	return /*"content-length" in headers &&*/ // TODO investigate
			//headers["content-length"].to!ulong < config.maxResSize &&
		    "content-type" in headers &&
			(headers["content-type"] == "text/html" ||
			headers["content-type"].startsWith("text/html;"));
}

SumType!(ReceiveAsRange, string) requestUrl(const string url) @trusted
{
    import std.utf ;
	import std.array : appender;
	import std.algorithm.iteration;

	typeof(return) ret;


	auto rq = Request();
	rq.useStreaming = true;
	auto rs = rq.get(url);
	auto resBody = appender!(string);

	if (rs.responseHeaders.isHTMLFile) {
		rs.receiveAsRange().each!(e => resBody.put(e));
		ret = resBody.data;
	} else {
		ret = rs.receiveAsRange();
	}

	return ret;
}

void makeDir(const string path)
{
	import std.file : mkdirRecurse;
	import std.string : lastIndexOf;

	auto dir = path[0..(path.lastIndexOf('/'))];
	logInfo("Creating dir: %s", dir);

	dir.mkdirRecurse;

	handleFileError(path);
}

/** handle cases in which:
  * 1. a html file was saved, but it is a directory (returns DIR/index.html)
  * 2. a directory exists and a html file with the same name is present (returns DIR/index.html)
  * throws if file is not HTML OR is POSIX special file
*/
string handleFileError(const string path)
{
	import std.file;
	//import magic;


	//m.load("/usr/share/misc/magic.mgc");

	//auto type = m.file(path);
	
	//logWarn("%s: %s", path, type);
	//path.cond!(
			//p => p.isFile && m.file(p) == "text/html",

	// case 1

}
