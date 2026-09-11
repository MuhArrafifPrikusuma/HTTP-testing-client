pub const styles: struct {
    dim: []const u8 = "\x1b[2m",
    undim_or_unbold: []const u8 = "\x1b[22m",
    italic: []const u8 = "\x1b[3m",
    unitalic: []const u8 = "\x1b[23m",
    bold: []const u8 = "\x1b[1m",
} = .{};

pub const colors: struct {
    errMessage: []const u8 = "\x1B[38;2;255;20;10m",
} = .{};

/// Reset all styles and colors
pub const reset = "\x1b[0m";
