const std = @import("std");
const Task = @import("Task.zig");

const http = std.http;
const Allocator = std.mem.Allocator;

pub const Response = struct {
    body: []const u8 = "dummy body",
};

const ResponsePoolErr = error{InvalidKey};

const HashContext = struct {
    pub fn hash(self: HashContext, key: Response) u64 {
        _ = self;
        var wyhash = std.hash.Wyhash.init(0);

        wyhash.update(key.body);

        return wyhash.final();
    }

    pub fn eql(self: HashContext, a: Response, b: Response) bool {
        _ = self;
        return std.mem.eql(u8, a.body, b.body);
    }
};

pub const ResponsePool = struct {
    pool: std.HashMap(
        Response,
        usize,
        HashContext,
        std.hash_map.default_max_load_percentage,
    ),
    allocator: std.mem.Allocator,

    pub fn init(allocator: Allocator) ResponsePool {
        return .{
            .pool = std.HashMap(
                Response,
                usize,
                HashContext,
                std.hash_map.default_max_load_percentage,
            ).init(allocator),

            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResponsePool) void {
        var iter = self.pool.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.pool.deinit();
    }

    /// acquire and duplicate key string if not already exist
    pub fn intern(self: *ResponsePool, key: Response) !void {
        const ptr = try self.pool.getOrPut(key);

        if (ptr.found_existing) {
            ptr.value_ptr.* += 1;
            return;
        } else {
            ptr.key_ptr.* = key;

            ptr.key_ptr.body = try self.allocator.dupe(u8, key.body);

            ptr.value_ptr.* = 1;
            return;
        }
        unreachable;
    }

    /// decrement counter and when the counter reaches 0 delete the key
    pub fn release(self: *ResponsePool, key: *Response) !void {
        if (self.pool.getPtr(key.*)) |count| {
            count.* -= 1;
            if (count.* == 0) {
                _ = self.pool.remove(key.*);
                self.allocator.destroy(key);
            }
            return;
        }
        return ResponsePoolErr.InvalidKey;
    }

    pub fn get(self: *ResponsePool) ?*Response {
        var iter = self.pool.iterator();

        if (iter.next()) |item| {
            return item.key_ptr;
        }
        return null;
    }

    // store string and allocate new memory for the string if it's a new string
    // pub fn interns(self: *ResponsePool, str: []const u8) ![]const u8 {
    //     if (self.pool.getKey(str)) |existing| {
    //         return existing;
    //     }
    //
    //     const permanent_cpy = try self.allocator.dupe(u8, str);
    //     try self.pool.put(permanent_cpy, {});
    //     return permanent_cpy;
    // }
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
    _ = max;
    if (task.response.count() == 0) {
        try task.response.ensureTotalCapacity(5);
        _ = task.response.fetchPutAssumeCapacity(.success, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.client_error, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.informational, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.redirect, .init(allocator));
        _ = task.response.fetchPutAssumeCapacity(.server_error, .init(allocator));
        return;
    }

    if (task.response.getPtr(status)) |res| {
        // NOTE: default by now fill with response from server later
        try res.intern(.{});
        return;
    }
    unreachable;
}
