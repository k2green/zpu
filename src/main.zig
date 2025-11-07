const std = @import("std");
const zpu = @import("zpu");

pub fn main() !void {
    var instance = try zpu.Instance.create(.{});
    defer instance.release();
}
