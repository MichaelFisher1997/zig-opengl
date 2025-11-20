pub const BlockType = enum(u8) {
    Air = 0,
    Grass = 1,
    Dirt = 2,
    Stone = 3,
    _, // Make the enum non-exhaustive to handle corrupt values gracefully if that's the issue
};

pub const Block = struct {
    type: BlockType,

    pub fn isActive(self: Block) bool {
        return self.type != .Air;
    }
};
