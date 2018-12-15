module actors;

import config : config;
import events;
import database;

import sumtype;

import std.concurrency;
import std.typecons;
import std.container.dlist;

void mainActor(Tid ownerTid)
{
	auto db = refCounted(createDB(config.projdir ~ "/scarpa.db"));

	auto queue = DList!Event();

	while(true) {
		// Receive a message from the owner thread.
		receive(
			(Event e) {
				auto ddb = db;
				if(!ddb.testEvent(e.uuid) && e.resolved) queue.insertBack(e);
				else insertEvent(ddb, e);
				},
			(Tid tid) {
				//shared Event ev = queue.front;
				//queue.removeFront();
				//tid.send(ev);
			}
		);
	}
}
