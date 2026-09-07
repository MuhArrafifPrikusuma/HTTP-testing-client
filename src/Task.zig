const std = @import("std");

const Res = @import("Response.zig");

const Self = @This();

const SharedErr = error{
    ReadComplete,
};

/// NOTE: if a thread finished it should free all of memory they use for other slices, use loop with allocator free for this
mutex: std.Io.Mutex = .init,
arena: std.heap.ArenaAllocator,

// use counter for indexing
read_counter: std.ArrayList(std.atomic.Value(usize)),
write_counter: std.ArrayList(std.atomic.Value(usize)),
// if null sleep the thread for 5ms
options: std.ArrayList(std.atomic.Value(?*std.http.Client.FetchOptions)),
response: std.ArrayList(Res.Response),

pub fn init(backing_allocator: std.mem.Allocator) !*Self {
    var arena_tmp = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena_tmp.deinit();

    const allocator = arena_tmp.allocator();

    const self = try allocator.create(Self);

    self.* = .{
        .arena = arena_tmp,
        .response = .empty,
        .options = .empty,
        .read_counter = .empty,
        .write_counter = .empty,
    };

    return self;
}

pub fn deinit(self: *Self) void {
    const allocator = self.arena.allocator();
    self.options.deinit(allocator);
    self.arena.deinit();
}

/// return SharedErr.ReadComplete when there is no more request string to process
pub fn read(
    self: *Self,
    io: std.Io,
    thread_id: usize,
    max: u32,
) SharedErr!*std.http.Client.FetchOptions {
    const idx: usize = self.read_counter.items[thread_id].fetchAdd(1, .acq_rel);

    while (true) {
        if (idx >= max) return SharedErr.ReadComplete;

        if (self.options.items[idx].load(.acquire)) |opt| {
            return opt;
        } else {
            std.Io.sleep(io, std.Io.Duration.fromMilliseconds(1), std.Io.Clock.real) catch |err| {
                std.log.err("sleep: {any}\n", .{err});
                std.process.exit(1);
            };
        }
    }
}

// NOTE: writer should be outside of this right in requestHandler
