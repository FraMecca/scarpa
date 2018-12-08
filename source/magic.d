// wrap libmagic
import std.string;
import std.exception : enforce;

string magicType(const string path)
{
	char[32] dst;
	auto rc = magic_type(path.toStringz, dst.ptr);
	if(rc == 1) enforce(false, "Unable to initialize libmagic");
	else if(rc == 2) enforce(false, "Unable to load magic MIME db");
	return cast(string)dst.ptr.fromStringz;
}

extern (C) {
@system:
nothrow:

alias magic_t = void*;

magic_t magic_open(int flags);
void magic_close(magic_t ms);
int magic_load(magic_t ms, in char *path);
immutable(char) *magic_file(magic_t ms, in char *path);

int magic_type(const char* path, char* dst)
{
	magic_t magic_cookie;

	magic_cookie = magic_open(MAGIC_MIME);

	if (magic_cookie == null) {
		return 1; // unable to open magic
	}

	if (magic_load(magic_cookie, null) != 0) {
		magic_close(magic_cookie);
		return 2; // unable to load magic db
	}

	dst = magic_file(magic_cookie, path);
	magic_close(magic_cookie);
	return 0;
}
}

