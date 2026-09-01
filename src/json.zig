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

pub fn parseJson() !*Req.ClientInterface {
    const ci = Req.ClientInterface.init(std.heap.smp_allocator) catch |err| {
        std.log.err("{any}\n", .{err});
        std.process.exit(1);
    };
    const allocator = ci.arena.allocator();

    var scanner = std.json.Scanner.initCompleteInput(allocator, raw_file.content.items);
    defer scanner.deinit();

    // var list: std.ArrayList(Req.Client) = .empty;
    // defer list.deinit(allocator);

    // var count: usize = 1;

    // while (true) {
    // NOTE: PLEASSEE! DON'T BE LAZY MAKE THIS BETTER ERROR HANDLING YOU IDIOT PIECE OF GARBAGE
    const parsed = std.json.parseFromTokenSource([]Req.Client, allocator, &scanner, .{ .ignore_unknown_fields = true }) catch |err| {
        // if (err == error.EndOfStream) break;
        std.log.err("parse Json: {any}\n", .{err});
        std.process.exit(1);
        // break;
    };
    //
    // std.log.debug("fuzz: {any}\n", .{parsed.value.fuzz});
    // std.log.debug("repeat: {d}\n", .{parsed.value.repeat});
    // std.log.debug("method: {any}\n", .{parsed.value.request.method});

    // try list.append(allocator, parsed.value);

    //     count += 1;
    // }
    //
    // var parsed = std.json.parseFromSlice(
    //     Req.Client,
    //     allocator,
    //     raw_file.content.items,
    //     .{ .ignore_unknown_fields = true },
    // ) catch |err| {
    //     std.log.err("parser: {any}\n", .{err});
    //     std.process.exit(1);
    // };
    // defer parsed.deinit();
    //
    ci.client = try allocator.dupe(Req.Client, parsed.value);

    return ci;
}
