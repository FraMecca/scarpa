module parse;

import scarpa;
import config : config;

import vibe.core.log;
import requests;
import ddash.functional;
import sumtype;

import std.file;
import std.exception;
import std.string;
import std.typecons;

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
	assert("https://fragal.eu/".toFileName == "fragal.eu/index.html");
	assert("https://fragal.eu".toFileName == "fragal.eu/index.html");
}

string removeAnchor(const string src) @safe
{
    auto idx = src.lastIndexOf('#');
    if(idx <= 0) return src;
    else return src[0 .. idx];
}

unittest{
    assert("http://example.com/p#anchor".removeAnchor == "http://example.com/p");
    assert("http://example.com/p#anchor/".removeAnchor == "http://example.com/p");
    assert("http://example.com/#anchor".removeAnchor == "http://example.com/");
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
	dir.cond!(
		d => d.exists && d.isFile, d => handleFileExists(d),
		d => d.exists && !d.isDir, { throw new Exception("Special file"); },
		d => d.mkdirRecurse
	);
}

/** handle cases in which:
  * 1. a html file was saved, but a directory has to be created
  * Moves the file to DIR/index.html, creating DIR
  * throws if file is not HTML OR is POSIX special file
*/
void handleFileExists(const string path)
in {
	assert(path.isFile, "Given path is not a file");
}
do {
	import magic;

	if(path.magicType.startsWith("text/html")) {
		string tname = "." ~ path[(path.lastIndexOf('/')+1)..$] ~ ".tmp";
		path.rename(tname);
		mkdirRecurse(path);
		tname.rename(path ~ "/index.html");
	} else {
		// TODO checks?
		enforce(false, "Given path is not an HTML file.");
	}
}
/** 2. a directory exists and a html file with the same name has to be written
  * (returns DIR/index.html)
*/
string handleDirExists(const string path)
in {
	assert(path.isDir, "Given path is not a directory");
}
do {
	return path ~ "/index.html";
}
