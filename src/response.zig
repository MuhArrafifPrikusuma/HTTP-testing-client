const std = @import("std");
const Task = @import("Task.zig");

const http = std.http;
const Allocator = std.mem.Allocator;

const Response = struct {
    body: []const u8 = "dummy body",
};

pub const ResponseMap = struct {
    id: usize,
    response: std.ArrayList(Response),
};

pub fn storeResponse(
    task: *Task,
    io: std.Io,
    status: http.Status.Class,
    max: u32,
) void {
    const allocator = task.arena.allocator();
    // NOTE: make response body later after i figure out how to make the response writer thread safe
    task.mutex.lock(io) catch |err| {
        std.log.err("responseHandler mutex: {any}\n", .{err});
        std.process.exit(1);
    };
    defer task.mutex.unlock(io);

    storeInMap(task, status, max, allocator) catch |err| {
        std.log.err("Failed to allocate memory: {any}\n", .{err});
        return;
    };
}

fn storeInMap(task: *Task, status: std.http.Status.Class, max: u32, allocator: Allocator) !void {
    if (task.response.count() == 0)
        try task.response.ensureTotalCapacity(5);

    if (task.response.getPtr(status)) |list| {
        if (list.id >= list.response.items.len) {
            try list.response.ensureUnusedCapacity(allocator, max);
        }

        list.response.appendAssumeCapacity(.{});

        list.id += 1;

        return;
    } else {
        _ = task.response.fetchPutAssumeCapacity(status, .{
            .id = 0,
            .response = .empty,
        });
        return;
    }
    unreachable;
}
