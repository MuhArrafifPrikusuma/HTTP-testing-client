const std = @import("std");
const argument = @import("arguments.zig");

pub fn main(init: std.process.Init) !void {
    try argument.handleArgs(init.minimal.args, init.io);
}
