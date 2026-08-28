const std = @import("std");

var next_should_bfile: bool = false;

pub fn handleArgs(args: std.process.Args, io: std.Io) !void {
    var iter = args.iterate();
    const allocator = std.heap.smp_allocator;

    var buf: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &writer.interface;

    // start from 1 to match argument len which also start from 1
    var i: usize = 1;
    while (iter.next()) |arg| : (i += 1) {
        if (i == 1) continue;
        if (next_should_bfile) consume(arg, io, allocator) catch |err| {
            try stdout.print("{any}\n", .{err});
            break;
        };

        processArg(arg, stdout) catch |err| std.log.err("{any}\n", .{err});
    }
    try stdout.flush();
}

const ArgsHandlers = *const fn (*std.Io.Writer) anyerror!void;

fn processArg(arg: []const u8, writer: *std.Io.Writer) !void {
    const validArgs = [_][]const u8{
        "-h",
        "-run",
    };

    const argsFunctions = [_]ArgsHandlers{
        help,
        setConsume,
    };

    for (argsFunctions, 0..) |func, i| {
        if (std.ascii.eqlIgnoreCase(arg, validArgs[i])) {
            try func(writer);
            return;
        }
    }

    writer.print("\x1B[38;2;255;20;10mError: Invalid argument\x1B[0m\n", .{}) catch {};
    writer.flush() catch {};
    std.process.exit(1);
}
fn help(writer: *std.Io.Writer) !void {
    try writer.print("test help\n", .{});
    std.log.debug("fill later\n", .{});
}

/// consume json files to feed data to request builder to build request from the json files
fn setConsume(writer: *std.Io.Writer) !void {
    try writer.print("test consume\n", .{});
    if (!next_should_bfile) {
        next_should_bfile = true;
        return;
    }
}

fn consume(arg: []const u8, io: std.Io, allocator: std.mem.Allocator) !void {
    const file = try std.Io.Dir.cwd().openFile(io, arg, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf).interface;

    var list: std.ArrayList(u8) = .empty;
    list.deinit(allocator);

    try reader.appendRemaining(allocator, &list, .unlimited);
}
