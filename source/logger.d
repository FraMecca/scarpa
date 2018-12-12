public import std.experimental.logger;
import std.stdio : stdout, File;

enum  WARNING = "\033[93m"; // yellow
enum  ERROR = "\033[91m"; // red
enum  END = "\033[0m";

void enableLogging(const string path)
{

    auto m = new MultiLogger();
    m.insertLogger("stdout", new ColoredLogger(stdout));
    m.insertLogger("error", new FileLogger(path, LogLevel.error, CreateFolder.yes));
    sharedLog = m; // register as global logger
}

class ColoredLogger : FileLogger
{
    this(File file, const LogLevel lv = LogLevel.all) @safe
    {
        super(file, lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted
    {
        import std.array : appender;

        auto msg = appender!(char[]);
        msg.reserve(payload.msg.length + 7 + 7);

        auto ll = payload.logLevel;
        if(ll == LogLevel.warning){
            msg.put(WARNING);
            msg.put(payload.msg);
            msg.put(END);
        } else if(ll == LogLevel.error){
            msg.put(ERROR);
            msg.put(payload.msg);
            msg.put(END);
        } else {
            msg.put(payload.msg);
        }
        this.logMsgPart(msg.data);
        this.finishLogMsg();
    }
}
