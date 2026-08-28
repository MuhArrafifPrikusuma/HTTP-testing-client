const std = @import("std");
const argument = @import("arguments.zig");
const json = @import("json.zig");

pub fn main(init: std.process.Init) !void {
    argument.handleArgs(init.minimal.args, init.io);
}
