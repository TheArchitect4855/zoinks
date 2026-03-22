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

        pub fn intersectWith(self: *Self, gpa: std.mem.Allocator, entities: *std.DynamicBitSetUnmanaged) !void {
            _ = self;
            _ = gpa;
            _ = entities;
        }
    };
}

fn SparseComponentStorage(T: type) type {
    const page_size = 1024;
    const Page = [page_size]T;

    return struct {
        const Self = @This();

        entities: std.DynamicBitSetUnmanaged = .{},
        pages: std.ArrayListUnmanaged(?*Page) = .empty,

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.entities.deinit(gpa);

            for (self.pages.items) |i| {
                if (i) |page| gpa.destroy(page);
            }

            self.pages.deinit(gpa);
        }

        pub fn get(self: *Self, index: usize) ?*T {
            if (index >= self.entities.capacity() or !self.entities.isSet(index)) return null;
            return &self.pages.items[index / page_size].?[index % page_size];
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
                    self.pages.items[page_index] = page;
                }

                page.*[index % page_size] = v;

                if (index >= self.entities.capacity()) try self.entities.resize(gpa, index + 1, false);
                self.entities.set(index);
            } else if (index < self.entities.capacity()) {
                self.entities.unset(index);
            }
        }

        pub fn intersectWith(self: *Self, gpa: std.mem.Allocator, entities: *std.DynamicBitSetUnmanaged) !void {
            if (self.entities.capacity() < entities.capacity()) {
                try self.entities.resize(gpa, entities.capacity(), false);
            }

            entities.setIntersection(self.entities);
        }
    };
}
