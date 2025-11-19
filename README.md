# Zig 0.14 + SDL3 + OpenGL Pyramid

A simple 3D spinning pyramid implemented in [Zig](https://ziglang.org/) (0.14/master), using [SDL3](https://wiki.libsdl.org/SDL3/FrontPage) for windowing and [OpenGL 3.3](https://www.opengl.org/) for rendering.

This project uses **Nix** to provide a reproducible development and build environment, ensuring all dependencies (Zig compiler, SDL3, GLEW, OpenGL drivers) are correctly linked and patched.

## Features
- **Modern OpenGL (3.3 Core):** Uses Shaders, VAOs, and VBOs.
- **3D Math:** Custom matrix math struct for perspective projection, translation, and rotation.
- **Nix Flake:** Fully hermetic build and development shell.
- **Auto-Patching:** The Nix build process automatically fixes ELF interpreters and RPATHs (including `libstdc++` for audio backends).

## Prerequisites
- [Nix](https://nixos.org/download.html) with `flakes` enabled.

## Build & Run

### 1. Build with Nix
This produces a patched binary in `./result/bin/`:

```bash
nix build
```

### 2. Run
```bash
./result/bin/zig-triangle
```

### Development Shell
To work on the code with `zls` and the `zig` compiler available in your path:

```bash
nix develop
zig build run
```
*(Note: `zig build run` inside `nix develop` uses the local cache and might require `LD_LIBRARY_PATH` setup if not fully patched, but the flake handles the production build perfectly)*

## Project Structure
- `src/main.zig`: Application entry point, render loop, and shader logic.
- `build.zig`: Zig build configuration.
- `flake.nix`: Nix dependencies, package definition, and wrapper logic.
