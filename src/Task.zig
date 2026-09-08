const std = @import("std");
const res = @import("response.zig");

const Self = @This();

const SharedErr = error{
    ReadComplete,
};

/// NOTE: if a thread finished it should free all of memory they use for other slices, use loop with allocator free for this
mutex: std.Io.Mutex,
arena: std.heap.ArenaAllocator,

// use counter for atomic indexing
read_counter: std.ArrayList(std.atomic.Value(usize)),
write_counter: std.ArrayList(std.atomic.Value(usize)),

options: std.ArrayList(std.atomic.Value(?*std.http.Client.FetchOptions)),

/// status accumulator to store how many response with that status class
response: std.AutoHashMap(std.http.Status.Class, res.ResponseMap),

pub fn init(backing_allocator: std.mem.Allocator) !*Self {
    var start_arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer start_arena.deinit();

    const bootstrap = start_arena.allocator();

    const self = try bootstrap.create(Self);

    self.*.arena = start_arena;
    const allocator = self.arena.allocator();

    self.*.mutex = .init;
    self.*.options = .empty;
    self.*.read_counter = .empty;
    self.*.write_counter = .empty;
    self.*.response = .init(allocator);

    return self;
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

/// return SharedErr.ReadComplete when there is no more request string to process
pub fn read(
    self: *Self,
    io: std.Io,
    thread_id: usize,
    max: u32,
) SharedErr!*const std.http.Client.FetchOptions {
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
