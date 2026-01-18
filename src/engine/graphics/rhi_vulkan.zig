const std = @import("std");
const c = @import("../../c.zig").c;
const rhi = @import("rhi.zig");
const VulkanDevice = @import("vulkan_device.zig").VulkanDevice;
const VulkanSwapchain = @import("vulkan_swapchain.zig").VulkanSwapchain;
const RenderDevice = @import("render_device.zig").RenderDevice;
const Mat4 = @import("../math/mat4.zig").Mat4;
const Vec3 = @import("../math/vec3.zig").Vec3;
const build_options = @import("build_options");

const MAX_FRAMES_IN_FLIGHT = rhi.MAX_FRAMES_IN_FLIGHT;
const DEPTH_FORMAT = c.VK_FORMAT_D32_SFLOAT;

const GlobalUniforms = extern struct {
    view_proj: Mat4,
    cam_pos: [4]f32,
    sun_dir: [4]f32,
    sun_color: [4]f32,
    fog_color: [4]f32,
    cloud_wind_offset: [4]f32,
    params: [4]f32,
    lighting: [4]f32,
    cloud_params: [4]f32,
    pbr_params: [4]f32,
    volumetric_params: [4]f32,
    viewport_size: [4]f32,
};

const SSAOParams = extern struct {
    projection: Mat4,
    invProjection: Mat4,
    samples: [64][4]f32,
    radius: f32 = 0.5,
    bias: f32 = 0.025,
    _padding: [2]f32 = undefined,
};

const ShadowUniforms = extern struct {
    light_space_matrices: [rhi.SHADOW_CASCADE_COUNT]Mat4,
    cascade_splits: [4]f32,
    shadow_texel_sizes: [4]f32,
};

const ModelUniforms = extern struct {
    model: Mat4,
    color: [3]f32,
    mask_radius: f32,
};

const ShadowModelUniforms = extern struct {
    light_space_matrix: Mat4,
    model: Mat4,
};

const SkyPushConstants = extern struct {
    cam_forward: [4]f32,
    cam_right: [4]f32,
    cam_up: [4]f32,
    sun_dir: [4]f32,
    sky_color: [4]f32,
    horizon_color: [4]f32,
    params: [4]f32,
    time: [4]f32,
};

const VulkanBuffer = struct {
    buffer: c.VkBuffer = null,
    memory: c.VkDeviceMemory = null,
    size: c.VkDeviceSize = 0,
    is_host_visible: bool = false,
};

const TextureResource = struct {
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    view: c.VkImageView,
    sampler: c.VkSampler,
    width: u32,
    height: u32,
    format: rhi.TextureFormat,
    config: rhi.TextureConfig,
};

const ZombieBuffer = struct {
    buffer: c.VkBuffer,
    memory: c.VkDeviceMemory,
};

const ZombieImage = struct {
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    view: c.VkImageView,
    sampler: c.VkSampler,
};

const StagingBuffer = struct {
    buffer: c.VkBuffer,
    memory: c.VkDeviceMemory,
    size: u64,
    current_offset: u64,
    mapped_ptr: ?*anyopaque,

    fn init(ctx: *VulkanContext, size: u64) !StagingBuffer {
        const buf = try createVulkanBuffer(ctx, size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        if (buf.buffer == null) return error.VulkanError;

        var mapped: ?*anyopaque = null;
        try checkVk(c.vkMapMemory(ctx.vulkan_device.vk_device, buf.memory, 0, size, 0, &mapped));

        return StagingBuffer{
            .buffer = buf.buffer,
            .memory = buf.memory,
            .size = size,
            .current_offset = 0,
            .mapped_ptr = mapped,
        };
    }

    fn deinit(self: *StagingBuffer, device: c.VkDevice) void {
        if (self.mapped_ptr != null) {
            c.vkUnmapMemory(device, self.memory);
        }
        c.vkDestroyBuffer(device, self.buffer, null);
        c.vkFreeMemory(device, self.memory, null);
    }

    fn reset(self: *StagingBuffer) void {
        self.current_offset = 0;
    }

    fn allocate(self: *StagingBuffer, size: u64) ?u64 {
        const alignment = 256;
        const aligned_offset = std.mem.alignForward(u64, self.current_offset, alignment);

        if (aligned_offset + size > self.size) return null;

        self.current_offset = aligned_offset + size;
        return aligned_offset;
    }
};

const ShadowSystem = @import("shadow_system.zig").ShadowSystem;

const DebugShadowResources = if (build_options.debug_shadows) struct {
    pipeline: ?c.VkPipeline = null,
    pipeline_layout: ?c.VkPipelineLayout = null,
    descriptor_set_layout: ?c.VkDescriptorSetLayout = null,
    descriptor_sets: [MAX_FRAMES_IN_FLIGHT]?c.VkDescriptorSet = .{null} ** MAX_FRAMES_IN_FLIGHT,
    descriptor_pool: [MAX_FRAMES_IN_FLIGHT][8]?c.VkDescriptorSet = .{.{null} ** 8} ** MAX_FRAMES_IN_FLIGHT,
    descriptor_next: [MAX_FRAMES_IN_FLIGHT]u32 = .{0} ** MAX_FRAMES_IN_FLIGHT,
    vbo: VulkanBuffer = .{ .buffer = null, .memory = null, .size = 0, .is_host_visible = false },
} else struct {};

fn checkVk(result: c.VkResult) !void {
    switch (result) {
        c.VK_SUCCESS => return,
        c.VK_ERROR_DEVICE_LOST => return error.GpuLost,
        c.VK_ERROR_OUT_OF_HOST_MEMORY, c.VK_ERROR_OUT_OF_DEVICE_MEMORY => return error.OutOfMemory,
        c.VK_ERROR_SURFACE_LOST_KHR => return error.SurfaceLost,
        c.VK_ERROR_INITIALIZATION_FAILED => return error.InitializationFailed,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => return error.ExtensionNotPresent,
        c.VK_ERROR_FEATURE_NOT_PRESENT => return error.FeatureNotPresent,
        c.VK_ERROR_TOO_MANY_OBJECTS => return error.TooManyObjects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => return error.FormatNotSupported,
        c.VK_ERROR_FRAGMENTED_POOL => return error.FragmentedPool,
        else => return error.Unknown,
    }
}

fn createShaderModule(device: c.VkDevice, code: []const u8) !c.VkShaderModule {
    var create_info = std.mem.zeroes(c.VkShaderModuleCreateInfo);
    create_info.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    create_info.codeSize = code.len;
    create_info.pCode = @ptrCast(@alignCast(code.ptr));

    var shader_module: c.VkShaderModule = null;
    try checkVk(c.vkCreateShaderModule(device, &create_info, null, &shader_module));
    return shader_module;
}

fn findMemoryType(physical_device: c.VkPhysicalDevice, type_filter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
    var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);

    var i: u32 = 0;
    while (i < mem_properties.memoryTypeCount) : (i += 1) {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return i;
        }
    }
    return error.NoMatchingMemoryType;
}

