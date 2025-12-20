# AGENTS.md - Zig OpenGL Project

## Build Commands
```bash
nix develop              # Enter dev shell with zig, SDL3, GLEW, OpenGL
zig build                # Build the project
zig build run            # Build and run
nix build                # Production build (patched binary in ./result/bin/)
```

## Code Style Guidelines
- **Language**: Zig 0.14 (master/nightly)
- **Imports**: Use `@import("std")` first, then `@cImport` for C headers
- **Naming**: snake_case for variables/functions, PascalCase for types/structs
- **Error Handling**: Return error unions (`!void`), use `try` for propagation
- **Defer**: Use `defer` for cleanup (SDL_Quit, glDeleteProgram, etc.)
- **C Interop**: Access via `c.` prefix after `@cImport`, handle optional fn pointers with `.?()`
- **Constants**: Use `const` by default, multiline strings with `\\` prefix
- **Types**: Explicit types for C interop (c.GLuint, c.GLenum), infer Zig types
- **Comments**: Use `//` for single-line, document sections with numbered steps
- **Architecture**: Follow SOLID principles per ROADMAP.md for extensibility
