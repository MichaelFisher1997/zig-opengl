const std = @import("std");

pub fn main() !void {
    const argv = std.os.argv;
    if (argv.len < 2) return error.MissingArgument;

    // The argument is a raw C pointer, convert to slice
    const path_c = argv[1];
    const path = std.mem.span(path_c);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf: [1024]u8 = undefined;
    const len = try file.readAll(&buf);
    if (len < 64) return error.FileTooSmall;

    // Check for ELF magic
    if (!std.mem.eql(u8, buf[0..4], "\x7fELF")) return error.NotELF;

    std.debug.print("ELF Header found.\n", .{});
    // Very rudimentary Program Header scan for PT_INTERP (0x03)
    // This is 64-bit specific logic

    // e_phoff is at offset 32 (8 bytes)
    const phoff = std.mem.readInt(u64, buf[32..40], .little);
    // e_phentsize at 54 (2 bytes)
    const phentsize = std.mem.readInt(u16, buf[54..56], .little);
    // e_phnum at 56 (2 bytes)
    const phnum = std.mem.readInt(u16, buf[56..58], .little);

    std.debug.print("phoff: {d}, phentsize: {d}, phnum: {d}\n", .{ phoff, phentsize, phnum });

    // We need to read the program headers.
    // They might be beyond our initial buffer.
    try file.seekTo(phoff);

    var i: u16 = 0;
    while (i < phnum) : (i += 1) {
        var ph_buf: [56]u8 = undefined; // typical 64-bit Phdr size
        _ = try file.readAll(&ph_buf);

        const p_type = std.mem.readInt(u32, ph_buf[0..4], .little);
        if (p_type == 3) { // PT_INTERP
            const p_offset = std.mem.readInt(u64, ph_buf[8..16], .little);
            const p_filesz = std.mem.readInt(u64, ph_buf[32..40], .little);

            std.debug.print("Found PT_INTERP at offset {d} size {d}\n", .{ p_offset, p_filesz });

            try file.seekTo(p_offset);
            var interp: [256]u8 = undefined;
            const read_len = try file.read(&interp);
            std.debug.print("Interpreter: {s}\n", .{interp[0..read_len]});
            return;
        }
    }
    std.debug.print("No PT_INTERP found.\n", .{});
}
