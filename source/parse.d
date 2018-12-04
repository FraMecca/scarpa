module parse;

// import fluent.asserts;
import ddash.functional;

import std.stdio;
import std.conv : to;
import std.string;
import std.typecons;

alias ParseResult = Tuple!(string, "url", string, "fname");
alias parseResult = tuple!("url", "fname");
ParseResult parseUrl(const string url, const string absRooturl)
in{
    assert(absRooturl.endsWith("/"), absRooturl);
    assert(absRooturl.startsWith("http://") || absRooturl.startsWith("https://"), absRooturl);
}
do{

    string rooturl = absRooturl.cond!(
          u => u.startsWith("http://"), u => u.stripLeft("http://"),
          u => u.startsWith("https://"), u => u.stripLeft("https://"),
          "");
    assert(rooturl);
    string src, dst;
    // write full path in case of relative urls
    src = tuple!("url", "root")(url, absRooturl).cond!(
          t => t.url.startsWith("/"), t => t.root[0..$-1] ~ t.url,
          t => t.url
    );

    // write filename on disk
    dst = tuple!("url", "fpath")(url, rooturl).cond!(
          t => t.url.startsWith("http://"), t => t.url.stripLeft("http://"),
          t => t.url.startsWith("https://"), t => t.url.stripLeft("https://"),
          t => t.url.startsWith("/"), t => t.fpath ~ t.url.stripLeft("/"),
          t => t.url
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
