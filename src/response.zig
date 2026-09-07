const std = @import("std");
const Task = @import("Task.zig");

const http = std.http;
const Allocator = std.mem.Allocator;

pub const Response = struct {
    // body: []const u8,
    status: std.http.Status.Class,
};

pub fn storeResponse(
    task: *Task,
    io: std.Io,
    status_class: http.Status.Class,
) void {
    // const allocator = task.arena.allocator();

    const response: Response = .{
        .status = status_class,
    };

    task.mutex.lock(io) catch |err| {
        std.log.err("responseHandler mutex: {any}\n", .{err});
        std.process.exit(1);
    };
    defer task.mutex.unlock(io);

    const id = storeInStatus(task, response) catch |err| {
        std.log.err("Failed to allocate memory: {any}\n", .{err});
        return;
    };

    storeResponseInID(task, response, id) catch |err| {
        std.log.err("Failed to store response: {any}", .{err});
        return;
    };
}

fn storeInStatus(task: *Task, res: Response) !usize {
    if (task.response_status_accu.get(res.status)) |total_res| {
        const new_value = total_res + 1;
        _ = task.response_status_accu.fetchPutAssumeCapacity(res.status, new_value) orelse unreachable;

        return new_value;
    } else {
        try task.response_status_accu.ensureTotalCapacity(5);
        _ = task.response_status_accu.fetchPutAssumeCapacity(res.status, 0) orelse return 0;
        unreachable;
    }
    unreachable;
}

fn storeResponseInID(task: *Task, res: Response, res_id: usize) !void {
    if (res_id >= task.response.count()) {
        const reserve_capacity: u32 = if (task.response.count() == 0) 10 else task.response.count();
        try task.response.ensureUnusedCapacity(reserve_capacity);
    }
    _ = task.response.fetchPutAssumeCapacity(res_id, res) orelse {};
}
