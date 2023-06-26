const std = @import("std");
const FeatureFlags = @This();

write: *std.Build.WriteFileStep,
module: *std.Build.Module,

pub const Builder = struct {
    contents: std.ArrayListUnmanaged(u8) = .{},
    builder: *std.Build,

    fn allocator(self: *Builder) std.mem.Allocator {
        return self.builder.allocator;
    }

    pub fn addFeatureFlag(self: *Builder, name: []const u8, value: anytype, inferred: bool) !void {
        const T = @TypeOf(value);
        const type_value = try self.serializeVariable(T, value);
        defer self.allocator().free(type_value);

        if (inferred) {
            try std.fmt.format(self.contents.writer(self.allocator()), "pub const {s} = {s};\n", .{
                name,
                type_value,
            });
        } else {
            try std.fmt.format(self.contents.writer(self.allocator()), "pub const {s}: {s} = {s};\n", .{
                name,
                @typeName(T),
                type_value,
            });
        }
    }

    fn serializeVariable(self: *Builder, comptime T: type, x: T) ![]const u8 {
        const error_msg = "feature flag not implemented for this type";

        return switch (@typeInfo(T)) {
            .Void => try self.allocator().dupe(u8, "{}"),
            .Undefined => try self.allocator().dupe(u8, "undefined"),
            .Null => try self.allocator().dupe(u8, "null"),
            .Bool => try self.allocator().dupe(u8, if (x) "true" else "false"),
            .Int, .ComptimeInt, .Float, .ComptimeFloat => try std.fmt.allocPrint(self.allocator(), "{}", .{x}),

            .Pointer => |ptr| switch (ptr.size) {
                .Slice => brk: {
                    var res = std.ArrayList(u8).init(self.allocator());
                    errdefer res.deinit();
                    try std.fmt.format(res.writer(), "&[_]{s}{{", .{@typeName(ptr.child)});
                    for (x) |v| {
                        const value = try self.serializeVariable(ptr.child, v);
                        defer self.allocator().free(value);
                        try std.fmt.format(res.writer(), "{s},", .{value});
                    }
                    try res.appendSlice("}");
                    break :brk res.toOwnedSlice();
                },
                else => @compileError(error_msg),
            },

            .Struct => |s| brk: {
                var res = std.ArrayList(u8).init(self.allocator());
                errdefer res.deinit();

                res.appendSlice(".{");
                inline for (res.fields) |field| {
                    const value = try self.serializeVariable(field.child, @field(x, field.name));
                    defer self.allocator().free(value);

                    if (s.is_tuple) {
                        try std.fmt.format(res.writer(), "{s},", .{value});
                    } else {
                        try std.fmt.format(res.writer(), "{s}: {s},", .{ field.name, value });
                    }
                }
                res.appendSlice("}");

                break :brk res.toOwnedSlice();
            },

            .ErrorUnion => |eu| brk: {
                const v = x catch |e| break :brk self.serializeVariable(eu.error_set, e);
                break :brk self.serializeVariable(eu.payload, v);
            },

            .Enum => std.fmt.allocPrint(self.allocator(), ".{s}", .{@tagName(x)}),
            .Optional => |opt| if (x) |v| self.serializeVariable(opt.child, v) else self.serializeVariable(@TypeOf(null), null),
            .ErrorSet => std.fmt.allocPrint(self.allocator(), "error.{s}", .{@errorName(x)}),
            else => @compileError(error_msg),
        };
    }

    pub fn build(self: *Builder) !FeatureFlags {
        defer self.deinit();

        const path = try std.fs.path.join(self.allocator(), &[_][]const u8{
            self.builder.makeTempPath(),
            "feature_flags.zig",
        });
        //defer self.allocator().free(path);

        const write = self.builder.addWriteFile(path, self.contents.items);
        const module = self.builder.createModule(.{ .source_file = .{ .path = path } });

        return .{
            .write = write,
            .module = module,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.contents.deinit(self.allocator());
    }
};

pub fn builder(b: *std.Build) Builder {
    return .{
        .builder = b,
    };
}

pub fn installOn(self: *const FeatureFlags, compile: *std.Build.Step.Compile, name: ?[]const u8) void {
    compile.addModule(name orelse "features", self.module);
    compile.step.dependOn(&self.write.step);
}
