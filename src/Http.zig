const std = @import("std");
const curl = @import("curl.zig");

pub const RequestHeader = struct {
    body: ?[]const u8 = null,
    content_type: []const u8 = "text/plain",
    accept_type: ?[]const u8 = null,

    keep_alive: bool = true,
};

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,
    TRACE,
    CONNECT,
    QUERY,
    PRI,
};

/// for custom header
const Self = @This();

pub const HttpError = error{
    NoUrlFound,
    NoMethodFound,
    NoHeaderFound,
    CurlSetoptFailed,
};

var header_changed: std.atomic.Value(bool) = .init(true);

// everything must go here first before going to header

// this is nullable just so i can append alot safely all this is actually
// required
url: ?[*:0]const u8 = null,
headers: ?*curl.curl_slist = null,
method: ?Method = null,
payload: ?[]const u8 = null,

// free
pub fn applyToEasy(self: *const Self, easy: *curl.CURL) !void {
    const url = self.url orelse return HttpError.NoUrlFound;
    const method = self.method orelse return HttpError.NoMethodFound;

    var code = curl.curl_easy_setopt(easy, curl.CURLOPT_URL, url);
    if (code != curl.CURLE_OK) {
        std.log.err("curl_easy_setopt url: {d}\n", .{code});
        return HttpError.CurlSetoptFailed;
    }

    if (self.headers) |headers| {
        code = curl.curl_easy_setopt(easy, curl.CURLOPT_HTTPHEADER, headers);

        if (code != curl.CURLE_OK) {
            std.log.err("curl_easy_setopt header: {d}\n", .{code});
            return HttpError.CurlSetoptFailed;
        }
    }

    code = switch (method) {
        .GET => curl.curl_easy_setopt(easy, curl.CURLOPT_HTTPGET, @as(c_long, 1)),
        .POST => curl.curl_easy_setopt(easy, curl.CURLOPT_POST, @as(c_long, 1)),
        .HEAD => curl.curl_easy_setopt(easy, curl.CURLOPT_NOBODY),
        else => @panic("method not yet supported"),
    };
    if (code != curl.CURLE_OK) {
        std.log.err("curl_easy_setopt method: {d}\n", .{code});
        return HttpError.CurlSetoptFailed;
    }

    if (method == .POST) {
        if (self.payload) |body| {
            code = curl.curl_easy_setopt(easy, curl.CURLOPT_POSTFIELDS, body.ptr);
            if (code != curl.CURLE_OK) {
                std.log.err("curl_easy_setopt postfield: {d}\n", .{code});
                return HttpError.CurlSetoptFailed;
            }

            code = curl.curl_easy_setopt(
                easy,
                curl.CURLOPT_POSTFIELDSIZE,
                @as(c_long, @intCast(body.len)),
            );
            if (code != curl.CURLE_OK) {
                std.log.err("curl_easy_setopt postfieldsize: {d}\n", .{code});
                return HttpError.CurlSetoptFailed;
            }
        }
    }
}

/// this copies the string therefore caller is responsible for free the string after appending
pub fn appendHeader(
    self: *Self,
    data: [*:0]const u8,
) !void {
    const tmp: *curl.curl_slist = null;
    curl.curl_slist_append(self.headers, data);
}

/// use this after perform
pub fn free(self: *Self, allocator: std.mem.Allocator) !void {
    if (self.payload) |payload|
        allocator.free(payload);

    curl.curl_slist_free_all(self.headers);
}

// pub fn destroyHeader(self: *Self, header: ?*curl.curl_slist) void {
//     curl.curl_slist_free_all(header);
// }

test "Self.applyToEasy populates curl options" {
    const code = curl.curl_global_init(curl.CURL_GLOBAL_ALL);
    if (code != curl.CURLE_OK) {
        return error.FailedInitGlobal;
    }

    defer curl.curl_global_cleanup();

    const easy = curl.curl_easy_init() orelse return error.TestFailed;
    defer curl.curl_easy_cleanup(easy);

    const ctx = Self{
        .url = "http://127.0.0.1:1/",
        .method = .POST,
        .payload = "hello world",
        .headers = null,
    };

    try ctx.applyToEasy(easy);
}
