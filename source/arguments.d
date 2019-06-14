module arguments;

import logger;
import parse;
import io;

import sdlang;
import simpleconfig;
import sumtype;
import ddash : cond;
import url : URL, parseURL;
import vibe.core.file : writeFile;

import std.exception : enforce;
import std.string;
import std.range;
import std.traits;
import std.algorithm.searching : canFind;
import std.conv : to;

struct NEW_PROJECT {};
struct RESUME_PROJECT {};
struct DUMP_CONF {};
struct HELP_WANTED {};
struct NO_ARGS {};
struct ARGS_ERROR { string error; };

alias CLIResult = SumType!(NEW_PROJECT, RESUME_PROJECT, DUMP_CONF, HELP_WANTED,
                           NO_ARGS, ARGS_ERROR);

///
struct Config {
	@cli("init")
	bool init = false;
    @cli("directory|d")
    string projdir; // considered project name
    @cli("resume|R")
    bool resume = false;

    @cli("max-response-size") @cfg("max-response-size")
	long maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
    @cli("parallel") @cfg("parallel")
	int maxEvents = 64; // number of events processed concurrently
    @cli("check-after-save") @cfg("check-after-save")
	bool checkFileAfterSave = true; // after a file is saved, check if it is HTML and parse it again
    @cli("url|u") @cfg("url")
    string rootUrl;
    @cli("speed") @cfg("speed")
    long kbps;
    @cli("log") @cfg("log")
    string log = "scarpa.log";
    @cli("rules") @cfg("rules")
    string ruleFile = "rules.sdl";

    URLRule[] rules;
    CLIResult action;
	// wildcard on type of file TODO

    void finalizeConfig()
    {
        import std.path : isAbsolute, asAbsolutePath;
        import std.array : array;

        if (resume && !init) {
            action = RESUME_PROJECT();
		} else if(resume && init) {
			action = ARGS_ERROR("Cannot init a non-empty project");
        } else {
            action = NEW_PROJECT();
        }

		if(init) {
			immutable cfile = projdir ~ "scarpa.cfg";
			immutable rls = projdir ~ "rules.sdl";

            if(rootUrl.empty)
                action = ARGS_ERROR("Specify root url");
            else if(Path(cfile).fileExists) 
                action = ARGS_ERROR("Configuration file already present");
            else if(Path(rls).fileExists) 
                action = ARGS_ERROR("Rules file already present");
            else
                action = DUMP_CONF();
			return;
		}

        if(rootUrl.empty) {
			action = ARGS_ERROR("Invalid root URL");
			return;
		}

        if(projdir == "" || projdir.empty) {
            action = ARGS_ERROR("Must get a valid project directory");

        } else {
            if(!projdir.isAbsolute)
                projdir = projdir.asAbsolutePath.array;
            if(!projdir.endsWith("/"))
                projdir ~= "/";

			immutable _rules = ruleFile.cond!(
					r => r.isAbsolute, r => r,
					r => projdir ~ r
					);

			try{
				enforce(!_rules.empty, "Rule file cannot be empty");
				enforce(Path(_rules).fileExists, "Rule file does not exist: " ~ _rules);
				rules = loadRules(_rules);

			} catch(Exception e){
				action = ARGS_ERROR("Can't read rule file: " ~ _rules);
			}
        }
    }

	/** Reads a file in "path" containing URL rules
	  * in regex or literal format.
	  * Path is set from projdir~ruleFile in struct Config.
	*/
	private URLRule[] loadRules(const string path) @trusted
	{
		import std.algorithm.iteration : filter;
		import std.file : readText;

		URLRule[] rules;

		auto globalRule = URLRule(".*", 0, true); /// catch-all rule, always at the end

		if(!path.empty) {
			auto dst = readText(path);
			auto root = parseSource(dst);

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
		}

		rules ~= globalRule; // always at the end

		return rules;
	}

}

/** Dump default config files in projdir
 * rules.sdl
 * scarpa.cfg (key-value)
 */
void dumpInitConfig() @trusted// TODO
{
	// dump projdir/scarpa.cfg
	string cfile;
	// TODO finish (how do function as UDAs work is still a mistery)
	static foreach(opt; __traits(allMembers, Config)) {
		mixin("foreach(attr; __traits(getAttributes, _config."~opt~")) {
					if(attr.stringof.canFind(\"CFG\"))
						cfile ~= \""~opt~"\" ~ \" = \" ~ to!string(_config."~opt~") ~ \"\n\";
				}");
	}

	writeFile(Path(_config.projdir ~ "/" ~ "scarpa.cfg"), cast(immutable(ubyte)[])cfile);

	// dump projdir/rules.sdl
	URL root = _config.rootUrl.parseURL;
	string rules = "rule \""~root.host~"/*\" 5 regex=true\n";
	rules ~= "rule \".*."~root.host~"/*\" 1 regex=true\n";
	rules ~= "rule \".*\" 0 regex=true\n";

	writeFile(Path(_config.projdir ~ "/" ~ "rules.sdl"), cast(immutable(ubyte)[])rules);
}

__gshared Config _config;

Config config() @trusted
{
    return _config;
}

CLIResult parseCli(string[] args)
{

	if(args.length <= 1) return CLIResult(NO_ARGS());

    readConfiguration(_config);

	return _config.action;
}
