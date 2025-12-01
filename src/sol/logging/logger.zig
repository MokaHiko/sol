const std = @import("std");

pub const Level = enum {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Critical,
};

pub const Options = struct {
    level: Level = Level.Debug,
    prefix: []const u8 = "",
};

pub fn Logger(comptime opts: Options) type {
    return struct {
        pub inline fn trace(comptime format: []const u8, args: anytype) void {
            log(Level.Trace, format, args);
        }

        pub inline fn debug(comptime format: []const u8, args: anytype) void {
            log(Level.Debug, format, args);
        }

        pub inline fn err(comptime format: []const u8, args: anytype) void {
            log(Level.Error, format, args);
        }

        inline fn log(level: Level, comptime format: []const u8, args: anytype) void {
            const color_reset = "\x1b[0m";

            const prefix = comptime blk: {
                var prefix = level_color(level);

                prefix = prefix ++ opts.prefix;

                break :blk prefix;
            };

            const full_format = prefix ++ format ++ color_reset;

            switch (level) {
                .Debug => std.log.debug(full_format, args),
                .Info => std.log.info(full_format, args),
                .Trace => std.log.debug(full_format, args),
                .Error => std.log.err(full_format, args),
                .Critical => std.log.err(full_format, args),

                else => {},
            }
        }
    };
}

fn level_color(level: Level) []const u8 {
    return switch (level) {
        .Trace => "\x1b[37m", // white
        .Debug => "\x1b[36m", // cyan
        .Info => "\x1b[32m", // green
        .Warn => "\x1b[33m", // yellow
        .Error => "\x1b[31m", // red
        .Critical => "\x1b[35m", // magenta
    };
}
