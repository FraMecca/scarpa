module io;

import vibe.core.file;
import vibe.core.path;

import ddash.functional : cond;
import sumtype : SumType, match;
import requests : ReceiveAsRange;

import std.exception: enforce;
import std.typecons : Tuple, tuple;

// TODO : manage special files

/**
 * Functions related to disk I/O
 */

alias existsDir = existsFile;
alias Path = PosixPath;

/**
 * Create a directory.
 * Recur if the parent is a file or it does not exist.
 */
void makeDirRecursive(const Path src)
{
    auto path = src.endsWithSlash ? Path(src.toString[0 .. $-1]) : src;

    auto parent = path.parentPath;
    if(!parent.existsDir) makeDirRecursive(parent);
    auto parentInfo = parent.getFileInfo;

    // check for special file
    parentInfo.cond!(
        p => p.isDirectory, {},
        // special
        { handleFileExists(parent); } // is a file
    );

    if(!path.existsFile){
        path.createDirectory;
        return;
    } else {
      auto dir = getFileInfo(path);

      dir.cond!(
          d => d.isDirectory, {},
          // special
          d => handleFileExists(path), // is a file
      );
    }
}

/// ditto
void makeDirRecursive(const string fpath)
in{
    import std.string : lastIndexOf;
    assert(fpath.lastIndexOf('/') > 0, fpath);
} do
{
    auto path = Path(fpath);
    makeDirRecursive(path);
}


/** Handle the case in which
  * a html file was saved, but a directory has to be created
  * Moves the file to DIR/index.html, creating DIR
  * throws if file is not HTML OR is POSIX special file
*/
void handleFileExists(const Path path)
in {
    import std.file : isFile;
	assert(path.toString.isFile, "Given path is not a file");
}
do {
    import magic;
    import std.string : lastIndexOf;
    import std.file : tempDir;
    import std.random : rndGen;
    import std.conv : to;
    import std.algorithm.searching : startsWith;

	enforce(path.toString.magicType.startsWith("text/html"), "Given path is not an HTML file.");

    auto tmp = tempDir;
    auto tname = Path(tmp ~ "/" ~ path.head.name ~ "." ~ rndGen.front.to!string);
    path.moveFile(tname, true);
    makeDirRecursive(path);
    auto dst = Path(path.toString ~ "/index.html");
    tname.moveFile(dst, true);
}

/** Handle the case in which
 * a directory exists and a html file with the same name has to be written
 * returns DIR/index.html
*/
Path handleDirExists(const Path path) @safe
in {
    import std.file : isDir;
	assert(path.toString.isDir, "Given path is not a directory");
}
do {
	return Path(path.toString ~ "/index.html");
}

alias FileContent = SumType!(ReceiveAsRange, string);
/**
 * Write to File.
 * Given that many modern webservers don't follow
 * conventions on trailing slashes
 * it overwrites the file in case two url that differ only bcs of the trailing slash
 * are found
 */
void writeToFile(const Path fname, inout FileContent content)
{
    import vibe.core.file : openFile, FileMode, createTempFile;
    import std.string : representation;
    import std.algorithm.iteration : each;

    Path manageSlash(const Path path)
    {
        assert(fname.existsFile);
        auto info = getFileInfo(path);
        return info.cond!(
            i => i.isDirectory, { return handleDirExists(path); },
            // special file
            { return path; }
            );
    }

    auto fp = createTempFile();
    content.match!(
        (const string s) {
            fp.write(s.representation);
        },
        (const ReceiveAsRange cr) {
            auto r = cast(ReceiveAsRange)cr; // cannot use bcs const
            r.each!((e) => fp.write(e));
        }
    );
    auto dst = fname.existsDir ? manageSlash(fname) : fname;
    copyFile(fp.path, dst, true);
}

/**
 * Make an HTTP request given the URL.
 * Either fetch the entire content as a string if it is an HTML page
 * or return an OutputRange containing binary data
 */
FileContent requestUrl(const string url) @trusted
{
    import requests : Request;
    import parse : isHTMLFile;
    import std.utf;
	import std.array : appender;
	import std.algorithm.iteration : each;

	typeof(return) ret;

	auto rq = Request();
	rq.useStreaming = true;
    rq.sslSetCaCert("/etc/ssl/cert.pem"); // TODO manage
	auto rs = rq.get(url);
	auto resBody = appender!string;

	if (rs.responseHeaders.isHTMLFile) {
		rs.receiveAsRange().each!(e => resBody.put(e));
		ret = resBody.data;
	} else {
		ret = rs.receiveAsRange();
	}

	return ret;
}