fn getMSAASampleCountFlag(samples: u8) c.VkSampleCountFlagBits {
    return switch (samples) {
        2 => c.VK_SAMPLE_COUNT_2_BIT,
        4 => c.VK_SAMPLE_COUNT_4_BIT,
        8 => c.VK_SAMPLE_COUNT_8_BIT,
        else => c.VK_SAMPLE_COUNT_1_BIT,
    };
}

fn createVulkanBuffer(ctx: *VulkanContext, size: usize, usage: c.VkBufferUsageFlags, properties: c.VkMemoryPropertyFlags) !VulkanBuffer {
    var buffer_info = std.mem.zeroes(c.VkBufferCreateInfo);
    buffer_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = @intCast(size);
    buffer_info.usage = usage;
    buffer_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    var buffer: c.VkBuffer = null;
    try checkVk(c.vkCreateBuffer(ctx.vulkan_device.vk_device, &buffer_info, null, &buffer));

    var mem_reqs: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(ctx.vulkan_device.vk_device, buffer, &mem_reqs);

    var alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = try findMemoryType(ctx.vulkan_device.physical_device, mem_reqs.memoryTypeBits, properties);

    var memory: c.VkDeviceMemory = null;
    try checkVk(c.vkAllocateMemory(ctx.vulkan_device.vk_device, &alloc_info, null, &memory));
    try checkVk(c.vkBindBufferMemory(ctx.vulkan_device.vk_device, buffer, memory, 0));

    return .{
        .buffer = buffer,
        .memory = memory,
        .size = mem_reqs.size,
        .is_host_visible = (properties & c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0,
    };
}

pub const VulkanResourceManager = struct {
    allocator: std.mem.Allocator,
    vulkan_device: *VulkanDevice,
    buffers: std.AutoHashMap(rhi.BufferHandle, VulkanBuffer),
    next_buffer_handle: rhi.BufferHandle,
    textures: std.AutoHashMap(rhi.TextureHandle, TextureResource),
    next_texture_handle: rhi.TextureHandle,
    staging_buffers: [MAX_FRAMES_IN_FLIGHT]StagingBuffer,
    transfer_command_pool: c.VkCommandPool,
    transfer_command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer,
    buffer_deletion_queue: [MAX_FRAMES_IN_FLIGHT]std.ArrayListUnmanaged(ZombieBuffer),
    image_deletion_queue: [MAX_FRAMES_IN_FLIGHT]std.ArrayListUnmanaged(ZombieImage),

    pub fn init(allocator: std.mem.Allocator, vulkan_device: *VulkanDevice) !VulkanResourceManager {
        var self = VulkanResourceManager{
            .allocator = allocator,
            .vulkan_device = vulkan_device,
            .buffers = std.AutoHashMap(rhi.BufferHandle, VulkanBuffer).init(allocator),
            .next_buffer_handle = 1,
            .textures = std.AutoHashMap(rhi.TextureHandle, TextureResource).init(allocator),
            .next_texture_handle = 1,
            .staging_buffers = undefined,
            .transfer_command_pool = null,
            .transfer_command_buffers = .{null} ** MAX_FRAMES_IN_FLIGHT,
            .buffer_deletion_queue = undefined,
            .image_deletion_queue = undefined,
        };

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            self.buffer_deletion_queue[i] = std.ArrayListUnmanaged(ZombieBuffer){};
            self.image_deletion_queue[i] = std.ArrayListUnmanaged(ZombieImage){};
            self.staging_buffers[i] = try StagingBuffer.init(&VulkanContext{}, 16 * 1024 * 1024);
        }

        const pool_info = std.mem.zeroes(c.VkCommandPoolCreateInfo);
        pool_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        pool_info.queueFamilyIndex = vulkan_device.queue_family_index;
        pool_info.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        try checkVk(c.vkCreateCommandPool(vulkan_device.vk_device, &pool_info, null, &self.transfer_command_pool));

        const cmd_alloc_info = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cmd_alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cmd_alloc_info.commandPool = self.transfer_command_pool;
        cmd_alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cmd_alloc_info.commandBufferCount = MAX_FRAMES_IN_FLIGHT;
        try checkVk(c.vkAllocateCommandBuffers(vulkan_device.vk_device, &cmd_alloc_info, &self.transfer_command_buffers));

        return self;
    }

    pub fn deinit(self: *VulkanResourceManager, ctx: *VulkanContext) void {
        self.processDeletionQueues(ctx, 0);
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            self.buffer_deletion_queue[i].deinit(self.allocator);
            self.image_deletion_queue[i].deinit(self.allocator);
            self.staging_buffers[i].deinit(ctx.vulkan_device.vk_device);
        }
        if (self.transfer_command_pool != null) {
            c.vkDestroyCommandPool(ctx.vulkan_device.vk_device, self.transfer_command_pool, null);
        }
        self.buffers.deinit();
        self.textures.deinit();
    }

    pub fn createBuffer(self: *VulkanResourceManager, ctx: *VulkanContext, size: usize, usage: rhi.BufferUsage) rhi.BufferHandle {
        const handle = self.next_buffer_handle;
        self.next_buffer_handle += 1;

        const vk_usage = switch (usage) {
            .vertex => c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .index => c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            .uniform => c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .indirect => c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT,
            .storage => c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        };

        const is_host_visible = usage == .uniform or usage == .vertex or usage == .index;
        const properties = if (is_host_visible)
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
        else
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;

        const buffer = createVulkanBuffer(ctx, size, vk_usage, properties) catch return rhi.InvalidBufferHandle;
        self.buffers.put(handle, buffer) catch return rhi.InvalidBufferHandle;
        return handle;
    }

    pub fn uploadBuffer(self: *VulkanResourceManager, ctx: *VulkanContext, handle: rhi.BufferHandle, data: []const u8, frame_index: usize) void {
        const buffer = self.buffers.get(handle) orelse return;
        if (!buffer.is_host_visible) return;

        var mapped: ?*anyopaque = null;
        _ = c.vkMapMemory(ctx.vulkan_device.vk_device, buffer.memory, 0, data.len, 0, &mapped);
        @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..data.len], data);
        c.vkUnmapMemory(ctx.vulkan_device.vk_device, buffer.memory);
    }

    pub fn updateBuffer(self: *VulkanResourceManager, ctx: *VulkanContext, handle: rhi.BufferHandle, offset: usize, data: []const u8, frame_index: usize) void {
        const buffer = self.buffers.get(handle) orelse return;
        if (!buffer.is_host_visible) return;

        var mapped: ?*anyopaque = null;
        _ = c.vkMapMemory(ctx.vulkan_device.vk_device, buffer.memory, offset, data.len, 0, &mapped);
        @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..data.len], data);
        c.vkUnmapMemory(ctx.vulkan_device.vk_device, buffer.memory);
    }

    pub fn destroyBuffer(self: *VulkanResourceManager, ctx: *VulkanContext, handle: rhi.BufferHandle, frame_index: usize) void {
        const existing = self.buffers.remove(handle) orelse return;
        self.buffer_deletion_queue[frame_index].append(self.allocator, .{ .buffer = existing.buffer, .memory = existing.memory }) catch {};
    }

    pub fn createTexture(self: *VulkanResourceManager, ctx: *VulkanContext, width: u32, height: u32, format: rhi.TextureFormat, config: rhi.TextureConfig, data: ?[]const u8) rhi.TextureHandle {
        _ = config;
        const handle = self.next_texture_handle;
        self.next_texture_handle += 1;

        const vk_format = switch (format) {
            .rgb => c.VK_FORMAT_R8G8B8_UNORM,
            .rgba => c.VK_FORMAT_R8G8B8A8_UNORM,
            .rgba_srgb => c.VK_FORMAT_R8G8B8A8_SRGB,
            .red => c.VK_FORMAT_R8_UNORM,
            .depth => c.VK_FORMAT_D32_SFLOAT,
            .rgba32f => c.VK_FORMAT_R32G32B32A32_SFLOAT,
        };

        var image_info = std.mem.zeroes(c.VkImageCreateInfo);
        image_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
        image_info.imageType = c.VK_IMAGE_TYPE_2D;
        image_info.extent = .{ .width = width, .height = height, .depth = 1 };
        image_info.mipLevels = 1;
        image_info.arrayLayers = 1;
        image_info.format = vk_format;
        image_info.tiling = c.VK_IMAGE_TILING_OPTIMAL;
        image_info.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
        image_info.usage = c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        image_info.samples = c.VK_SAMPLE_COUNT_1_BIT;
        image_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

        var image: c.VkImage = null;
        try checkVk(c.vkCreateImage(ctx.vulkan_device.vk_device, &image_info, null, &image));

        var mem_reqs: c.VkMemoryRequirements = undefined;
        c.vkGetImageMemoryRequirements(ctx.vulkan_device.vk_device, image, &mem_reqs);

        var alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
        alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        alloc_info.allocationSize = mem_reqs.size;
        alloc_info.memoryTypeIndex = findMemoryType(ctx.vulkan_device.physical_device, mem_reqs.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) catch return rhi.InvalidTextureHandle;

        var memory: c.VkDeviceMemory = null;
        try checkVk(c.vkAllocateMemory(ctx.vulkan_device.vk_device, &alloc_info, null, &memory));
        try checkVk(c.vkBindImageMemory(ctx.vulkan_device.vk_device, image, memory, 0));

        var view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
        view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view_info.image = image;
        view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        view_info.format = vk_format;
        view_info.subresourceRange = .{ .aspectMask = if (format == .depth) c.VK_IMAGE_ASPECT_DEPTH_BIT else c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };

        var view: c.VkImageView = null;
        try checkVk(c.vkCreateImageView(ctx.vulkan_device.vk_device, &view_info, null, &view));

        var sampler_info = std.mem.zeroes(c.VkSamplerCreateInfo);
        sampler_info.sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        sampler_info.magFilter = c.VK_FILTER_LINEAR;
        sampler_info.minFilter = c.VK_FILTER_LINEAR;
        sampler_info.addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sampler_info.addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        sampler_info.addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;

        var sampler: c.VkSampler = null;
        _ = c.vkCreateSampler(ctx.vulkan_device.vk_device, &sampler_info, null, &sampler);

        const resource = TextureResource{
            .image = image,
            .memory = memory,
            .view = view,
            .sampler = sampler,
            .width = width,
            .height = height,
            .format = format,
            .config = config,
        };

        self.textures.put(handle, resource) catch return rhi.InvalidTextureHandle;
        return handle;
    }

    pub fn destroyTexture(self: *VulkanResourceManager, ctx: *VulkanContext, handle: rhi.TextureHandle, frame_index: usize) void {
        const existing = self.textures.remove(handle) orelse return;
        self.image_deletion_queue[frame_index].append(self.allocator, .{ .image = existing.image, .memory = existing.memory, .view = existing.view, .sampler = existing.sampler }) catch {};
    }

    pub fn processDeletionQueues(self: *VulkanResourceManager, ctx: *VulkanContext, frame_index: usize) void {
        const vk = ctx.vulkan_device.vk_device;
        for (self.buffer_deletion_queue[frame_index].items) |zombie| {
            c.vkDestroyBuffer(vk, zombie.buffer, null);
            c.vkFreeMemory(vk, zombie.memory, null);
        }
        self.buffer_deletion_queue[frame_index].clearRetainingCapacity();

        for (self.image_deletion_queue[frame_index].items) |zombie| {
            c.vkDestroyImageView(vk, zombie.view, null);
            c.vkDestroyImage(vk, zombie.image, null);
            c.vkFreeMemory(vk, zombie.memory, null);
            if (zombie.sampler != null) c.vkDestroySampler(vk, zombie.sampler, null);
        }
        self.image_deletion_queue[frame_index].clearRetainingCapacity();
    }
};

