const std = @import("std");
const builtin = @import("builtin");

const argument = @import("arguments.zig");
const json = @import("json.zig");
const client = @import("client.zig");
const res = @import("response.zig");

const Req = @import("Request.zig");
const Task = @import("Task.zig");

const Allocator = std.mem.Allocator;

var debug_allocator: std.heap.DebugAllocator(.{ .safety = true, .thread_safe = true }) = .init;

pub const std_Options = struct {
    pub const http_connection_pool_size = 10000;
};

// NOTE: i think switch the way the writer work by only working on batch of maximum 10k request per second
// to keep the memory usage under 100mb even when sending like 100m requests
pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = switch (builtin.mode) {
        .debug, .safe => debug_allocator.allocator(),
        .fast, .small => std.heap.smp_allocator,
    };
    // NOTE: limit this later to be pinned directly to target machine number of cpu cores
    var threaded = std.Io.Threaded.init(allocator, .{ .concurrent_limit = .unlimited });
    const io = threaded.io();

    const todo = argument.handleArgs(init.args, io);
    if (todo == .exit) std.process.exit(0);
    std.debug.print("what todo: {any}\n", .{todo});

    const ci = try json.parseJson();

    splitTasks(ci, io, todo, allocator) catch |err| std.log.err("{any}\n", .{err});
}

fn splitTasks(
    ci: *Req.ClientInterface,
    io: std.Io,
    todo: argument.DoAfter,
    backing_allocator: Allocator,
) !void {
    const task = Task.init(backing_allocator) catch @panic("failed to initiate tasks");
    defer task.deinit();

    const allocator = task.arena.allocator();
    // get client fields from parsed json

    const total_task = ci.client.len;

    try task.write_counter.ensureUnusedCapacity(allocator, total_task);
    try task.read_counter.ensureUnusedCapacity(allocator, total_task);
    try task.halt.ensureUnusedCapacity(allocator, total_task);

    try task.halt.appendNTimesBounded(false, total_task);
    try task.write_counter.appendNTimesBounded(.init(0), total_task);
    try task.read_counter.appendNTimesBounded(.init(0), total_task);

    var max_response: u32 = 0;
    for (ci.client, 0..) |c, i| {
        max_response += c.repeat;

        if (c.repeat == 0) continue;

        task.options.appendNTimes(allocator, .init(null), @as(usize, ci.client[i].repeat)) catch |err| {
            std.log.err("not enough memory: {any}\n", .{err});
            std.process.exit(1);
        };
    }
    // NOTE: for debug purposes remove later
    std.log.debug("sizeof fetchoptions ptr: {d:.2}\n", .{@sizeOf(?*std.http.Client.FetchOptions)});
    const memory_usage: f128 = @as(f128, task.options.items.len * @sizeOf(?*std.http.Client.FetchOptions) / 1024);
    std.log.debug("total memory allocated for options: {d:.2} KB\n", .{memory_usage});

    const progress = std.Progress.start(io, .{
        .root_name = "waiting",
    });

    var total_repeat: u32 = 0;

    var group: std.Io.Group = .init;
    for (ci.client, 0..) |cl, i| {
        total_repeat += cl.repeat;
        try group.concurrent(io, Req.initBuilder, .{ io, ci, task, i, progress });
        try group.concurrent(io, client.clientNet, .{ io, ci, task, i, max_response, progress });
    }

    group.await(io) catch |err| std.log.err("{any}\n", .{err});
    ci.deinit();

    progress.end();
    if (total_repeat != 0) {
        switch (todo) {
            .showClass => |show| try task.showResponseByClass(show, io),
            else => std.debug.print("replace later\n", .{}),
        }
    }
}

// NOTE: repeat = 0 is not handled properly handle it later and finish task immediately if it's 0
