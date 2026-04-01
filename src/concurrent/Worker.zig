const std = @import("std");

pub const VTable = struct {
    deinit: *const fn (self: *anyopaque, allocator: std.mem.Allocator) void,
    join: *const fn (self: *anyopaque) void,
};

const Self = @This();
ptr: *anyopaque,
vtable: *const VTable,

pub fn from(T: type, ptr: *T) Self {
    const vtable = VTable{
        .deinit = @ptrCast(&T.deinit),
        .join = @ptrCast(&T.join),
    };

    return .{ .ptr = ptr, .vtable = &vtable };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.vtable.deinit(self.ptr, allocator);
}

pub fn join(self: *Self) void {
    self.vtable.join(self.ptr);
}
