const std = @import("std");

const Client = struct {
    // fuzz = true for auto generate data
    fuzz: bool,
    // how many times to repeat this, if you combine this with fuzz
    // it will generate different data on every request
    repeat: std.atomic.Value(u32),
    request: std.http.Client.FetchOptions,
};

/// initiate client arena allocator
pub const ClintInterface = struct {
    arena: std.heap.ArenaAllocator,
    client: Client,

    pub fn init(backing_allocator: std.mem.Allocator) !*ClintInterface {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer arena.deinit();

        const allocator = arena.allocator();

        const self = try allocator.create(ClintInterface);

        self.* = .{
            .arena = arena,
            .client = .{},
        };
        return self;
    }

    pub fn deinit(self: *ClintInterface) !void {
        self.arena.deinit();
    }
};

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
