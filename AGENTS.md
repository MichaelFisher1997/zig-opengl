# Agent Guidelines for ZigCraft

## Commands
- **Build**: `nix develop --command zig build`
- **Run (OpenGL)**: `nix develop --command zig build run`
- **Run (Vulkan)**: `nix develop --command zig build run -- --backend vulkan`
- **Test all**: `nix develop --command zig build test`
- **Single test**: `nix develop --command zig build test -- --test-filter "Test Name"`
- **Formatting**: `zig fmt src/` (always auto-format before committing)

## Code Style
- **Naming**: `snake_case` for functions/variables, `PascalCase` for types, `SCREAMING_SNAKE_CASE` for constants.
- **Error Handling**: Use `try` for propagation. Prefer explicit error sets.
- **Memory**: Pass `Allocator` explicitly to functions that allocate. Use `defer` for cleanup.
- **Indentation**: 4 spaces (standard Zig style).
- **Comments**: `///` for documentation, `//!` for module-level docs.
- **Imports**: `std` first, then external, then local. Use relative paths for local modules.
- **Safety**: Prefer Zig's standard library safe methods (e.g., `ArrayList`).

## Design Patterns
- **RHI**: Respect the Render Hardware Interface abstraction in `src/engine/graphics/rhi.zig`.
- **Jobs**: Use the `JobSystem` for heavy computations (generation, meshing).
- **Decoupling**: Keep WorldGen logic free of rendering or windowing dependencies.
