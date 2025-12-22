const std = @import("std");
const c = @import("../../c.zig").c;
const rhi = @import("rhi.zig");
const Mat4 = @import("../math/mat4.zig").Mat4;
const Vec3 = @import("../math/vec3.zig").Vec3;

const GlobalUniforms = extern struct {
    view_proj: Mat4,
    cam_pos: [4]f32,
    sun_dir: [4]f32,
    fog_color: [4]f32,
    time: f32,
    fog_density: f32,
    fog_enabled: f32,
    sun_intensity: f32,
    ambient: f32,
    padding: [3]f32,
};

const ModelUniforms = extern struct {
    model: Mat4,
};

const VulkanBuffer = struct {
    buffer: c.VkBuffer,
    memory: c.VkDeviceMemory,
    size: c.VkDeviceSize,
};

const TextureResource = struct {
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    view: c.VkImageView,
    sampler: c.VkSampler,
    width: u32,
    height: u32,
};

const VulkanContext = struct {
    allocator: std.mem.Allocator,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    queue: c.VkQueue,
    graphics_family: u32,
    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,

    // Sync
    image_available_semaphore: c.VkSemaphore,
    render_finished_semaphore: c.VkSemaphore,
    in_flight_fence: c.VkFence,

    // Swapchain
    swapchain: c.VkSwapchainKHR,
    swapchain_images: std.ArrayListUnmanaged(c.VkImage),
    swapchain_image_views: std.ArrayListUnmanaged(c.VkImageView),
    swapchain_format: c.VkFormat,
    swapchain_extent: c.VkExtent2D,
    swapchain_framebuffers: std.ArrayListUnmanaged(c.VkFramebuffer),
    render_pass: c.VkRenderPass,

    // Depth buffer
    depth_image: c.VkImage,
    depth_image_memory: c.VkDeviceMemory,
    depth_image_view: c.VkImageView,

    // Uniforms
    global_ubo: VulkanBuffer,
    model_ubo: VulkanBuffer,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_set: c.VkDescriptorSet,

    // Pipeline
    pipeline_layout: c.VkPipelineLayout,
    pipeline: c.VkPipeline,

    image_index: u32,
    frame_index: usize,

    buffers: std.AutoHashMap(rhi.BufferHandle, VulkanBuffer),
    next_buffer_handle: rhi.BufferHandle,

    textures: std.AutoHashMap(rhi.TextureHandle, TextureResource),
    next_texture_handle: rhi.TextureHandle,
    current_texture: rhi.TextureHandle,

    memory_type_index: u32, // Host visible coherent

    current_model: Mat4,

    // For swapchain recreation
    window: *c.SDL_Window,
    framebuffer_resized: bool,

    // Debug
    draw_call_count: u32,

    // UI Pipeline
    ui_pipeline: c.VkPipeline,
    ui_pipeline_layout: c.VkPipelineLayout,
    ui_vbo: VulkanBuffer,
    ui_screen_width: f32,
    ui_screen_height: f32,
    ui_in_progress: bool,
};

fn checkVk(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) return error.VulkanError;
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

fn findMemoryType(physical_device: c.VkPhysicalDevice, type_filter: u32, properties: c.VkMemoryPropertyFlags) u32 {
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
    return 0;
}

fn createVulkanBuffer(ctx: *VulkanContext, size: usize, usage: c.VkBufferUsageFlags) VulkanBuffer {
    var buffer_info = std.mem.zeroes(c.VkBufferCreateInfo);
    buffer_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = @intCast(size);
    buffer_info.usage = usage;
    buffer_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    var buffer: c.VkBuffer = null;
    _ = c.vkCreateBuffer(ctx.device, &buffer_info, null, &buffer);

    var mem_reqs: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(ctx.device, buffer, &mem_reqs);

    var alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = findMemoryType(ctx.physical_device, mem_reqs.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    var memory: c.VkDeviceMemory = null;
    _ = c.vkAllocateMemory(ctx.device, &alloc_info, null, &memory);
    _ = c.vkBindBufferMemory(ctx.device, buffer, memory, 0);

    return .{ .buffer = buffer, .memory = memory, .size = mem_reqs.size };
}

fn init(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
    _ = ctx_ptr;
    _ = allocator;
}

fn deinit(ctx_ptr: *anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    _ = c.vkDeviceWaitIdle(ctx.device);

    // Clean up UI pipeline
    c.vkDestroyPipeline(ctx.device, ctx.ui_pipeline, null);
    c.vkDestroyPipelineLayout(ctx.device, ctx.ui_pipeline_layout, null);
    c.vkDestroyBuffer(ctx.device, ctx.ui_vbo.buffer, null);
    c.vkFreeMemory(ctx.device, ctx.ui_vbo.memory, null);

    c.vkDestroyPipeline(ctx.device, ctx.pipeline, null);
    c.vkDestroyPipelineLayout(ctx.device, ctx.pipeline_layout, null);

    for (ctx.swapchain_framebuffers.items) |fb| c.vkDestroyFramebuffer(ctx.device, fb, null);
    ctx.swapchain_framebuffers.deinit(ctx.allocator);

    for (ctx.swapchain_image_views.items) |iv| c.vkDestroyImageView(ctx.device, iv, null);
    ctx.swapchain_image_views.deinit(ctx.allocator);
    ctx.swapchain_images.deinit(ctx.allocator);

    c.vkDestroyImageView(ctx.device, ctx.depth_image_view, null);
    c.vkFreeMemory(ctx.device, ctx.depth_image_memory, null);
    c.vkDestroyImage(ctx.device, ctx.depth_image, null);

    c.vkDestroySwapchainKHR(ctx.device, ctx.swapchain, null);
    c.vkDestroyRenderPass(ctx.device, ctx.render_pass, null);

    c.vkDestroySemaphore(ctx.device, ctx.image_available_semaphore, null);
    c.vkDestroySemaphore(ctx.device, ctx.render_finished_semaphore, null);
    c.vkDestroyFence(ctx.device, ctx.in_flight_fence, null);

    c.vkDestroyCommandPool(ctx.device, ctx.command_pool, null);

    // Clean up UBOS
    c.vkDestroyBuffer(ctx.device, ctx.global_ubo.buffer, null);
    c.vkFreeMemory(ctx.device, ctx.global_ubo.memory, null);
    c.vkDestroyBuffer(ctx.device, ctx.model_ubo.buffer, null);
    c.vkFreeMemory(ctx.device, ctx.model_ubo.memory, null);

    c.vkDestroyDescriptorPool(ctx.device, ctx.descriptor_pool, null);
    c.vkDestroyDescriptorSetLayout(ctx.device, ctx.descriptor_set_layout, null);

    var buf_iter = ctx.buffers.iterator();
    while (buf_iter.next()) |entry| {
        c.vkDestroyBuffer(ctx.device, entry.value_ptr.buffer, null);
        c.vkFreeMemory(ctx.device, entry.value_ptr.memory, null);
    }
    ctx.buffers.deinit();

    var tex_iter = ctx.textures.iterator();
    while (tex_iter.next()) |entry| {
        c.vkDestroySampler(ctx.device, entry.value_ptr.sampler, null);
        c.vkDestroyImageView(ctx.device, entry.value_ptr.view, null);
        c.vkFreeMemory(ctx.device, entry.value_ptr.memory, null);
        c.vkDestroyImage(ctx.device, entry.value_ptr.image, null);
    }
    ctx.textures.deinit();

    c.vkDestroyDevice(ctx.device, null);
    c.vkDestroySurfaceKHR(ctx.instance, ctx.surface, null);
    c.vkDestroyInstance(ctx.instance, null);

    ctx.allocator.destroy(ctx);
}

fn createBuffer(ctx_ptr: *anyopaque, size: usize, usage: rhi.BufferUsage) rhi.BufferHandle {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    if (size == 0) return 0;

    const vk_usage: c.VkBufferUsageFlags = switch (usage) {
        .vertex => c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        .index => c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        .uniform => c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    };

    const buf = createVulkanBuffer(ctx, size, vk_usage);

    const handle = ctx.next_buffer_handle;
    ctx.next_buffer_handle += 1;
    ctx.buffers.put(handle, buf) catch return 0;

    return handle;
}

fn uploadBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, data: []const u8) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    if (data.len == 0 or handle == 0) return;
    if (ctx.buffers.get(handle)) |buf| {
        var map_ptr: ?*anyopaque = null;
        if (c.vkMapMemory(ctx.device, buf.memory, 0, @intCast(data.len), 0, &map_ptr) == c.VK_SUCCESS) {
            @memcpy(@as([*]u8, @ptrCast(map_ptr))[0..data.len], data);
            c.vkUnmapMemory(ctx.device, buf.memory);
        }
    }
}

