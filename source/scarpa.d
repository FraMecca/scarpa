module scarpa;

debug {
    public import std.stdio : writeln;
}

import parse;
import arguments;
import io;
import storage;
import events;
import logger;


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
    import sumtype : match;
	int exitCode = 0;

	parseCli(args)
        .match!((HELP_WANTED r) {},
                (ARGS_ERROR r) { stderr.writeln(r.error); exitCode = 2; },
                (EXAMPLE_CONF r) { dumpExampleConfig(); },
                (NEW_PROJECT r) { startProject(); },
                (RESUME_PROJECT r) { writeln("Resume this project"); }, // TODO import data from db
                (NO_ARGS r) { stderr.writeln("No arguments specified"); exitCode = 1; }
        );

    return exitCode;
}

void startProject()
{
    import std.algorithm.iteration : each, filter;
    import std.range;

    import vibe.core.concurrency;
    import vibe.core.task;
    import ddash.functional : cond;
    import ddash.utils : Expect, Unexpected, match;

	enableLogging(config.log);

	auto first = firstEvent(config.rootUrl);
	auto storage = Storage(config.projdir ~ "/scarpa.db", first, thisTid);
	auto maxEvents = config.maxEvents;
	uint cntEvents;

	while(true){
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
