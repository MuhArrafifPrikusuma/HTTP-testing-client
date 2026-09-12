const std = @import("std");
const Task = @import("Task.zig");

const http = std.http;
const Allocator = std.mem.Allocator;

pub const Response = struct {
    status: std.http.Status,
    // WARNING: don't forget to make it so that the body will be "" if there is no body from response
    body: []const u8 = "dummy body",
    location: []const u8 = "nowhere",
};

pub const Show = std.http.Status;

pub const ShowClass = union(enum) {
    all: void,
    class: std.http.Status.Class,
};

const ResponsePoolErr = error{InvalidKey};

pub const ResponseHashContext = struct {
    pub fn hash(self: ResponseHashContext, key: Response) u64 {
        _ = self;
        var wyhash = std.hash.Wyhash.init(0);

        const status = @tagName(key.status);

        wyhash.update(key.body);
        wyhash.update(status);

        return wyhash.final();
    }

    pub fn eql(self: ResponseHashContext, a: Response, b: Response) bool {
        _ = self;

        return std.mem.eql(u8, a.body, b.body) and a.status == b.status;
    }
};

pub fn storeResponse(
    task: *Task,
    io: std.Io,
    status: http.Status,
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

fn storeInMap(task: *Task, status: std.http.Status, max: u32, allocator: Allocator) !void {
    // const allocator = task.arena.allocator();
    _ = max;
    if (task.response.count() == 0) {
        try task.response.ensureTotalCapacity(5);
        _ = task.response.fetchPutAssumeCapacity(.success, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.redirect, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.client_error, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.informational, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.server_error, .init(allocator));
    }

    const to_intern_temp_constant: Response = .{ .location = "localhost://8080/", .status = status };

    if (task.response.getPtr(status.class())) |res| {
        // NOTE: default by now fill with response from server later
        try res.intern(&to_intern_temp_constant);
        return;
    }
}