pub const VulkanRenderCommandQueue = struct {
    allocator: std.mem.Allocator,
    vulkan_device: *VulkanDevice,
    command_pool: c.VkCommandPool,
    command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer,
    frame_index: usize,
    frame_in_progress: bool,
    image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore,
    render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence,

    pub fn init(allocator: std.mem.Allocator, vulkan_device: *VulkanDevice) !VulkanRenderCommandQueue {
        var self = VulkanRenderCommandQueue{
            .allocator = allocator,
            .vulkan_device = vulkan_device,
            .command_pool = null,
            .command_buffers = .{null} ** MAX_FRAMES_IN_FLIGHT,
            .frame_index = 0,
            .frame_in_progress = false,
            .image_available_semaphores = .{null} ** MAX_FRAMES_IN_FLIGHT,
            .render_finished_semaphores = .{null} ** MAX_FRAMES_IN_FLIGHT,
            .in_flight_fences = .{null} ** MAX_FRAMES_IN_FLIGHT,
        };

        const pool_info = std.mem.zeroes(c.VkCommandPoolCreateInfo);
        pool_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        pool_info.queueFamilyIndex = vulkan_device.queue_family_index;
        pool_info.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        try checkVk(c.vkCreateCommandPool(vulkan_device.vk_device, &pool_info, null, &self.command_pool));

        const cmd_alloc_info = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cmd_alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cmd_alloc_info.commandPool = self.command_pool;
        cmd_alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cmd_alloc_info.commandBufferCount = MAX_FRAMES_IN_FLIGHT;
        try checkVk(c.vkAllocateCommandBuffers(vulkan_device.vk_device, &cmd_alloc_info, &self.command_buffers));

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            const semaphore_info = std.mem.zeroes(c.VkSemaphoreCreateInfo);
            semaphore_info.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
            try checkVk(c.vkCreateSemaphore(vulkan_device.vk_device, &semaphore_info, null, &self.image_available_semaphores[i]));
            try checkVk(c.vkCreateSemaphore(vulkan_device.vk_device, &semaphore_info, null, &self.render_finished_semaphores[i]));

            const fence_info = std.mem.zeroes(c.VkFenceCreateInfo);
            fence_info.sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
            fence_info.flags = c.VK_FENCE_CREATE_SIGNALED_BIT;
            try checkVk(c.vkCreateFence(vulkan_device.vk_device, &fence_info, null, &self.in_flight_fences[i]));
        }

        return self;
    }

    pub fn deinit(self: *VulkanRenderCommandQueue, ctx: *VulkanContext) void {
        const vk = ctx.vulkan_device.vk_device;
        _ = vkDeviceWaitIdle(vk);

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (self.image_available_semaphores[i] != null) c.vkDestroySemaphore(vk, self.image_available_semaphores[i], null);
            if (self.render_finished_semaphores[i] != null) c.vkDestroySemaphore(vk, self.render_finished_semaphores[i], null);
            if (self.in_flight_fences[i] != null) c.vkDestroyFence(vk, self.in_flight_fences[i], null);
        }

        if (self.command_pool != null) {
            c.vkDestroyCommandPool(vk, self.command_pool, null);
        }
    }

    pub fn beginFrame(self: *VulkanRenderCommandQueue, ctx: *VulkanContext, image_index: u32) !void {
        _ = ctx;
        self.frame_in_progress = true;

        _ = c.vkWaitForFences(ctx.vulkan_device.vk_device, 1, &self.in_flight_fences[self.frame_index], c.VK_TRUE, std.math.maxInt(u64));

        const result = c.vkAcquireNextImageKHR(
            ctx.vulkan_device.vk_device,
            ctx.vulkan_swapchain.handle,
            std.math.maxInt(u64),
            self.image_available_semaphores[self.frame_index],
            null,
        );

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            try ctx.vulkan_swapchain.recreate(ctx.msaa_samples);
            return error.SurfaceLost;
        }
        try checkVk(result);

        _ = c.vkResetFences(ctx.vulkan_device.vk_device, 1, &self.in_flight_fences[self.frame_index]);

        const cmd = self.command_buffers[self.frame_index];
        const begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        try checkVk(c.vkBeginCommandBuffer(cmd, &begin_info));
    }

    pub fn endFrame(self: *VulkanRenderCommandQueue, ctx: *VulkanContext, image_index: u32) !void {
        const cmd = self.command_buffers[self.frame_index];
        try checkVk(c.vkEndCommandBuffer(cmd));

        const wait_semaphores = [_]c.VkSemaphore{ self.image_available_semaphores[self.frame_index] };
        const wait_stages = [_]c.VkPipelineStageFlags{ c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
        const signal_semaphores = [_]c.VkSemaphore{ self.render_finished_semaphores[self.frame_index] };

        var submit_info = std.mem.zeroes(c.VkSubmitInfo);
        submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit_info.waitSemaphoreCount = 1;
        submit_info.pWaitSemaphores = &wait_semaphores;
        submit_info.pWaitDstStageMask = &wait_stages;
        submit_info.commandBufferCount = 1;
        submit_info.pCommandBuffers = &cmd;
        submit_info.signalSemaphoreCount = 1;
        submit_info.pSignalSemaphores = &signal_semaphores;

        try ctx.vulkan_device.submitGuarded(submit_info, self.in_flight_fences[self.frame_index]);

        const present_info = std.mem.zeroes(c.VkPresentInfoKHR);
        present_info.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present_info.waitSemaphoreCount = 1;
        present_info.pWaitSemaphores = &signal_semaphores;
        present_info.swapchainCount = 1;
        present_info.pSwapchains = &ctx.vulkan_swapchain.handle;
        present_info.pImageIndices = &image_index;

        const present_result = c.vkQueuePresentKHR(ctx.vulkan_device.queue, &present_info);

        if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
            ctx.framebuffer_resized = true;
        }
        try checkVk(present_result);

        self.frame_index = (self.frame_index + 1) % MAX_FRAMES_IN_FLIGHT;
        self.frame_in_progress = false;
    }

    pub fn getFrameIndex(self: *VulkanRenderCommandQueue) usize {
        return self.frame_index;
    }
};

