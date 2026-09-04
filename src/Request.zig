const std = @import("std");

pub const Client = struct {
    // fuzz = true for auto generate data
    fuzz: bool = false,
    // how many times to repeat this, if you combine this with fuzz
    // it will generate different data on every request
    repeat: u32 = 1,
    // NOTE: use this as the best url and combine it with path or i might not have to do that if i connect first
    uri: []const u8,
    request: Request = .{},
};

const Methods = enum {
    GET,
    POST,
    PUT,
    DELETE,
};

const Request = struct {
    method: ?std.http.Method = null,
    path: []const u8 = "/",
    host: []const u8 = "127.0.0.1", // <- NOTE: replace this with client host after this
    agent: []const u8 = "idk-for-now/tester", // <- automatically filled
    body: ?[]const u8 = null,
    content_type: []const u8 = "text/plain",
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
    request: std.ArrayList(?std.http.Client.FetchOptions) = .empty,
    mutex: std.Io.Mutex = .init,

    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) !*Shared {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer arena.deinit();

        const allocator = arena.allocator();

        const self = try allocator.create(Shared);

        self.* = .{
            .arena = arena,
            .mutex = .init,
        };

        // NOTE: CHANGE THE WAY TO RESIZE ARRAY LIST DON'T RESIZE IT ONE BY ONE ADD LIKE 5 OR 10 AND MAKE THE VALUE NULL
        return self;
    }

    pub fn deinit(self: *Shared) void {
        const allocator = self.arena.allocator();
        self.request.deinit(allocator);
        self.arena.deinit();
    }

    /// return SharedErr.ReadComplete when there is no more request string to process
    pub fn read(self: *Shared, io: std.Io, thread_id: usize, max: u32) SharedErr!*const std.http.Client.FetchOptions {
        const idx: usize = self.read_counter.items[thread_id].fetchAdd(1, .acq_rel);
        // std.debug.print("now reading: {d}\n", .{idx});
        // std.debug.print("max: {d}\n", .{max});

        while (true) {
            if (idx >= max) return SharedErr.ReadComplete;

            // std.debug.print("what is it {?any}\n", .{self.request.items[idx]});

            if (self.request.items[idx]) |req| {
                // FIXME: i don't know how can i be this bad but somehow this print function is the one
                // that makes it work and without it the program will simply freezes
                std.debug.print("", .{}); // <WARNING: WAAAAAAAAAAAAAAAAHHHHHHHHHHH!
                return &req;
            } else {
                std.debug.print("ever gone here?\n", .{});
                std.Io.sleep(io, std.Io.Duration.fromMilliseconds(5), std.Io.Clock.real) catch |err| {
                    std.log.err("sleep: {any}\n", .{err});
                    std.process.exit(1);
                };
            }
        }
    }

    // NOTE: writer should be outside of this right in requestHandler
};

// NOTE: determine whether it wants random data for fixed data and if it's random then take the struct see the requirements
// and then generate data on the fly when a thread requested for it

pub fn initBuilder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    // const allocator = req.arena.allocator();
    // const initial_value: std.atomic.Value(usize) = .init(0);
    //
    // req.write_counter.ensureUnusedCapacity(allocator, 1) catch |err| {
    //     std.log.err("failed to allocate memory: {any}\n", .{err});
    //     std.process.exit(1);
    // };
    //
    // req.write_counter.appendAssumeCapacity(initial_value);

    builder(ci, io, req, thread_id);
}

// this will be called by client to generate data
fn builder(ci: *const ClientInterface, io: std.Io, req: *Shared, thread_id: usize) void {
    var c = ci.client[thread_id];
    std.debug.print("sizeof: {d}\n", .{req.request.items.len});
    while (true) {
        const idx = req.write_counter.items[thread_id].fetchAdd(1, .acq_rel);
        if (idx >= c.repeat) {
            // NOTE: this sub is only for debug purposes
            _ = req.write_counter.items[thread_id].fetchSub(1, .acq_rel);
            break;
        }

        // std.log.debug("thread id:{d}::{d}\n", .{ thread_id, idx });

        parseBody(&c, req, idx, io) catch |err| std.log.err("is there error {any}\n", .{err});
    }
}

