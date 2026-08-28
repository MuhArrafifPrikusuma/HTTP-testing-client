const std = @import("std");

/// this should only be modified by handleArgs and then never modified again
/// until deinit is called after all the data has been parsed
pub var raw_file: struct {
    content: std.ArrayList(u8) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn deinit(self: *@This()) void {
        self.content.deinit(self.allocator);
    }
} = .{};

pub fn parseJson() !void {}
