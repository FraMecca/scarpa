module actors;

import config : config;
import events;
import database;
import logger;

import sumtype;

import std.concurrency;
import std.typecons;
import std.container.dlist;


void mainActor()
{
	auto db = createDB(config.projdir ~ "/scarpa.db");
    log(config.projdir);

	auto queue = DList!Event();

	while(true) {
        log("db nel while");
		receive(
			(shared Event ee) {
                auto e = cast(Event) ee;
                // TODO investigate how to avoid shared
                log("db ev");
				if(!db.testEvent(e.uuid) && !e.resolved) queue.insertBack(e);
				else insertEvent(db, e);
				},
			(Tid tid) {
                log(cast(int)queue.empty);
                if(!queue.empty) {
                    log(tid);
                  auto ev = cast(shared) queue.front;
                  queue.removeFront();
                  tid.send(ev);
                }
			},
            (Variant v) {
                assert(false);
            }
		);
	}
}
