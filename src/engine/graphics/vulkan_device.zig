const std = @import("std");
const c = @import("../../c.zig").c;
const rhi = @import("rhi.zig");

pub const VulkanDevice = struct {
    allocator: std.mem.Allocator,
    instance: c.VkInstance = null,
    surface: c.VkSurfaceKHR = null,
    physical_device: c.VkPhysicalDevice = null,
    vk_device: c.VkDevice = null,
    queue: c.VkQueue = null,
    graphics_family: u32 = 0,

    // Limits and capabilities
    max_anisotropy: f32 = 0.0,
    max_msaa_samples: u8 = 1,
    multi_draw_indirect: bool = false,
    draw_indirect_first_instance: bool = false,

    pub fn init(allocator: std.mem.Allocator, window: *c.SDL_Window) !VulkanDevice {
        var self: VulkanDevice = undefined;
        self.allocator = allocator;

        // 1. Create Instance
        var count: u32 = 0;
        const extensions_ptr = c.SDL_Vulkan_GetInstanceExtensions(&count);
        if (extensions_ptr == null) return error.VulkanExtensionsFailed;

        var app_info = std.mem.zeroes(c.VkApplicationInfo);
        app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
        app_info.pApplicationName = "ZigCraft";
        app_info.apiVersion = c.VK_API_VERSION_1_0;

        const enable_validation = std.debug.runtime_safety;
        const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};

        var create_info = std.mem.zeroes(c.VkInstanceCreateInfo);
        create_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        create_info.pApplicationInfo = &app_info;
        create_info.enabledExtensionCount = count;
        create_info.ppEnabledExtensionNames = extensions_ptr;

        if (enable_validation) {
            var layer_count: u32 = 0;
            _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);
            if (layer_count > 0) {
                const layer_props = allocator.alloc(c.VkLayerProperties, layer_count) catch null;
                if (layer_props) |props| {
                    defer allocator.free(props);
                    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, props.ptr);
                    var found = false;
                    for (props) |layer| {
                        const layer_name: [*:0]const u8 = @ptrCast(&layer.layerName);
                        if (std.mem.eql(u8, std.mem.span(layer_name), "VK_LAYER_KHRONOS_validation")) {
                            found = true;
                            break;
                        }
                    }
                    if (found) {
                        create_info.enabledLayerCount = 1;
                        create_info.ppEnabledLayerNames = &validation_layers;
                        std.log.info("Vulkan validation layers enabled", .{});
                    }
                }
            }
        }
        try checkVk(c.vkCreateInstance(&create_info, null, &self.instance));

        // 2. Create Surface
        if (!c.SDL_Vulkan_CreateSurface(window, self.instance, null, &self.surface)) return error.VulkanSurfaceFailed;

        // 3. Pick Physical Device
        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, null);
        if (device_count == 0) return error.NoVulkanDevice;
        const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
        defer allocator.free(devices);
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);
        self.physical_device = devices[0];

        // 4. Create Logical Device
        var supported_features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(self.physical_device, &supported_features);

        var device_properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(self.physical_device, &device_properties);
        self.max_anisotropy = device_properties.limits.maxSamplerAnisotropy;

        const color_samples = device_properties.limits.framebufferColorSampleCounts;
        const depth_samples = device_properties.limits.framebufferDepthSampleCounts;
        const sample_counts = color_samples & depth_samples;
        if ((sample_counts & c.VK_SAMPLE_COUNT_8_BIT) != 0) {
            self.max_msaa_samples = 8;
        } else if ((sample_counts & c.VK_SAMPLE_COUNT_4_BIT) != 0) {
            self.max_msaa_samples = 4;
        } else if ((sample_counts & c.VK_SAMPLE_COUNT_2_BIT) != 0) {
            self.max_msaa_samples = 2;
        } else {
            self.max_msaa_samples = 1;
        }

        var device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
        if (supported_features.fillModeNonSolid == c.VK_TRUE) device_features.fillModeNonSolid = c.VK_TRUE;
        if (supported_features.samplerAnisotropy == c.VK_TRUE) device_features.samplerAnisotropy = c.VK_TRUE;
        if (supported_features.multiDrawIndirect == c.VK_TRUE) device_features.multiDrawIndirect = c.VK_TRUE;
        if (supported_features.drawIndirectFirstInstance == c.VK_TRUE) device_features.drawIndirectFirstInstance = c.VK_TRUE;
        self.multi_draw_indirect = supported_features.multiDrawIndirect == c.VK_TRUE;
        self.draw_indirect_first_instance = supported_features.drawIndirectFirstInstance == c.VK_TRUE;

        var queue_family_count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, null);
        const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, queue_families.ptr);

        var graphics_family: ?u32 = null;
        for (queue_families, 0..) |qf, i| {
            if ((qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                graphics_family = @intCast(i);
                break;
            }
        }
        if (graphics_family == null) return error.NoGraphicsQueue;
        self.graphics_family = graphics_family.?;

        const queue_priority: f32 = 1.0;
        var queue_create_info = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
        queue_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_create_info.queueFamilyIndex = self.graphics_family;
        queue_create_info.queueCount = 1;
        queue_create_info.pQueuePriorities = &queue_priority;

        const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};
        var device_create_info = std.mem.zeroes(c.VkDeviceCreateInfo);
        device_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        device_create_info.queueCreateInfoCount = 1;
        device_create_info.pQueueCreateInfos = &queue_create_info;
        device_create_info.pEnabledFeatures = &device_features;
        device_create_info.enabledExtensionCount = 1;
        device_create_info.ppEnabledExtensionNames = &device_extensions;

        try checkVk(c.vkCreateDevice(self.physical_device, &device_create_info, null, &self.vk_device));
        c.vkGetDeviceQueue(self.vk_device, self.graphics_family, 0, &self.queue);

        return self;
    }

    pub fn deinit(self: *VulkanDevice) void {
        c.vkDestroyDevice(self.vk_device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }

    pub fn findMemoryType(self: VulkanDevice, type_filter: u32, properties: c.VkMemoryPropertyFlags) u32 {
        var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &mem_properties);

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
};

fn checkVk(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) return error.VulkanError;
}
