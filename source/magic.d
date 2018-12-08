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
enum
    MAGIC_NONE              = 0x000000, /// No flags
    MAGIC_DEBUG             = 0x000001, /// Turn on debugging
    MAGIC_SYMLINK           = 0x000002, /// Follow symlinks
    MAGIC_COMPRESS          = 0x000004, /// Check inside compressed files
    MAGIC_DEVICES           = 0x000008, /// Look at the contents of devices
    MAGIC_MIME_TYPE         = 0x000010, /// Return the MIME type
    MAGIC_CONTINUE          = 0x000020, /// Return all matches
    MAGIC_CHECK             = 0x000040, /// Print warnings to stderr
    MAGIC_PRESERVE_ATIME    = 0x000080, /// Restore access time on exit
    MAGIC_RAW               = 0x000100, /// Don't translate unprintable chars
    MAGIC_ERROR             = 0x000200, /// Handle ENOENT etc as real errors
    MAGIC_MIME_ENCODING     = 0x000400, /// Return the MIME encoding
    MAGIC_APPLE = 0x000800; /// Return the Apple creator

enum MAGIC_MIME = MAGIC_MIME_TYPE | MAGIC_MIME_ENCODING;

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

