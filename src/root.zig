const std = @import("std");
const component_storage = @import("./component_storage.zig");
const Type = std.builtin.Type;

pub const EntityId = packed struct { generation: u8, index: u24 };

pub fn Ecs(E: type) type {
    const entity_struct = switch (@typeInfo(E)) {
        .@"struct" => |s| s,
        else => @compileError("Entity must be a struct"),
    };

    return struct {
        pub const Entity = E;
        const Self = @This();

        allocator: std.mem.Allocator,
        components: Components(entity_struct.fields),
        entity_pool: std.ArrayListUnmanaged(u24) = .empty,
        entity_set: std.DynamicBitSetUnmanaged = .{},
        generations: std.ArrayListUnmanaged(u8) = .empty,

        pub fn init(gpa: std.mem.Allocator) Self {
            var components: Components(entity_struct.fields) = undefined;
            inline for (entity_struct.fields) |field| {
                @field(components, field.name) = .{};
            }

            return .{ .allocator = gpa, .components = components };
        }

        pub fn deinit(self: *Self) void {
            inline for (entity_struct.fields) |field| {
                @field(self.components, field.name).deinit(self.allocator);
            }

            self.entity_pool.deinit(self.allocator);
            self.entity_set.deinit(self.allocator);
            self.generations.deinit(self.allocator);
        }

        pub fn spawn(self: *Self, entity: Entity) !EntityId {
            const id = try self.allocEntity();
            self.entity_set.set(id.index);
            inline for (entity_struct.fields) |field| {
                const value = @field(entity, field.name);
                try @field(self.components, field.name).set(self.allocator, id.index, value);
            }

            return id;
        }

        pub fn despawn(self: *Self, entity: EntityId) !void {
            if (entity.index >= self.generations.items.len or entity.generation != self.generations.items[entity.index]) return;
            try self.entity_pool.append(self.allocator, entity.index);
            self.entity_set.unset(entity.index);
            self.generations.items[entity.index] += 1;
        }

        pub fn query(self: *Self, Query: type) !QueryIterator(Query, entity_struct.fields) {
            return try QueryIterator(Query, entity_struct.fields).init(self);
        }

        fn allocEntity(self: *Self) !EntityId {
            if (self.entity_pool.pop()) |index| {
                return .{
                    .generation = self.generations.items[index],
                    .index = index,
                };
            }

            if (self.generations.items.len >= self.entity_set.capacity()) {
                const prev = self.entity_set.capacity();
                const len = @max(@sizeOf(usize) * 8, prev * 2);
                try self.entity_set.resize(self.allocator, len, false);
            }

            const index = self.generations.items.len;
            try self.generations.append(self.allocator, 0);
            return .{ .generation = 0, .index = @intCast(index) };
        }
    };
}

fn Components(comptime entity_fields: []const Type.StructField) type {
    var component_fields: [entity_fields.len]Type.StructField = undefined;
    inline for (entity_fields, 0..) |field, i| {
        const Storage = component_storage.ComponentStorage(field.type);
        component_fields[i] = .{
            .name = field.name,
            .type = Storage,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Storage),
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .backing_integer = null,
        .fields = &component_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn QueryIterator(Query: type, comptime entity_fields: []const Type.StructField) type {
    const query_fields = switch (@typeInfo(Query)) {
        .@"struct" => |s| s.fields,
        else => @compileError("Query must be a struct"),
    };

    return struct {
        const Self = @This();

        current_entity_id: EntityId = undefined,
        components: *Components(entity_fields),
        entities: std.DynamicBitSet,
        generations: []const u8,
        iter: std.DynamicBitSet.Iterator(.{}),

        pub fn init(ecs: anytype) !Self {
            var entities: std.DynamicBitSetUnmanaged = try ecs.entity_set.clone(ecs.allocator);
            inline for (query_fields) |q| {
                const e = getField(q.name, entity_fields);
                if (isOptional(e.type) and !isOptional(q.type)) {
                    try @field(ecs.components, q.name).intersectWith(ecs.allocator, &entities);
                }
            }

            return .{
                .components = &ecs.components,
                .entities = .{ .allocator = ecs.allocator, .unmanaged = entities },
                .generations = ecs.generations.items,
                .iter = entities.iterator(.{}),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit();
        }

        pub fn next(self: *Self) ?Query {
            const index = self.iter.next() orelse return null;
            self.current_entity_id = .{ .generation = self.generations[index], .index = @intCast(index) };

            var result: Query = undefined;
            inline for (query_fields) |target| {
                const component = @field(self.components, target.name).get(index);
                const Source = unwrapNullablePointer(@TypeOf(component));
                @field(result, target.name) = convertComponentToQueryType(target.type, Source, component);
            }

            return result;
        }
    };
}

fn convertComponentToQueryType(Target: type, Source: type, value: ?*Source) Target {
    if (Source == Target) {
        return value.?.*;
    } else if (?Source == Target) {
        if (value == null) return null;
        return value.?.*;
    } else if (*Source == Target) {
        return value.?;
    } else if (?*Source == Target) {
        return value;
    } else {
        @compileError("cannot convert " ++ @typeName(Source) ++ " to " ++ @typeName(Target) ++ " for query");
    }
}

fn getField(comptime name: [:0]const u8, comptime fields: []const Type.StructField) Type.StructField {
    inline for (fields) |f| {
        if (std.mem.eql(u8, name, f.name)) return f;
    }

    @compileError(name ++ " is not a valid query field");
}

fn isOptional(T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => true,
        else => false,
    };
}

fn unwrapNullablePointer(T: type) type {
    const U = @typeInfo(T).optional.child;
    return @typeInfo(U).pointer.child;
}
