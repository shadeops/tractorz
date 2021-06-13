
const c = @cImport({
    @cInclude("chipmunk/chipmunk.h");
    @cInclude("curl/curl.h");
});

pub const chipmunk = c;
pub const curl = c;

pub const ray = @import("clibs/raylib.zig");

