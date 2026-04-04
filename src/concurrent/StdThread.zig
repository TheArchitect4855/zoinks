//! A wrapper around `std.Thread` to be used with a concurrent ECS.

const std = @import("std");

thread: std.Thread,

pub fn join(self: @This()) void {
    self.thread.join();
}

pub fn spawn(comptime function: anytype, args: anytype) std.Thread.SpawnError!@This() {
    const thread = try std.Thread.spawn(.{}, function, args);
    return .{ .thread = thread };
}
