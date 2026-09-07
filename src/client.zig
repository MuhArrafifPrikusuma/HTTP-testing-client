//! handle network io etc
const std = @import("std");

const Req = @import("Request.zig");
const Task = @import("Task.zig");
const Res = @import("Response.zig");

pub fn clientNet(
    io: std.Io,
    ci: *Req.ClientInterface,
    task: *Task,
    thread_id: usize,
) void {
    const allocator = task.arena.allocator();
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(allocator);

    while (true) {
        const opt = task.read(io, thread_id, ci.client[thread_id].repeat) catch {
            std.log.debug("thread: {d} finished", .{thread_id});
            break;
        };
        opt.*.response_writer = &response_writer.writer;

        const response = client.fetch(opt.*) catch |err| {
            std.log.err("Client request fetch: {any}\n", .{err});
            continue;
        };
        allocator.destroy(opt);

        Res.responseHandler(task, io, response.status.class(), response_writer.written());

        if (response.status.class() == .success) {
            // std.debug.print("status: {s}\n", .{shared.response_writer.written()});
        }
    }
}

// NOTE: right now focus on making response and response checker and then rules
