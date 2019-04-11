module scarpa;

debug {
    public import std.stdio : writeln;
}

import parse;
import io;
import storage;
import events;
import logger;
import config : config, parseCli, CLIResult, dumpExampleConfig;

import vibe.core.concurrency;
import vibe.core.task;
import ddash.functional : cond;
import ddash.utils : Expect, Unexpected, match;

import std.algorithm.iteration : each, filter;

/**
 * Allows to assert(false) inside a function that requires a return value;
 */
template assertFail(T){
    debug{
        T assertFail(string msg=""){
            assert(false, msg);
        }
    } else {
        T assertFail(string msg=""){
            import std.exception : enforce;
            enforce(false, msg);
            return T();
        }
    }
}

debug{
    alias logException = fatal;
} else {
    alias logException = error;
 }

int main(string[] args)
{
	import std.stdio : writeln, stderr;
	int exitCode = 0;

	parseCli(args).cond!(
		CLIResult.HELP_WANTED, {},
		CLIResult.ERROR, { exitCode = 2; },
		CLIResult.EXAMPLE_CONF, { dumpExampleConfig(); },
		CLIResult.NEW_PROJECT, { startProject(); },
		CLIResult.RESUME_PROJECT, { writeln("Resume this project"); }, // TODO import data from db
		CLIResult.NO_ARGS, { stderr.writeln("No arguments specified"); exitCode = 1; },
		);

	return exitCode;
}

void startProject()
{
    import std.range;
	enableLogging(config.log);

	warning(config.projdir);

	auto first = firstEvent(config.rootUrl);
	auto storage = Storage(config.projdir ~ "/scarpa.db", first, thisTid);
	auto maxEvents = config.maxEvents;

	while(true){
		uint cntEvents;
		storage
			.take(maxEvents - cntEvents)
			.filter!((Event e) => !storage.toSkip(e)) 
			.each!((Event e) { cntEvents++; storage.fire(e); });

		// receive result (from first available)
		if(storage.tasks.empty && storage.queue.empty) break;

		auto uuid = receiveOnly!string;
		cntEvents--;
		storage.tasks[uuid]
			.getResult()
			.match!( // match from ddash, not sumtype
					(EventRange r) {
						r.each!(e => storage.put(e)); // enqueue
					},
					(Unexpected!string s) {
						logException(s);
					},
			);
		storage.tasks.remove(uuid);
	}
}
