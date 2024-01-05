const std = @import("std");

// unneeded print function to make my life easier
pub fn print(text: []const u8) void {
    std.debug.print("{s}", .{text});
}

pub fn main() !void {
    print("test");
}
