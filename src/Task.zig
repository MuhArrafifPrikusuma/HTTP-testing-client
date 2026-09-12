const std = @import("std");

const res = @import("response.zig");
const ansii = @import("ansii.zig");
const zcpy = @import("zerocpy.zig");

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

halt: std.ArrayList(bool),

options: std.ArrayList(std.atomic.Value(?*std.http.Client.FetchOptions)),

/// status accumulator to store how many response with that status class
response: std.AutoHashMap(std.http.Status.Class, zcpy.StructHashMap(res.Response, res.ResponseHashContext)),

pub fn init(backing_allocator: std.mem.Allocator) !*Self {
    var start_arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer start_arena.deinit();

    const bootstrap_allocator = start_arena.allocator();

    const self = try bootstrap_allocator.create(Self);

    self.*.arena = start_arena;
    const allocator = self.arena.allocator();

    self.*.halt = .empty;
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

fn showAllResponse(self: *Self, out_writer: *std.Io.Writer) !void {
    const repeat: u8 = @typeInfo(std.http.Status.Class).@"enum".field_names.len;

    var i: u8 = 0;
    while (i < repeat) : (i += 1) {
        const class: std.http.Status.Class = @enumFromInt(i);
        try self.showResponseByClassesSpecific(class, out_writer);
    }
}

fn showResponseByClassesSpecific(
    self: *Self,
    class: std.http.Status.Class,
    out_writer: *std.Io.Writer,
) !void {
    const to_show: []const u8 = @tagName(class);

    try out_writer.print("All response in class: {s}{s}{s}\r\n", .{
        ansii.styles.dim,
        to_show,
        ansii.reset,
    });

    var found_total: u32 = 0;

    if (self.response.getPtr(class)) |res_map| {
        while (res_map.get()) |response| : (found_total += 1) {
            const total_found = res_map.map.get(response.*) orelse 0;

            try out_writer.print("\n{s}{s}{s}\n", .{
                ansii.styles.dim,
                response.location,
                ansii.reset,
            });
            try out_writer.print("{s}status{s}: {any}\r\n", .{
                ansii.styles.bold,
                ansii.reset,
                response.status,
            });
            try out_writer.print("{s}body{s}: {s}\r\n", .{
                ansii.styles.bold,
                ansii.reset,
                response.body,
            });
            try out_writer.print("{s}Total Found{s}: {d}\r\n\n", .{
                ansii.styles.bold,
                ansii.reset,
                total_found,
            });

            try res_map.invalidate(response);
        } else if (found_total == 0) {
            try out_writer.print("nothing in {s}{s}{s}\r\n", .{
                ansii.styles.dim,
                to_show,
                ansii.reset,
            });
            return;
        }
    } else {} // <- NOTE: idk what to put here

    const @"total > 1": []const u8 = if (found_total > 1) "responses" else "response";

    try out_writer.print("total {s}{d}{s} unique {s} in {s}{s}{s}\r\n", .{
        ansii.styles.dim,
        found_total,
        ansii.reset,
        @"total > 1",
        ansii.styles.dim,
        to_show,
        ansii.reset,
    });
}

pub fn showResponseByClass(self: *Self, show: res.ShowClass, io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &writer.interface;
    switch (show) {
        .all => try self.showAllResponse(stdout),
        .class => |c| try self.showResponseByClassesSpecific(c, stdout),
    }

    try stdout.flush();
}
