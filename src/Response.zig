const std = @import("std");
const Task = @import("Task.zig");

const http = std.http;

pub const Response = struct {
    body: []const u8,
    status: std.http.Status.Class,
};

pub fn responseHandler(
    task: *Task,
    io: std.Io,
    status_class: http.Status.Class,
    payload: []const u8,
) void {
    const allocator = task.arena.allocator();

    const response: Response = .{
        .body = payload,
        .status = status_class,
    };

    task.mutex.lock(io) catch |err| {
        std.log.err("responseHandler mutex: {any}\n", .{err});
        std.process.exit(1);
    };
    defer task.mutex.unlock(io);

    task.response.append(allocator, response) catch @panic("replace this later\n");
}
