module database;

import events;

import d2sqlite3;
import sumtype;

import std.algorithm.mutation : move;
import std.json;
import std.typecons;
import std.uuid;

enum Type {
           RequestEvent = 0,
           HTMLEvent = 1,
           ToFileEvent = 2
};

auto createDB(const string location)
{
    auto db = Database(location);

    // TODO text length for uuid
    auto table =
        r"create table Event (
           id integer primary key autoincrement,
           type integer,
		   resolved integer not null,
           uuid text not null unique,
           parent text,
           data text not null
          )";
    db.run(table);
    return db;
}

/** resolved is used to resume interrupted work.
  * HTML/FILE events are always the result of a single request event.
  * Request events need to be marked as `over` when its only child is resolved.
*/
void insertEvent(RefCounted!(Database, RefCountedAutoInitialize.no) db, Event e)
{
	assert(e.resolved == true); // To be called only when an event is solved

	auto data = e.toJson.toString();
	auto parent = e.parent.isNull ? "" : e.parent.get.toString;
	auto uuid = e.uuid.get.toString;

	Statement statement = db.prepare(
				"INSERT INTO Event (type, resolved, uuid, parent, data)
				VALUES (:type, :uuid, :parent, :data)"
			);
	statement.bind(":type", e.match!(
				 (RequestEvent _ev) => Type.RequestEvent,
				 (HTMLEvent _ev) => Type.HTMLEvent,
				 (ToFileEvent _ev) => Type.ToFileEvent
			));
	statement.bind(":resolved", e.match!(
				 (RequestEvent _ev) => _ev.requestOver,
				 (HTMLEvent _ev) => true,
				 (ToFileEvent _ev) => true,
			));
	statement.bind(":uuid", uuid);
	statement.bind(":parent", parent);
	statement.bind(":data", e.toJson.toString());

	statement.execute();
	statement.reset(); // Need to reset the statement after execution.

	e.match!(
		 (RequestEvent _ev) {},
		 (HTMLEvent _ev) {
			 //auto ddb = db;
			 //updateParent(ddb, _ev.parent.get);
		 	 assert(false);
			 },
		 (ToFileEvent _ev) {
			 //auto ddb = db;
			 //updateParent(ddb, _ev.parent.get);
		 	 assert(false);
			 }
	);
}

/// find parent and update its `resolved` status to `true`
void updateParent(Database db, UUID parent)
{
	Statement statement = db.prepare(
			"UPDATE Event
				SET resolved = 1,
				WHERE uuid = :uuid"
			);

	statement.bind(":uuid", parent.toString);

	statement.execute();
	statement.reset(); // Need to reset the statement after execution.
}

bool testEvent(Database db, UUID uuid)
{
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
