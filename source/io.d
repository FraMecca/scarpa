module io;

import vibe.core.file;
import vibe.core.path;

import ddash.functional : cond;
import sumtype : SumType, match;
import requests : ReceiveAsRange;

import std.exception: enforce;
import std.string;
import std.typecons : Tuple, tuple;

/**
 * Functions related to disk I/O
 */

alias existsDir = existsFile;

void makeDirRecursive(string fpath)
in{
	import std.string : lastIndexOf;
    assert(fpath.lastIndexOf('/') > 0, fpath);
} do
{
    auto path = PosixPath(fpath);
    makeDirRecursive(path);
}

void makeDirRecursive(PosixPath path)
{

    auto parent = path.parentPath;
    if(!parent.existsDir) makeDirRecursive(parent);
    auto parentInfo = parent.getFileInfo;

    // check for special file
    parentInfo.cond!(
        p => p.isDirectory, {},
        // special
        { handleFileExists(parent.toString); } // is a file
    );

    if(!path.existsFile){
        path.createDirectory;
        return;
    } else {
      auto dir = getFileInfo(path);

      dir.cond!(
          d => d.isDirectory, {},
          // special
          d => handleFileExists(path.toString), // is a file
      );
    }
}

/** handle cases in which:
  * 1. a html file was saved, but a directory has to be created
  * Moves the file to DIR/index.html, creating DIR
  * throws if file is not HTML OR is POSIX special file
*/
void handleFileExists(const string path)
in {
    import std.file : isFile;
	assert(path.isFile, "Given path is not a file");
}
do {
    import magic;
    import std.string : lastIndexOf;
    import std.algorithm.searching : startsWith;

    // use tmp dir
	enforce(path.magicType.startsWith("text/html"), "Given path is not an HTML file.");

    string tname = path[(path.lastIndexOf('/')+1)..$] ~ ".scarpa.tmp";
    path.moveFile(tname);
    makeDirRecursive(path);
    tname.moveFile(path ~ "/index.html");
    // TODO checks?
}

/** 2. a directory exists and a html file with the same name has to be written
  * (returns DIR/index.html)
*/
string handleDirExists(const string path)
in {
    import std.file : isDir;
	assert(path.isDir, "Given path is not a directory");
}
do {
	return path ~ "/index.html";
}

alias FileContent = SumType!(ReceiveAsRange, string);
void writeToFile(const PosixPath fname, inout FileContent content)
{
    import vibe.core.file : openFile, FileMode, createTempFile;
    import std.string : representation;
    import std.algorithm.iteration : each;

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
    import std.stdio;
    writeln(fp.path);
    // auto dst = PosixPath(fname);
    auto dst = fname;
    copyFile(fp.path, dst);
}
