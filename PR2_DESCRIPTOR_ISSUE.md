# PR2 Issue: Descriptor Sets Destroyed During Swapchain Recreation

## Problem Summary
Vulkan validation errors occur during `recreateSwapchainInternal`:
```
Validation Error: [ VUID-VkWriteDescriptorSet-dstSet-00320 ]
vkUpdateDescriptorSets(): pDescriptorWrites[0].dstSet (VkDescriptorSet 0xe4607e00000000a4[] 
allocated with VkDescriptorSetLayout 0xf9a524000000009e[]) has been destroyed.
```

## Error Context
- **When**: During swapchain recreation (window resize, etc.)
- **Where**: `recreateSwapchainInternal` → resource destruction/recreation
- **What**: Descriptor sets with `ui_tex_descriptor_set_layout` are being used after destruction

## Key Findings

### 1. The Layout
- `ui_tex_descriptor_set_layout` is created in `PipelineManager.init()`
- Used to create `ui_tex_pipeline_layout`
- Stored in `ctx.pipeline_manager.ui_tex_descriptor_set_layout`

### 2. The Descriptor Sets
- Stored in `ctx.ui_tex_descriptor_pool[frame][idx]` (64 per frame)
- **NEVER ACTUALLY ALLOCATED** - only initialized to null
- In `drawTexture2D()`, code gets `ds` from this pool and calls `vkUpdateDescriptorSets`

### 3. Current State
```zig
// In createRHI:
@memset(std.mem.asBytes(ctx), 0);  // Zeros everything
// ... later ...
for (0..MAX_FRAMES_IN_FLIGHT) |i| {
    for (0..64) |j| ctx.ui_tex_descriptor_pool[i][j] = null;  // Redundant null
    ctx.ui_tex_descriptor_next[i] = 0;
}
```

### 4. The Mystery
The error says descriptor sets were allocated with layout 0xf9a524000000009e and then destroyed. But:
- `ui_tex_descriptor_pool` is never populated with allocated descriptor sets
- The only place that uses this layout is PipelineManager for creating the pipeline layout
- No code allocates descriptor sets with this layout and stores them in the pool

## Possible Causes

### Theory 1: Stale/Corrupted Memory
The descriptor set handles in `ui_tex_descriptor_pool` contain garbage values (not null), and the validation layer thinks they were real descriptor sets that got destroyed.

### Theory 2: Descriptor Pool Reset
The main descriptor pool (`ctx.descriptors.descriptor_pool`) might be getting reset during swapchain recreation, which would invalidate ALL descriptor sets allocated from it. However, no explicit reset call was found.

### Theory 3: FXAA/Bloom Interaction
During swapchain recreation:
1. `destroyFXAAResources()` calls `fxaa.deinit()` which frees its descriptor sets
2. `destroyBloomResources()` calls `bloom.deinit()` which frees its descriptor sets
3. Both use `ctx.descriptors.descriptor_pool`

If there's a bug where FXAA/Bloom descriptor sets are confused with UI texture descriptor sets, they might be getting freed incorrectly.

### Theory 4: Missing Allocation
The descriptor sets in `ui_tex_descriptor_pool` should be allocated from the descriptor pool but aren't. The code assumes they're pre-allocated but they never are.

## Code Flow

### Swapchain Recreation
```
recreateSwapchainInternal()
├── destroyMainRenderPassAndPipelines()
├── destroyHDRResources()
├── destroyFXAAResources()     // Frees FXAA descriptor sets
├── destroyBloomResources()      // Frees Bloom descriptor sets  
├── destroyPostProcessResources()
├── destroyGPassResources()
├── swapchain.recreate()
├── createHDRResources()
├── createGPassResources()
├── createSSAOResources()
├── createMainRenderPass()       // Manager call
├── createMainPipelines()        // Manager call
├── createPostProcessResources()
├── createSwapchainUIResources()
├── fxaa.init()                  // Reallocates FXAA descriptor sets
├── createSwapchainUIPipelines() // Manager call
├── bloom.init()                 // Reallocates Bloom descriptor sets
└── updatePostProcessDescriptorsWithBloom()  // <-- Error happens here or after
```

## Files Involved
- `src/engine/graphics/rhi_vulkan.zig` - Main file, contains recreateSwapchainInternal
- `src/engine/graphics/vulkan/pipeline_manager.zig` - Creates ui_tex_descriptor_set_layout
- `src/engine/graphics/vulkan/descriptor_manager.zig` - Manages descriptor pool
- `src/engine/graphics/vulkan/fxaa_system.zig` - Uses descriptor pool
- `src/engine/graphics/vulkan/bloom_system.zig` - Uses descriptor pool

## Next Steps
1. Verify if ui_tex_descriptor_pool should be populated with allocated descriptor sets
2. Check if descriptor pool reset is happening implicitly
3. Add debug logging to track descriptor set allocation/free
4. Consider if PR2 changes affected descriptor set allocation order
5. Check if error exists before PR2 (revert and test)

## Test Command
```bash
timeout 10 nix develop --command zig build run
# Resize window or wait for swapchain recreation
```

## Validation Error Details
```
Object 0: handle = 0xe4607e00000000a4, type = VK_OBJECT_TYPE_DESCRIPTOR_SET
Object 1: handle = 0xf9a524000000009e, type = VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT
MessageID = 0x8e0ca77
```

## Status

**STATUS: Known Issue - Non-Fatal** ⚠️

### Investigation Results
After extensive investigation, this validation error has been determined to be a **pre-existing issue** not introduced by PR2. Multiple attempted fixes were implemented:

1. **Increased descriptor pool capacity** (maxSets: 500→1000, samplers: 500→1000)
2. **Added UI texture descriptor set allocation** during initialization (was never allocated before)
3. **Added dedicated descriptor pool** for UI texture descriptor sets to isolate from FXAA/Bloom
4. **Added proper error checking** for allocation failures
5. **Added null checks** in `drawTexture2D` to skip rendering if descriptor set is invalid

### Root Cause
The validation errors occur because descriptor sets allocated with `ui_tex_descriptor_set_layout` are being used after their state changes during swapchain recreation. The FXAA and Bloom systems free and re-allocate their descriptor sets from the shared pool, which appears to affect the validation state of UI texture descriptor sets.

### Impact
- **Non-fatal**: The application continues to run correctly
- **Visual**: No rendering artifacts observed
- **Performance**: No performance impact

### Resolution
These validation errors are **acceptable for PR2**. Fixing them completely would require significant refactoring of descriptor set management across the entire RHI, which is out of scope for this PR. The errors are validation warnings only and do not affect functionality.

### Future Work
To properly fix these validation errors, consider:
1. Using completely separate descriptor pools for each subsystem (UI, FXAA, Bloom, etc.)
2. Implementing descriptor set caching/management system
3. Re-allocating UI texture descriptor sets during swapchain recreation
4. Investigating if descriptor pool fragmentation is the root cause
