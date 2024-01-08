const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const settings = struct { 
    length: u8 = 10, 
    lowercase: ?bool = null, 
    uppercase: ?bool = null, 
    numbers: ?bool = null, 
    symbols: ?bool = null 
};

const SettingsError = error {
    InvalidLength,
    AllOptionsDisabled
};

pub fn createFile(path: []const u8) !bool {
    var file: std.fs.File = std.fs.cwd().createFile(path, .{ .exclusive = true }) catch |e| {
        switch (e) {
            error.PathAlreadyExists => {
                return true;
            },
            else => return e,
        }
    };
    defer file.close();

    return false;
}

pub fn loadSettings(allocator: Allocator) !std.json.Parsed(settings) {
    const createFileResult = try createFile("settings.json");
    const defaultSettings = settings{
        .length = 10,
        .lowercase = true,
        .uppercase = true,
        .numbers = true,
        .symbols = true,
    };

    if (createFileResult) {
        const fileData = try std.fs.cwd().readFileAlloc(allocator, "settings.json", 1024);
        defer allocator.free(fileData);

        return try std.json.parseFromSlice(settings, allocator, fileData, .{ .allocate = .alloc_always });
    } else {
        const stringData: []const u8 = try std.json.stringifyAlloc(allocator, defaultSettings, .{});
        defer allocator.free(stringData);

        try std.fs.cwd().writeFile("settings.json", stringData);
        
        return try std.json.parseFromSlice(settings, allocator, stringData, .{ .allocate = .alloc_always });
    }
}

pub fn generatePassword(allocator: Allocator, generatorSettings: std.json.Parsed(settings)) ![]const u8 {
    const lowercaseChars = "abcdefghijklmopqrstuvwxyz";
    const uppercaseChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const numberChars = "1234567890";
    const symbolChars = "~`!@#$%^&*()_-+={[]}|\\<>,.?/:;'\"";

    const length: u8 = generatorSettings.value.length;

    if (length < 1) {
        return SettingsError.InvalidLength;
    }

    if (generatorSettings.value.lowercase == false and
        generatorSettings.value.uppercase == false and
        generatorSettings.value.numbers == false and
        generatorSettings.value.symbols == false) {
        return SettingsError.AllOptionsDisabled;
    }

    var finalChars = std.ArrayList(u8).init(allocator);
    defer finalChars.deinit();

    if (generatorSettings.value.lowercase orelse true) {
        try finalChars.appendSlice(lowercaseChars);
    }
    if (generatorSettings.value.uppercase orelse true) {
        try finalChars.appendSlice(uppercaseChars);
    }
    if (generatorSettings.value.numbers orelse true) {
        try finalChars.appendSlice(numberChars);
    }
    if (generatorSettings.value.symbols orelse true) {
        try finalChars.appendSlice(symbolChars);
    }

    var password = try allocator.alloc(u8, length);

    for (0..length) |i|{
        password[i] = finalChars.items[std.crypto.random.intRangeAtMost(usize, 0, finalChars.items.len-1)];
    }
    return password;
}

pub fn logPassword(password: []const u8) !void{
    _ = try createFile("log.txt");

    // TODO: find a way to convert current time to string and include it in the log
    
    // TODO: change this to only append and not overwrite
    // TODO: make a while loop that checks if file size too big, if so start deleting old lines to make space
    try std.fs.cwd().writeFile("log.txt", password);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const generatorSettings = try loadSettings(allocator);
    defer generatorSettings.deinit();

    const password: []const u8 = try generatePassword(allocator, generatorSettings);
    defer allocator.free(password);

    try logPassword(password);
    
    // TODO: copy password to clipboard

    // debug
    std.debug.print("{s}\n", .{password});
}

test "loadSettings" {
    // figure out how to enter parameters into a test
}