fn destroyBuffer(ctx_ptr: *anyopaque, handle: rhi.BufferHandle) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.buffers.fetchRemove(handle)) |entry| {
        c.vkDestroyBuffer(ctx.device, entry.value.buffer, null);
        c.vkFreeMemory(ctx.device, entry.value.memory, null);
    }
}

fn cleanupSwapchain(ctx: *VulkanContext) void {
    for (ctx.swapchain_framebuffers.items) |fb| c.vkDestroyFramebuffer(ctx.device, fb, null);
    ctx.swapchain_framebuffers.clearRetainingCapacity();

    for (ctx.swapchain_image_views.items) |iv| c.vkDestroyImageView(ctx.device, iv, null);
    ctx.swapchain_image_views.clearRetainingCapacity();
    ctx.swapchain_images.clearRetainingCapacity();

    c.vkDestroyImageView(ctx.device, ctx.depth_image_view, null);
    c.vkFreeMemory(ctx.device, ctx.depth_image_memory, null);
    c.vkDestroyImage(ctx.device, ctx.depth_image, null);

    c.vkDestroySwapchainKHR(ctx.device, ctx.swapchain, null);
}

fn recreateSwapchain(ctx: *VulkanContext) void {
    // Wait for device idle
    _ = c.vkDeviceWaitIdle(ctx.device);

    // Get new window size
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSize(ctx.window, &w, &h);

    // Handle minimized window
    while (w == 0 or h == 0) {
        _ = c.SDL_GetWindowSize(ctx.window, &w, &h);
        _ = c.SDL_WaitEvent(null);
    }

    cleanupSwapchain(ctx);

    // Get surface capabilities
    var cap: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &cap);

    ctx.swapchain_extent = cap.currentExtent;
    if (ctx.swapchain_extent.width == 0xFFFFFFFF) {
        ctx.swapchain_extent.width = @intCast(w);
        ctx.swapchain_extent.height = @intCast(h);
    }

    var swapchain_info = std.mem.zeroes(c.VkSwapchainCreateInfoKHR);
    swapchain_info.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    swapchain_info.surface = ctx.surface;
    swapchain_info.minImageCount = cap.minImageCount + 1;
    if (cap.maxImageCount > 0 and swapchain_info.minImageCount > cap.maxImageCount) {
        swapchain_info.minImageCount = cap.maxImageCount;
    }
    swapchain_info.imageFormat = ctx.swapchain_format;
    swapchain_info.imageColorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    swapchain_info.imageExtent = ctx.swapchain_extent;
    swapchain_info.imageArrayLayers = 1;
    swapchain_info.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    swapchain_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    swapchain_info.preTransform = cap.currentTransform;
    swapchain_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swapchain_info.presentMode = c.VK_PRESENT_MODE_FIFO_KHR;
    swapchain_info.clipped = c.VK_TRUE;

    _ = c.vkCreateSwapchainKHR(ctx.device, &swapchain_info, null, &ctx.swapchain);

    // Get swapchain images
    var image_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &image_count, null);
    ctx.swapchain_images.resize(ctx.allocator, image_count) catch return;
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &image_count, ctx.swapchain_images.items.ptr);

    // Create image views
    for (ctx.swapchain_images.items) |image| {
        var view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
        view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view_info.image = image;
        view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        view_info.format = ctx.swapchain_format;
        view_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        view_info.subresourceRange.baseMipLevel = 0;
        view_info.subresourceRange.levelCount = 1;
        view_info.subresourceRange.baseArrayLayer = 0;
        view_info.subresourceRange.layerCount = 1;

        var view: c.VkImageView = null;
        _ = c.vkCreateImageView(ctx.device, &view_info, null, &view);
        ctx.swapchain_image_views.append(ctx.allocator, view) catch {};
    }

    // Recreate depth buffer
    const depth_format = c.VK_FORMAT_D32_SFLOAT;
    var depth_image_info = std.mem.zeroes(c.VkImageCreateInfo);
    depth_image_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    depth_image_info.imageType = c.VK_IMAGE_TYPE_2D;
    depth_image_info.extent.width = ctx.swapchain_extent.width;
    depth_image_info.extent.height = ctx.swapchain_extent.height;
    depth_image_info.extent.depth = 1;
    depth_image_info.mipLevels = 1;
    depth_image_info.arrayLayers = 1;
    depth_image_info.format = depth_format;
    depth_image_info.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    depth_image_info.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    depth_image_info.usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    depth_image_info.samples = c.VK_SAMPLE_COUNT_1_BIT;
    depth_image_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    _ = c.vkCreateImage(ctx.device, &depth_image_info, null, &ctx.depth_image);

    var depth_mem_reqs: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(ctx.device, ctx.depth_image, &depth_mem_reqs);

    var depth_alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    depth_alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    depth_alloc_info.allocationSize = depth_mem_reqs.size;
    depth_alloc_info.memoryTypeIndex = findMemoryType(ctx.physical_device, depth_mem_reqs.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    _ = c.vkAllocateMemory(ctx.device, &depth_alloc_info, null, &ctx.depth_image_memory);
    _ = c.vkBindImageMemory(ctx.device, ctx.depth_image, ctx.depth_image_memory, 0);

    var depth_view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
    depth_view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    depth_view_info.image = ctx.depth_image;
    depth_view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
    depth_view_info.format = depth_format;
    depth_view_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    depth_view_info.subresourceRange.baseMipLevel = 0;
    depth_view_info.subresourceRange.levelCount = 1;
    depth_view_info.subresourceRange.baseArrayLayer = 0;
    depth_view_info.subresourceRange.layerCount = 1;

    _ = c.vkCreateImageView(ctx.device, &depth_view_info, null, &ctx.depth_image_view);

    // Recreate framebuffers
    for (ctx.swapchain_image_views.items) |iv| {
        const fb_attachments = [_]c.VkImageView{ iv, ctx.depth_image_view };
        var framebuffer_info = std.mem.zeroes(c.VkFramebufferCreateInfo);
        framebuffer_info.sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebuffer_info.renderPass = ctx.render_pass;
        framebuffer_info.attachmentCount = 2;
        framebuffer_info.pAttachments = &fb_attachments[0];
        framebuffer_info.width = ctx.swapchain_extent.width;
        framebuffer_info.height = ctx.swapchain_extent.height;
        framebuffer_info.layers = 1;

        var fb: c.VkFramebuffer = null;
        _ = c.vkCreateFramebuffer(ctx.device, &framebuffer_info, null, &fb);
        ctx.swapchain_framebuffers.append(ctx.allocator, fb) catch {};
    }

    ctx.framebuffer_resized = false;
}

