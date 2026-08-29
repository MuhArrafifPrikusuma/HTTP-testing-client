const std = @import("std");

const Methods = enum {
    GET,
    POST,
    PUT,
    DELETE,
};

const Request = struct {
    method: Methods,
    path: []const u8,
    host: []const u8 = "localhost:8080", // <- automatically filled
    agent: []const u8 = "idk-for-now/tester",
    body: []const u8,
};

pub const Client = struct {
    // fuzz = true for auto generate data
    fuzz: bool = false,
    // how many times to repeat this, if you combine this with fuzz
    // it will generate different data on every request
    repeat: u32 = 0,
    // ^ that one is just for parsing use atomic_repeat with repeat as it's value for
    // thread safe counter
    atomic_repeat: std.atomic.Value(u32) = .init(0),
    request: Request = undefined,
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
