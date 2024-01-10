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

const TimeError = error {
    InvalidMonthInt
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

fn getMonthEnum(int: u8) TimeError!std.time.epoch.Month {
    switch (int) {
        1 => return .jan,
        2 => return .feb,
        3 => return .mar,
        4 => return .apr,
        5 => return .may,
        6 => return .jun,
        7 => return .jul,
        8 => return .aug,
        9 => return .sep,
        10 => return .oct,
        11 => return .nov,
        12 => return .dec,
        else => return TimeError.InvalidMonthInt,
    }
}

fn getMonthString(int: u8) TimeError![]const u8 {
    switch (int) {
        1 => return "jan",
        2 => return "feb",
        3 => return "mar",
        4 => return "apr",
        5 => return "may",
        6 => return "jun",
        7 => return "jul",
        8 => return "aug",
        9 => return "sep",
        10 => return "oct",
        11 => return "nov",
        12 => return "dec",
        else => return TimeError.InvalidMonthInt,
    }
}

pub fn getCustomFormattedTime(allocator: Allocator, timeStamp: i64) ![]const u8{
    const startYear: u16 = 1970;
    var currentYearDelta: u16 = 0;

    const startDay: u8 = 1;
    var currentDayDelta: u8 = 0;

    const startMonth: u8 = 1;
    var currentMonthDelta: u8 = 0;

    while (true) {
        var isLeapYear: std.time.epoch.YearLeapKind = undefined;
        if (std.time.epoch.isLeapYear(startYear+currentYearDelta)) {
            isLeapYear = std.time.epoch.YearLeapKind.leap;
        } else {
            isLeapYear = std.time.epoch.YearLeapKind.not_leap;
        }

        const secondsInDay = 86400;
        const secondsInMonth: u32 = @as(u32,std.time.epoch.getDaysInMonth(isLeapYear, try getMonthEnum(startMonth+currentMonthDelta)))*secondsInDay;
        const secondsInYear: u32 = @as(u32,std.time.epoch.getDaysInYear(startYear+currentYearDelta))*secondsInDay;

        if ((timeStamp-secondsInYear)>secondsInYear) {
            currentYearDelta += 1;
        } else if ((timeStamp-secondsInMonth)>secondsInMonth) {
            currentMonthDelta += 1;
        } else if ((timeStamp-secondsInDay)>secondsInDay) {
            currentDayDelta += 1;
        } else {
            break;
        }
    }

    const currentMonth: []const u8 = try getMonthString(startMonth+currentMonthDelta);
    const currentDay: u8 = startDay+currentDayDelta;
    const currentYear: u16 = startDay+currentDayDelta;

    const formattedTime = try std.fmt.allocPrint(allocator, "{s} {d}, {d}", .{currentMonth, currentDay, currentYear});

    return formattedTime;
}

pub fn logPassword(allocator: Allocator, password: []const u8) !void{
    _ = try createFile("log.txt");

    const timeStamp = std.time.timestamp();

    const timeStampStr = try getCustomFormattedTime(allocator, timeStamp);
    defer allocator.free(timeStampStr);

    std.debug.print("{d}\n", .{timeStampStr});

    // TODO: change this to only append and not overwrite
    // TODO: make a while loop that checks if file size will be too big, if so start deleting old lines to make space
    //       (over around 1mb, this is a temporary backup log and should not be used as a password keeper)
    try std.fs.cwd().writeFile("log.txt", password);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const generatorSettings = try loadSettings(allocator);
    defer generatorSettings.deinit();

    const password: []const u8 = try generatePassword(allocator, generatorSettings);
    defer allocator.free(password);

    try logPassword(allocator, password);
    
    // TODO: copy password to clipboard

    // debug
    std.debug.print("{s}\n", .{password});
}

test "loadSettings" {
    // figure out how to enter parameters into a test
}
