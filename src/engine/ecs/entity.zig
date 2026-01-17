//! Entity definition and ID generation.

const std = @import("std");

pub const EntityId = u64;

pub const EntityManager = struct {
    next_id: EntityId = 1,

    pub fn create(self: *EntityManager) EntityId {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }
};
