const std = @import("std");
const argument = @import("arguments.zig");
const json = @import("json.zig");
const client = @import("client.zig");

const Req = @import("Request.zig");
const Task = @import("Task.zig");

pub fn main(init: std.process.Init) !void {
    argument.handleArgs(init.minimal.args, init.io);
    const ci = try json.parseJson();

    splitTasks(ci, init.io) catch |err| std.log.err("{any}\n", .{err});
}

fn splitTasks(ci: *Req.ClientInterface, io: std.Io) !void {
    const task = Task.init(std.heap.smp_allocator) catch @panic("failed to initiate tasks");
    defer task.deinit();

    const allocator = task.arena.allocator();
    // get client fields from parsed json

    const total_task = ci.client.len;

    try task.write_counter.ensureUnusedCapacity(allocator, total_task);
    try task.read_counter.ensureUnusedCapacity(allocator, total_task);

    var index: usize = 0;
    while (index < total_task) : (index += 1) {
        task.write_counter.appendAssumeCapacity(.init(0));
        task.read_counter.appendAssumeCapacity(.init(0));
    }

    for (ci.client, 0..) |_, i| {
        task.options.appendNTimes(allocator, .init(null), @as(usize, ci.client[i].repeat)) catch |err| {
            std.log.err("not enough memory: {any}\n", .{err});
            std.process.exit(1);
        };
    }

    var group: std.Io.Group = .init;
    for (ci.client, 0..) |_, i| {
        try group.concurrent(io, Req.initBuilder, .{ ci, io, task, i });
        try group.concurrent(io, client.clientNet, .{ io, ci, task, i });
    }

    group.await(io) catch |err| std.log.err("{any}\n", .{err});
    ci.deinit();
}
