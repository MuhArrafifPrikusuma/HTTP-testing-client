const std = @import("std");

const Allocator = std.mem.Allocator;
pub const ZhashMapErr = error{
    InvalidKey,
};

inline fn isPrimitive(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .float, .void, .type, .noreturn, .comptime_float, .comptime_int, .@"enum" => true,
        else => false,
    };
}

/// NOTE: also use this for the error accumulator
/// return a hash map with K as key and usize as a counter for how many times that key has been found
pub fn StructHashMap(comptime K: type, comptime Context: type) type {
    if (@typeInfo(K) != .@"struct")
        @compileError("Expected struct ");

    return struct {
        const Self = @This();

        map: std.HashMap(
            K,
            usize,
            Context,
            std.hash_map.default_max_load_percentage,
        ),
        allocator: std.mem.Allocator,

        pub fn init(allocator: Allocator) StructHashMap(K, Context) {
            return .{
                .map = std.HashMap(
                    K,
                    usize,
                    Context,
                    std.hash_map.default_max_load_percentage,
                ).init(allocator),

                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.map.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            self.map.deinit();
        }
        //
        // fn MakeStorage(comptime T: type) type {
        //     var field_names: [@typeInfo(T).@"struct".field_names.len][:0]const u8 = undefined;
        //     var field_types: [@typeInfo(T).@"struct".field_types.len]type = undefined;
        //     var attributes: [@typeInfo(T).@"struct".field_names.len]std.builtin.Type.Struct.FieldAttributes = undefined;
        //
        //     inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_attrs, 0..) |name, attr, i| {
        //         field_names[i] = name;
        //         field_types[i] = @FieldType(T, name);
        //         attributes[i] = attr;
        //     }
        //
        //     return @Struct(.auto, null, field_names, field_types, attributes);
        // }

        /// acquire and duplicate key string if not already exist
        /// NOTE: this function copy the data therefore caller is responsible of freeing the Key after calling this function
        pub fn intern(self: *Self, key: *const K) !void {
            const ptr = try self.map.getOrPut(key.*);

            if (ptr.found_existing) {
                ptr.value_ptr.* += 1;
                return;
            } else {
                inline for (
                    @typeInfo(K).@"struct".field_types,
                    @typeInfo(K).@"struct".field_names,
                ) |@"type", name| {
                    const source_value = @field(key, name);

                    if (comptime isPrimitive(@"type")) {
                        @field(ptr.key_ptr, name) = source_value;
                    } else if (@typeInfo(@"type") == .pointer) {
                        std.debug.assert(@typeInfo(@"type").pointer.child == u8);
                        @field(ptr.key_ptr, name) = try self.allocator.dupe(
                            @typeInfo(@"type").pointer.child,
                            source_value,
                        );
                    } else {
                        @compileError("can only support pointer type");
                    }
                }

                ptr.value_ptr.* = 1;

                return;
            }
            unreachable;
        }

        /// decrement counter and when the counter reaches 0 delete the key
        pub fn release(self: *Self, key: *K) !void {
            if (self.map.getPtr(key.*)) |count| {
                count.* -= 1;
                if (count.* == 0) {
                    _ = self.map.remove(key.*);
                    self.allocator.destroy(key);
                }
                return;
            }
            return ZhashMapErr.InvalidKey;
        }

        pub fn invalidate(self: *Self, key: *K) !void {
            if (self.map.getPtr(key.*)) |count| {
                count.* = 0;
                _ = self.map.remove(key.*);
                self.allocator.destroy(key);
                return;
            }
            return ZhashMapErr.InvalidKey;
        }

        pub fn get(self: *Self) ?*K {
            var iter = self.map.iterator();

            if (iter.next()) |item| {
                return item.key_ptr;
            }
            return null;
        }
    };
}
