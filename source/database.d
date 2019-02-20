module database;

import events;
import logger;
import config : config;

import d2sqlite3;
import sumtype;

import std.algorithm.mutation : move;
import std.json;
import std.typecons;
import std.uuid;

auto createDB(const string location) @trusted
{
    debug{
        import std.file;
        if(exists(config.projdir ~ "scarpa.db")) remove(config.projdir ~ "scarpa.db");
    }
    auto db = Database(location);

    // TODO text length for uuid
    auto table =
        r"create table Event (
           type integer,
		   resolved integer not null,
           uuid text not null unique,
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
