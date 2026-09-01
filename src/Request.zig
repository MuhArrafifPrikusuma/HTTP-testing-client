const std = @import("std");
const regex = @import("regex");

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

/// NOTE: if a thread finished it should free all of memory they use for other slices, use loop with allocator free for this
pub const Shared = struct {
    // use counter for indexing
    read_counter: std.ArrayList(std.atomic.Value(u32)) = .empty,
    write_counter: std.ArrayList(std.atomic.Value(u32)) = .empty,
    // if null sleep the thread for 5ms
    request: std.ArrayList(std.http.Client.FetchOptions) = .empty,
    mutex: std.Io.Mutex = .{},

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
        const idx: usize = self.read_counter.items[thread_id].fetchAdd(1, .acq_rel);

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

pub fn initBuilder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    const allocator = req.arena.allocator();
    req.write_counter.append(allocator, .init(0));

    builder(ci, io, req, thread_id);
}

// this will be called by client to generate data
fn builder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    const c = ci.client[thread_id];

    const idx = req.write_counter.items[thread_id].fetchAdd(1, .acq_rel);
    if (idx >= ci.client[thread_id].repeat) return;

    parseBody(&c, req, idx, io) catch |err| std.log.err("{any}\n", .{err});
}

fn parseBody(c: *Client, req: *Shared, idx: usize, io: std.Io) !void {
    var fetch_options: std.http.Client.FetchOptions = .{};

    // pass request line
    fetch_options.method = c.request.method;
    fetch_options.headers.content_type = .{ .override = c.request.content_type };
    fetch_options.location.url = c.request.uri;
    fetch_options.headers.user_agent = .{ .override = c.request.agent };
    fetch_options.headers.host = .{ .override = c.request.host };
    fetch_options.payload = c.request.body;

    req.mutex.lock(io);
    defer req.mutex.unlock(io);

    req.*.request.items[idx].payload = c.request.body;
}

const SpecialTags = enum {
    // after you can add rules like this: {RAND_***;{rules}}
    RAND_NUM,
    RAND_FLOAT,
    RAND_STR,
};

const Value = union(enum) {
    // might be needed or might be not figure it out on testing
    // uint: u64,
    int: i64,
    float: f64,
    // remember this is json so the string must contain "" for string type
    string: []const u8,
};

const SNIndex = struct {
    read_start: usize = 0, // <- for the very start of a replacement
    start: usize = 0,
    end: usize = 0,
};

const Rules = struct {
    // for random integers
    min: ?i64 = null,
    max: ?i64 = null,
};

/// search and replaces special indicator, return new formatted slice if found return null if not
/// NOTE: invalid specials are just regular string and won't be processes nor will it throw an error
fn handleSpecial(content: []const u8, io: std.Io) ?[]const u8 {
    var start: usize = 0;
    const idx: SNIndex = .{};

    while (true) {
        const first_idx = std.mem.find(u8, content[start..], "{") orelse break;
        const last_idx = std.mem.find(u8, content[first_idx..], "}") orelse break;
        start = last_idx;

        idx = .{
            .start = first_idx,
            .end = last_idx,
        };

        if (rebuildContent(content[idx.start + 1 .. idx.end - 1], content, idx, io)) {} else {
            continue;
        }
    }
}

/// check whether a target is truly a special and pass it to the replacer which then generate a replacement with fuzzer and replaced the original string
fn rebuildContent(special_content: []const u8, orig: []const u8, idx: *const SNIndex, io: std.Io) !?void {
    // NOTE: don't forget to handle rules here and on fuzzer too
    var iter = std.mem.splitScalar(u8, special_content, ';');
    const content = iter.next() orelse return null;

    var buf: [256]u8 = undefined;
    const tag_name = std.ascii.upperString(&buf, content);
    const tag = std.meta.stringToEnum(SpecialTags, tag_name) orelse return null;

    const new_data = try fuzzer(tag, io);

    var buf_dat: [2048]u8 = undefined;
    const data_string = switch (new_data) {
        .int => |val| {
            try std.fmt.bufPrint(&buf_dat, "{d}", .{val});
        },
        .float => |val| {
            try std.fmt.bufPrint(&buf_dat, "{d}", .{val});
        },
        .string => |val| {
            try std.fmt.bufPrint(&buf_dat, "\"{s}\"", .{val});
        },
    };

    std.mem.replacementSize(u8, orig[idx.read_start..idx.end], orig[idx.start..idx.end], data_string);
}

const FuzzErr = error{
    UnexpectedError,
    InvalidRules,
};

// random data generators
// NOTE: later pass rules as parameters to this functions
fn randNumbers(comptime T: type, random: std.Random) Value {
    switch (T) {
        i64 => {
            // NOTE: do the actual thing later
            random.intRangeLessThan(T, 0, 65553);
        },
        f64 => {
            // NOTE: finish later
        },
        else => unreachable,
    }
}

/// return newly generated data based on tag and rules
fn fuzzer(tag: SpecialTags, io: std.Io) !Value {
    var prng: std.Random.DefaultPrng = .init(blk: {
        var b: [8]u8 = undefined;
        try std.Io.random(io, &b);
        const seeder = std.mem.readInt(u64, &b, .native);

        break :blk seeder;
    });
    const random = prng.random();

    switch (tag) {
        .RAND_NUM => randNumbers(i64, random),
        .RAND_FLOAT => randNumbers(f64, random),
        else => std.log.err("Idk lol why ask", .{}),
    }
}
