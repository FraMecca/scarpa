module config;

struct Config {
	ulong maxResSize = 8 * 1024 * 1024; // limits the size of the stream parsed in memory
	bool checkFileAfterSave; // after a file is saved, check if it is HTML and parse it again
	ulong recurLevel;
	ulong externRecurLevel;
	// TODO kb/sec max
	// wildcard on type of file TODO
}

__gshared Config config;
