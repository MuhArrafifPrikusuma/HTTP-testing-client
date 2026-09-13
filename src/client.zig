//! handle network io etc
const std = @import("std");
const res = @import("response.zig");
const ansii = @import("ansii.zig");
const curl = @import("curl.zig");

const Req = @import("Request.zig");
const Task = @import("Task.zig");

pub fn clientNet(
    io: std.Io,
    ci: *Req.ClientInterface,
    task: *Task,
    thread_id: usize,
    max_response: u32,
    progress: std.Progress.Node,
) void {
    var buferr: [1028]u8 = undefined;
    var err_writer = std.Io.File.stderr().writer(io, &buferr);
    const stderr = &err_writer.interface;

    const allocator = task.arena.allocator();
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    // const testing = curl.curl_global_init(curl.CURL_GLOBAL_ALL);
    // std.debug.print("testing curl {d}\n", .{testing});

    var buf: [8196]u8 = undefined;
    const progress_name: []const u8 = pn: {
        break :pn std.fmt.bufPrint(&buf, "Fetching payload to: {s}{s}", .{
            ci.client[thread_id].uri,
            ci.client[thread_id].request.path,
        }) catch {
            break :pn "Unknown";
        };
    };

    const prog = progress.start(progress_name, ci.client[thread_id].repeat);
    defer prog.end();

    while (true) {
        const opt = task.read(io, thread_id, ci.client[thread_id].repeat) catch {
            break;
        };

        const response = client.fetch(opt.*) catch |err| {
            handleFetchError(stderr, opt, err);

            allocator.destroy(opt);
            continue;
        };
        if (opt.payload) |payload| {
            allocator.free(payload);
        }
        allocator.destroy(opt);

        res.storeResponse(task, io, response.status, max_response);

        prog.completeOne();
    }
    stderr.flush() catch |err| std.log.err("stderr.flush(): {any}\n", .{err});
}

fn handleFetchError(
    stderr: *std.Io.Writer,
    options: *const std.http.Client.FetchOptions,
    err: std.http.Client.FetchError,
) void {
    switch (err) {
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionPending,
        => connectionErrors(stderr, options, err) catch |e|
            std.log.err("connectionErrors: {any}\n", .{e}),
        else => stderr.print("{s}{s}{s}:{any} PLACEHOLDER\n", .{
            ansii.styles.dim,
            options.location.url,
            ansii.reset,
            err,
        }) catch |e|
            std.log.err("else placeholder Err: {any}\n", .{e}),
    }
}

fn connectionErrors(
    stderr: *std.Io.Writer,
    options: *const std.http.Client.FetchOptions,
    err: std.http.Client.FetchError,
) !void {
    switch (err) {
        error.ConnectionRefused => try stderr.print(
            "{s}{s}{s}:Connection Refused\n",
            .{
                ansii.styles.dim,
                options.location.url,
                ansii.reset,
            },
        ),

        error.ConnectionPending => try stderr.print(
            "{s}{s}{s}:Attempting initiate connection before the previous connection finishes\n",
            .{
                ansii.styles.dim,
                options.location.url,
                ansii.reset,
            },
        ),

        error.ConnectionResetByPeer => try stderr.print(
            "{s}{s}{s}:Connection dropped by server\n",
            .{
                ansii.styles.dim,
                options.location.url,
                ansii.reset,
            },
        ),
        else => unreachable,
    }
}

fn fetcher(task: *Task, multi: *curl.CURL) void {
    const easy = curl.curl_easy_init() orelse {
        std.log.err("failed to initiate curl easy\n", .{});
        return;
    };

    curl.curl_easy_setopt(easy, curl.CURLOPT_HTTPHEADER, headers);

    if (curl.curl_multi_add_handle(multi, easy) != 0) {
        std.log.err("curl_multi_add_handle in fetcher\n", .{});
    }
}

// NOTE: right now focus on making response and response checker and then rules
