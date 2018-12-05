module parse;

import scarpa;
import config : config;

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
    assert(url.startsWith("http://") || url.startsWith("https://")
           || url.startsWith("/"), url);
}
do{

    string rooturl = absRooturl.cond!(
          u => u.startsWith("http://"), u => u.stripLeft("http://"),
          u => u.startsWith("https://"), u => u.stripLeft("https://"),
          "");
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
    dst = url.cond!(
          u => u.startsWith("http://"), u => u.stripLeft("http://"),
          u => u.startsWith("https://"), u => u.stripLeft("https://"),
          u => u.startsWith("/"), u => rooturl ~ u.stripLeft("/"),
          u => u
    );
    return parseResult(src, dst);
}

unittest{
    auto p = parseUrl("/about", "http://fragal.eu/");
    assert(p == parseResult("http://fragal.eu/about", "fragal.eu/about"), p.to!string);

    p = parseUrl("http://example.com", "http://fragal.eu/");
    assert(p == parseResult("http://example.com", "example.com"), p.to!string);

    p = parseUrl("http://example.com/about", "http://fragal.eu/");
    assert(p == parseResult("http://example.com/about", "example.com/about"), p.to!string);
}


private bool isHTMLFile(string[string] headers)
{
	import std.conv : to;
	return "Content-Length" in headers &&
			headers["Content-Length"].to!ulong < config.maxResSize &&
			"Content-Type" in headers &&
			headers["Content-Type"] == "text/html";
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
