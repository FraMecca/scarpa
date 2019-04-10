module config;

import logger;
import parse;

import sdlang;
import std.io;

import std.exception : enforce;
import std.string;
import std.range;
import std.traits;

import std.stdio : writeln;

enum CONFIG_FILE = "config.sdl";

///
struct Config {
	long maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
	uint maxEvents = 256; // number of events processed concurrently
	bool checkFileAfterSave = true; // after a file is saved, check if it is HTML and parse it again
    string projdir; // considered project name
    string rootUrl;
    string log = "scarpa.error.log";
    URLRule[] rules;
	// TODO kb/sec max
	// wildcard on type of file TODO
}

__gshared Config _config;

private Config loadConfig(const string path, Config c) @trusted
{
    import std.algorithm.iteration : filter;
    import std.algorithm.searching : canFind;

	auto fp = File(path, mode!"r");
	auto dst = appender!string;
	ubyte[64] buf;
	ulong s = 0;

	do {
		s = fp.read(buf);
		dst.put(cast(string)buf[0..s]);
	} while(s > 0);

	auto root = parseSource(dst.data);

	c.maxResSize = root.getTagValue!long("maxResSize", 8 * 1024 * 1024);
	c.maxResSize = root.getTagValue!long("maxEvents", 256);
	c.checkFileAfterSave = root.getTagValue!bool("checkFileAfterSave", true);
	c.log = root.getTagValue!string("log", "scarpa.error.log");

	c.rootUrl = root.expectTagValue!string("rootUrl");

    auto globalRule = URLRule(".*", 0, true); /// catch-all rule, always at the end
    foreach(val ; root.tags().filter!(s => s.getFullName.name == "rule")){
        auto urlst = val.getValue!string;
        auto lev = val.getValue!int;
        if(urlst == ".*"){
            globalRule = URLRule(urlst, lev, true);
            continue;
        }
        auto isRegex = !val.getAttribute!bool("literal") || val.getAttribute!bool("regex");
        c.rules ~= URLRule(urlst, lev, isRegex);
    }
    c.rules ~= globalRule; // always at the end

    return c;
}

Config config() @trusted
{
    return _config;
}

enum CLIResult {
	NEW_PROJECT,
	RESUME_PROJECT,
	EXAMPLE_CONF,
	HELP_WANTED,
	NO_ARGS,
    ERROR
}

void dumpExampleConfig() // TODO
{
	assert(false);
}

CLIResult parseCli(string[] args)
{
    import std.getopt;
    import std.path : isAbsolute, asAbsolutePath;
    import std.array : array;

	if(args.length <= 1) return CLIResult.NO_ARGS;

	bool resume;
    Config c;
    string projdir;
    scope(exit)
        _config = c;

	typeof(return) res;

    auto helpInformation = getopt(args,
        // "domain|d", "wildcard of the main domain", &c.mainDomain,
        // "url|u", "initial url to request", &c.rootUrl,
        "project-dir|p", "path of the project directory", &projdir, // TODO maybe current dir default
        // "check-after-save", "check if a file can be parsed after save", &c.checkFileAfterSave,
        // "log", "location of the log file", &c.log,
        // "max-mem-size",  "limit maximum size of files parsed in memory", &c.maxResSize,
		"resume", "resume a project; if project directory is not specified, pwd is used", &resume
        );
    // TODO implement priority of cli with respect to conf file


    if (helpInformation.helpWanted){
        defaultGetoptPrinter("Scarpa the scraper. ", helpInformation.options);
        return CLIResult.HELP_WANTED;
    }

    if(projdir == "" || projdir.empty){
        writeln("Must get a valid project directory");
        return CLIResult.ERROR;
    } else {
        c = loadConfig(projdir ~ "/" ~ CONFIG_FILE, c);
        c.projdir = projdir;
    }

    if (resume) {
		res = CLIResult.RESUME_PROJECT;

	} else {
		// sanity checks
		if(!c.projdir.isAbsolute)
			c.projdir = c.projdir.asAbsolutePath.array;
		if(!c.projdir.endsWith("/"))
			c.projdir ~= "/";
		// if(c.mainDomain == "") // TODO remove
		// 	c.mainDomain = c.rootUrl;

		res = CLIResult.NEW_PROJECT;
	}
	enforce(!c.projdir.empty, "invalid project directory");
	enforce(!c.rootUrl.empty, "invalid root URL");

	return res;
}
