//! LOD Manager - orchestrates multi-level chunk loading for extreme render distances.
//!
//! Implements a Distant Horizons-style system where:
//! - LOD0 (0-16 chunks): Full detail, current chunk system
//! - LOD1 (16-32 chunks): 2x simplified, 4 chunks merged
//! - LOD2 (32-64 chunks): 4x simplified, 16 chunks merged
//! - LOD3 (64-100 chunks): 8x simplified, 64 chunks merged, heightmap only
//!
//! Key principles:
//! - LOD3 generates first (fast heightmap), fills horizon quickly
//! - LOD0 generates last but gets priority in movement direction
//! - Smooth transitions via fog masking

const std = @import("std");
const lod_chunk = @import("lod_chunk.zig");
const LODLevel = lod_chunk.LODLevel;
const LODChunk = lod_chunk.LODChunk;
const LODRegionKey = lod_chunk.LODRegionKey;
const LODRegionKeyContext = lod_chunk.LODRegionKeyContext;
const LODConfig = lod_chunk.LODConfig;
const LODState = lod_chunk.LODState;

const Chunk = @import("chunk.zig").Chunk;
const ChunkMesh = @import("chunk_mesh.zig").ChunkMesh;
const worldToChunk = @import("chunk.zig").worldToChunk;
const Vec3 = @import("../engine/math/vec3.zig").Vec3;
const RHI = @import("../engine/graphics/rhi.zig").RHI;
const log = @import("../engine/core/log.zig");

const JobSystem = @import("../engine/core/job_system.zig");
const JobQueue = JobSystem.JobQueue;
const WorkerPool = JobSystem.WorkerPool;
const Job = JobSystem.Job;

const RingBuffer = @import("../engine/core/ring_buffer.zig").RingBuffer;

/// Statistics for LOD system monitoring
pub const LODStats = struct {
    lod0_loaded: u32 = 0,
    lod1_loaded: u32 = 0,
    lod2_loaded: u32 = 0,
    lod3_loaded: u32 = 0,
    lod0_generating: u32 = 0,
    lod1_generating: u32 = 0,
    lod2_generating: u32 = 0,
    lod3_generating: u32 = 0,
    memory_used_mb: u32 = 0,
    upgrades_pending: u32 = 0,
    downgrades_pending: u32 = 0,

    pub fn totalLoaded(self: *const LODStats) u32 {
        return self.lod0_loaded + self.lod1_loaded + self.lod2_loaded + self.lod3_loaded;
    }

    pub fn totalGenerating(self: *const LODStats) u32 {
        return self.lod0_generating + self.lod1_generating + self.lod2_generating + self.lod3_generating;
    }
};

/// LOD transition request
const LODTransition = struct {
    region_key: LODRegionKey,
    target_lod: LODLevel,
    priority: i32,
};

