# Minecraft-Style Voxel Engine Roadmap
Strictly following **SOLID principles** throughout development:
- **S**ingle Responsibility: Each module and class performs exactly one conceptual job.
- **O**pen/Closed: Systems designed to be extended (new blocks, biomes, UI components) without modification to core logic.
- **L**iskov Substitution: Interfaces and abstract types allow interchangeable implementations (renderers, world generators, block types).
- **I**nterface Segregation: Small, focused interfaces (e.g., `IMeshable`, `IUpdatable`, `IRenderable`, `IChunkSource`) instead of giant ones.
- **D**ependency Inversion: Core engine depends on abstractions, not concrete implementations (e.g., world → IChunkProvider, renderer → IGraphicsBackend).

---

## High-Level Goal
A voxel engine similar to early Minecraft (2009–2010 era), built from scratch using **SDL3 + OpenGL + C++** with chunked voxel rendering, procedural worldgen, greedy meshing, player interaction, inventory, water, trees, and day/night cycle.

---

## Phase Roadmap

### **Phase 1 – Engine Foundation**
Goal: Base engine loop and camera movement.
- SDL3 window + GL context setup
- Main loop (input → update → render)
- Depth test + backface culling
- Basic math library (vec3, mat4, perspective, lookAt)
- FPS camera (WASD + mouse look)
- Render a single cube using a VAO/VBO + shader

**Done when:** You can fly around a cube smoothly in 3D space.

---

### **Phase 2 – Block & Chunk System (Naive Implementation)**
Goal: A block world stored in chunks.
- Block type enum
- Chunk structure (16×256×16 recommended)
- 3D block storage (flat array index or array)
- World grid of chunks
- Naive render: draw cube for every non-air block

**Done when:** A visible world of blocks renders and navigation works.

---

### **Phase 3 – Visible Face Culling + Chunk Meshes**
Goal: Render only visible faces, not every cube.
- For each block, emit face only if neighbor is air/transparent
- Build **one mesh per chunk**
- Rebuild chunk mesh only after modification

**Done when:** High FPS and correct geometry using visible-face logic.

---

### **Phase 4 – Greedy Meshing**
Goal: Reduce vertex count by merging similar faces.
- Implement greedy sweep for each face direction
- Transparent blocks meshed separately
- Opaque draw pass + transparent draw pass

**Done when:** Flat areas (e.g., plains) merge large surfaces into huge quads.

---

### **Phase 5 – Procedural Terrain & World Streaming**
Goal: Infinite terrain generation.
- Perlin or simplex noise heightmap generation
- Basic materials (grass/dirt/stone)
- Chunk streaming based on player position
- Chunk load/unload radius
- Multi-threaded generation (later)

**Done when:** Terrain generates dynamically as you move.

---

### **Phase 6 – Day/Night Cycle & Basic Lighting**
Goal: Sun movement and lighting change.
- World time variable
- Directional lighting from sun
- Ambient light curve across day
- Sky gradient or skybox

**Done when:** World visually transitions from day to night.

---

### **Phase 7 – Water Rendering**
Goal: Transparent water blocks.
- Special water block type
- Render after opaques
- Semi-transparent color + slight wave shader

**Done when:** Lakes/rivers appear realistic and render correctly.

---

### **Phase 8 – Trees & World Decoration**
Goal: Populate terrain.
- Simple tree generator added during chunk generation
- Logs & leaves placement
- Probability-based distribution

**Done when:** World feels alive with vegetation.

---

### **Phase 9 – Player Physics + Block Interaction**
Goal: Walk, jump, break, place blocks.
- AABB collision & physics
- Raycast block targeting
- Destroy block (set AIR & rebuild chunk)
- Place block (from inventory hotbar)

**Done when:** Full creative construction loop works.

---

### **Phase 10 – Inventory & Hotbar UI**
Goal: Store and manage items.
- Inventory structure
- Block stacks
- Hotbar selection via keys / mouse scroll
- 2D UI overlay

**Done when:** You can collect blocks and choose what to place.

---

### **Phase 11 – Saving & Loading**
Goal: World persistence.
- Serialize chunk data to disk per chunk
- Load existing chunks before generating
- Save player pos + inventory
- Store seed & metadata

**Done when:** World persists across sessions.

---

### **Phase 12 – Polish, Tools, Extensibility**
Goal: Improve developer and gameplay experience.
- Debug UI overlay (FPS, mesh stats, chunk borders)
- Config system (FOV, render distance)
- Toggle wireframe/debug visualizations
- Data-driven block definitions

**Done when:** Engine becomes extendable and maintainable.

---

## Final Expected Features
| Feature | Delivered By |
|---------|--------------|
| Chunked voxel rendering | Phase 2–4 |
| Infinite world | Phase 5 |
| Day/night cycle | Phase 6 |
| Water | Phase 7 |
| Trees / world decoration | Phase 8 |
| Block break/place | Phase 9 |
| Inventory | Phase 10 |
| Save/Load | Phase 11 |
| Debug tools & extensibility | Phase 12 |

---

## Recommended Directory Structure (SOLID-Friendly)

