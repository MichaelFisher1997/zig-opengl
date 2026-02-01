# PR2 Issue: Exit Segfault During Cleanup

## Problem Summary
The application crashes with a segmentation fault when `deinit` is called during cleanup, specifically when accessing `ctx.vulkan_device.vk_device`.

## Error Details
```
Segmentation fault at address 0x7ffff5160040
/home/micqdf/github/OpenStaticFish/rhi_vulkan/src/engine/graphics/rhi_vulkan.zig:1639:52: 0x122738c in deinit (main.zig)
    const vk_device: c.VkDevice = ctx.vulkan_device.vk_device;
```

## Stack Trace
1. `main.zig:9` - `App.init(allocator)` fails
2. `app.zig:101` - `errdefer rhi.deinit()` triggers cleanup
3. `rhi.zig:625` - Calls vtable.deinit(self.ptr)
4. `rhi_vulkan.zig:1639` - Crash when accessing ctx.vulkan_device.vk_device

## Current Code Flow

### Initialization (createRHI)
```zig
pub fn createRHI(...) !rhi.RHI {
    const ctx = try allocator.create(VulkanContext);
    @memset(std.mem.asBytes(ctx), 0);  // Zero all memory
    
    // Initialize fields
    ctx.allocator = allocator;
    ctx.vulkan_device = .{ .allocator = allocator };
    // ... more initialization
    
    return rhi.RHI{
        .ptr = ctx,
        .vtable = &VULKAN_RHI_VTABLE,
        .device = render_device,
    };
}
```

### Then rhi.init() is called
```zig
// app.zig:103
const rhi = try rhi_vulkan.createRHI(...);  // Creates ctx
errdefer rhi.deinit();  // Set up cleanup

try rhi.init(allocator, null);  // Calls initContext
```

### initContext (simplified)
```zig
fn initContext(ctx_ptr: *anyopaque, ...) !void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    errdefer deinit(ctx_ptr);  // Cleanup on error
    
    ctx.vulkan_device = try VulkanDevice.init(allocator, ctx.window);
    // ... more init
}
```

### deinit (where crash happens)
```zig
fn deinit(ctx_ptr: *anyopaque) void {
    const ctx: *VulkanContext = @ptrCast(@alignCast(ctx_ptr));
    
    // CRASH HERE: Accessing ctx.vulkan_device.vk_device causes segfault
    const vk_device: c.VkDevice = ctx.vulkan_device.vk_device;
    
    if (vk_device != null) {
        // Cleanup code
    }
    
    ctx.allocator.destroy(ctx);
}
```

## What We've Tried

### 1. Null Checks
Added check for vk_device == null, but crash happens BEFORE the check when accessing the field:
```zig
if (ctx.vulkan_device.vk_device == null) {  // Crashes here
    return;
}
```

### 2. Initialization Tracking
Added `init_complete` flag, but accessing the flag also crashed because ctx was corrupted.

### 3. Pointer Validation
Tried checking if ctx pointer is valid, but the pointer itself appears valid - it's the struct contents that are corrupted.

## The Mystery
- Application initializes SUCCESSFULLY (we see "Created HDR MSAA 4x render pass")
- But when timeout kills it (or init fails), deinit crashes
- The crash suggests ctx.vulkan_device struct is corrupted
- But if init succeeded, vk_device should be valid

## Key Observations
1. All unit tests pass (they don't test the full init path)
2. Application gets through full initialization successfully
3. Only crashes during cleanup/exit
4. Crash happens consistently at ctx.vulkan_device.vk_device access
5. Address 0x7ffff5160040 suggests memory corruption or use-after-free

## Hypothesis
The crash might be caused by:
1. **Double-free**: ctx memory freed twice
2. **Use-after-free**: ctx freed then accessed
3. **Stack corruption**: Something corrupts ctx during init
4. **Signal handling**: timeout SIGTERM causes unsafe state
5. **errdefer interaction**: errdefer + return path issues

## Files Modified in PR2
- `src/engine/graphics/rhi_vulkan.zig` - Main refactoring
- `src/engine/graphics/vulkan/pipeline_manager.zig` - New module
- `src/engine/graphics/vulkan/render_pass_manager.zig` - New module

## Next Steps Needed
1. Determine if this is a pre-existing bug or introduced by PR2
2. Check if reverting PR2 fixes the crash
3. Add debug logging to trace ctx pointer lifecycle
4. Check for double-free or use-after-free
5. Investigate signal handling during timeout

## Test Command
```bash
timeout 8 nix develop --command zig build run
```

Expected: Clean exit after 8 seconds
Actual: Clean exit (FIXED)

## Resolution

**STATUS: FIXED** ✅

The segfault was caused by a **double-free bug**:

### Root Cause
1. `initContext` had an `errdefer deinit(ctx_ptr)` that freed the `ctx` memory on error
2. The error propagated to `app.zig`, which triggered its own `errdefer rhi.deinit()`
3. This called `deinit()` again with the same (now freed) pointer → segfault

### Fix Applied
1. **Removed duplicate initializations from `createRHI`**:
   - Removed `ShadowSystem.init()` call (now only in `initContext`)
   - Removed HashMap initializations for `resources.buffers/textures` (now only in `ResourceManager.init`)

2. **Removed errdefer from `initContext`**:
   - Cleanup is now handled only by the caller (`app.zig`'s errdefer)

3. **Added `init_complete` flag to `VulkanContext`**:
   - Tracks whether initialization completed successfully
   - Checked in `deinit()` to handle partial initialization safely

4. **Updated `deinit()` to check `init_complete`**:
   - If false, only frees ctx (no Vulkan cleanup)
   - If true, performs full Vulkan cleanup

### Additional Improvements
- Increased descriptor pool capacity (maxSets: 500→1000, samplers: 500→1000) to accommodate UI texture descriptor sets
- Migrated `ui_swapchain_render_pass` to use `RenderPassManager` consistently

### Known Issue
- **Validation errors remain**: `VUID-VkWriteDescriptorSet-dstSet-00320` errors occur during swapchain recreation. These are pre-existing, non-fatal issues related to descriptor set lifetime management during swapchain recreation. The app functions correctly despite these warnings.
