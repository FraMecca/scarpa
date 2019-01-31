module scarpa;

import parse;
import io;
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
import std.algorithm;

struct BinnedPQ {
	EventRange[EventType] bins;

	@property bool empty() @safe
	{
		foreach(bin; bins) {
			if(!bin.empty) return false;
		}
		return true;
	}

	@property Event front() @safe
	{
		import std.stdio;
		static foreach_reverse(T; EventSeq) {
			mixin("if(EventType."~T.stringof~" in bins && !bins[EventType."~T.stringof~"].empty)
					return bins[EventType."~T.stringof~"].front;");
		}
		assert(false, "Cannot return front from an empty BinnedPQ");
	}

	void popFront() @safe
	{
		static foreach_reverse(T; EventSeq) {
			mixin("if(EventType."~T.stringof~" in bins && !bins[EventType."~T.stringof~"].empty)
					{ bins[EventType."~T.stringof~"].popFront(); return; }");
		}
		assert(false, "Cannot pop front from an empty BinnedPQ");
	}

	void put(Event ev) @safe
	{
		ev.match!(
				(RequestEvent e) => bins[EventType.RequestEvent] ~= makeEvent!e,
				(HTMLEvent e) => bins[EventType.HTMLEvent] ~= makeEvent!e,
				(inout ToFileEvent e) => bins[EventType.ToFileEvent] ~= makeEvent!e
				);
	}
}

// TODO handle update / existing files
struct Storage {
	import d2sqlite3;

	Database db;
	//HashMap!(string, Future!(Event[])) tasks;
	Future!(Event[])[string] tasks;
	BinnedPQ queue; // TODO priority queue
	Tid mainTid;

	this(const string location, Event first, Tid tid) @trusted
	{
		db = createDB(location);
		queue.put(first);
		mainTid = tid;
	}

	@property bool empty() @safe
	{
		return queue.empty;
	}

	@property Event front() @trusted
	{
		assert(!empty(), "Cannot fetch front from an empty Storage Range");

		return queue.front;
	}

	@property bool toSkip(Event ev) @trusted
	{
		if(db.testEvent(ev)) {
			return true;
		} else {
			return false;
		}
	}

	void popFront() @safe
	{
		assert(!empty(), "Cannot pop the front from an empty Storage Range");
		queue.popFront();
	}

	void put(Event ev) @safe
	{
		if(toSkip(ev)) return;
		queue.put(ev);
	}

	void fire(Event ev) @trusted
	{
		assert(!toSkip(ev));

		db.insertEvent(ev);
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
            makeDirRecursive(config.projdir);
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
		storage
			.take(NEVENTS)
			.filter!((Event e) => !storage.toSkip(e))
			.each!((Event e) => storage.fire(e));

        // receive result (from first available)
        auto uuid = receiveOnly!string();
        auto newEvents = storage.tasks[uuid].getResult();

        // enqueue
        foreach (e; newEvents) {
            storage.put(e);
		}
    }
}