pub const VulkanSwapchainPresenter = struct {
    allocator: std.mem.Allocator,
    vulkan_device: *VulkanDevice,
    window: *c.SDL_Window,
    swapchain: VulkanSwapchain,
    vsync_enabled: bool,
    present_mode: c.VkPresentModeKHR,
    framebuffer_resized: bool,

    pub fn init(allocator: std.mem.Allocator, vulkan_device: *VulkanDevice, window: *c.SDL_Window, msaa_samples: u8) !VulkanSwapchainPresenter {
        var self = VulkanSwapchainPresenter{
            .allocator = allocator,
            .vulkan_device = vulkan_device,
            .window = window,
            .swapchain = try VulkanSwapchain.init(allocator, vulkan_device, window, msaa_samples),
            .vsync_enabled = true,
            .present_mode = c.VK_PRESENT_MODE_FIFO_KHR,
            .framebuffer_resized = false,
        };
        return self;
    }

    pub fn deinit(self: *VulkanSwapchainPresenter) void {
        self.swapchain.deinit();
    }

    pub fn setVSync(self: *VulkanSwapchainPresenter, enabled: bool) void {
        self.vsync_enabled = enabled;
        self.present_mode = if (enabled) c.VK_PRESENT_MODE_FIFO_KHR else c.VK_PRESENT_MODE_IMMEDIATE_KHR;
    }

    pub fn getVSync(self: *VulkanSwapchainPresenter) bool {
        return self.vsync_enabled;
    }

    pub fn recreate(self: *VulkanSwapchainPresenter, msaa_samples: u8) !void {
        try self.swapchain.recreate(msaa_samples);
    }
};

