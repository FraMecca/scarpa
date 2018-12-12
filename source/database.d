import d2sqlite3;

import events;

import sumtype;

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
           type smallint,
           uuid text not null unique,
           parent text not null unique,
           data text not null
          )";
    db.run(table);
    return db;
}


