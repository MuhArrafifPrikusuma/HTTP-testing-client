const std = @import("std");
const Req = @import("Request.zig");

/// this should only be modified by handleArgs and then never modified again
/// until deinit is called after all the data has been parsed
pub var raw_file: struct {
    content: std.ArrayList(u8) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn deinit(self: *@This()) void {
        self.content.deinit(self.allocator);
    }
} = .{};

pub fn parseJson() void {
    const ci = Req.ClintInterface.init(std.heap.smp_allocator) catch |err| {
        std.log.err("{any}\n", .{err});
        std.process.exit(1);
    };
    const allocator = ci.arena.allocator();

    var parsed = std.json.parseFromSlice(
        Req.Client,
        allocator,
        raw_file.content.items,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        std.log.err("parser: {any}\n", .{err});
        std.process.exit(1);
    };
    defer parsed.deinit();

    // NOTE: use acq_rel for write and acquire for read
    parsed.value.atomic_repeat.store(parsed.value.repeat, .monotonic);

    std.log.debug("fuzz {any}\n", .{parsed.value.fuzz});
    std.log.debug("repeat: {d}\n", .{parsed.value.repeat});
    std.log.debug("method: {any}\n", .{parsed.value.request.method});
    std.log.debug("atomic counter: {d}\n", .{parsed.value.atomic_repeat.load(.acquire)});
}