const VulkanContext = struct {
    allocator: std.mem.Allocator,
    window: *c.SDL_Window,
    render_device: ?*RenderDevice,
    vulkan_device: VulkanDevice,
    vulkan_swapchain: VulkanSwapchain,

    resource_manager: VulkanResourceManager,
    command_queue: VulkanRenderCommandQueue,
    presenter: VulkanSwapchainPresenter,

    command_pool: c.VkCommandPool,
    command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer,
    transfer_ready: bool,
    image_index: u32,
    frame_index: usize,

    global_ubos: [MAX_FRAMES_IN_FLIGHT]VulkanBuffer,
    global_ubos_mapped: [MAX_FRAMES_IN_FLIGHT]?*anyopaque,
    model_ubo: VulkanBuffer,
    dummy_instance_buffer: VulkanBuffer,
    shadow_ubos: [MAX_FRAMES_IN_FLIGHT]VulkanBuffer,
    shadow_ubos_mapped: [MAX_FRAMES_IN_FLIGHT]?*anyopaque,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet,
    lod_descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet,
    transfer_fence: c.VkFence = null,

    pipeline_layout: c.VkPipelineLayout,
    pipeline: c.VkPipeline,
    sky_pipeline: c.VkPipeline,
    sky_pipeline_layout: c.VkPipelineLayout,

    wireframe_enabled: bool,
    textures_enabled: bool,
    wireframe_pipeline: c.VkPipeline,
    anisotropic_filtering: u8,
    msaa_samples: u8,
    safe_mode: bool,

    g_normal_image: c.VkImage = null,
    g_normal_memory: c.VkDeviceMemory = null,
    g_normal_view: c.VkImageView = null,
    g_normal_handle: rhi.TextureHandle = 0,
    g_depth_image: c.VkImage = null,
    g_depth_memory: c.VkDeviceMemory = null,
    g_depth_view: c.VkImageView = null,
    ssao_image: c.VkImage = null,
    ssao_memory: c.VkDeviceMemory = null,
    ssao_view: c.VkImageView = null,
    ssao_handle: rhi.TextureHandle = 0,
    ssao_blur_image: c.VkImage = null,
    ssao_blur_memory: c.VkDeviceMemory = null,
    ssao_blur_view: c.VkImageView = null,
    ssao_blur_handle: rhi.TextureHandle = 0,
    ssao_noise_image: c.VkImage = null,
    ssao_noise_memory: c.VkDeviceMemory = null,
    ssao_noise_view: c.VkImageView = null,
    ssao_noise_handle: rhi.TextureHandle = 0,
    ssao_kernel_ubo: VulkanBuffer = .{},
    ssao_params: SSAOParams = undefined,
    ssao_sampler: c.VkSampler = null,

    g_render_pass: c.VkRenderPass = null,
    ssao_render_pass: c.VkRenderPass = null,
    ssao_blur_render_pass: c.VkRenderPass = null,
    g_framebuffer: c.VkFramebuffer = null,
    ssao_framebuffer: c.VkFramebuffer = null,
    ssao_blur_framebuffer: c.VkFramebuffer = null,
    g_pass_extent: c.VkExtent2D = .{ .width = 0, .height = 0 },

    g_pipeline: c.VkPipeline = null,
    g_pipeline_layout: c.VkPipelineLayout = null,
    ssao_pipeline: c.VkPipeline = null,
    gpu_fault_detected: bool = false,
    ssao_pipeline_layout: c.VkPipelineLayout = null,
    ssao_blur_pipeline: c.VkPipeline = null,
    ssao_blur_pipeline_layout: c.VkPipelineLayout = null,
    ssao_descriptor_set_layout: c.VkDescriptorSetLayout = null,
    ssao_descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = .{null} ** MAX_FRAMES_IN_FLIGHT,
    ssao_blur_descriptor_set_layout: c.VkDescriptorSetLayout = null,
    ssao_blur_descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = .{null} ** MAX_FRAMES_IN_FLIGHT,

    shadow_system: ShadowSystem,
    shadow_resolution: u32,
    memory_type_index: u32,
    draw_call_count: u32,
    main_pass_active: bool = false,
    g_pass_active: bool = false,
    ssao_pass_active: bool = false,
    terrain_pipeline_bound: bool,
    descriptors_updated: bool,
    lod_mode: bool = false,
    bound_instance_buffer: [MAX_FRAMES_IN_FLIGHT]rhi.BufferHandle = .{ 0, 0 },
    bound_lod_instance_buffer: [MAX_FRAMES_IN_FLIGHT]rhi.BufferHandle = .{ 0, 0 },
    pending_instance_buffer: rhi.BufferHandle = 0,
    pending_lod_instance_buffer: rhi.BufferHandle = 0,
    current_view_proj: Mat4,
    current_model: Mat4,
    current_color: [3]f32,
    current_mask_radius: f32,
    mutex: std.Thread.Mutex,
    clear_color: [4]f32,

    ui_pipeline: c.VkPipeline,
    ui_pipeline_layout: c.VkPipelineLayout,
    ui_tex_pipeline: c.VkPipeline,
    ui_tex_pipeline_layout: c.VkPipelineLayout,
    ui_tex_descriptor_set_layout: c.VkDescriptorSetLayout,
    ui_tex_descriptor_sets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet,
    ui_tex_descriptor_pool: [MAX_FRAMES_IN_FLIGHT][64]c.VkDescriptorSet,
    ui_tex_descriptor_next: [MAX_FRAMES_IN_FLIGHT]u32,
    ui_vbos: [MAX_FRAMES_IN_FLIGHT]VulkanBuffer,
    ui_screen_width: f32,
    ui_screen_height: f32,
    ui_in_progress: bool,
    ui_vertex_offset: u64,
    ui_flushed_vertex_count: u32,
    ui_mapped_ptr: ?*anyopaque,

    cloud_pipeline: c.VkPipeline,
    cloud_pipeline_layout: c.VkPipelineLayout,
    cloud_vbo: VulkanBuffer,
    cloud_ebo: VulkanBuffer,
    cloud_mesh_size: f32,
    cloud_vao: c.VkBuffer,

    debug_shadow: DebugShadowResources = .{},
};

