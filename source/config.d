module config;

import logger;

import sdlang;
import std.io;

import std.exception : enforce;
import std.string;
import std.range;
import std.traits;

enum CONFIG_FILE = "config.sdl";

struct Config {
	long maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
	bool checkFileAfterSave = true; // after a file is saved, check if it is HTML and parse it again
	long recurLevel = -1;
	long externRecurLevel = -1;
    string projdir; // considered project name
    string mainDomain;
    string rootUrl;
    string log = "scarpa.error.log";
	// TODO kb/sec max
	// wildcard on type of file TODO
}

__gshared Config _config;

void dumpConfig() @trusted
{
	auto root = new Tag();

	static foreach(f; __traits(allMembers, Config)) {
		mixin("root.add(
					new Tag(null, \""~f~"\", [Value(_config."~f~")])
					);");
	}

	auto fp = File(_config.projdir ~ CONFIG_FILE, mode!"w");
	fp.write(root.toSDLDocument().representation);
}

void loadConfig(const string path) @trusted
{
	auto fp = File(path, mode!"r");
	auto dst = appender!string;
	ubyte[64] buf;
	ulong s = 0;

	do {
		s = fp.read(buf);
		dst.put(cast(string)buf[0..s]);
	} while(s > 0);

	auto root = parseSource(dst.data);

	static foreach(f; __traits(allMembers, Config)) {
		mixin("_config."~f~" = root.expectTagValue!(typeof(_config."~f~"))
				(\""~f~"\");");
	}
}

Config config() @trusted
{
    return _config;
}

enum CLIResult {
	NEW_PROJECT = 0,
	RESUME_PROJECT = 1,
	HELP_WANTED = 2,
	NO_ARGS = 3
}

CLIResult parseCli(string[] args)
{
    import std.getopt;
    import std.path : isAbsolute, asAbsolutePath;
    import std.array : array;

	if(args.length <= 1) return CLIResult.NO_ARGS;

	bool resume;
    Config c;
    scope(exit)
        _config = c;

	typeof(return) res;

    auto helpInformation = getopt(args,
        "domain|d", "wildcard of the main domain", &c.mainDomain,
        "url|u", "initial url to request", &c.rootUrl,
        "project-dir|p", "path of the project directory", &c.projdir,
        "level|l", "recur for [n] levels for the main domain", &c.recurLevel,
        "external-level|e", "recur for [n] levels for external dommains", &c.externRecurLevel,
        "check-after-save", "check if a file can be parsed after save", &c.checkFileAfterSave,
        "log", "location of the log file", &c.log,
        "max-mem-size",  "limit maximum size of files parsed in memory", &c.maxResSize,
		"resume", "resume a project\nif project directory is not specified, pwd is used", &resume
        );

    if (helpInformation.helpWanted){
        defaultGetoptPrinter("Scarpa the scraper. ", helpInformation.options);
        return CLIResult.HELP_WANTED;

    } else if (resume) {
		if(!c.projdir.empty) loadConfig(c.projdir ~ CONFIG_FILE);
		else loadConfig(CONFIG_FILE);
		res = CLIResult.RESUME_PROJECT;

	} else {
		// sanity checks
		if(!c.projdir.isAbsolute)
			c.projdir = c.projdir.asAbsolutePath.array;
		if(!c.projdir.endsWith("/"))
			c.projdir ~= "/";
		if(c.mainDomain == "")
			c.mainDomain = c.rootUrl;

		res = CLIResult.NEW_PROJECT;
	}
	enforce(!c.projdir.empty, "invalid project directory");
	enforce(!c.rootUrl.empty, "invalid root URL");

	return res;
}
