const std = @import("std");
const json = @import("json.zig");

var next_should_bfile: bool = false;
var next_must_async: bool = false;

const Show = enum {
    ALL,
    SUCCESS,
    FAILED_ALL,
    FAIL_SERVER,
    FAIL_CLIENT,
};

pub const DoAfter = union(enum) {
    show: Show,
    nothing: void,
    exit: void,
};

const ArgError = error{
    UnknownArgument,
};

pub fn handleArgs(args: std.process.Args, io: std.Io) DoAfter {
    var iter = args.iterate();

    var buf_writer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf_writer);
    const stdout = &writer.interface;

    var todo: DoAfter = .exit;

    json.raw_file = .{
        .allocator = std.heap.smp_allocator,
        .content = .empty,
    };

    // start from 1 to match argument len which also start from 1
    var i: usize = 1;
    while (iter.next()) |arg| : (i += 1) {
        if (i == 1) continue;

        if (next_should_bfile) {
            consume(arg, io, json.raw_file.allocator, &json.raw_file.content) catch |err| {
                stdout.print("\x1B[38;2;255;20;10m{any}\x1B[0m\r\n", .{err}) catch |perr| std.log.err("{any}\n", .{perr});
            };
            break;
        }

        todo = processArg(arg, stdout);
    }
    if (args.vector.len == 1)
        stdout.print("No arguments found!\r\nuse \x1B[2m-h\x1B[22m for help\r\n", .{}) catch |err| std.log.err("{any}\n", .{err});

    stdout.flush() catch |err| std.log.err("{any} -> handleArgs\n", .{err});
    std.log.debug("test: {s}\n", .{json.raw_file.content.items});
    return todo;
}

fn handleUnknownArgs(arg: []const u8) noreturn {
    std.log.err("Unknown argument: \x1B[2m{s}\x1B[22m\nuse \x1B[2m-h\x1B[22m for help ", .{arg});
    std.process.exit(1);
}

const ArgsHandlers = *const fn (*std.Io.Writer) anyerror!DoAfter;

const Argument = enum {
    SHOW,
    HELP,
    RUN,
};

fn convrtToEnum(arg: []const u8) ArgError!Argument {
    if (arg.len > 255) handleUnknownArgs(arg);

    var tmp_arg = if (std.mem.findScalar(u8, arg, '=')) |end| arg[0..end] else arg;
    tmp_arg = if (std.mem.eql(u8, tmp_arg, "-h")) "HELP" else tmp_arg;

    var buf: [256]u8 = undefined;
    const stripped_arg = std.ascii.upperString(&buf, if (tmp_arg[0] == '-') tmp_arg[1..] else tmp_arg[0..]);

    return std.meta.stringToEnum(Argument, stripped_arg) orelse ArgError.UnknownArgument;
}

fn getExternsion(arg: []const u8) ArgError!?[]const u8 {
    var iter = std.mem.splitScalar(u8, arg, '=');
    var i: usize = 0;

    while (iter.next()) |ext| : (i += 1) {
        if (i != 1) continue;
        std.debug.print("have i ever here?\n", .{});
        return ext;
    }
    if (i == 1) return null;
    if (i > 1) return ArgError.UnknownArgument;
    unreachable;
}

fn processArg(arg: []const u8, stdout: *std.Io.Writer) DoAfter {
    const stripped_arg = convrtToEnum(arg) catch handleUnknownArgs(arg);
    const extension = getExternsion(arg) catch handleUnknownArgs(arg);

    return blk: {
        switch (stripped_arg) {
            .HELP => {
                break :blk help(stdout) catch |err| {
                    std.log.err("Failed to help: {any}", .{err});
                    std.process.exit(1);
                };
            },
            .RUN => break :blk setConsume(),
            .SHOW => break :blk setShow(arg, extension),
        }
    };

    //
    // const validArgs = [_][]const u8{
    //     "-h",
    //     "run",
    //     "-show",
    // };
    //
    // const argsFunctions = [_]ArgsHandlers{
    //     help,
    //     setConsume,
    //     setShow,
    // };
    //
    // var return_value: DoAfterFinished = .nothing;
    //
    // for (argsFunctions, 0..) |func, i| {
    //     if (std.mem.startsWith(u8, arg, "-show")) {
    //         return_value = try func(stdout);
    //         return return_value;
    //     }
    //     if (std.ascii.eqlIgnoreCase(arg, validArgs[i])) {
    //         return_value = try func(stdout);
    //         return return_value;
    //     }
    // }
    //
    // stdout.print("\x1B[38;2;255;20;10mError: Invalid argument\x1B[0m -> \x1B[3m{s}\x1B[23m\r\nuse \x1B[2m-h\x1B[22m for help\r\n", .{arg}) catch {};
    // stdout.flush() catch {};
    // std.process.exit(1);
}
fn help(stdout: *std.Io.Writer) !DoAfter {
    try stdout.print("test help\n", .{});
    try stdout.flush();
    return .exit;
}

fn setConsume() DoAfter {
    next_should_bfile = true;
    return .nothing;
}

fn consume(arg: []const u8, io: std.Io, allocator: std.mem.Allocator, list: *std.ArrayList(u8)) !void {
    const file = try std.Io.Dir.cwd().openFile(io, arg, .{});
    defer file.close(io);

    errdefer list.deinit(allocator);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);

    try reader.interface.appendRemaining(allocator, list, .limited(50 * 1024 * 1024));
}

fn setShow(arg: []const u8, ext: ?[]const u8) DoAfter {
    if (ext) |e| {
        var buf: [256]u8 = undefined;
        const to_upper = std.ascii.upperString(&buf, e);

        const enum_val = std.meta.stringToEnum(Show, to_upper) orelse handleUnknownArgs(arg);
        const doaf: DoAfter = .{ .show = enum_val };

        return doaf;
    } else return .{ .show = .ALL };
    unreachable;
}
