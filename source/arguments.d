module arguments;

import logger;
import parse;

import sdlang;
import simpleconfig;
import sumtype;

import std.exception : enforce;
import std.string;
import std.range;
import std.traits;

import std.stdio : writeln;

struct NEW_PROJECT {};
struct RESUME_PROJECT {};
struct EXAMPLE_CONF {};
struct HELP_WANTED {};
struct NO_ARGS {};
struct ARGS_ERROR { string error; };

alias CLIResult = SumType!(NEW_PROJECT, RESUME_PROJECT, EXAMPLE_CONF, HELP_WANTED,
                           NO_ARGS, ARGS_ERROR);

///
struct Config {
    @cli("max-response-size") @cfg("max-response-size")
	long maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
    @cli("parallel|P") @cfg("parallel")
	int maxEvents = 64; // number of events processed concurrently
    @cli("check-after-save") @cfg("check-after-save")
	bool checkFileAfterSave = true; // after a file is saved, check if it is HTML and parse it again
    @cli("resume|R")
    bool resume = false;
    @cli("directory|d")
    string projdir; // considered project name
    @cli("url|u") @cfg("url")
    string rootUrl;
    @cli("speed|s") @cfg("speed")
    long kbps;
    @cli("log|l") @cfg("log")
    string log = "scarpa.log";
    @cli("rules|r") @cfg("rules")
    string ruleFile = "rules.sdl";
    @cli("url-all") @cfg("all")
    long allUrlsRule = 0;
    @cli("url-domain") @cfg("domain")
    long domainRule = 0;
    @cli("url-subdomain") @cfg("subdomain")
    long subdomainRule = 0;

    URLRule[] rules;
    CLIResult action;
	// wildcard on type of file TODO

    void finalizeConfig()
    {
        import std.path : isAbsolute, asAbsolutePath;
        import std.array : array;
        if(projdir == "" || projdir.empty){
            action = ARGS_ERROR("Must get a valid project directory");
        } else {
            try{
                rules = loadRules(ruleFile);
            } catch(Exception e){
                action = ARGS_ERROR("Can't read rule file.");
            }
        }

        if (resume) {
            action = RESUME_PROJECT();

        } else {
            // sanity checks
            if(!projdir.isAbsolute)
                projdir = projdir.asAbsolutePath.array;
            if(!projdir.endsWith("/"))
                projdir ~= "/";

            action = NEW_PROJECT();
        }
        if(projdir.empty) action = ARGS_ERROR("invalid project directory");
        if(rootUrl.empty) action = ARGS_ERROR("invalid root URL");
        if(rules.empty) action = ARGS_ERROR("No rules specified");
    }
}

__gshared Config _config;

private URLRule[] loadRules(const string path) @trusted
{
    import std.algorithm.iteration : filter;
    import std.file : readText;

    auto dst = readText(path);
	auto root = parseSource(dst);

    URLRule[] rules;

    // TODO: make aliases for SUBDOMAIN and DOMAIN

    auto globalRule = URLRule(".*", 0, true); /// catch-all rule, always at the end
    foreach(val ; root.tags().filter!(s => s.getFullName.name == "rule")){
        auto urlst = val.getValue!string;
        auto lev = val.getValue!int;
        if(urlst == ".*"){
            globalRule = URLRule(urlst, lev, true);
            continue;
        }
        auto isRegex = !val.getAttribute!bool("literal") || val.getAttribute!bool("regex");
        rules ~= URLRule(urlst, lev, isRegex);
    }
    rules ~= globalRule; // always at the end

    return rules;
}

Config config() @trusted
{
    return _config;
}

void dumpExampleConfig() // TODO
{
	assert(false);
}

CLIResult parseCli(string[] args)
{

	if(args.length <= 1) return CLIResult(NO_ARGS());

    Config c;
    scope(success)
        _config = c;

    readConfiguration(c);


	return c.action;
}