fn beginFrame(ctx_ptr: *anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));

    ctx.draw_call_count = 0;
    _ = c.vkWaitForFences(ctx.device, 1, &ctx.in_flight_fence, c.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    const result = c.vkAcquireNextImageKHR(ctx.device, ctx.swapchain, 1000000000, ctx.image_available_semaphore, null, &image_index);

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
        recreateSwapchain(ctx);
        return;
    } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
        return;
    }

    ctx.image_index = image_index;

    _ = c.vkResetFences(ctx.device, 1, &ctx.in_flight_fence);
    _ = c.vkResetCommandBuffer(ctx.command_buffer, 0);

    var begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
    begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;

    _ = c.vkBeginCommandBuffer(ctx.command_buffer, &begin_info);

    var render_pass_info = std.mem.zeroes(c.VkRenderPassBeginInfo);
    render_pass_info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    render_pass_info.renderPass = ctx.render_pass;
    render_pass_info.framebuffer = ctx.swapchain_framebuffers.items[image_index];
    render_pass_info.renderArea.offset = .{ .x = 0, .y = 0 };
    render_pass_info.renderArea.extent = ctx.swapchain_extent;

    var clear_values: [2]c.VkClearValue = undefined;
    clear_values[0].color.float32 = .{ 0.1, 0.1, 0.1, 1.0 };
    clear_values[1].depthStencil = .{ .depth = 0.0, .stencil = 0 };
    render_pass_info.clearValueCount = 2;
    render_pass_info.pClearValues = &clear_values[0];

    c.vkCmdBeginRenderPass(ctx.command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    // Set dynamic viewport and scissor
    var viewport = std.mem.zeroes(c.VkViewport);
    viewport.x = 0.0;
    viewport.y = 0.0;
    viewport.width = @floatFromInt(ctx.swapchain_extent.width);
    viewport.height = @floatFromInt(ctx.swapchain_extent.height);
    viewport.minDepth = 0.0;
    viewport.maxDepth = 1.0;
    c.vkCmdSetViewport(ctx.command_buffer, 0, 1, &viewport);

    var scissor = std.mem.zeroes(c.VkRect2D);
    scissor.offset = .{ .x = 0, .y = 0 };
    scissor.extent = ctx.swapchain_extent;
    c.vkCmdSetScissor(ctx.command_buffer, 0, 1, &scissor);
}

fn endFrame(ctx_ptr: *anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));

    c.vkCmdEndRenderPass(ctx.command_buffer);
    _ = c.vkEndCommandBuffer(ctx.command_buffer);

    var submit_info = std.mem.zeroes(c.VkSubmitInfo);
    submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;

    const wait_semaphores = [_]c.VkSemaphore{ctx.image_available_semaphore};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = &wait_semaphores;
    submit_info.pWaitDstStageMask = &wait_stages;

    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &ctx.command_buffer;

    const signal_semaphores = [_]c.VkSemaphore{ctx.render_finished_semaphore};
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = &signal_semaphores;

    if (c.vkQueueSubmit(ctx.queue, 1, &submit_info, ctx.in_flight_fence) != c.VK_SUCCESS) {
        std.log.err("Failed to submit draw command buffer", .{});
    }

    var present_info = std.mem.zeroes(c.VkPresentInfoKHR);
    present_info.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = &signal_semaphores;

    const swapchains = [_]c.VkSwapchainKHR{ctx.swapchain};
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &swapchains;
    present_info.pImageIndices = &ctx.image_index;

    const result = c.vkQueuePresentKHR(ctx.queue, &present_info);

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or ctx.framebuffer_resized) {
        ctx.framebuffer_resized = false;
        recreateSwapchain(ctx);
    }

    ctx.frame_index += 1;
}

fn updateGlobalUniforms(ctx_ptr: *anyopaque, view_proj: Mat4, cam_pos: Vec3, sun_dir: Vec3, time: f32, fog_color: Vec3, fog_density: f32, fog_enabled: bool, sun_intensity: f32, ambient: f32) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));

    const uniforms = GlobalUniforms{
        .view_proj = view_proj,
        .cam_pos = .{ cam_pos.x, cam_pos.y, cam_pos.z, 0 },
        .sun_dir = .{ sun_dir.x, sun_dir.y, sun_dir.z, 0 },
        .fog_color = .{ fog_color.x, fog_color.y, fog_color.z, 1 },
        .time = time,
        .fog_density = fog_density,
        .fog_enabled = if (fog_enabled) 1.0 else 0.0,
        .sun_intensity = sun_intensity,
        .ambient = ambient,
        .padding = .{ 0, 0, 0 },
    };

    var map_ptr: ?*anyopaque = null;
    if (c.vkMapMemory(ctx.device, ctx.global_ubo.memory, 0, @sizeOf(GlobalUniforms), 0, &map_ptr) == c.VK_SUCCESS) {
        const mapped: *GlobalUniforms = @ptrCast(@alignCast(map_ptr));
        mapped.* = uniforms;
        c.vkUnmapMemory(ctx.device, ctx.global_ubo.memory);
    }
}

fn setModelMatrix(ctx_ptr: *anyopaque, model: Mat4) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.current_model = model;
}

