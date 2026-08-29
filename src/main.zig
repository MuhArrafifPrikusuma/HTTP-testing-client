const std = @import("std");
const argument = @import("arguments.zig");
const json = @import("json.zig");
const client = @import("client.zig");
const Req = @import("Request.zig");

pub var repeat: std.atomic.Value(u32) = .init(0);

pub fn main(init: std.process.Init) !void {
    argument.handleArgs(init.minimal.args, init.io);
    const ci = try json.parseJson();

    repeat.store(ci.client., .monotonic);

    var group: std.Io.Group = .init;
    // start processes
    var i: usize = 0;
    while (i < ci.client.repeat) : (i += 1)
        group.concurrent(init.io, client.clientNet, .{ init.io, init.gpa, ci }) catch |err| std.log.err("{any}\n", .{err});

    group.await(init.io) catch |err| std.log.err("{any}\n", .{err});
    std.debug.print("{d}\n", .{repeat.load(.acquire)});
}

fn split(ci: *Req.ClientInterface) !void {
    // get client fields from parsed json
    for (ci.client) |cf| {}
}