fn destroyGPassResources(ctx: *VulkanContext) void {
    const vk = ctx.vulkan_device.vk_device;
    if (ctx.g_pipeline != null) c.vkDestroyPipeline(vk, ctx.g_pipeline, null);
    if (ctx.g_pipeline_layout != null) c.vkDestroyPipelineLayout(vk, ctx.g_pipeline_layout, null);
    if (ctx.g_framebuffer != null) c.vkDestroyFramebuffer(vk, ctx.g_framebuffer, null);
    if (ctx.g_render_pass != null) c.vkDestroyRenderPass(vk, ctx.g_render_pass, null);
    if (ctx.g_normal_view != null) c.vkDestroyImageView(vk, ctx.g_normal_view, null);
    if (ctx.g_normal_image != null) c.vkDestroyImage(vk, ctx.g_normal_image, null);
    if (ctx.g_normal_memory != null) c.vkFreeMemory(vk, ctx.g_normal_memory, null);
    if (ctx.g_depth_view != null) c.vkDestroyImageView(vk, ctx.g_depth_view, null);
    if (ctx.g_depth_image != null) c.vkDestroyImage(vk, ctx.g_depth_image, null);
    if (ctx.g_depth_memory != null) c.vkFreeMemory(vk, ctx.g_depth_memory, null);
    ctx.g_pipeline = null;
    ctx.g_pipeline_layout = null;
    ctx.g_framebuffer = null;
    ctx.g_render_pass = null;
    ctx.g_normal_view = null;
    ctx.g_normal_image = null;
    ctx.g_normal_memory = null;
    ctx.g_depth_view = null;
    ctx.g_depth_image = null;
    ctx.g_depth_memory = null;
}

fn destroySSAOResources(ctx: *VulkanContext) void {
    const vk = ctx.vulkan_device.vk_device;
    if (vk == null) return;

    if (ctx.ssao_pipeline != null) c.vkDestroyPipeline(vk, ctx.ssao_pipeline, null);
    if (ctx.ssao_blur_pipeline != null) c.vkDestroyPipeline(vk, ctx.ssao_blur_pipeline, null);
    if (ctx.ssao_pipeline_layout != null) c.vkDestroyPipelineLayout(vk, ctx.ssao_pipeline_layout, null);
    if (ctx.ssao_blur_pipeline_layout != null) c.vkDestroyPipelineLayout(vk, ctx.ssao_blur_pipeline_layout, null);

    if (ctx.descriptor_pool != null) {
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (ctx.ssao_descriptor_sets[i] != null) {
                _ = c.vkFreeDescriptorSets(vk, ctx.descriptor_pool, 1, &ctx.ssao_descriptor_sets[i]);
                ctx.ssao_descriptor_sets[i] = null;
            }
            if (ctx.ssao_blur_descriptor_sets[i] != null) {
                _ = c.vkFreeDescriptorSets(vk, ctx.descriptor_pool, 1, &ctx.ssao_blur_descriptor_sets[i]);
                ctx.ssao_blur_descriptor_sets[i] = null;
            }
        }
    }

    if (ctx.ssao_descriptor_set_layout != null) c.vkDestroyDescriptorSetLayout(vk, ctx.ssao_descriptor_set_layout, null);
    if (ctx.ssao_blur_descriptor_set_layout != null) c.vkDestroyDescriptorSetLayout(vk, ctx.ssao_blur_descriptor_set_layout, null);
    if (ctx.ssao_framebuffer != null) c.vkDestroyFramebuffer(vk, ctx.ssao_framebuffer, null);
    if (ctx.ssao_blur_framebuffer != null) c.vkDestroyFramebuffer(vk, ctx.ssao_blur_framebuffer, null);
    if (ctx.ssao_render_pass != null) c.vkDestroyRenderPass(vk, ctx.ssao_render_pass, null);
    if (ctx.ssao_blur_render_pass != null) c.vkDestroyRenderPass(vk, ctx.ssao_blur_render_pass, null);
    if (ctx.ssao_view != null) c.vkDestroyImageView(vk, ctx.ssao_view, null);
    if (ctx.ssao_image != null) c.vkDestroyImage(vk, ctx.ssao_image, null);
    if (ctx.ssao_memory != null) c.vkFreeMemory(vk, ctx.ssao_memory, null);
    if (ctx.ssao_blur_view != null) c.vkDestroyImageView(vk, ctx.ssao_blur_view, null);
    if (ctx.ssao_blur_image != null) c.vkDestroyImage(vk, ctx.ssao_blur_image, null);
    if (ctx.ssao_blur_memory != null) c.vkFreeMemory(vk, ctx.ssao_blur_memory, null);
    if (ctx.ssao_noise_view != null) c.vkDestroyImageView(vk, ctx.ssao_noise_view, null);
    if (ctx.ssao_noise_image != null) c.vkDestroyImage(vk, ctx.ssao_noise_image, null);
    if (ctx.ssao_noise_memory != null) c.vkFreeMemory(vk, ctx.ssao_noise_memory, null);
    if (ctx.ssao_kernel_ubo.buffer != null) c.vkDestroyBuffer(vk, ctx.ssao_kernel_ubo.buffer, null);
    if (ctx.ssao_kernel_ubo.memory != null) c.vkFreeMemory(vk, ctx.ssao_kernel_ubo.memory, null);
    if (ctx.ssao_sampler != null) c.vkDestroySampler(vk, ctx.ssao_sampler, null);
    ctx.ssao_pipeline = null;
    ctx.ssao_blur_pipeline = null;
    ctx.ssao_pipeline_layout = null;
    ctx.ssao_blur_pipeline_layout = null;
    ctx.ssao_descriptor_set_layout = null;
    ctx.ssao_blur_descriptor_set_layout = null;
    ctx.ssao_framebuffer = null;
    ctx.ssao_blur_framebuffer = null;
    ctx.ssao_render_pass = null;
    ctx.ssao_blur_render_pass = null;
    ctx.ssao_view = null;
    ctx.ssao_image = null;
    ctx.ssao_memory = null;
    ctx.ssao_blur_view = null;
    ctx.ssao_blur_image = null;
    ctx.ssao_blur_memory = null;
    ctx.ssao_noise_view = null;
    ctx.ssao_noise_image = null;
    ctx.ssao_noise_memory = null;
    ctx.ssao_kernel_ubo = .{};
    ctx.ssao_sampler = null;
}

pub fn createRHI(allocator: std.mem.Allocator, window: *c.SDL_Window, device: ?*RenderDevice) !rhi.RHI {
    var ctx = try allocator.create(VulkanContext);
    ctx.* = undefined;

    ctx.allocator = allocator;
    ctx.window = window;
    ctx.render_device = device;

    ctx.vulkan_device = try VulkanDevice.init(window, allocator);
    ctx.vulkan_swapchain = try VulkanSwapchain.init(allocator, &ctx.vulkan_device, window, 4);

    ctx.resource_manager = try VulkanResourceManager.init(allocator, &ctx.vulkan_device);
    ctx.command_queue = try VulkanRenderCommandQueue.init(allocator, &ctx.vulkan_device);
    ctx.presenter = try VulkanSwapchainPresenter.init(allocator, &ctx.vulkan_device, window, 4);

    return rhi.RHI{
        .ptr = ctx,
        .vtable = &vtable,
        .device = device,
        .subsystems = &ctx.resource_manager, // Temporary - will be updated with full subsystems struct
    };
}

