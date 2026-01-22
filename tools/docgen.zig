const std = @import("std");
const Ast = std.zig.Ast;

const OutputConfig = struct {
    source_dir: []const u8 = "src",
    output_dir: []const u8 = "docs/generated",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.print("Memory leaked\n", .{});
    };
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = OutputConfig{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--source=")) {
            config.source_dir = arg["--source=".len..];
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            config.output_dir = arg["--output=".len..];
        }
    }

    const source_dir = try std.fs.cwd().openDir(config.source_dir, .{});
    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".zig")) {
            try files.append(try allocator.dupe(u8, entry.path));
        }
    }

    try std.fs.cwd().makePath(config.output_dir);

    for (files.items) |file_path| {
        try processFile(allocator, source_dir, file_path, config.output_dir);
    }

    try generateSidebar(allocator, config.output_dir);
}

fn processFile(allocator: Allocator, source_dir: std.fs.Dir, file_path: []const u8, output_dir: []const u8) !void {
    const full_source_path = try allocator.dupe(u8, config.source_dir);
    defer allocator.free(full_source_path);

    const source = source_dir.readFileAllocOptions(allocator, file_path, 1024 * 1024, null, 1, 0) catch |err| {
        std.debug.print("Failed to read {s}: {s}\n", .{ file_path, @errorName(err) });
        return;
    };
    defer allocator.free(source);

    const ast = try Ast.parse(allocator, source, .{.comments = true});
    defer ast.deinit(allocator);

    const output_file_path = try getOutputPath(allocator, file_path, output_dir);
    defer allocator.free(output_file_path);

    const output_file = try std.fs.cwd().createFile(output_file_path, .{});
    defer output_file.close();

    var writer = output_file.writer();

    const module_doc = extractModuleDoc(ast, source);

    try writeFrontmatter(&writer, file_path, module_doc);
    try writeContent(&writer, allocator, ast, source, file_path);

    std.debug.print("Generated: {s}\n", .{output_file_path});
}

fn getOutputPath(allocator: Allocator, file_path: []const u8, output_dir: []const u8) ![]const u8 {
    const base_name = std.fs.path.basename(file_path);
    const name_without_ext = std.mem.trim(u8, base_name, ".zig");

    var output_path = try std.fs.path.join(allocator, &.{ output_dir, file_path });
    errdefer allocator.free(output_path);

    try std.fs.cwd().makePath(std.fs.path.dirname(output_path).?);

    const result = try std.fs.path.join(allocator, &.{ std.fs.path.dirname(output_path).?, std.mem.concat(allocator, u8, &.{ name_without_ext, ".mdx" }) });
    errdefer allocator.free(result);

    allocator.free(output_path);
    return result;
}

fn extractModuleDoc(ast: Ast, source: []const u8) ?[]const u8 {
    for (0..ast.nodes.len) |i| {
        const node = ast.nodes[i];
        if (node.tag == .doc_comment) {
            const line = ast.getNodeSourceSlice(i, source) orelse continue;
            const trimmed = std.mem.trim(u8, line, "//! ");
            return trimmed;
        }
    }
    return null;
}

fn writeFrontmatter(writer: anytype, file_path: []const u8, module_doc: ?[]const u8) !void {
    try writer.writeAll("---\n");
    try writer.writeAll("sidebar_position: 0\n");
    try writer.writeAll("sidebar_label: \"");
    const base_name = std.fs.path.basename(file_path);
    const name_without_ext = std.mem.trim(u8, base_name, ".zig");
    try writer.writeAll(name_without_ext);
    try writer.writeAll("\"\n");
    try writer.writeAll("---\n\n");

    if (module_doc) |doc| {
        try writer.writeAll(doc);
        try writer.writeAll("\n\n");
    }
}

