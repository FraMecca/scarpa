module scarpa;

import parse;
import database;
import events;
import logger;
import config : config, parseCli ;

// TODO handle update / existing files

/**
events:
1. request to website
2. parse links -> find links -> to .1
3. translation links -> files
4. save to disk
*/
void main(string[] args)
{
    import std.range;

    if(!parseCli(args))
        return;
    enableLogging(config.log);

    warning(config.projdir);

	Event[] list;
	Event req = RequestEvent("http://fragal.eu");
	list ~= req;

    auto db = createDB("prova.db");

    while(!list.empty){
        auto ev = list.front; list.popFront;
        list ~= ev.resolve;
    }
}

