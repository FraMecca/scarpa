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

    try{
        while(true) {
            receive(
                (shared Event ee) {
                    auto e = cast(Event) ee;
                    // TODO investigate how to avoid shared
                    if(!db.testEvent(e.uuid)){
                        if(!e.resolved) queue.insertBack(e);
                        insertEvent(db, e);
                    }
                },
                (Tid tid) {
                    if(!queue.empty) {
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
    } catch(Exception e){
        fatal(e.msg);
    }
}
