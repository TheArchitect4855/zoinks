const std = @import("std");

pub fn ComponentStorage(T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |opt| SparseComponentStorage(opt.child),
        else => PackedComponentStorage(T),
    };
}

fn PackedComponentStorage(T: type) type {
    return struct {
        const Self = @This();

        values: std.ArrayListUnmanaged(T) = .empty,

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.values.deinit(gpa);
        }

        pub fn get(self: *Self, index: usize) ?*T {
            if (index >= self.values.items.len) return null;
            return &self.values.items[index];
        }

        pub fn set(self: *Self, gpa: std.mem.Allocator, index: usize, value: T) !void {
            if (index < self.values.items.len) {
                self.values.items[index] = value;
                return;
            }

            const n = index - self.values.items.len + 1;
            try self.values.appendNTimes(gpa, undefined, n);
            self.values.items[index] = value;
        }
    };
}

fn SparseComponentStorage(T: type) type {
    const page_size = 1024;
    const Page = [page_size]?T;

    return struct {
        const Self = @This();

        pages: std.ArrayListUnmanaged(?*Page) = .empty,

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            for (self.pages.items) |i| {
                if (i) |page| gpa.destroy(page);
            }

            self.pages.deinit(gpa);
        }

        pub fn get(self: *Self, index: usize) ?*T {
            const page_index = index / page_size;
            if (page_index >= self.pages.items.len) return null;

            const page = self.pages.items[page_index] orelse return null;
            const value = &page[index % page_size];
            if (value.* == null) return null;
            return &value.*.?;
        }

        pub fn set(self: *Self, gpa: std.mem.Allocator, index: usize, value: ?T) !void {
            const page_index = index / page_size;
            if (value) |v| {
                if (page_index >= self.pages.items.len) {
                    const n = page_index - self.pages.items.len + 1;
                    try self.pages.appendNTimes(gpa, null, n);
                }

                var page: *Page = undefined;
                if (self.pages.items[page_index]) |p| {
                    page = p;
                } else {
                    page = try gpa.create(Page);
                    page.* = [_]?T{null} ** page_size;
                    self.pages.items[page_index] = page;
                }

                page.*[index % page_size] = v;
            } else {
                if (page_index >= self.pages.items.len) return;
                if (self.pages.items[page_index]) |page| page[index % page_size] = null;
            }
        }
    };
}
