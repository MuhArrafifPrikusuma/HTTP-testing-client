const std = @import("std");

const Allocator = std.mem.Allocator;
pub const ZhashMapErr = error{
    InvalidKey,
};

inline fn isPrimitive(comptime T: type) bool {
    return switch (T) {
        .Int, .Float, .Bool, .void, .null, .type, .comptime_int, .comptime_float => true,
        else => false,
    };
}

/// return a hash map with K as key and usize as a counter for how many times that key has been found
pub fn StructHashMap(comptime K: type, comptime Context: type) type {
    if (K != std.builtin.Type.Struct)
        @compileError("Expected struct, got" ++ @typeInfo(K));

    return struct {
        const Self = @This();

        pool: std.HashMap(
            K,
            usize,
            Context,
            std.hash_map.default_max_load_percentage,
        ),
        allocator: std.mem.Allocator,

        pub fn init(allocator: Allocator) StructHashMap(K, Context) {
            return .{
                .pool = std.HashMap(
                    K,
                    usize,
                    Context,
                    std.hash_map.default_max_load_percentage,
                ).init(allocator),

                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.pool.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            self.pool.deinit();
        }

        fn MakeStorage(comptime T: type) type {
            var field_names: [@typeInfo(T).@"struct".field_names.len][:0]const u8 = undefined;
            var field_types: [@typeInfo(T).@"struct".field_types.len]type = undefined;
        }

        /// acquire and duplicate key string if not already exist
        /// NOTE: this function copy the data therefore caller is responsible of freeing the Key after calling this function
        pub fn intern(self: *Self, key: K) !void {
            const ptr = try self.pool.getOrPut(key);

            if (ptr.found_existing) {
                ptr.value_ptr.* += 1;
                return;
            } else {
                inline for (
                    @typeInfo(K).@"struct".field_types,
                    @typeInfo(K).@"struct".field_names,
                ) |@"type", name| {
                    if (isPrimitive(@"type")) {} else {}
                }
                const body = try self.allocator.dupe(u8, key.body);

                ptr.value_ptr.* = 1;

                ptr.key_ptr.* = key;

                ptr.key_ptr.body = body;

                return;
            }
            unreachable;
        }

        /// decrement counter and when the counter reaches 0 delete the key
        pub fn release(self: *Self, key: *K) !void {
            if (self.pool.getPtr(key.*)) |count| {
                count.* -= 1;
                if (count.* == 0) {
                    _ = self.pool.remove(key.*);
                    self.allocator.destroy(key);
                }
                return;
            }
            return ZhashMapErr.InvalidKey;
        }

        pub fn invalidate(self: *Self, key: *K) !void {
            if (self.pool.getPtr(key.*)) |count| {
                count.* = 0;
                _ = self.pool.remove(key.*);
                self.allocator.destroy(key);
                return;
            }
            return ZhashMapErr.InvalidKey;
        }

        pub fn get(self: *Self) ?*K {
            var iter = self.pool.iterator();

            if (iter.next()) |item| {
                return item.key_ptr;
            }
            return null;
        }
    };
}