/// Main LOD Manager - coordinates all LOD levels
pub const LODManager = struct {
    allocator: std.mem.Allocator,
    config: LODConfig,

    // Storage per LOD level (LOD0 uses existing World.chunks)
    lod1_regions: std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80),
    lod2_regions: std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80),
    lod3_regions: std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80),

    // Separate job queues per LOD level
    // LOD3 queue processes first (fast), LOD0 queue last (slow but priority)
    lod1_gen_queue: *JobQueue,
    lod2_gen_queue: *JobQueue,
    lod3_gen_queue: *JobQueue,

    // Worker pools (shared across LOD levels for now)
    lod_gen_pool: ?*WorkerPool,

    // Upload queues per LOD level
    lod1_upload_queue: RingBuffer(*LODChunk),
    lod2_upload_queue: RingBuffer(*LODChunk),
    lod3_upload_queue: RingBuffer(*LODChunk),

    // Transition queue for LOD upgrades/downgrades
    transition_queue: std.ArrayList(LODTransition),

    // Current player position (chunk coords)
    player_cx: i32,
    player_cz: i32,

    // Next job token
    next_job_token: u32,

    // Stats
    stats: LODStats,

    // Mutex for thread safety
    mutex: std.Thread.Mutex,

    // RHI for GPU operations
    rhi: RHI,

    // Paused state
    paused: bool,

    pub fn init(allocator: std.mem.Allocator, config: LODConfig, rhi: RHI) !*LODManager {
        const mgr = try allocator.create(LODManager);

        // Create job queues for each LOD level
        const lod1_queue = try allocator.create(JobQueue);
        lod1_queue.* = JobQueue.init(allocator);

        const lod2_queue = try allocator.create(JobQueue);
        lod2_queue.* = JobQueue.init(allocator);

        const lod3_queue = try allocator.create(JobQueue);
        lod3_queue.* = JobQueue.init(allocator);

        mgr.* = .{
            .allocator = allocator,
            .config = config,
            .lod1_regions = std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80).init(allocator),
            .lod2_regions = std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80).init(allocator),
            .lod3_regions = std.HashMap(LODRegionKey, *LODChunk, LODRegionKeyContext, 80).init(allocator),
            .lod1_gen_queue = lod1_queue,
            .lod2_gen_queue = lod2_queue,
            .lod3_gen_queue = lod3_queue,
            .lod_gen_pool = null, // Will be initialized later
            .lod1_upload_queue = try RingBuffer(*LODChunk).init(allocator, 32),
            .lod2_upload_queue = try RingBuffer(*LODChunk).init(allocator, 32),
            .lod3_upload_queue = try RingBuffer(*LODChunk).init(allocator, 32),
            .transition_queue = std.ArrayList(LODTransition).init(allocator),
            .player_cx = 0,
            .player_cz = 0,
            .next_job_token = 1,
            .stats = .{},
            .mutex = .{},
            .rhi = rhi,
            .paused = false,
        };

        log.log.info("LODManager initialized with radii: LOD0={}, LOD1={}, LOD2={}, LOD3={}", .{
            config.lod0_radius,
            config.lod1_radius,
            config.lod2_radius,
            config.lod3_radius,
        });

        return mgr;
    }

    pub fn deinit(self: *LODManager) void {
        // Stop queues
        self.lod1_gen_queue.stop();
        self.lod2_gen_queue.stop();
        self.lod3_gen_queue.stop();

        // Cleanup worker pool
        if (self.lod_gen_pool) |pool| {
            pool.deinit();
        }

        // Cleanup queues
        self.lod1_gen_queue.deinit();
        self.lod2_gen_queue.deinit();
        self.lod3_gen_queue.deinit();
        self.allocator.destroy(self.lod1_gen_queue);
        self.allocator.destroy(self.lod2_gen_queue);
        self.allocator.destroy(self.lod3_gen_queue);

        // Cleanup upload queues
        self.lod1_upload_queue.deinit();
        self.lod2_upload_queue.deinit();
        self.lod3_upload_queue.deinit();

        // Cleanup regions
        var iter1 = self.lod1_regions.iterator();
        while (iter1.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.lod1_regions.deinit();

        var iter2 = self.lod2_regions.iterator();
        while (iter2.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.lod2_regions.deinit();

        var iter3 = self.lod3_regions.iterator();
        while (iter3.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.lod3_regions.deinit();

        self.transition_queue.deinit();
        self.allocator.destroy(self);
    }

    /// Update LOD system with player position
    pub fn update(self: *LODManager, player_pos: Vec3, player_velocity: Vec3) !void {
        if (self.paused) return;

        const pc = worldToChunk(@intFromFloat(player_pos.x), @intFromFloat(player_pos.z));
        const moved = pc.chunk_x != self.player_cx or pc.chunk_z != self.player_cz;

        if (moved) {
            self.player_cx = pc.chunk_x;
            self.player_cz = pc.chunk_z;

            // Queue LOD regions that need loading
            // Priority: LOD3 first (fast, fills horizon), then LOD2, LOD1
            try self.queueLODRegions(.lod3, player_velocity);
            try self.queueLODRegions(.lod2, player_velocity);
            try self.queueLODRegions(.lod1, player_velocity);
        }

        // Process state transitions
        try self.processStateTransitions();

        // Process uploads (limited per frame)
        self.processUploads();

        // Update stats
        self.updateStats();

        // Unload distant regions
        try self.unloadDistantRegions();
    }

    /// Queue LOD regions that need generation
    fn queueLODRegions(self: *LODManager, lod: LODLevel, velocity: Vec3) !void {
        const radius = switch (lod) {
            .lod0 => self.config.lod0_radius, // LOD0 handled by existing World
            .lod1 => self.config.lod1_radius,
            .lod2 => self.config.lod2_radius,
            .lod3 => self.config.lod3_radius,
        };

        // Skip LOD0 - handled by existing World system
        if (lod == .lod0) return;

        const scale: i32 = @intCast(lod.chunksPerSide());
        const region_radius = @divFloor(radius, scale) + 1;

        const player_rx = @divFloor(self.player_cx, scale);
        const player_rz = @divFloor(self.player_cz, scale);

        const storage = switch (lod) {
            .lod0 => unreachable,
            .lod1 => &self.lod1_regions,
            .lod2 => &self.lod2_regions,
            .lod3 => &self.lod3_regions,
        };

        const queue = switch (lod) {
            .lod0 => unreachable,
            .lod1 => self.lod1_gen_queue,
            .lod2 => self.lod2_gen_queue,
            .lod3 => self.lod3_gen_queue,
        };

        // Calculate velocity direction for priority
        const vel_len = @sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
        const has_velocity = vel_len > 0.1;
        const vel_dx: f32 = if (has_velocity) velocity.x / vel_len else 0;
        const vel_dz: f32 = if (has_velocity) velocity.z / vel_len else 0;

        var rz = player_rz - region_radius;
        while (rz <= player_rz + region_radius) : (rz += 1) {
            var rx = player_rx - region_radius;
            while (rx <= player_rx + region_radius) : (rx += 1) {
                const dx = rx - player_rx;
                const dz = rz - player_rz;
                const dist_sq = dx * dx + dz * dz;

                if (dist_sq > region_radius * region_radius) continue;

                const key = LODRegionKey{ .rx = rx, .rz = rz, .lod = lod };

                // Check if region exists
                if (storage.get(key) == null) {
                    // Create new LOD chunk
                    const chunk = try self.allocator.create(LODChunk);
                    chunk.* = LODChunk.init(rx, rz, lod);
                    chunk.job_token = self.next_job_token;
                    self.next_job_token += 1;

                    try storage.put(key, chunk);

                    // Calculate velocity-weighted priority
                    var priority = dist_sq;
                    if (has_velocity) {
                        const fdx: f32 = @floatFromInt(dx);
                        const fdz: f32 = @floatFromInt(dz);
                        const dist = @sqrt(fdx * fdx + fdz * fdz);
                        if (dist > 0.01) {
                            const dot = (fdx * vel_dx + fdz * vel_dz) / dist;
                            // Ahead = lower priority number, behind = higher
                            const weight = 1.0 - dot * 0.5;
                            priority = @intFromFloat(@as(f32, @floatFromInt(dist_sq)) * weight);
                        }
                    }

                    // Queue for generation
                    try queue.push(.{
                        .type = .generation,
                        .chunk_x = rx, // Using chunk coords for region coords
                        .chunk_z = rz,
                        .job_token = chunk.job_token,
                        .dist_sq = priority,
                    });
                    chunk.state = .queued_for_generation;
                }
            }
        }
    }

    /// Process state transitions (generated -> meshing -> ready)
    fn processStateTransitions(self: *LODManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check LOD1 regions
        var iter1 = self.lod1_regions.iterator();
        while (iter1.next()) |entry| {
            const chunk = entry.value_ptr.*;
            if (chunk.state == .generated) {
                chunk.state = .queued_for_mesh;
                // TODO: Queue for meshing
            } else if (chunk.state == .mesh_ready) {
                chunk.state = .uploading;
                try self.lod1_upload_queue.push(chunk);
            }
        }

        // Check LOD2 regions
        var iter2 = self.lod2_regions.iterator();
        while (iter2.next()) |entry| {
            const chunk = entry.value_ptr.*;
            if (chunk.state == .generated) {
                chunk.state = .queued_for_mesh;
            } else if (chunk.state == .mesh_ready) {
                chunk.state = .uploading;
                try self.lod2_upload_queue.push(chunk);
            }
        }

        // Check LOD3 regions
        var iter3 = self.lod3_regions.iterator();
        while (iter3.next()) |entry| {
            const chunk = entry.value_ptr.*;
            if (chunk.state == .generated) {
                chunk.state = .queued_for_mesh;
            } else if (chunk.state == .mesh_ready) {
                chunk.state = .uploading;
                try self.lod3_upload_queue.push(chunk);
            }
        }
    }

    /// Process GPU uploads (limited per frame)
    fn processUploads(self: *LODManager) void {
        const max_uploads = self.config.max_uploads_per_frame;
        var uploads: u32 = 0;

        // Process LOD3 first (furthest, should be ready first)
        while (!self.lod3_upload_queue.isEmpty() and uploads < max_uploads) {
            if (self.lod3_upload_queue.pop()) |chunk| {
                // TODO: Upload mesh to GPU
                chunk.state = .renderable;
                uploads += 1;
            }
        }

        // Then LOD2
        while (!self.lod2_upload_queue.isEmpty() and uploads < max_uploads) {
            if (self.lod2_upload_queue.pop()) |chunk| {
                chunk.state = .renderable;
                uploads += 1;
            }
        }

        // Then LOD1
        while (!self.lod1_upload_queue.isEmpty() and uploads < max_uploads) {
            if (self.lod1_upload_queue.pop()) |chunk| {
                chunk.state = .renderable;
                uploads += 1;
            }
        }
    }

    /// Unload regions that are too far from player
    fn unloadDistantRegions(self: *LODManager) !void {
        const unload_buffer: i32 = 2;

        // Unload LOD1
        try self.unloadDistantForLevel(.lod1, self.config.lod1_radius + unload_buffer);
        try self.unloadDistantForLevel(.lod2, self.config.lod2_radius + unload_buffer);
        try self.unloadDistantForLevel(.lod3, self.config.lod3_radius + unload_buffer);
    }

    fn unloadDistantForLevel(self: *LODManager, lod: LODLevel, max_radius: i32) !void {
        const storage = switch (lod) {
            .lod0 => return,
            .lod1 => &self.lod1_regions,
            .lod2 => &self.lod2_regions,
            .lod3 => &self.lod3_regions,
        };

        const scale: i32 = @intCast(lod.chunksPerSide());
        const player_rx = @divFloor(self.player_cx, scale);
        const player_rz = @divFloor(self.player_cz, scale);
        const region_radius = @divFloor(max_radius, scale);

        var to_remove = std.ArrayList(LODRegionKey).init(self.allocator);
        defer to_remove.deinit();

        self.mutex.lock();
        var iter = storage.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const chunk = entry.value_ptr.*;

            const dx = key.rx - player_rx;
            const dz = key.rz - player_rz;

            if (dx * dx + dz * dz > region_radius * region_radius) {
                if (!chunk.isPinned() and
                    chunk.state != .generating and
                    chunk.state != .meshing and
                    chunk.state != .uploading)
                {
                    try to_remove.append(key);
                }
            }
        }
        self.mutex.unlock();

        // Remove outside of iteration
        for (to_remove.items) |key| {
            if (storage.get(key)) |chunk| {
                chunk.deinit(self.allocator);
                self.allocator.destroy(chunk);
                _ = storage.remove(key);
            }
        }
    }

    /// Update statistics
    fn updateStats(self: *LODManager) void {
        self.stats = .{};

        self.mutex.lock();
        defer self.mutex.unlock();

        var iter1 = self.lod1_regions.iterator();
        while (iter1.next()) |entry| {
            if (entry.value_ptr.*.state == .renderable) {
                self.stats.lod1_loaded += 1;
            } else if (entry.value_ptr.*.state == .generating) {
                self.stats.lod1_generating += 1;
            }
        }

        var iter2 = self.lod2_regions.iterator();
        while (iter2.next()) |entry| {
            if (entry.value_ptr.*.state == .renderable) {
                self.stats.lod2_loaded += 1;
            } else if (entry.value_ptr.*.state == .generating) {
                self.stats.lod2_generating += 1;
            }
        }

        var iter3 = self.lod3_regions.iterator();
        while (iter3.next()) |entry| {
            if (entry.value_ptr.*.state == .renderable) {
                self.stats.lod3_loaded += 1;
            } else if (entry.value_ptr.*.state == .generating) {
                self.stats.lod3_generating += 1;
            }
        }
    }

    /// Get current statistics
    pub fn getStats(self: *LODManager) LODStats {
        return self.stats;
    }

    /// Pause all LOD generation
    pub fn pause(self: *LODManager) void {
        self.paused = true;
        self.lod1_gen_queue.setPaused(true);
        self.lod2_gen_queue.setPaused(true);
        self.lod3_gen_queue.setPaused(true);
    }

    /// Resume LOD generation
    pub fn resume(self: *LODManager) void {
        self.paused = false;
        self.lod1_gen_queue.setPaused(false);
        self.lod2_gen_queue.setPaused(false);
        self.lod3_gen_queue.setPaused(false);
    }

    /// Get LOD level for a given chunk distance
    pub fn getLODForDistance(self: *const LODManager, chunk_x: i32, chunk_z: i32) LODLevel {
        const dx = chunk_x - self.player_cx;
        const dz = chunk_z - self.player_cz;
        const dist = @max(@abs(dx), @abs(dz));
        return self.config.getLODForDistance(dist);
    }

    /// Check if a position is within LOD range
    pub fn isInRange(self: *const LODManager, chunk_x: i32, chunk_z: i32) bool {
        const dx = chunk_x - self.player_cx;
        const dz = chunk_z - self.player_cz;
        const dist = @max(@abs(dx), @abs(dz));
        return self.config.isInRange(dist);
    }
};

// Tests
test "LODManager initialization" {
    const allocator = std.testing.allocator;
    
    // We can't fully test without RHI, but we can test the config
    const config = LODConfig{
        .lod0_radius = 8,
        .lod1_radius = 16,
        .lod2_radius = 32,
        .lod3_radius = 64,
    };

    try std.testing.expectEqual(LODLevel.lod0, config.getLODForDistance(5));
    try std.testing.expectEqual(LODLevel.lod1, config.getLODForDistance(12));
    try std.testing.expectEqual(LODLevel.lod2, config.getLODForDistance(24));
    try std.testing.expectEqual(LODLevel.lod3, config.getLODForDistance(50));

    _ = allocator;
}
