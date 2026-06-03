const std = @import("std");
const component_storage = @import("component_storage.zig");
const Type = std.builtin.Type;

const EntityId = @import("entity_id.zig").EntityId;

/// The core ECS type. `E` is a struct that represents your entity.
///
/// Generally, you should not access any of the fields on the ECS, and only use
/// the public methods.
pub fn Ecs(E: type) type {
    return struct {
        /// The entity struct you passed to the ECS function.
        pub const Entity = E;

        /// Field info for the entity struct.
        pub const entity_fields = switch (@typeInfo(E)) {
            .@"struct" => |s| s,
            else => @compileError("Entity must be a struct"),
        }.fields;

        // Error types
        pub const DespawnError = std.mem.Allocator.Error;
        pub const SpawnError = std.mem.Allocator.Error;
        pub const QueryError = std.mem.Allocator.Error;
        pub const Error = DespawnError || SpawnError || QueryError;

        const ThisEcs = @This();

        allocator: std.mem.Allocator,
        components: Components(entity_fields),
        entity_pool: std.ArrayListUnmanaged(u24) = .empty,
        entity_set: std.DynamicBitSetUnmanaged = .{},
        generations: std.ArrayListUnmanaged(u8) = .empty,

        /// Initializes a new ECS instance.
        pub fn init(gpa: std.mem.Allocator) ThisEcs {
            var components: Components(entity_fields) = undefined;
            inline for (entity_fields) |field| {
                @field(components, field.name) = .{};
            }

            return .{ .allocator = gpa, .components = components };
        }

        /// Deinitializes this ECS. Once called, it can no longer be used.
        pub fn deinit(self: *ThisEcs) void {
            inline for (entity_fields) |field| {
                @field(self.components, field.name).deinit(self.allocator);
            }

            self.entity_pool.deinit(self.allocator);
            self.entity_set.deinit(self.allocator);
            self.generations.deinit(self.allocator);
        }

        /// Tries to spawn a new entity and return its ID.
        pub fn spawn(self: *ThisEcs, entity: Entity) SpawnError!EntityId {
            const id = try self.allocEntity();
            self.entity_set.set(id.index);
            inline for (entity_fields) |field| {
                const value = @field(entity, field.name);
                try @field(self.components, field.name).set(self.allocator, id.index, value);
            }

            return id;
        }

        /// Tries to despawn the specified entity. If successful, the passed
        /// entity ID is no longer valid.
        pub fn despawn(self: *ThisEcs, entity: EntityId) DespawnError!void {
            if (entity.index >= self.generations.items.len or entity.generation != self.generations.items[entity.index]) return;
            try self.entity_pool.append(self.allocator, entity.index);
            self.entity_set.unset(entity.index);
            self.generations.items[entity.index] += 1;
        }

        /// Tries to run the specified query on this ECS and return its
        /// iterator.
        ///
        /// `Query` must be a struct. The field names of the struct must match
        /// fields on the `Entity` type. The types of those fields must be an
        /// optional of, a pointer to, or an optional pointer to the type on the
        /// entity struct. (i.e., if `foo: u32` is a field on the `Entity`
        /// struct, a query field for `foo` may be one of `foo: u32`,
        /// `foo: ?u32`, `foo: *u32`, `foo: ?*u32`, `foo: *const u32`, or
        /// `foo: ?*const u32`)
        ///
        /// A query field may have a default value. If a query field has a
        /// default value, it will filter the results returned from this
        /// iterator to only entities where that field is equal to the query
        /// field's default value. (using the `==` operator)
        pub fn query(self: *ThisEcs, Query: type) QueryError!QueryIterator(Query) {
            return try QueryIterator(Query).init(self);
        }

        fn allocEntity(self: *ThisEcs) std.mem.Allocator.Error!EntityId {
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

        /// An iterator over a query. Generally should not be used directly; use
        /// `Ecs.query` instead.
        pub fn QueryIterator(Query: type) type {
            return struct {
                const ThisQueryIterator = @This();

                /// Field info for the query struct.
                pub const query_fields = switch (@typeInfo(Query)) {
                    .@"struct" => |s| s.fields,
                    else => @compileError("Query must be a struct"),
                };

                /// The entity ID of the last result returned from `next`. This
                /// is undefined before `next` has been called for the first
                /// time and after `next` returns `null`.
                current_entity_id: EntityId = undefined,

                allocator: std.mem.Allocator,
                components: *Components(entity_fields),
                entities: std.DynamicBitSetUnmanaged,
                ecs_generations: []const u8,
                generations: []const u8,
                iter: std.DynamicBitSet.Iterator(.{}),

                /// Tries to initialize a query iterator. This generally should
                /// not be used directly; use `Ecs.query` instead.
                pub fn init(ecs: *ThisEcs) QueryError!ThisQueryIterator {
                    const allocator = ecs.allocator;
                    const generations = try allocator.alloc(u8, ecs.generations.items.len);
                    @memcpy(generations, ecs.generations.items);

                    var entities: std.DynamicBitSetUnmanaged = try ecs.entity_set.clone(allocator);
                    inline for (query_fields) |q| {
                        const e = getField(q.name, entity_fields);
                        if (isOptional(e.type) and !isOptional(q.type)) {
                            try @field(ecs.components, q.name).intersectWith(allocator, &entities);
                        }
                    }

                    return .{
                        .allocator = allocator,
                        .components = &ecs.components,
                        .entities = entities,
                        .ecs_generations = ecs.generations.items,
                        .generations = generations,
                        .iter = entities.iterator(.{}),
                    };
                }

                /// Deinitializes this query iterator. After this method is
                /// called, this iterator is no longer valid.
                pub fn deinit(self: *ThisQueryIterator) void {
                    self.entities.deinit(self.allocator);
                    self.allocator.free(self.generations);
                }

                /// Returns the next result from this iterator, or `null` when
                /// the iterator is empty.
                ///
                /// Use `current_entity_id` to get the ID of the current entity
                /// after calling this function.
                pub fn next(self: *ThisQueryIterator) ?Query {
                    outer: while (self.iter.next()) |index| {
                        if (self.generations[index] != self.ecs_generations[index]) continue; // Make sure the entity hasn't despawned
                        self.current_entity_id = .{ .generation = self.generations[index], .index = @intCast(index) };

                        var result: Query = undefined;
                        inline for (query_fields) |target| {
                            const component = @field(self.components, target.name).get(index);
                            const Source = unwrapNullablePointer(@TypeOf(component));
                            const value: target.type = convertComponentToQueryType(target.type, Source, component);

                            // Filter on query values
                            if (target.defaultValue()) |default_value| {
                                if (default_value != value) continue :outer;
                            }

                            @field(result, target.name) = value;
                        }

                        return result;
                    }

                    return null;
                }
            };
        }
    };
}

fn Components(entity_fields: []const Type.StructField) type {
    var field_names: [entity_fields.len][]const u8 = undefined;
    var field_types: [entity_fields.len]type = undefined;
    inline for (entity_fields, 0..) |field, i| {
        field_names[i] = field.name;
        field_types[i] = component_storage.ComponentStorage(field.type);
    }

    const field_attrs = [1]std.builtin.Type.StructField.Attributes{.{}} ** entity_fields.len;
    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
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
