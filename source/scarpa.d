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

// TODO handle update / existing files
struct Storage {
	import d2sqlite3;
	import containers;
	import std.container : BinaryHeap;

	Database db;
	//HashMap!(string, Future!(Event[])) tasks;
	Future!(Event[])[string] tasks;
	Event[] queue;

	this(const string location, Event first) @trusted
	{
		db = createDB(location);
		queue ~= first;
	}

	@property bool empty() @safe
	{
		return queue.empty;
	}

	Event getEvent() @safe
	{
		auto ev = queue.front;
		queue.popFront();

		if(db.testEvent(ev)) return getEvent();
		else {
			db.insertEvent(ev);
			return ev;
		}
	}

	void put(Event ev) @safe
	{
		queue ~= ev;
	}

	void fire(Event ev, Tid tid) @trusted
	{
		auto uuid = ev.uuid.get.toString;

		auto go() {
			auto results = ev.resolve;
			db.setResolved(ev);
			tid.send(uuid);
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
        }, // TODO createDB
		CLIResult.RESUME_PROJECT, { writeln("Resume this project"); }, // TODO import data from db
		CLIResult.NO_ARGS, { stderr.writeln("No arguments specified"); exit = true; },
		);

	if(exit) return 2;

    enableLogging(config.log);

    warning(config.projdir);

    auto first = firstEvent(config.rootUrl);
	auto storage = Storage(config.projdir ~ "/scarpa.db", first);

    while(!storage.empty){
		auto ev = storage.getEvent();
		storage.fire(ev, thisTid);

		// receive result (from first available)
		auto uuid = receiveOnly!string();
		auto newEvents = storage.tasks[uuid].getResult();

		// enqueue
		foreach (e; newEvents) {
			storage.put(e);
		}
    }

	return 0;
}
