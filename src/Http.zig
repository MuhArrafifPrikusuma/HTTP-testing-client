const std = @import("std");
const curl = @import("curl.zig");

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

const Self = @This();

slist: [*c]curl.curl_slist = null,
method: Method,
payload: [*c]const u8,

pub fn appendToSlist(self: *Self, h_string: [*c]const u8) void {
    const temp: [*c]curl.curl_slist = curl.curl_slist_append(self.slist, h_string);
    self.slist = temp;
}