fn writeContent(writer: anytype, allocator: Allocator, ast: Ast, source: []const u8, file_path: []const u8) !void {
    try writer.writeAll("```zig\n");

    var node_index: usize = 0;
    while (node_index < ast.nodes.len) : (node_index += 1) {
        const node = ast.nodes[node_index];
        if (node.tag == .doc_comment) {
            const doc_line = ast.getNodeSourceSlice(node_index, source) orelse continue;
            const trimmed = std.mem.trim(u8, doc_line, "/// ");
            try writer.writeAll("/// ");
            try writer.writeAll(trimmed);
            try writer.writeAll("\n");
        } else if (isPublicDeclaration(node.tag)) {
            const decl_name = getDeclarationName(ast, node_index) orelse continue;
            try writer.writeAll("\n// ");
            try writer.writeAll(decl_name);
            try writer.writeAll("\n");

            const slice = ast.getNodeSourceSlice(node_index, source) orelse continue;
            try writer.writeAll(slice);
            try writer.writeAll("\n");
        }
    }

    try writer.writeAll("```\n");
}

fn isPublicDeclaration(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .fn_decl, .struct_decl, .enum_decl, .union_decl, .opaque_decl, .global_var_decl, .local_var_decl, .const_decl => true,
        else => false,
    };
}

fn getDeclarationName(ast: Ast, node_index: usize) ?[]const u8 {
    const node = ast.nodes[node_index];
    return switch (node.tag) {
        .fn_decl => getFnName(ast, node_index),
        .struct_decl => getContainerName(ast, node_index),
        .enum_decl => getContainerName(ast, node_index),
        .union_decl => getContainerName(ast, node_index),
        .opaque_decl => getContainerName(ast, node_index),
        .global_var_decl, .local_var_decl, .const_decl => getVarName(ast, node_index),
        else => null,
    };
}

fn getFnName(ast: Ast, node_index: usize) ?[]const u8 {
    const node = ast.nodes[node_index];
    const fn_node = ast.fullFnDecl(node_index) orelse return null;
    const name_index = fn_node.name_token orelse return null;
    return ast.tokenSlice(name_index);
}

fn getContainerName(ast: Ast, node_index: usize) ?[]const u8 {
    const node = ast.nodes[node_index];
    const container = ast.fullContainerDecl(node_index) orelse return null;
    if (container.layout_token) |token| {
        if (ast.tokenTag(token) != .keyword_pub) return null;
    }
    const name_token = container.name orelse return null;
    return ast.tokenSlice(name_token);
}

fn getVarName(ast: Ast, node_index: usize) ?[]const u8 {
    const node = ast.nodes[node_index];
    const var_node = ast.fullVarDecl(node_index) orelse return null;
    if (var_node.visibility_token == null) return null;
    return ast.tokenSlice(var_node.name);
}

fn generateSidebar(allocator: Allocator, output_dir: []const u8) !void {
    const sidebar_path = try std.fs.path.join(allocator, &.{ output_dir, "sidebar.json" });
    defer allocator.free(sidebar_path);

    const sidebar_file = try std.fs.cwd().createFile(sidebar_path, .{});
    defer sidebar_file.close();

    var walker = try std.fs.cwd().walk(output_dir);
    defer walker.deinit();

    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".mdx")) {
            const relative_path = try allocator.dupe(u8, entry.path);
            defer allocator.free(relative_path);
            try files.append(relative_path);
        }
    }

    var writer = sidebar_file.writer();
    try writer.writeAll("{\n");
    try writer.writeAll("  \"items\": [\n");

    for (files.items, 0..) |file, i| {
        const base_name = std.fs.path.basename(file);
        const name_without_ext = std.mem.trim(u8, base_name, ".mdx");

        try writer.writeAll("    {\n");
        try writer.writeAll("      \"type\": \"doc\",\n");
        try writer.writeAll("      \"id\": \"");
        try writer.writeAll(name_without_ext);
        try writer.writeAll("\"\n");
        try writer.writeAll("    }");

        if (i < files.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");

    std.debug.print("Generated sidebar: {s}\n", .{sidebar_path});
}
