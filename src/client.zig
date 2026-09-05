//! handle network io etc
const std = @import("std");
const Req = @import("Request.zig");

pub fn clientNet(
    io: std.Io,
    ci: *Req.ClientInterface,
    group: *std.Io.Group,
    shared: *Req.Shared,
    thread_id: usize,
) void {
    const allocator = shared.arena.allocator();
    _ = group;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();
    while (true) {
        const opt = shared.read(io, thread_id, ci.client[thread_id].repeat) catch {
            std.log.debug("thread: {d} finished", .{thread_id});
            break;
        };
        std.debug.print("options method: {?any} in thread: {d}\n", .{ opt.method, thread_id });
        const result = client.fetch(opt.*) catch |err| {
            std.log.err("Client request fetch: {any}\n", .{err});
            continue;
        };
        std.debug.print("we ever here?\n", .{});
        if (result.status.phrase()) |res| {
            _ = res;
            // std.debug.print("test result: {s}\n", .{res});
        }
    }
}
