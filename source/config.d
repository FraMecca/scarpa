module config;


struct Config {
	ulong maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
	bool checkFileAfterSave = true; // after a file is saved, check if it is HTML and parse it again
	ulong recurLevel = -1;
	ulong externRecurLevel = -1;
    string projdir; // considered project name
    string mainDomain;
    string rootUrl;
    string log = "scarpa.error.log";
	// TODO kb/sec max
	// wildcard on type of file TODO
}

__gshared Config _config;

Config config() @trusted
{
    return _config;
}

bool parseCli(string[] args)
{
    import std.getopt;
    import std.path : isAbsolute, asAbsolutePath;
    import std.array : array;

    import ddash.functional : cond;

    Config c;
    scope(exit)
        _config = c;

    auto helpInformation = getopt(args,
        "domain|d", "wildcard of the main domain", &c.mainDomain,
        "url|u", "initial url to request", &c.rootUrl,
        "project-dir|p", "path of the project directory", &c.projdir,
        "level|l", "recur for [n] levels for the main domain", &c.recurLevel,
        "external-level|e", "recur for [n] levels for external dommains", &c.externRecurLevel,
        "check-after-save", "check if a file can be parsed after save", &c.checkFileAfterSave,
        "log", "location of the log file", &c.log,
        "max-mem-size",  "limit maximum size of files parsed in memory", &c.maxResSize,
        );
    if (helpInformation.helpWanted){
        defaultGetoptPrinter("Scarpa the scraper. ", helpInformation.options);
        return false;
    }

    // sanity checks

    if(!c.projdir.isAbsolute)
        c.projdir = c.projdir.asAbsolutePath.array;
    if(c.mainDomain == "")
        c.mainDomain = c.rootUrl;

    bool exitErr(const string err){
        import std.stdio;
        stderr.writef(err);
        return false;
    }


    return c.cond!(
                   cc => cc.projdir.length == 0, { return exitErr("empty project directory."); },
                   cc => cc.rootUrl.length == 0, { return exitErr("empty initial url."); },
                   true);
}
