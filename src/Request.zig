const std = @import("std");

pub const Client = struct {
    // fuzz = true for auto generate data
    fuzz: bool = false,
    // how many times to repeat this, if you combine this with fuzz
    // it will generate different data on every request
    repeat: u32 = 0,
    request: Request = undefined,
};

const Methods = enum {
    GET,
    POST,
    PUT,
    DELETE,
};

const Request = struct {
    method: Methods,
    path: []const u8,
    host: []const u8 = "localhost:8080",
    agent: []const u8 = "idk-for-now/tester", // <- automatically filled
    body: []const u8,
};

/// initiate client arena allocator
pub const ClientInterface = struct {
    arena: std.heap.ArenaAllocator,
    uri: []const u8 = undefined,
    client: []Client,

    pub fn init(backing_allocator: std.mem.Allocator) !*ClientInterface {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer arena.deinit();

        const allocator = arena.allocator();

        const self = try allocator.create(ClientInterface);

        self.* = .{
            .arena = arena,
            .client = undefined,
        };
        return self;
    }

    pub fn deinit(self: *ClientInterface) !void {
        self.arena.deinit();
    }
};

pub const Shared = struct {
    repeat: []std.atomic.Value(u32) = .init(0),
    // if null sleep the thread for 5ms
    response_string: ?[]const u8 = null,
    mutex: std.Io.Mutex = .init,
};

// NOTE: determine whether it wants random data for fixed data and if it's random then take the struct see the requirements
// and then generate data on the fly when a thread requested for it

// NOTE: use smp_allocator for the response string for memory safety
pub fn requestHandler(ci: *ClientInterface) !void {
    ci.deinit();
}

// this will be called by client to generate data
// pub fn requestBuilder(ci: *ClientInterface) std.http.Client {}
