/// A unique identifier for an entity. It should be treated as an immutable,
/// opaque type.
pub const EntityId = packed struct { generation: u8, index: u24 };
