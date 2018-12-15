module scarpa;

import parse;
import database;
import events;
import logger;
import config : config, parseCli, dumpConfig, CLIResult;

import ddash.functional : cond;
import sumtype;
// TODO handle update / existing files

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
		CLIResult.NEW_PROJECT, { dumpConfig(); }, // TODO createDB
		CLIResult.RESUME_PROJECT, { writeln("Resume this project"); }, // TODO import data from db
		CLIResult.NO_ARGS, { stderr.writeln("No arguments specified"); exit = true; },
		);

	if(exit) return 2;

    enableLogging(config.log);

    warning(config.projdir);

	Event[] list;
	Event req = RequestEvent("http://fragal.eu");
	list ~= req;

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }

	return 0;
}

