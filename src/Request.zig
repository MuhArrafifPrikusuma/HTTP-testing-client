const std = @import("std");

pub const Client = struct {
    // fuzz = true for auto generate data
    fuzz: bool = false,
    // how many times to repeat this, if you combine this with fuzz
    // it will generate different data on every request
    repeat: u32 = 1,
    // NOTE: use this as the best url and combine it with path or i might not have to do that if i connect first
    uri: []const u8,
    request: Request = undefined,
};

const Methods = enum {
    GET,
    POST,
    PUT,
    DELETE,
};

const Request = struct {
    method: std.http.Method,
    path: []const u8,
    host: []const u8 = "localhost:8080",
    agent: []const u8 = "idk-for-now/tester", // <- automatically filled
    body: []const u8,
    content_type: []const u8,
    accept_type: []const u8,
};

/// initiate client arena allocator
pub const ClientInterface = struct {
    arena: std.heap.ArenaAllocator,
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

const SharedErr = error{
    ReadComplete,
};

pub const Shared = struct {
    // use counter for indexing
    read_counter: []std.atomic.Value(u32) = undefined,
    write_counter: []std.atomic.Value(u32) = undefined,
    // if null sleep the thread for 5ms
    request: std.ArrayList(std.http.Client.FetchOptions) = .empty,
    mutex: std.Io.RwLock = .{},

    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) !*Shared {
        const arena = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer arena.deinit();

        const allocator = arena.allocator();

        const self = try allocator.create(Shared);

        self.* = .{
            .arena = arena,
        };

        return self;
    }

    pub fn deinit(self: *Shared) void {
        const allocator = self.arena.allocator();
        self.request.deinit(allocator);
        self.arena.deinit();
    }

    /// return SharedErr.ReadComplete when there is no more request string to process
    pub fn read(self: *Shared, io: std.Io, thread_id: usize, max: u32) SharedErr!*std.http.Client.FetchOptions {
        self.mutex.lockShared(io);
        defer self.mutex.unlockShared(io);

        const idx: usize = self.read_counter[thread_id].fetchAdd(1, .acq_rel);

        while (true) {
            if (idx >= max) return SharedErr.ReadComplete;

            if (self.request_string.items[idx]) |req| {
                return &req;
            } else {
                std.Io.sleep(io, std.Io.Duration.fromMilliseconds(5), std.Io.Clock.real);
            }
        }
    }

    // NOTE: writer should be outside of this right in requestHandler
};

// NOTE: determine whether it wants random data for fixed data and if it's random then take the struct see the requirements
// and then generate data on the fly when a thread requested for it

fn MethodHandler(method: std.http.Method) type {}

// this will be called by client to generate data
pub fn builder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    const c = ci.client[thread_id];

    parseBody(&c) catch |err| std.log.err("{any}\n", .{err});
}

fn parseBody(c: *Client, req: *Shared) !void {
    const allocator = req.arena.allocator();

    var fetch_options: std.http.Client.FetchOptions = undefined;

    // pass request line
    fetch_options.method = c.request.method;
    fetch_options.location.url = c.request.uri;

    if (fetch_options.method) |method| {
        switch (method) {}
    } else {
        // NOTE: later on make a function to point directly to the invalid string in the json file
        std.log.err("Method is required please provide a method\n", .{});
    }
}

fn fuzzer(c: *const Client, req: *Shared) !void {}
