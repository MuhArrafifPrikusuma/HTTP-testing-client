const std = @import("std");
const argument = @import("arguments.zig");
const json = @import("json.zig");
const client = @import("client.zig");
const Req = @import("Request.zig");

pub fn main(init: std.process.Init) !void {
    argument.handleArgs(init.minimal.args, init.io);
    const ci = try json.parseJson();

    splitTasks(ci, init.io) catch |err| std.log.err("{any}\n", .{err});
}

fn splitTasks(ci: *Req.ClientInterface, io: std.Io) !void {
    const shared = Req.Shared.init(std.heap.smp_allocator) catch @panic("failed to initiate tasks");
    const allocator = shared.arena.allocator();
    // get client fields from parsed json

    const total_task = ci.client.len;

    try shared.write_counter.ensureUnusedCapacity(allocator, total_task);
    try shared.read_counter.ensureUnusedCapacity(allocator, total_task);

    var index: usize = 0;
    while (index < total_task) : (index += 1) {
        shared.write_counter.appendAssumeCapacity(.init(0));
        shared.read_counter.appendAssumeCapacity(.init(0));
    }

    for (ci.client, 0..) |_, i| {
        shared.options.appendNTimes(allocator, .init(null), @as(usize, ci.client[i].repeat)) catch |err| {
            std.log.err("not enough memory: {any}\n", .{err});
            std.process.exit(1);
        };
    }

    var group: std.Io.Group = .init;
    for (ci.client, 0..) |_, i| {
        try group.concurrent(io, Req.initBuilder, .{ ci, io, shared, i });
        try group.concurrent(io, client.clientNet, .{ io, ci, &group, shared, i });
    }

    group.await(io) catch |err| std.log.err("{any}\n", .{err});
    std.log.debug("{any}\n", .{shared.write_counter.items});
}
