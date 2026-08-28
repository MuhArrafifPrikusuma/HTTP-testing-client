const std = @import("std");

pub fn requestHandler(io: std.Io) !void {
    const allocator = std.heap.smp_allocator;

    const client = initClient(io, allocator);
    client.deinit();
}

fn initClient(io: std.Io, allocator: std.mem.Allocator) std.http.Client {
    return std.http.Client{
        .io = io,
        .allocator = allocator,
    };
}
