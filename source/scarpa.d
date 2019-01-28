module scarpa;

import parse;
import database;
import events;
import logger;
import config : config, parseCli, dumpConfig, CLIResult;

import vibe.core.concurrency;
import vibe.core.task;
import ddash.functional : cond;
import sumtype;

import std.range;
import std.typecons;

alias ValidEvent = SumType!(Event, Flag!"event");

// TODO handle update / existing files
struct Storage {
	import d2sqlite3;
	import containers;
	import std.container : BinaryHeap;

	Database db;
	//HashMap!(string, Future!(Event[])) tasks;
	Future!(Event[])[string] tasks;
	Event[] queue;
	Tid mainTid;

	this(const string location, Event first, Tid tid) @trusted
	{
		db = createDB(location);
		queue ~= first;
		mainTid = tid;
	}

	@property bool empty() @safe
	{
		return queue.empty;
	}

	ValidEvent getEvent() @trusted
	{
		auto ev = queue.front;
		queue.popFront();

		if(db.testEvent(ev) && !queue.empty) {
			return getEvent();

		} else if(!db.testEvent(ev)) {
			db.insertEvent(ev);
			return ValidEvent(ev);

		} else {
			return ValidEvent(No.event);
		}
	}

	void put(Event ev) @safe
	{
		queue ~= ev;
	}

	void fire(Event ev) @trusted
	{
		auto uuid = ev.uuid.get.toString;

		auto go() {
			auto results = ev.resolve;
			db.setResolved(ev);
			mainTid.send(uuid);
			return results;
		}

		auto task = async(&go);

		tasks[uuid] = task;
	}
}

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
        },
		CLIResult.RESUME_PROJECT, { writeln("Resume this project"); }, // TODO import data from db
		CLIResult.NO_ARGS, { stderr.writeln("No arguments specified"); exit = true; },
		);

	if(exit) return 2;

    enableLogging(config.log);

    warning(config.projdir);

    auto first = firstEvent(config.rootUrl);
	auto storage = Storage(config.projdir ~ "/scarpa.db", first, thisTid);

	const uint NEVENTS = 2; // TODO remove, debug purpose
    while(true){
		uint ne;
        while(!storage.empty && ne < NEVENTS){
            auto ev = storage.getEvent();
			ev.match!(
				(Event e) => storage.fire(e),
				(Flag!"event" f) => warning("No events in list")
				);
			ne++;
        }

        // receive result (from first available)
        auto uuid = receiveOnly!string();
        auto newEvents = storage.tasks[uuid].getResult();

        // enqueue
        foreach (e; newEvents) {
            storage.put(e);
		}
    }

	// return 0;
}
