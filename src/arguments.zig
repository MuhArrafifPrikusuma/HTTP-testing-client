const std = @import("std");
const json = @import("json.zig");

var next_should_bfile: bool = false;

pub fn handleArgs(args: std.process.Args, io: std.Io) void {
    var iter = args.iterate();

    var buf_writer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf_writer);
    const stdout = &writer.interface;

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

        processArg(arg, stdout) catch |err| std.log.err("processArg: {any}\n", .{err});
    }
    if (args.vector.len == 1)
        stdout.print("No arguments found!\r\nuse \x1B[2m-h\x1B[22m for help\r\n", .{}) catch |err| std.log.err("{any}\n", .{err});

    stdout.flush() catch |err| std.log.err("{any} -> handleArgs\n", .{err});
    std.log.debug("test: {s}\n", .{json.raw_file.content.items});
}

const ArgsHandlers = *const fn (*std.Io.Writer) anyerror!void;

fn processArg(arg: []const u8, stdout: *std.Io.Writer) !void {
    const validArgs = [_][]const u8{
        "-h",
        "run",
    };

    const argsFunctions = [_]ArgsHandlers{
        help,
        setConsume,
    };

    for (argsFunctions, 0..) |func, i| {
        if (std.ascii.eqlIgnoreCase(arg, validArgs[i])) {
            try func(stdout);
            return;
        }
    }

    stdout.print("\x1B[38;2;255;20;10mError: Invalid argument\x1B[0m -> \x1B[3m{s}\x1B[23m\r\nuse \x1B[2m-h\x1B[22m for help\r\n", .{arg}) catch {};
    stdout.flush() catch {};
    std.process.exit(1);
}
fn help(stdout: *std.Io.Writer) !void {
    try stdout.print("test help\n", .{});
    std.log.debug("fill later\n", .{});
    std.process.exit(1);
}

fn setConsume(stdout: *std.Io.Writer) !void {
    _ = stdout;
    if (!next_should_bfile) {
        next_should_bfile = true;
        return;
    }
}

fn consume(arg: []const u8, io: std.Io, allocator: std.mem.Allocator, list: *std.ArrayList(u8)) !void {
    const file = try std.Io.Dir.cwd().openFile(io, arg, .{});
    defer file.close(io);
    errdefer list.deinit(allocator);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);

    try reader.interface.appendRemaining(allocator, list, .limited(50 * 1024 * 1024));
}
