module io;

import std.exception: enforce;
import std.typecons : Tuple, tuple;
import std.conv : to;

import url : URL, parseURL, percentDecode;
import vibe.core.file;
import vibe.core.path;
import ddash.functional : cond;
import sumtype : SumType, match;
import requests : ReceiveAsRange, Request, Response;

import scarpa : assertFail;

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

    parentInfo.cond!(
        p => p.isDirectory, {},
        p => !p.isFile && !p.isDirectory, {
            enforce(false, "Special file inside work directory: " ~ parent.to!string);
        },
        { handleFileExists(parent); } // is a file
    );

    if(!path.existsFile){
        path.createDirectory;
        return;
    } else {
      auto dir = getFileInfo(path);

      dir.cond!(
          d => d.isDirectory, {},
          d => !d.isFile && !d.isDirectory, {
              enforce(false, "Special file inside work directory: " ~ dir.to!string);
          },
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

/**
 * Write to File.
 * Given that many modern webservers don't follow
 * conventions on trailing slashes
 * it overwrites the file in case two url that differ only bcs of the trailing slash
 * are found
 */
ulong writeToFile(const Path fname, const FileContent content) @trusted
{
    import vibe.core.file : openFile, FileMode, createTempFile, FileStream;
    import std.string : representation;
    import std.algorithm.iteration : each;

    Path manageSlash(const Path path)
    {
        assert(fname.existsFile);
        auto info = getFileInfo(path);
        return info.cond!(
            i => i.isDirectory, { return handleDirExists(path); },
            i => !i.isFile && !i.isDirectory, {
                return assertFail!Path("Special file inside work directory: " ~ path.to!string);
            },
            { return path; }
            );
    }

    auto dst = fname.existsDir ? manageSlash(fname) : fname;
    content.match!(
        (const HTMLPayload s) {
			auto fp = createTempFile(); 
			fp.write(s.representation);
			moveFile(fp.path, dst, true);
		},
        (const FilePayload pt) {
			moveFile(pt, dst, true);
		}
    );

	return getFileInfo(dst).size;
}

debug{
void removeFile(const FileContent content)
{
    import vibe.core.file : removeFile;
    content.match!(
        (const HTMLPayload s) {
		},
        (const FilePayload pt) {
			removeFile(pt);
		}
    );
}
}

/**
 * Read from File.
 */
string readFromFile(const Path fname)
{
    import vibe.core.file : readFile;
    import std.string : assumeUTF;

    auto content = fname.readFile;
    return content.assumeUTF;
}

struct HTMLPayload {
	string payload;
	alias payload this;
	this(string rhs) @safe { payload = rhs; }
};
alias FilePayload = Path;
alias FileContent = SumType!(FilePayload, HTMLPayload);

/**
 * Make an HTTP request given the URL.
 * Either fetch the entire content as a string if it is an HTML page
 * or return an OutputRange containing binary data
 */
FileContent requestUrl(const URL url, bool isAsset) @trusted
{
    // TODO: accept all certificates
    import parse : isHTMLFile;
    import arguments : config;
    import std.utf;
	import std.array : appender;
	import std.algorithm.iteration : each;
    import core.time : msecs;
    import vibe.core.core : sleep;

	typeof(return) ret;

	auto rq = Request();
    // rq.verbosity = 2;
	rq.useStreaming = true;
    rq.sslSetCaCert("/etc/ssl/cert.pem");

    import std.stdio;
    auto reqUrl = url.toString.percentDecode; // TODO maybe percentDecode not needed
	auto rs = rq.get(reqUrl);
	auto resBody = appender!string;

	enforce(rs.code < 400, "HTTP Response: " ~ rs.code.to!string);


    immutable kbps = config.kbps * 8 * 1024;
    long bitWritten;

    // respect speed limit configured by user
    void wait(const ubyte[] buf){
        while(kbps > 0 && buf.length + bitWritten > kbps){
            sleep(200.msecs);
            bitWritten /= 5;
        }
        bitWritten += buf.length;
    }

	if (!isAsset && rs.responseHeaders.isHTMLFile) {
		rs.receiveAsRange.each!((buf) {
            wait(buf);
            resBody.put(buf);
        });
		ret = HTMLPayload(resBody.data);
	} else {
		auto fp = createTempFile();
		rs.receiveAsRange.each!((buf) {
                wait(buf); // TODO why do we get destination already exists?
            fp.write(buf);
        });
		ret = fp.path;
	}

	return ret;
}

bool fileExists(const Path fp)
{
    import vibe.core.file : existsFile;
    return existsFile(fp);
}
