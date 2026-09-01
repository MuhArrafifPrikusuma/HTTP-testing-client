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
    method: std.http.Method = .GET,
    path: []const u8,
    host: []const u8 = "localhost:8080",
    agent: []const u8 = "idk-for-now/tester", // <- automatically filled
    body: ?[]const u8 = null,
    content_type: []const u8,
    accept_type: ?[]const u8 = null,
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
    read_counter: std.ArrayList(std.atomic.Value(usize)) = .empty,
    write_counter: std.ArrayList(std.atomic.Value(usize)) = .empty,
    // if null sleep the thread for 5ms
    request: std.ArrayList(std.http.Client.FetchOptions) = .empty,
    mutex: std.Io.Mutex = undefined,

    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) !*Shared {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
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
    req.write_counter.append(allocator, .init(0)) catch |err| {
        std.log.err("{any}\n", .{err});
        std.process.exit(1);
    };

    builder(ci, io, req, thread_id);
}

// this will be called by client to generate data
fn builder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    var c = ci.client[thread_id];
    while (true) {
        const idx = req.write_counter.items[thread_id].fetchAdd(1, .acq_rel);
        if (idx >= c.repeat) {
            // NOTE: this sub is only for debug purposes
            _ = req.write_counter.items[thread_id].fetchSub(1, .acq_rel);
            break;
        }

        std.log.debug("thread id:{d}::{d}\n", .{ thread_id, idx });

        parseBody(&c, req, idx, io) catch |err| std.log.err("{any}\n", .{err});
    }
}

fn parseBody(c: *Client, req: *Shared, idx: usize, io: std.Io) !void {
    var fetch_options: std.http.Client.FetchOptions = undefined;
    _ = idx;

    try req.mutex.lock(io);
    defer req.mutex.unlock(io);

    std.debug.print("previous body: {s}\n", .{c.request.body.?});
    if (c.fuzz) c.request.body = handleSpecial(c.request.body, io, req.arena.allocator()) orelse c.request.body;
    std.debug.print("current body: {s}\n", .{c.request.body.?});
    // pass request line
    fetch_options.method = c.request.method;
    fetch_options.headers.content_type = .{ .override = c.request.content_type };
    fetch_options.location.url = c.uri;
    fetch_options.headers.user_agent = .{ .override = c.request.agent };
    fetch_options.headers.host = .{ .override = c.request.host };
    fetch_options.payload = c.request.body;

    try req.*.request.append(req.arena.allocator(), fetch_options);
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
fn handleSpecial(content: ?[]const u8, io: std.Io, allocator: std.mem.Allocator) ?[]const u8 {
    const content_string = content orelse return null;
    var start: usize = 0;
    var idx: SNIndex = .{};

    var new_content: ?[]const u8 = null;
    while (true) {
        const first_idx = std.mem.find(u8, content_string[start..], "{") orelse break;
        const last_idx = std.mem.find(u8, content_string[first_idx..], "}") orelse break;
        start = last_idx;

        idx = .{
            .start = first_idx,
            .end = last_idx,
        };

        new_content = rebuildContent(content_string[idx.start + 1 .. idx.end], content_string, &idx, io, allocator) catch |err| {
            std.log.err("{any}\n", .{err});
            continue;
        } orelse continue;
    }
    return new_content;
}

/// check whether a target is truly a special and pass it to the replacer which then generate a replacement with fuzzer and replaced the original string
fn rebuildContent(
    special_content: []const u8,
    orig: []const u8,
    idx: *const SNIndex,
    io: std.Io,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    // NOTE: don't forget to handle rules here and on fuzzer too
    var iter = std.mem.splitScalar(u8, special_content, ';');
    const content = iter.next() orelse return null;

    // make this better later
    if (content.len > ~@as(u8, 0)) return null;

    var buf: [256]u8 = undefined;
    const tag_name = std.ascii.upperString(&buf, content);
    const tag = std.meta.stringToEnum(SpecialTags, tag_name) orelse return null;

    const new_data = try fuzzer(tag, io);

    var buf_dat: [2048]u8 = undefined;
    const replacement = blk: {
        switch (new_data) {
            .int => |val| {
                break :blk try std.fmt.bufPrint(&buf_dat, "{d}", .{val});
            },
            .float => |val| {
                break :blk try std.fmt.bufPrint(&buf_dat, "{d}", .{val});
            },
            .string => |val| {
                break :blk try std.fmt.bufPrint(&buf_dat, "\"{s}\"", .{val});
            },
        }
    };

    const new_size = std.mem.replacementSize(u8, orig[idx.read_start..idx.end], orig[idx.start..idx.end], replacement);
    const buffer = try allocator.alloc(u8, new_size);

    const original = orig;
    allocator.free(original);

    _ = std.mem.replace(u8, original, original[idx.start..idx.end], replacement, buffer);
    return buffer;
}

const FuzzErr = error{
    UnexpectedError,
    InvalidRules,
};

// random data generators
// NOTE: later pass rules as parameters to this functions
fn randNumbers(comptime T: type, random: std.Random) Value {
    var value: Value = undefined;
    switch (T) {
        i64 => {
            // NOTE: do the actual thing later
            value = .{ .int = random.intRangeLessThan(i64, 0, 65553) };
        },
        f64 => {},
        else => unreachable,
    }
    return value;
}

/// return newly generated data based on tag and rules
fn fuzzer(tag: SpecialTags, io: std.Io) !Value {
    var prng: std.Random.DefaultPrng = .init(blk: {
        var b: [8]u8 = undefined;
        std.Io.random(io, &b);
        const seeder = std.mem.readInt(u64, &b, .native);

        break :blk seeder;
    });
    const random = prng.random();

    const randomize = switch (tag) {
        .RAND_NUM => randNumbers(i64, random),
        .RAND_FLOAT => randNumbers(f64, random),
        else => unreachable,
    };
    return randomize;
}