const vtable = rhi.RHI.VTable{
    .init = initRHI,
    .deinit = deinitRHI,
    .resources = .{
        .createBuffer = createBuffer,
        .uploadBuffer = uploadBuffer,
        .updateBuffer = updateBuffer,
        .destroyBuffer = destroyBuffer,
        .createTexture = createTexture,
        .destroyTexture = destroyTexture,
        .updateTexture = updateTexture,
        .createShader = createShader,
        .destroyShader = destroyShader,
        .mapBuffer = mapBuffer,
        .unmapBuffer = unmapBuffer,
    },
    .render = .{
        .beginFrame = beginFrame,
        .endFrame = endFrame,
        .abortFrame = abortFrame,
        .beginMainPass = beginMainPass,
        .endMainPass = endMainPass,
        .beginGPass = beginGPass,
        .endGPass = endGPass,
        .computeSSAO = computeSSAO,
        .bindShader = bindShader,
        .bindTexture = bindTexture,
        .setModelMatrix = setModelMatrix,
        .setInstanceBuffer = setInstanceBuffer,
        .setLODInstanceBuffer = setLODInstanceBuffer,
        .updateGlobalUniforms = updateGlobalUniforms,
        .setTextureUniforms = setTextureUniforms,
        .draw = draw,
        .drawOffset = drawOffset,
        .drawIndexed = drawIndexed,
        .drawIndirect = drawIndirect,
        .drawInstance = drawInstance,
        .setViewport = setViewport,
        .bindBuffer = bindBuffer,
        .pushConstants = pushConstants,
        .setClearColor = setClearColor,
        .drawSky = drawSky,
        .beginCloudPass = beginCloudPass,
        .drawDebugShadowMap = drawDebugShadowMap,
    },
    .shadow = .{
        .beginPass = beginShadowPass,
        .endPass = endShadowPass,
        .updateUniforms = updateShadowUniforms,
    },
    .ui = .{
        .beginPass = beginUIPass,
        .endPass = endUIPass,
        .drawRect = drawUIRect,
        .drawTexture = drawUITexture,
        .bindPipeline = bindUIPipeline,
    },
    .query = .{
        .getFrameIndex = getFrameIndex,
        .supportsIndirectFirstInstance = supportsIndirectFirstInstance,
        .getMaxAnisotropy = getMaxAnisotropy,
        .getMaxMSAASamples = getMaxMSAASamples,
        .getFaultCount = getFaultCount,
        .waitIdle = waitIdle,
    },
    .presenter = .{
        .setVSync = setVSync,
        .getVSync = getVSync,
        .present = present,
        .recreateSwapchain = recreateSwapchain,
        .getAspectRatio = getAspectRatio,
    },
    .commands = .{
        .beginFrame = cmdBeginFrame,
        .endFrame = cmdEndFrame,
        .abortFrame = cmdAbortFrame,
        .submit = cmdSubmit,
        .getFrameIndex = cmdGetFrameIndex,
    },
    .setWireframe = setWireframe,
    .setTexturesEnabled = setTexturesEnabled,
    .setAnisotropicFiltering = setAnisotropicFiltering,
    .setVolumetricDensity = setVolumetricDensity,
    .setMSAA = setMSAA,
    .recover = recover,
};

fn initRHI(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, device: ?*RenderDevice) anyerror!void {
    _ = allocator;
    _ = device;
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn deinitRHI(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.deinit();
}

fn createBuffer(ctx_ptr: *anyopaque, size: usize, usage: rhi.BufferUsage) rhi.BufferHandle {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.resource_manager.createBuffer(ctx, size, usage);
}

fn uploadBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, data: []const u8) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.resource_manager.uploadBuffer(ctx, handle, data, ctx.command_queue.getFrameIndex());
}

fn updateBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, offset: usize, data: []const u8) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.resource_manager.updateBuffer(ctx, handle, offset, data, ctx.command_queue.getFrameIndex());
}

fn destroyBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.resource_manager.destroyBuffer(ctx, handle, ctx.command_queue.getFrameIndex());
}

fn createTexture(ctx_ptr: *anyopaque, width: u32, height: u32, format: rhi.TextureFormat, config: rhi.TextureConfig, data: ?[]const u8) rhi.TextureHandle {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = data;
    return ctx.resource_manager.createTexture(ctx, width, height, format, config, null);
}

fn destroyTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.resource_manager.destroyTexture(ctx, handle, ctx.command_queue.getFrameIndex());
}

fn updateTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, data: []const u8) void {
    _ = ctx_ptr;
    _ = handle;
    _ = data;
}

fn createShader(ctx_ptr: *anyopaque, vertex_src: [*c]const u8, fragment_src: [*c]const u8) RhiError!rhi.ShaderHandle {
    _ = ctx_ptr;
    _ = vertex_src;
    _ = fragment_src;
    return rhi.InvalidShaderHandle;
}

fn destroyShader(ctx_ptr: *anyopaque, handle: rhi.ShaderHandle) void {
    _ = ctx_ptr;
    _ = handle;
}

fn mapBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) ?*anyopaque {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    const buffer = ctx.resource_manager.buffers.get(handle) orelse return null;
    var mapped: ?*anyopaque = null;
    _ = c.vkMapMemory(ctx.vulkan_device.vk_device, buffer.memory, 0, buffer.size, 0, &mapped);
    return mapped;
}

fn unmapBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    const buffer = ctx.resource_manager.buffers.get(handle) orelse return;
    c.vkUnmapMemory(ctx.vulkan_device.vk_device, buffer.memory);
}

fn beginFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn endFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn abortFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn beginMainPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn endMainPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn beginGPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn endGPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn computeSSAO(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn bindShader(ctx_ptr: *anyopaque, handle: rhi.ShaderHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = ctx;
}

fn bindTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, slot: u32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = slot;
    _ = ctx;
}

fn setModelMatrix(ctx_ptr: *anyopaque, model: Mat4, color: Vec3, mask_radius: f32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = model;
    _ = color;
    _ = mask_radius;
    _ = ctx;
}

fn setInstanceBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = ctx;
}

fn setLODInstanceBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = ctx;
}