fn createTexture(ctx_ptr: *anyopaque, width: u32, height: u32, data: []const u8) rhi.TextureHandle {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));

    const staging_buffer = createVulkanBuffer(ctx, data.len, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    defer {
        c.vkDestroyBuffer(ctx.device, staging_buffer.buffer, null);
        c.vkFreeMemory(ctx.device, staging_buffer.memory, null);
    }

    var map_ptr: ?*anyopaque = null;
    if (c.vkMapMemory(ctx.device, staging_buffer.memory, 0, data.len, 0, &map_ptr) == c.VK_SUCCESS) {
        @memcpy(@as([*]u8, @ptrCast(map_ptr))[0..data.len], data);
        c.vkUnmapMemory(ctx.device, staging_buffer.memory);
    }

    var image: c.VkImage = null;
    var image_info = std.mem.zeroes(c.VkImageCreateInfo);
    image_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image_info.imageType = c.VK_IMAGE_TYPE_2D;
    image_info.extent.width = width;
    image_info.extent.height = height;
    image_info.extent.depth = 1;
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.format = c.VK_FORMAT_R8G8B8A8_SRGB;
    image_info.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    image_info.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    image_info.usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    image_info.samples = c.VK_SAMPLE_COUNT_1_BIT;
    image_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    if (c.vkCreateImage(ctx.device, &image_info, null, &image) != c.VK_SUCCESS) return 0;

    var mem_reqs: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(ctx.device, image, &mem_reqs);

    var memory: c.VkDeviceMemory = null;
    var alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = findMemoryType(ctx.physical_device, mem_reqs.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    if (c.vkAllocateMemory(ctx.device, &alloc_info, null, &memory) != c.VK_SUCCESS) return 0;
    _ = c.vkBindImageMemory(ctx.device, image, memory, 0);

    {
        var begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

        _ = c.vkBeginCommandBuffer(ctx.command_buffer, &begin_info);

        var barrier = std.mem.zeroes(c.VkImageMemoryBarrier);
        barrier.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
        barrier.image = image;
        barrier.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.baseMipLevel = 0;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;

        c.vkCmdPipelineBarrier(ctx.command_buffer, c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);

        var region = std.mem.zeroes(c.VkBufferImageCopy);
        region.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = .{ .width = width, .height = height, .depth = 1 };

        c.vkCmdCopyBufferToImage(ctx.command_buffer, staging_buffer.buffer, image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        barrier.oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;

        c.vkCmdPipelineBarrier(ctx.command_buffer, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);

        _ = c.vkEndCommandBuffer(ctx.command_buffer);

        var submit_info = std.mem.zeroes(c.VkSubmitInfo);
        submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit_info.commandBufferCount = 1;
        submit_info.pCommandBuffers = &ctx.command_buffer;

        _ = c.vkQueueSubmit(ctx.queue, 1, &submit_info, null);
        _ = c.vkQueueWaitIdle(ctx.queue);
    }

    var view: c.VkImageView = null;
    var view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
    view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = image;
    view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = c.VK_FORMAT_R8G8B8A8_SRGB;
    view_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    view_info.subresourceRange.baseMipLevel = 0;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.baseArrayLayer = 0;
    view_info.subresourceRange.layerCount = 1;

    _ = c.vkCreateImageView(ctx.device, &view_info, null, &view);

    var sampler: c.VkSampler = null;
    var sampler_info = std.mem.zeroes(c.VkSamplerCreateInfo);
    sampler_info.sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sampler_info.magFilter = c.VK_FILTER_NEAREST;
    sampler_info.minFilter = c.VK_FILTER_NEAREST;
    sampler_info.addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    sampler_info.addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    sampler_info.addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
    sampler_info.mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR;

    _ = c.vkCreateSampler(ctx.device, &sampler_info, null, &sampler);

    const handle = ctx.next_texture_handle;
    ctx.next_texture_handle += 1;
    ctx.textures.put(handle, .{ .image = image, .memory = memory, .view = view, .sampler = sampler, .width = width, .height = height }) catch return 0;

    return handle;
}

fn destroyTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.textures.fetchRemove(handle)) |entry| {
        c.vkDestroySampler(ctx.device, entry.value.sampler, null);
        c.vkDestroyImageView(ctx.device, entry.value.view, null);
        c.vkFreeMemory(ctx.device, entry.value.memory, null);
        c.vkDestroyImage(ctx.device, entry.value.image, null);
    }
}

fn bindTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, slot: u32) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    _ = slot;
    ctx.current_texture = handle;
}

fn updateTexture(ctx_ptr: *anyopaque, handle: rhi.TextureHandle, data: []const u8) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    const tex = ctx.textures.get(handle) orelse return;

    const staging_buffer = createVulkanBuffer(ctx, data.len, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    defer {
        c.vkDestroyBuffer(ctx.device, staging_buffer.buffer, null);
        c.vkFreeMemory(ctx.device, staging_buffer.memory, null);
    }

    var map_ptr: ?*anyopaque = null;
    if (c.vkMapMemory(ctx.device, staging_buffer.memory, 0, data.len, 0, &map_ptr) == c.VK_SUCCESS) {
        @memcpy(@as([*]u8, @ptrCast(map_ptr))[0..data.len], data);
        c.vkUnmapMemory(ctx.device, staging_buffer.memory);
    }

    {
        var begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

        _ = c.vkBeginCommandBuffer(ctx.command_buffer, &begin_info);

        var barrier = std.mem.zeroes(c.VkImageMemoryBarrier);
        barrier.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.image = tex.image;
        barrier.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;

        c.vkCmdPipelineBarrier(ctx.command_buffer, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);

        var region = std.mem.zeroes(c.VkBufferImageCopy);
        region.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = .{ .width = tex.width, .height = tex.height, .depth = 1 };

        c.vkCmdCopyBufferToImage(ctx.command_buffer, staging_buffer.buffer, tex.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        barrier.oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;

        c.vkCmdPipelineBarrier(ctx.command_buffer, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &barrier);

        _ = c.vkEndCommandBuffer(ctx.command_buffer);

        var submit_info = std.mem.zeroes(c.VkSubmitInfo);
        submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit_info.commandBufferCount = 1;
        submit_info.pCommandBuffers = &ctx.command_buffer;

        _ = c.vkQueueSubmit(ctx.queue, 1, &submit_info, null);
        _ = c.vkQueueWaitIdle(ctx.queue);
    }
}

fn getAllocator(ctx_ptr: *anyopaque) std.mem.Allocator {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    return ctx.allocator;
}

fn draw(ctx_ptr: *anyopaque, handle: rhi.BufferHandle, count: u32, mode: rhi.DrawMode) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    _ = mode;

    if (ctx.buffers.get(handle)) |vbo| {
        ctx.draw_call_count += 1;
        c.vkCmdBindPipeline(ctx.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline);

        if (ctx.textures.get(ctx.current_texture)) |tex| {
            var image_info = c.VkDescriptorImageInfo{
                .sampler = tex.sampler,
                .imageView = tex.view,
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            };

            var write = std.mem.zeroes(c.VkWriteDescriptorSet);
            write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            write.dstSet = ctx.descriptor_set;
            write.dstBinding = 1;
            write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            write.descriptorCount = 1;
            write.pImageInfo = &image_info;

            c.vkUpdateDescriptorSets(ctx.device, 1, &write, 0, null);
        }

        c.vkCmdBindDescriptorSets(ctx.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline_layout, 0, 1, &ctx.descriptor_set, 0, null);

        const uniforms = ModelUniforms{ .model = ctx.current_model };
        c.vkCmdPushConstants(ctx.command_buffer, ctx.pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(ModelUniforms), &uniforms);

        const offset: c.VkDeviceSize = 0;
        c.vkCmdBindVertexBuffers(ctx.command_buffer, 0, 1, &vbo.buffer, &offset);
        c.vkCmdDraw(ctx.command_buffer, count, 1, 0, 0);
    }
}

// UI Rendering functions
fn beginUI(ctx_ptr: *anyopaque, screen_width: f32, screen_height: f32) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.ui_screen_width = screen_width;
    ctx.ui_screen_height = screen_height;
    ctx.ui_in_progress = true;

    // Bind UI pipeline
    c.vkCmdBindPipeline(ctx.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.ui_pipeline);
}

fn endUI(ctx_ptr: *anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.ui_in_progress = false;
}

