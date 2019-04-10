module storage;

import events;
import logger;
import config : config;

import d2sqlite3;
import sumtype;
import vibe.core.concurrency;
import vibe.core.task;

import std.algorithm.mutation : move;
import std.json;
import std.typecons;
import std.uuid;
import std.range;
import std.typecons;
import std.algorithm;


auto createDB(const string location) @trusted
{
    debug{
        import std.file;
        if(exists(config.projdir ~ "scarpa.db")) remove(config.projdir ~ "scarpa.db");
    }
    auto db = Database(location);

    auto table =
        r"create table Event (
           type integer,
		   resolved integer not null,
           uuid varchar(16) not null unique,
           parent text,
           data text not null
          )";
    db.run(table);
    return db;
}

/** This function inserts an event in the database
  * resolved is used to resume interrupted work.
  * HTML/FILE events are always the result of a single request event.
  * Request events need to be marked as `over` when
  * its only grandchild (ToFileEvent) is resolved.
*/
void insertEvent(ref Database db, Event e) @trusted
{
	auto data = e.toJson.toString();
	auto parent = e.parent.isNull ? "" : e.parent.get.toString;
	auto uuid = e.uuid.get.toString;

	Statement statement = db.prepare(
        "INSERT INTO Event (type, resolved, uuid, parent, data)
        VALUES (:type, :resolved, :uuid, :parent, :data)"
    );
	statement.bind(":type", e.match!(
          (inout RequestEvent _ev) => EventType.RequestEvent,
          (inout HTMLEvent _ev) => EventType.HTMLEvent,
          (inout ToFileEvent _ev) => EventType.ToFileEvent,
    ));
	statement.bind(":resolved", e.match!(
          (inout RequestEvent _ev) => false,
          (inout HTMLEvent _ev) => true,
          (const ToFileEvent _ev) => true,
    ));
	statement.bind(":uuid", uuid);
	statement.bind(":parent", parent);
	statement.bind(":data", e.toJson.toString());

	statement.execute();
	statement.reset(); // Need to reset the statement after execution.


    void updateGrandParent(Database db, ID parent)
    {
        // get grandparent uuid
        Statement grandP = db.prepare("select uuid from Event
            where uuid = :uuid");
        grandP.bind(":uuid", parent.toString);
        auto requestEventId = grandP.execute().oneValue!string;
        grandP.reset();

        Statement setResolved = db.prepare(
           "UPDATE Event
            SET resolved = 1
            WHERE uuid = :uuid"
        );

        setResolved.bind(":uuid", requestEventId);
        setResolved.execute();
        setResolved.reset(); // Need to reset the statement after execution.
    }

	e.match!(
             (inout RequestEvent _ev) {},
             (inout HTMLEvent _ev) {},
             (inout ToFileEvent _ev) { updateGrandParent(db, e.parent); },
    );
}

/**
 * check if event was stored in db
 */
bool testEvent(ref Database db, Event ev) @trusted
{
	auto uuid = ev.uuid.get;

	Statement statement = db.prepare(
			"SELECT EXISTS(SELECT 1
				FROM Event
				WHERE uuid = :uuid)"
			);

	statement.bind(":uuid", uuid.toString);

	auto res = statement.execute().oneValue!bool;
	statement.reset(); // Need to reset the statement after execution.

	return res;
}

/**
 * check if event was stored in db and succesfully stored to disk
 */
bool isResolved(ref Database db, Event ev) @trusted
{
	auto uuid = ev.uuid.get;

	Statement statement = db.prepare(
			"SELECT EXISTS(SELECT 1
				FROM Event
				WHERE uuid = :uuid
				AND resolved = 1)"
			);

	statement.bind(":uuid", uuid.toString);

	auto res = statement.execute().oneValue!bool;
	statement.reset(); // Need to reset the statement after execution.

	return res;
}

void setResolved(ref Database db, Event ev) @trusted
{
	auto uuid = ev.uuid.get;

	Statement statement = db.prepare(
			"UPDATE Event
				SET resolved = 1
				WHERE uuid = :uuid
				AND resolved = 1"
			);

	statement.bind(":uuid", uuid.toString);

	statement.execute();
	statement.reset(); // Need to reset the statement after execution.
}

/**
 * A priority queue with one bin for each type of Event.
 */
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
		ev.match!((RequestEvent e) => bins[EventType.RequestEvent] ~= makeEvent!e,
				  (HTMLEvent e) => bins[EventType.HTMLEvent] ~= makeEvent!e,
				  (inout ToFileEvent e) => bins[EventType.ToFileEvent] ~= makeEvent!e
		);
	}

    @property ulong length() @safe
    {
        ulong a;
        foreach(b; bins) a += b.length;
        return a;
    }
}

// TODO handle update / existing files in the projdirectory before starting the program
/**
 * Holds a pointer to the Database, a table of executing tasks and a priority queue of Events yet to be resolved.
 */
struct Storage {

	Database db;
	Future!(EventResult)[string] tasks;
	BinnedPQ queue;
	Tid mainTid;

	this(const string location, Event first, Tid tid) @safe
	{
		db = createDB(location);
		queue.put(first);
		mainTid = tid;
	}

	/// made for std.range and std.algorithm. Resolves to queue.empty
	@property bool empty() @safe
	{
		return queue.empty;
	}

	@property Event front() @safe
	{
		assert(!empty(), "Cannot fetch front from an empty Storage Range");

		return queue.front;
	}

	@property bool toSkip(Event ev) @safe
	{
		if(db.testEvent(ev))
            return true;
		else
            return false;
	}

	void popFront() @safe
	{
		assert(!empty(), "Cannot pop the front from an empty Storage Range");
		queue.popFront();
	}

	void put(Event ev) @safe
	{
		if(toSkip(ev))  return;
		queue.put(ev);
	}

	void fire(Event ev) @trusted
	{
		assert(!toSkip(ev));

		db.insertEvent(ev);
		immutable uuid = ev.uuid.get.toString;

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
