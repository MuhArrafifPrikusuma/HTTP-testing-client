//! handle network io etc
const std = @import("std");
const Req = @import("Request.zig");
const g = @import("main.zig");

pub fn clientNet(io: std.Io, allocator: std.mem.Allocator, ci: *Req.ClientInterface) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    _ = ci;
    defer client.deinit();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = g.repeat.fetchAdd(1, .acq_rel);
    }
}
