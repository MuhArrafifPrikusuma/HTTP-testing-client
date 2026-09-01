//! handle network io etc
const std = @import("std");
const Req = @import("Request.zig");

pub fn clientNet(
    io: std.Io,
    ci: *Req.ClientInterface,
    group: std.Io.Group,
    shared: *Req.Shared,
    thread_id: usize,
) !void {
    const allocator = shared.arena.allocator();
    _ = group;
    _ = thread_id;
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    _ = ci;
    defer client.deinit();
    // var i: usize = 0;
    // while (i < 1000) : (i += 1) {
    //     _ = shared.read_counter.append(allocator, .init(0)) catch |err| {
    //         std.log.err("{any}\n", .{err});
    //         std.process.exit(1);
    //     };
    // }
}