fn updateGlobalUniforms(ctx_ptr: *anyopaque, view_proj: Mat4, cam_pos: Vec3, sun_dir: Vec3, sun_color: Vec3, time: f32, fog_color: Vec3, fog_density: f32, fog_enabled: bool, sun_intensity: f32, ambient: f32, use_texture: bool, cloud_params: rhi.CloudParams) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = view_proj;
    _ = cam_pos;
    _ = sun_dir;
    _ = sun_color;
    _ = time;
    _ = fog_color;
    _ = fog_density;
    _ = fog_enabled;
    _ = sun_intensity;
    _ = ambient;
    _ = use_texture;
    _ = cloud_params;
    _ = ctx;
}

fn setTextureUniforms(ctx_ptr: *anyopaque, texture_enabled: bool, shadow_map_handles: [rhi.SHADOW_CASCADE_COUNT]rhi.TextureHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = texture_enabled;
    _ = shadow_map_handles;
    _ = ctx;
}

fn draw(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, count: u32, mode: rhi.DrawMode) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = count;
    _ = mode;
    _ = ctx;
}

fn drawOffset(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, count: u32, mode: rhi.DrawMode, offset: usize) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = count;
    _ = mode;
    _ = offset;
    _ = ctx;
}

fn drawIndexed(ctx_ptr: *anyopaque, vbo: rhi.BufferHandle, ebo: rhi.BufferHandle, count: u32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = vbo;
    _ = ebo;
    _ = count;
    _ = ctx;
}

fn drawIndirect(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, command_buffer: rhi.BufferHandle, offset: usize, draw_count: u32, stride: u32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = command_buffer;
    _ = offset;
    _ = draw_count;
    _ = stride;
    _ = ctx;
}

fn drawInstance(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, count: u32, instance_index: u32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = count;
    _ = instance_index;
    _ = ctx;
}

fn setViewport(ctx_ptr: *anyopaque, width: u32, height: u32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = width;
    _ = height;
    _ = ctx;
}

fn bindBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, usage: rhi.BufferUsage) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = handle;
    _ = usage;
    _ = ctx;
}

fn pushConstants(ctx_ptr: *anyopaque, stages: rhi.ShaderStageFlags, offset: u32, size: u32, data: *const anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = stages;
    _ = offset;
    _ = size;
    _ = data;
    _ = ctx;
}

fn setClearColor(ctx_ptr: *anyopaque, color: Vec3) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = color;
    _ = ctx;
}

fn drawSky(ctx_ptr: *anyopaque, params: rhi.SkyParams) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = params;
    _ = ctx;
}

fn beginCloudPass(ctx_ptr: *anyopaque, params: rhi.CloudParams) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = params;
    _ = ctx;
}

fn drawDebugShadowMap(ctx_ptr: *anyopaque, cascade_index: usize, depth_map_handle: rhi.TextureHandle) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = cascade_index;
    _ = depth_map_handle;
    _ = ctx;
}

fn beginShadowPass(ctx_ptr: *anyopaque, cascade_index: u32, light_space_matrix: Mat4) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = cascade_index;
    _ = light_space_matrix;
    _ = ctx;
}

fn endShadowPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn updateShadowUniforms(ctx_ptr: *anyopaque, params: rhi.ShadowParams) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = params;
    _ = ctx;
}

fn beginUIPass(ctx_ptr: *anyopaque, width: f32, height: f32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = width;
    _ = height;
    _ = ctx;
}

fn endUIPass(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn drawUIRect(ctx_ptr: *anyopaque, rect: rhi.Rect, color: rhi.Color) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = rect;
    _ = color;
    _ = ctx;
}

fn drawUITexture(ctx_ptr: *anyopaque, texture: rhi.TextureHandle, rect: rhi.Rect) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = texture;
    _ = rect;
    _ = ctx;
}

fn bindUIPipeline(ctx_ptr: *anyopaque, textured: bool) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = textured;
    _ = ctx;
}

fn getFrameIndex(ctx_ptr: *anyopaque) usize {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.command_queue.getFrameIndex();
}

fn supportsIndirectFirstInstance(ctx_ptr: *anyopaque) bool {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.vulkan_device.supports_indirect_first_instance;
}

fn getMaxAnisotropy(ctx_ptr: *anyopaque) u8 {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return @as(u8, @intFromFloat(ctx.vulkan_device.max_anisotropy));
}

fn getMaxMSAASamples(ctx_ptr: *anyopaque) u8 {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.vulkan_device.max_msaa_samples;
}

fn getFaultCount(ctx_ptr: *anyopaque) u32 {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.vulkan_device.fault_count;
}

fn waitIdle(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = c.vkDeviceWaitIdle(ctx.vulkan_device.vk_device);
}

fn setVSync(ctx_ptr: *anyopaque, enabled: bool) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.presenter.setVSync(enabled);
}

fn getVSync(ctx_ptr: *anyopaque) bool {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.presenter.getVSync();
}

fn present(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn recreateSwapchain(ctx_ptr: *anyopaque, msaa_samples: u8) anyerror!void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    try ctx.presenter.recreate(msaa_samples);
}

fn getAspectRatio(ctx_ptr: *anyopaque) f32 {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    const extent = ctx.presenter.swapchain.extent;
    return @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height));
}

fn cmdBeginFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.command_queue.beginFrame(ctx, ctx.image_index) catch {};
}

fn cmdEndFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.command_queue.endFrame(ctx, ctx.image_index) catch {};
}

fn cmdAbortFrame(ctx_ptr: *anyopaque) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.command_queue.frame_in_progress = false;
}

fn cmdSubmit(ctx_ptr: *anyopaque) anyerror!void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = ctx;
}

fn cmdGetFrameIndex(ctx_ptr: *anyopaque) usize {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    return ctx.command_queue.getFrameIndex();
}

fn setWireframe(ctx_ptr: *anyopaque, enabled: bool) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.wireframe_enabled = enabled;
}

fn setTexturesEnabled(ctx_ptr: *anyopaque, enabled: bool) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.textures_enabled = enabled;
}

fn setAnisotropicFiltering(ctx_ptr: *anyopaque, level: u8) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.anisotropic_filtering = level;
}

fn setVolumetricDensity(ctx_ptr: *anyopaque, density: f32) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    _ = density;
    _ = ctx;
}

fn setMSAA(ctx_ptr: *anyopaque, samples: u8) void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    ctx.msaa_samples = samples;
}

fn recover(ctx_ptr: *anyopaque) anyerror!void {
    const ctx = @as(*VulkanContext, @ptrCast(@alignCast(ctx_ptr)));
    if (ctx.gpu_fault_detected) {
        ctx.gpu_fault_detected = false;
    }
}