fn drawUIQuad(ctx_ptr: *anyopaque, rect: rhi.Rect, color: rhi.Color) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    ctx.draw_call_count += 1; // Count UI draws too

    const x = rect.x;
    const y = rect.y;
    const w = rect.width;
    const h = rect.height;

    // Two triangles forming a quad - 6 vertices
    // Each vertex: x, y, r, g, b, a (6 floats)
    const vertices = [_]f32{
        // Triangle 1
        x,     y,     color.r, color.g, color.b, color.a,
        x + w, y,     color.r, color.g, color.b, color.a,
        x + w, y + h, color.r, color.g, color.b, color.a,
        // Triangle 2
        x,     y,     color.r, color.g, color.b, color.a,
        x + w, y + h, color.r, color.g, color.b, color.a,
        x,     y + h, color.r, color.g, color.b, color.a,
    };

    // Upload to UI VBO
    var map_ptr: ?*anyopaque = null;
    if (c.vkMapMemory(ctx.device, ctx.ui_vbo.memory, 0, @sizeOf(@TypeOf(vertices)), 0, &map_ptr) == c.VK_SUCCESS) {
        @memcpy(@as([*]u8, @ptrCast(map_ptr))[0..@sizeOf(@TypeOf(vertices))], std.mem.asBytes(&vertices));
        c.vkUnmapMemory(ctx.device, ctx.ui_vbo.memory);
    }

    // Set orthographic projection via push constants
    // For Vulkan with Y-flip in shader: (0,0) at top-left, matches OpenGL UI convention
    const proj = Mat4.orthographic(0, ctx.ui_screen_width, ctx.ui_screen_height, 0, -1, 1);
    c.vkCmdPushConstants(ctx.command_buffer, ctx.ui_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(Mat4), &proj.data);

    const offset: c.VkDeviceSize = 0;
    c.vkCmdBindVertexBuffers(ctx.command_buffer, 0, 1, &ctx.ui_vbo.buffer, &offset);
    c.vkCmdDraw(ctx.command_buffer, 6, 1, 0, 0);
}

fn drawUITexturedQuad(ctx_ptr: *anyopaque, texture: rhi.TextureHandle, rect: rhi.Rect) void {
    // For now, just draw a white quad - textured UI requires a separate pipeline
    _ = texture;
    drawUIQuad(ctx_ptr, rect, rhi.Color.white);
}

const vtable = rhi.RHI.VTable{
    .init = init,
    .deinit = deinit,
    .createBuffer = createBuffer,
    .uploadBuffer = uploadBuffer,
    .destroyBuffer = destroyBuffer,
    .beginFrame = beginFrame,
    .endFrame = endFrame,
    .updateGlobalUniforms = updateGlobalUniforms,
    .setModelMatrix = setModelMatrix,
    .draw = draw,
    .createTexture = createTexture,
    .destroyTexture = destroyTexture,
    .bindTexture = bindTexture,
    .updateTexture = updateTexture,
    .getAllocator = getAllocator,
    .beginUI = beginUI,
    .endUI = endUI,
    .drawUIQuad = drawUIQuad,
    .drawUITexturedQuad = drawUITexturedQuad,
};