fn parseBody(
    c: *Client,
    req: *Shared,
    idx: usize,
    io: std.Io,
) !void {
    var fetch_options: std.http.Client.FetchOptions = undefined;

    const allocator = req.arena.allocator();

    var body: ?[]const u8 = c.request.body;
    const uri_string = try std.mem.concat(allocator, u8, &.{ c.uri, c.request.path });
    // std.debug.print("uri string: {s}\n", .{uri_string});

    // std.debug.print("pref: {?s}\n", .{body});
    if (c.fuzz) body = handleSpecial(c.request.body, io, allocator) orelse body;
    // std.debug.print("after: {?s}\n", .{body});
    // pass request line
    fetch_options.method = c.request.method orelse {
        std.log.err("Method field is required!\n", .{});
        std.process.exit(1);
    };
    fetch_options.headers.content_type = .{ .override = c.request.content_type };
    fetch_options.location = .{ .url = uri_string };
    fetch_options.headers.user_agent = .{ .override = uri_string };
    fetch_options.headers.host = .{ .override = c.request.host };
    fetch_options.payload = body;
    fetch_options.keep_alive = true;

    try req.mutex.lock(io);
    {
        defer req.mutex.unlock(io);

        req.request.items[idx] = fetch_options;
    }
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
/// NOTE: this seems fine for now just don't type stupid shit for the json input and it will be fine
/// there are still rooms for improvement and this can be far better
fn handleSpecial(content: ?[]const u8, io: std.Io, allocator: std.mem.Allocator) ?[]const u8 {
    const content_string = content orelse return null;
    var start: usize = 0;
    var idx: SNIndex = .{};

    var current_offset: usize = 0;
    var prev_offset: usize = 0;

    var new_content: ?[]const u8 = null;
    while (true) {
        var first_idx = if (std.mem.find(u8, content_string[start..], "{")) |found_idx|
            found_idx + current_offset
        else
            break;

        const do_have_middle = if (std.mem.find(u8, content_string[first_idx + 1 ..], "{")) |found_idx|
            found_idx + first_idx
        else
            null;

        const last_idx = if (std.mem.find(u8, content_string[first_idx..], "}")) |found_idx|
            found_idx + first_idx
        else
            break;

        if (current_offset > content_string.len) break;
        current_offset = last_idx;

        start = last_idx;

        if (do_have_middle) |yes_do| if (yes_do < last_idx) {
            first_idx = yes_do + 1;
        };

        idx = .{
            .start = first_idx,
            .end = last_idx,
        };

        if (new_content) |ctn| {
            new_content = std.mem.concat(
                allocator,
                u8,

                &.{
                    ctn,
                    content_string[prev_offset + 1 .. idx.start],

                    rebuildContent(
                        content_string[idx.start + 1 .. idx.end],
                        content_string,
                        &idx,
                        io,
                        allocator,
                    ) catch |err| {
                        std.log.err("{any}\n", .{err});
                        continue;
                    } orelse content_string[idx.start .. idx.end + 1],
                },
            ) catch |err| {
                std.log.err("{any}\n", .{err});
                std.process.exit(1);
            };
        } else {
            new_content = std.mem.concat(
                allocator,
                u8,

                &.{
                    content_string[0..idx.start],

                    rebuildContent(
                        content_string[idx.start + 1 .. idx.end],
                        content_string,
                        &idx,
                        io,
                        allocator,
                    ) catch |err| {
                        std.log.err("{any}\n", .{err});
                        continue;
                    } orelse content_string[idx.start + 1 .. idx.end],
                },
            ) catch |err| {
                std.log.err("{any}\n", .{err});
                std.process.exit(1);
            };
        }

        prev_offset = last_idx;
    }

    if (new_content) |ctn| {
        if (current_offset < content_string.len) new_content = std.mem.concat(
            allocator,
            u8,
            &.{
                ctn,
                content_string[idx.end + 1 ..],
            },
        ) catch |err| {
            std.log.err("{any}\n", .{err});
            std.process.exit(1);
        };
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

    const new_size = std.mem.replacementSize(
        u8,
        orig[idx.start..idx.end],
        orig[idx.start..idx.end],
        replacement,
    );

    const buffer = try allocator.alloc(u8, new_size);

    _ = std.mem.replace(
        u8,
        orig[idx.start..idx.end],
        orig[idx.start..idx.end],
        replacement,
        buffer,
    );
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

/// NOTE: obviously replace this later
fn randString(random: std.Random) Value {
    _ = random;
    const value: Value = .{ .string = "this is random" };
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
        .RAND_STR => randString(random),
    };
    return randomize;
}
