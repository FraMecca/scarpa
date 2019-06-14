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

import vibe.core.concurrency;
import std.algorithm.iteration : each, filter;

// TODO: user agent

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
                (DUMP_CONF r) { dumpInitConfig(); },
				(NEW_PROJECT r) { startProject(); },
                (RESUME_PROJECT r) { resumeProject(); }, // TODO import data from db
                (NO_ARGS r) { stderr.writeln("No arguments specified"); exitCode = 1; }
        );

    return exitCode;
}

void startProject()
{
	enableLogging(config.log);
	auto first = firstEvent(config.rootUrl);
	auto storage = Storage(config.projdir ~ "/scarpa.db", [first], thisTid, true);
    work(storage);
}

void resumeProject()
{
	enableLogging(config.log);
    // TODO: maybe more eloquent
	auto storage = Storage(config.projdir ~ "/scarpa.db", [], thisTid, false);
    immutable firsts = storage.unresolvedEvents();
    firsts.each!(e => storage.put(e));
    work(storage);
}

void work(ref Storage storage)
{
    import std.range;

    import vibe.core.task;
    import ddash.functional : cond;
    import ddash.utils : Expect, Unexpected, dmatch = match;


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
            .dmatch!((EventRange r) {
                    r.each!(e => storage.put(e)); // enqueue
                },
                (Unexpected!string s) {
                    logException(s);
                });
		storage.tasks.remove(uuid);
	}
}
