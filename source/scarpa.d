module scarpa;

import parse;
import database;
import actors;
import events;
import logger;
import config : config, parseCli, dumpConfig, CLIResult;

import ddash.functional : cond;
import sumtype;
// TODO handle update / existing files

import std.concurrency;

/**
events:
1. request to website
2. parse links -> find links -> to .1
3. translation links -> files
4. save to disk
*/
int main(string[] args)
{
    import std.range;
	import std.stdio : writeln, stderr;
	bool exit;

	parseCli(args).cond!(
		CLIResult.HELP_WANTED, { exit = true; },
		CLIResult.NEW_PROJECT, {
            makeDir(config.projdir);
            dumpConfig();
        }, // TODO createDB
		CLIResult.RESUME_PROJECT, { writeln("Resume this project"); }, // TODO import data from db
		CLIResult.NO_ARGS, { stderr.writeln("No arguments specified"); exit = true; },
		);

	if(exit) return 2;

    enableLogging(config.log);

    warning(config.projdir);

	Event req = RequestEvent(config.rootUrl);

    auto actor = spawn(&mainActor);
    actor.send(cast(shared) req);

    while(true){
        actor.send(thisTid);
        log("main send");
        receive(
            (shared Event sevent) {
                auto event = cast(Event) sevent;
                log(event);
                foreach(ev; event.resolve){
                    actor.send(cast(shared) ev);
                }
            },
            (Variant v) { assert(false); },
        );
    }

	// return 0;
}

