/// Build configuration. This is the configuration that is populated
/// during `zig build` to control the rest of the build process.
const Config = @This();

const std = @import("std");
const builtin = @import("builtin");

optimize: std.builtin.OptimizeMode,
target: std.Build.ResolvedTarget,
