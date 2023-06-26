const std = @import("std");
const features = @import("features");

pub fn main() !void {
    std.debug.print("\n", .{});

    if (comptime features.a) {
        std.debug.print("Feature 'A' is active!\n", .{});
    }

    if (features.b) |b| {
        std.debug.print("Feature 'B' is active! (\"{s}\")\n", .{b});
    }

    if (features.c) |c| {
        std.debug.print("Feature 'C' is active! (\"{}\")\n", .{c});
    }
}