pub fn createRHI(allocator: std.mem.Allocator, window: *c.SDL_Window) !rhi.RHI {
    const ctx = try allocator.create(VulkanContext);
    ctx.* = undefined;
    ctx.allocator = allocator;
    ctx.window = window;
    ctx.framebuffer_resized = false;
    ctx.draw_call_count = 0;
    ctx.buffers = std.AutoHashMap(rhi.BufferHandle, VulkanBuffer).init(allocator);
    ctx.next_buffer_handle = 1;
    ctx.textures = std.AutoHashMap(rhi.TextureHandle, TextureResource).init(allocator);
    ctx.next_texture_handle = 1;
    ctx.current_texture = 0;
    ctx.swapchain_images = .empty;
    ctx.swapchain_image_views = .empty;
    ctx.swapchain_framebuffers = .empty;

    // 1. Create Instance
    var count: u32 = 0;
    const extensions_ptr = c.SDL_Vulkan_GetInstanceExtensions(&count);
    if (extensions_ptr == null) return error.VulkanExtensionsFailed;

    var app_info = std.mem.zeroes(c.VkApplicationInfo);
    app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "Zig Voxel Engine";
    app_info.apiVersion = c.VK_API_VERSION_1_0;

    var create_info = std.mem.zeroes(c.VkInstanceCreateInfo);
    create_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = count;
    create_info.ppEnabledExtensionNames = extensions_ptr;

    try checkVk(c.vkCreateInstance(&create_info, null, &ctx.instance));

    // 2. Create Surface
    if (!c.SDL_Vulkan_CreateSurface(window, ctx.instance, null, &ctx.surface)) {
        return error.VulkanSurfaceFailed;
    }

    // 3. Pick Physical Device
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(ctx.instance, &device_count, null);
    if (device_count == 0) return error.NoVulkanDevice;
    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.free(devices);
    _ = c.vkEnumeratePhysicalDevices(ctx.instance, &device_count, devices.ptr);
    ctx.physical_device = devices[0];

    // 4. Create Logical Device
    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(ctx.physical_device, &queue_family_count, null);
    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(ctx.physical_device, &queue_family_count, queue_families.ptr);

    var graphics_family: ?u32 = null;
    var i: u32 = 0;
    while (i < queue_family_count) : (i += 1) {
        if ((queue_families[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
            graphics_family = i;
            break;
        }
    }
    if (graphics_family == null) return error.NoGraphicsQueue;
    ctx.graphics_family = graphics_family.?;

    const queue_priority: f32 = 1.0;
    var queue_create_info = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
    queue_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_create_info.queueFamilyIndex = graphics_family.?;
    queue_create_info.queueCount = 1;
    queue_create_info.pQueuePriorities = &queue_priority;

    var device_create_info = std.mem.zeroes(c.VkDeviceCreateInfo);
    device_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_create_info.queueCreateInfoCount = 1;
    device_create_info.pQueueCreateInfos = &queue_create_info;

    const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    device_create_info.enabledExtensionCount = 1;
    device_create_info.ppEnabledExtensionNames = &device_extensions;

    try checkVk(c.vkCreateDevice(ctx.physical_device, &device_create_info, null, &ctx.device));
    c.vkGetDeviceQueue(ctx.device, graphics_family.?, 0, &ctx.queue);

    // 5. Create Swapchain
    var cap: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface, &cap);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &format_count, null);
    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
    defer allocator.free(formats);
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.physical_device, ctx.surface, &format_count, formats.ptr);

    var surface_format = formats[0];
    for (formats) |f| {
        if (f.format == c.VK_FORMAT_B8G8R8A8_SRGB and f.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            surface_format = f;
            break;
        }
    }

    ctx.swapchain_extent = cap.currentExtent;
    if (ctx.swapchain_extent.width == 0xFFFFFFFF) {
        ctx.swapchain_extent.width = 1280;
        ctx.swapchain_extent.height = 720;
    }
    ctx.swapchain_format = surface_format.format;

    var swapchain_info = std.mem.zeroes(c.VkSwapchainCreateInfoKHR);
    swapchain_info.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    swapchain_info.surface = ctx.surface;
    swapchain_info.minImageCount = cap.minImageCount + 1;
    if (cap.maxImageCount > 0 and swapchain_info.minImageCount > cap.maxImageCount) {
        swapchain_info.minImageCount = cap.maxImageCount;
    }
    swapchain_info.imageFormat = ctx.swapchain_format;
    swapchain_info.imageColorSpace = surface_format.colorSpace;
    swapchain_info.imageExtent = ctx.swapchain_extent;
    swapchain_info.imageArrayLayers = 1;
    swapchain_info.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    swapchain_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    swapchain_info.preTransform = cap.currentTransform;
    swapchain_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swapchain_info.presentMode = c.VK_PRESENT_MODE_FIFO_KHR;
    swapchain_info.clipped = c.VK_TRUE;

    try checkVk(c.vkCreateSwapchainKHR(ctx.device, &swapchain_info, null, &ctx.swapchain));

    var image_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &image_count, null);
    try ctx.swapchain_images.resize(ctx.allocator, image_count);
    _ = c.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, &image_count, ctx.swapchain_images.items.ptr);

    for (ctx.swapchain_images.items) |image| {
        var view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
        view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view_info.image = image;
        view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        view_info.format = ctx.swapchain_format;
        view_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        view_info.subresourceRange.baseMipLevel = 0;
        view_info.subresourceRange.levelCount = 1;
        view_info.subresourceRange.baseArrayLayer = 0;
        view_info.subresourceRange.layerCount = 1;

        var view: c.VkImageView = null;
        try checkVk(c.vkCreateImageView(ctx.device, &view_info, null, &view));
        try ctx.swapchain_image_views.append(ctx.allocator, view);
    }

    // 5b. Create Depth Buffer
    const depth_format = c.VK_FORMAT_D32_SFLOAT;
    var depth_image_info = std.mem.zeroes(c.VkImageCreateInfo);
    depth_image_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    depth_image_info.imageType = c.VK_IMAGE_TYPE_2D;
    depth_image_info.extent.width = ctx.swapchain_extent.width;
    depth_image_info.extent.height = ctx.swapchain_extent.height;
    depth_image_info.extent.depth = 1;
    depth_image_info.mipLevels = 1;
    depth_image_info.arrayLayers = 1;
    depth_image_info.format = depth_format;
    depth_image_info.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    depth_image_info.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    depth_image_info.usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    depth_image_info.samples = c.VK_SAMPLE_COUNT_1_BIT;
    depth_image_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    try checkVk(c.vkCreateImage(ctx.device, &depth_image_info, null, &ctx.depth_image));

    var depth_mem_reqs: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(ctx.device, ctx.depth_image, &depth_mem_reqs);

    var depth_alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    depth_alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    depth_alloc_info.allocationSize = depth_mem_reqs.size;
    depth_alloc_info.memoryTypeIndex = findMemoryType(ctx.physical_device, depth_mem_reqs.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    try checkVk(c.vkAllocateMemory(ctx.device, &depth_alloc_info, null, &ctx.depth_image_memory));
    try checkVk(c.vkBindImageMemory(ctx.device, ctx.depth_image, ctx.depth_image_memory, 0));

    var depth_view_info = std.mem.zeroes(c.VkImageViewCreateInfo);
    depth_view_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    depth_view_info.image = ctx.depth_image;
    depth_view_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
    depth_view_info.format = depth_format;
    depth_view_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    depth_view_info.subresourceRange.baseMipLevel = 0;
    depth_view_info.subresourceRange.levelCount = 1;
    depth_view_info.subresourceRange.baseArrayLayer = 0;
    depth_view_info.subresourceRange.layerCount = 1;

    try checkVk(c.vkCreateImageView(ctx.device, &depth_view_info, null, &ctx.depth_image_view));

    // 6. Create Render Pass
    var color_attachment = std.mem.zeroes(c.VkAttachmentDescription);
    color_attachment.format = ctx.swapchain_format;
    color_attachment.samples = c.VK_SAMPLE_COUNT_1_BIT;
    color_attachment.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR;
    color_attachment.storeOp = c.VK_ATTACHMENT_STORE_OP_STORE;
    color_attachment.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    color_attachment.stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    color_attachment.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    color_attachment.finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    var depth_attachment = std.mem.zeroes(c.VkAttachmentDescription);
    depth_attachment.format = depth_format;
    depth_attachment.samples = c.VK_SAMPLE_COUNT_1_BIT;
    depth_attachment.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR;
    depth_attachment.storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depth_attachment.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    depth_attachment.stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depth_attachment.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    depth_attachment.finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    var color_attachment_ref = std.mem.zeroes(c.VkAttachmentReference);
    color_attachment_ref.attachment = 0;
    color_attachment_ref.layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    var depth_attachment_ref = std.mem.zeroes(c.VkAttachmentReference);
    depth_attachment_ref.attachment = 1;
    depth_attachment_ref.layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    var subpass = std.mem.zeroes(c.VkSubpassDescription);
    subpass.pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color_attachment_ref;
    subpass.pDepthStencilAttachment = &depth_attachment_ref;

    var dependency = std.mem.zeroes(c.VkSubpassDependency);
    dependency.srcSubpass = c.VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dependency.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    var attachment_descs = [_]c.VkAttachmentDescription{ color_attachment, depth_attachment };
    var render_pass_info = std.mem.zeroes(c.VkRenderPassCreateInfo);
    render_pass_info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    render_pass_info.attachmentCount = 2;
    render_pass_info.pAttachments = &attachment_descs[0];
    render_pass_info.subpassCount = 1;
    render_pass_info.pSubpasses = &subpass;
    render_pass_info.dependencyCount = 1;
    render_pass_info.pDependencies = &dependency;

    try checkVk(c.vkCreateRenderPass(ctx.device, &render_pass_info, null, &ctx.render_pass));

    // 7. Create Framebuffers
    for (ctx.swapchain_image_views.items) |iv| {
        const fb_attachments = [_]c.VkImageView{ iv, ctx.depth_image_view };
        var framebuffer_info = std.mem.zeroes(c.VkFramebufferCreateInfo);
        framebuffer_info.sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebuffer_info.renderPass = ctx.render_pass;
        framebuffer_info.attachmentCount = 2;
        framebuffer_info.pAttachments = &fb_attachments[0];
        framebuffer_info.width = ctx.swapchain_extent.width;
        framebuffer_info.height = ctx.swapchain_extent.height;
        framebuffer_info.layers = 1;

        var fb: c.VkFramebuffer = null;
        try checkVk(c.vkCreateFramebuffer(ctx.device, &framebuffer_info, null, &fb));
        try ctx.swapchain_framebuffers.append(ctx.allocator, fb);
    }

    // 8. Command Pool & Buffer
    var pool_info = std.mem.zeroes(c.VkCommandPoolCreateInfo);
    pool_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.queueFamilyIndex = graphics_family.?;
    pool_info.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    try checkVk(c.vkCreateCommandPool(ctx.device, &pool_info, null, &ctx.command_pool));

    var cb_alloc_info = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
    cb_alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cb_alloc_info.commandPool = ctx.command_pool;
    cb_alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cb_alloc_info.commandBufferCount = 1;
    try checkVk(c.vkAllocateCommandBuffers(ctx.device, &cb_alloc_info, &ctx.command_buffer));

    // 9. Sync Objects
    var semaphore_info = std.mem.zeroes(c.VkSemaphoreCreateInfo);
    semaphore_info.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    var fence_info = std.mem.zeroes(c.VkFenceCreateInfo);
    fence_info.sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fence_info.flags = c.VK_FENCE_CREATE_SIGNALED_BIT;

    try checkVk(c.vkCreateSemaphore(ctx.device, &semaphore_info, null, &ctx.image_available_semaphore));
    try checkVk(c.vkCreateSemaphore(ctx.device, &semaphore_info, null, &ctx.render_finished_semaphore));
    try checkVk(c.vkCreateFence(ctx.device, &fence_info, null, &ctx.in_flight_fence));

    // 10. Uniform Buffers
    ctx.global_ubo = createVulkanBuffer(ctx, @sizeOf(GlobalUniforms), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
    ctx.model_ubo = createVulkanBuffer(ctx, @sizeOf(ModelUniforms) * 1000, c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);

    // 11. Descriptors
    var pool_sizes = [_]c.VkDescriptorPoolSize{
        .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1 },
    };

    var pool_info_desc = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
    pool_info_desc.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info_desc.poolSizeCount = 2;
    pool_info_desc.pPoolSizes = &pool_sizes[0];
    pool_info_desc.maxSets = 1;

    try checkVk(c.vkCreateDescriptorPool(ctx.device, &pool_info_desc, null, &ctx.descriptor_pool));

    var layout_bindings = [_]c.VkDescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .{
            .binding = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
    };

    var layout_info = std.mem.zeroes(c.VkDescriptorSetLayoutCreateInfo);
    layout_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layout_info.bindingCount = 2;
    layout_info.pBindings = &layout_bindings[0];

    try checkVk(c.vkCreateDescriptorSetLayout(ctx.device, &layout_info, null, &ctx.descriptor_set_layout));

    var ds_alloc_info = std.mem.zeroes(c.VkDescriptorSetAllocateInfo);
    ds_alloc_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ds_alloc_info.descriptorPool = ctx.descriptor_pool;
    ds_alloc_info.descriptorSetCount = 1;
    ds_alloc_info.pSetLayouts = &ctx.descriptor_set_layout;

    try checkVk(c.vkAllocateDescriptorSets(ctx.device, &ds_alloc_info, &ctx.descriptor_set));

    var global_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = ctx.global_ubo.buffer,
        .offset = 0,
        .range = @sizeOf(GlobalUniforms),
    };

    var write0 = std.mem.zeroes(c.VkWriteDescriptorSet);
    write0.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write0.dstSet = ctx.descriptor_set;
    write0.dstBinding = 0;
    write0.descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    write0.descriptorCount = 1;
    write0.pBufferInfo = &global_buffer_info;

    var descriptor_writes = [_]c.VkWriteDescriptorSet{write0};
    c.vkUpdateDescriptorSets(ctx.device, 1, &descriptor_writes, 0, null);

    ctx.current_model = Mat4.identity;

    // 12. Pipeline Layout
    var push_constant_range = std.mem.zeroes(c.VkPushConstantRange);
    push_constant_range.stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT;
    push_constant_range.offset = 0;
    push_constant_range.size = @sizeOf(ModelUniforms);

    var pipeline_layout_info = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
    pipeline_layout_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipeline_layout_info.setLayoutCount = 1;
    pipeline_layout_info.pSetLayouts = &ctx.descriptor_set_layout;
    pipeline_layout_info.pushConstantRangeCount = 1;
    pipeline_layout_info.pPushConstantRanges = &push_constant_range;

    try checkVk(c.vkCreatePipelineLayout(ctx.device, &pipeline_layout_info, null, &ctx.pipeline_layout));

    // 13. Graphics Pipeline
    const vert_code = try std.fs.cwd().readFileAlloc("assets/shaders/vulkan/terrain.vert.spv", ctx.allocator, @enumFromInt(1024 * 1024));
    defer ctx.allocator.free(vert_code);
    const frag_code = try std.fs.cwd().readFileAlloc("assets/shaders/vulkan/terrain.frag.spv", ctx.allocator, @enumFromInt(1024 * 1024));
    defer ctx.allocator.free(frag_code);

    const vert_module = try createShaderModule(ctx.device, vert_code);
    defer c.vkDestroyShaderModule(ctx.device, vert_module, null);
    const frag_module = try createShaderModule(ctx.device, frag_code);
    defer c.vkDestroyShaderModule(ctx.device, frag_module, null);

    var vert_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    vert_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vert_stage.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
    vert_stage.module = vert_module;
    vert_stage.pName = "main";

    var frag_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    frag_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    frag_stage.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    frag_stage.module = frag_module;
    frag_stage.pName = "main";

    var shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vert_stage, frag_stage };

    var vertex_input_info = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    vertex_input_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    const binding_description = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 14 * @sizeOf(f32),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    var attribute_descriptions: [7]c.VkVertexInputAttributeDescription = undefined;
    attribute_descriptions[0] = .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 };
    attribute_descriptions[1] = .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 3 * 4 };
    attribute_descriptions[2] = .{ .binding = 0, .location = 2, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 6 * 4 };
    attribute_descriptions[3] = .{ .binding = 0, .location = 3, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 9 * 4 };
    attribute_descriptions[4] = .{ .binding = 0, .location = 4, .format = c.VK_FORMAT_R32_SFLOAT, .offset = 11 * 4 };
    attribute_descriptions[5] = .{ .binding = 0, .location = 5, .format = c.VK_FORMAT_R32_SFLOAT, .offset = 12 * 4 };
    attribute_descriptions[6] = .{ .binding = 0, .location = 6, .format = c.VK_FORMAT_R32_SFLOAT, .offset = 13 * 4 };

    vertex_input_info.vertexBindingDescriptionCount = 1;
    vertex_input_info.pVertexBindingDescriptions = &binding_description;
    vertex_input_info.vertexAttributeDescriptionCount = 7;
    vertex_input_info.pVertexAttributeDescriptions = &attribute_descriptions[0];

    var input_assembly = std.mem.zeroes(c.VkPipelineInputAssemblyStateCreateInfo);
    input_assembly.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    input_assembly.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    var viewport = std.mem.zeroes(c.VkViewport);
    viewport.x = 0.0;
    viewport.y = 0.0;
    viewport.width = @floatFromInt(ctx.swapchain_extent.width);
    viewport.height = @floatFromInt(ctx.swapchain_extent.height);
    viewport.minDepth = 0.0;
    viewport.maxDepth = 1.0;

    var scissor = std.mem.zeroes(c.VkRect2D);
    scissor.offset = .{ .x = 0, .y = 0 };
    scissor.extent = ctx.swapchain_extent;

    var viewport_state = std.mem.zeroes(c.VkPipelineViewportStateCreateInfo);
    viewport_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_state.viewportCount = 1;
    viewport_state.pViewports = null; // Dynamic
    viewport_state.scissorCount = 1;
    viewport_state.pScissors = null; // Dynamic

    // Dynamic state for viewport and scissor (for window resize support)
    const dynamic_states = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    var dynamic_state = std.mem.zeroes(c.VkPipelineDynamicStateCreateInfo);
    dynamic_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic_state.dynamicStateCount = 2;
    dynamic_state.pDynamicStates = &dynamic_states;

    var rasterizer = std.mem.zeroes(c.VkPipelineRasterizationStateCreateInfo);
    rasterizer.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.lineWidth = 1.0;
    rasterizer.cullMode = c.VK_CULL_MODE_NONE; // Disable culling for now
    rasterizer.frontFace = c.VK_FRONT_FACE_CLOCKWISE; // Flip winding

    var multisampling = std.mem.zeroes(c.VkPipelineMultisampleStateCreateInfo);
    multisampling.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;

    var color_blend_attachment = std.mem.zeroes(c.VkPipelineColorBlendAttachmentState);
    color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;

    var color_blending = std.mem.zeroes(c.VkPipelineColorBlendStateCreateInfo);
    color_blending.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    color_blending.attachmentCount = 1;
    color_blending.pAttachments = &color_blend_attachment;

    var depth_stencil = std.mem.zeroes(c.VkPipelineDepthStencilStateCreateInfo);
    depth_stencil.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    depth_stencil.depthTestEnable = c.VK_TRUE;
    depth_stencil.depthWriteEnable = c.VK_TRUE;
    depth_stencil.depthCompareOp = c.VK_COMPARE_OP_GREATER_OR_EQUAL;
    depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
    depth_stencil.stencilTestEnable = c.VK_FALSE;

    var pipeline_info = std.mem.zeroes(c.VkGraphicsPipelineCreateInfo);
    pipeline_info.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipeline_info.stageCount = 2;
    pipeline_info.pStages = &shader_stages[0];
    pipeline_info.pVertexInputState = &vertex_input_info;
    pipeline_info.pInputAssemblyState = &input_assembly;
    pipeline_info.pViewportState = &viewport_state;
    pipeline_info.pRasterizationState = &rasterizer;
    pipeline_info.pMultisampleState = &multisampling;
    pipeline_info.pDepthStencilState = &depth_stencil;
    pipeline_info.pColorBlendState = &color_blending;
    pipeline_info.pDynamicState = &dynamic_state;
    pipeline_info.layout = ctx.pipeline_layout;
    pipeline_info.renderPass = ctx.render_pass;
    pipeline_info.subpass = 0;

    try checkVk(c.vkCreateGraphicsPipelines(ctx.device, null, 1, &pipeline_info, null, &ctx.pipeline));

    // 14. Create UI Pipeline
    const ui_vert_code = try std.fs.cwd().readFileAlloc("assets/shaders/vulkan/ui.vert.spv", ctx.allocator, @enumFromInt(1024 * 1024));
    defer ctx.allocator.free(ui_vert_code);
    const ui_frag_code = try std.fs.cwd().readFileAlloc("assets/shaders/vulkan/ui.frag.spv", ctx.allocator, @enumFromInt(1024 * 1024));
    defer ctx.allocator.free(ui_frag_code);

    const ui_vert_module = try createShaderModule(ctx.device, ui_vert_code);
    defer c.vkDestroyShaderModule(ctx.device, ui_vert_module, null);
    const ui_frag_module = try createShaderModule(ctx.device, ui_frag_code);
    defer c.vkDestroyShaderModule(ctx.device, ui_frag_module, null);

    var ui_vert_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    ui_vert_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    ui_vert_stage.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
    ui_vert_stage.module = ui_vert_module;
    ui_vert_stage.pName = "main";

    var ui_frag_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    ui_frag_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    ui_frag_stage.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    ui_frag_stage.module = ui_frag_module;
    ui_frag_stage.pName = "main";

    var ui_shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ ui_vert_stage, ui_frag_stage };

    // UI vertex format: position (2 floats) + color (4 floats) = 6 floats
    const ui_binding_description = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 6 * @sizeOf(f32),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    var ui_attribute_descriptions: [2]c.VkVertexInputAttributeDescription = undefined;
    ui_attribute_descriptions[0] = .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 0 };
    ui_attribute_descriptions[1] = .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 2 * 4 };

    var ui_vertex_input_info = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    ui_vertex_input_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    ui_vertex_input_info.vertexBindingDescriptionCount = 1;
    ui_vertex_input_info.pVertexBindingDescriptions = &ui_binding_description;
    ui_vertex_input_info.vertexAttributeDescriptionCount = 2;
    ui_vertex_input_info.pVertexAttributeDescriptions = &ui_attribute_descriptions[0];

    // UI pipeline layout with push constant for projection matrix
    var ui_push_constant_range = std.mem.zeroes(c.VkPushConstantRange);
    ui_push_constant_range.stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT;
    ui_push_constant_range.offset = 0;
    ui_push_constant_range.size = @sizeOf(Mat4);

    var ui_pipeline_layout_info = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
    ui_pipeline_layout_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    ui_pipeline_layout_info.setLayoutCount = 0;
    ui_pipeline_layout_info.pushConstantRangeCount = 1;
    ui_pipeline_layout_info.pPushConstantRanges = &ui_push_constant_range;

    try checkVk(c.vkCreatePipelineLayout(ctx.device, &ui_pipeline_layout_info, null, &ctx.ui_pipeline_layout));

    // UI depth/blend state - no depth test, alpha blending enabled
    var ui_depth_stencil = std.mem.zeroes(c.VkPipelineDepthStencilStateCreateInfo);
    ui_depth_stencil.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ui_depth_stencil.depthTestEnable = c.VK_FALSE;
    ui_depth_stencil.depthWriteEnable = c.VK_FALSE;

    var ui_color_blend_attachment = std.mem.zeroes(c.VkPipelineColorBlendAttachmentState);
    ui_color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    ui_color_blend_attachment.blendEnable = c.VK_TRUE;
    ui_color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
    ui_color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    ui_color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
    ui_color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
    ui_color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
    ui_color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;

    var ui_color_blending = std.mem.zeroes(c.VkPipelineColorBlendStateCreateInfo);
    ui_color_blending.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    ui_color_blending.attachmentCount = 1;
    ui_color_blending.pAttachments = &ui_color_blend_attachment;

    var ui_pipeline_info = std.mem.zeroes(c.VkGraphicsPipelineCreateInfo);
    ui_pipeline_info.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    ui_pipeline_info.stageCount = 2;
    ui_pipeline_info.pStages = &ui_shader_stages[0];
    ui_pipeline_info.pVertexInputState = &ui_vertex_input_info;
    ui_pipeline_info.pInputAssemblyState = &input_assembly;
    ui_pipeline_info.pViewportState = &viewport_state;
    ui_pipeline_info.pRasterizationState = &rasterizer;
    ui_pipeline_info.pMultisampleState = &multisampling;
    ui_pipeline_info.pDepthStencilState = &ui_depth_stencil;
    ui_pipeline_info.pColorBlendState = &ui_color_blending;
    ui_pipeline_info.pDynamicState = &dynamic_state;
    ui_pipeline_info.layout = ctx.ui_pipeline_layout;
    ui_pipeline_info.renderPass = ctx.render_pass;
    ui_pipeline_info.subpass = 0;

    try checkVk(c.vkCreateGraphicsPipelines(ctx.device, null, 1, &ui_pipeline_info, null, &ctx.ui_pipeline));

    // Create UI VBO (enough for a few quads)
    ctx.ui_vbo = createVulkanBuffer(ctx, 6 * 6 * @sizeOf(f32) * 100, c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    ctx.ui_screen_width = 1280;
    ctx.ui_screen_height = 720;
    ctx.ui_in_progress = false;

    // 11b. Create Dummy Texture for Descriptor set validity
    const white_pixel = [_]u8{ 255, 255, 255, 255 };
    const dummy_handle = createTexture(ctx, 1, 1, &white_pixel);
    ctx.current_texture = dummy_handle;

    std.log.info("Vulkan initialized successfully!", .{});

    return rhi.RHI{
        .ptr = ctx,
        .vtable = &vtable,
    };
}
