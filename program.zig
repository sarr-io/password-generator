const std = @import("std");
const fs = std.fs;

const lcb = @cImport({
    @cInclude("libclipboard.h");
});

const Allocator = std.mem.Allocator;

const settings = struct { 
    length: usize = 10, 
    lowercase: ?bool = null, 
    uppercase: ?bool = null, 
    numbers: ?bool = null, 
    symbols: ?bool = null 
};

const SettingsError = error {
    InvalidLength,
    AllOptionsDisabled
};

const ClipboardError = error {
    ClipboardSetTextFailed,
    NewClipboardFailed,
    TransferSizeTooLarge
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

    const length: usize = generatorSettings.value.length;

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

    var password = try allocator.alloc(u8, length+1);
    for (0..length) |i|{
        password[i] = finalChars.items[std.crypto.random.intRangeAtMost(usize, 0, finalChars.items.len-1)];
    }

    // add a blank character at the end
    // this solves a weird null termination string length problem later on with lcb.clipboard_set_text_ex()
    password[length] = ' ';
    
    return password;
}

pub fn getCustomFormattedTime(allocator: Allocator, timeStamp: i64) ![]const u8{
    var mutableTimeStamp: i64 = timeStamp;

    const startYear: u16 = 1970; // epoch start year
    var currentYearDelta: u16 = 0;

    const startDay: u8 = 1; // epoch start day
    var currentDayDelta: u8 = 0;

    const startMonth: u8 = 1; // epoch start month
    var currentMonthDelta: u8 = 0;

    while (true) {
        var isLeapYear: std.time.epoch.YearLeapKind = undefined;
        if (std.time.epoch.isLeapYear(startYear+currentYearDelta)) {
            isLeapYear = std.time.epoch.YearLeapKind.leap;
        } else {
            isLeapYear = std.time.epoch.YearLeapKind.not_leap;
        }

        const secondsInDay = 86400;
        const secondsInMonth: u32 = @as(u32,std.time.epoch.getDaysInMonth(isLeapYear, @enumFromInt(startMonth+currentMonthDelta)))*secondsInDay;
        const secondsInYear: u32 = @as(u32,std.time.epoch.getDaysInYear(startYear+currentYearDelta))*secondsInDay;

        if (mutableTimeStamp>secondsInYear) {
            currentYearDelta += 1;
            mutableTimeStamp -= secondsInYear;
        } else if (mutableTimeStamp>secondsInMonth) {
            currentMonthDelta += 1;
            mutableTimeStamp -= secondsInMonth;
        } else if (mutableTimeStamp>secondsInDay) {
            currentDayDelta += 1;
            mutableTimeStamp -= secondsInDay;
        } else {
            break;
        }
    }

    const currentMonth: []const u8 = @tagName(@as(std.time.epoch.Month,@enumFromInt(startMonth+currentMonthDelta)));
    const currentDay: u8 = startDay+currentDayDelta;
    const currentYear: u16 = startYear+currentYearDelta;

    const formattedTime = try std.fmt.allocPrint(allocator, "UTC {s} {d}, {d}", .{currentMonth, currentDay, currentYear});

    return formattedTime;
}

pub fn logPassword(allocator: Allocator, password: []const u8) !void{
    _ = try createFile("log.txt");

    const timeStamp = std.time.timestamp();

    const timeStampStr = try getCustomFormattedTime(allocator, timeStamp);
    defer allocator.free(timeStampStr);

    const fileData = try std.fs.cwd().readFileAlloc(allocator, "log.txt", 1048576);
    defer allocator.free(fileData);

    const logEntry = try std.fmt.allocPrint(allocator, "{s} - {s}\n{s}", .{timeStampStr, password, fileData});
    defer allocator.free(logEntry);

    if (logEntry.len > 1048576) {
        try std.fs.cwd().deleteFile("log.txt");
    }
    try std.fs.cwd().writeFile("log.txt", logEntry);
}

pub fn copyToClipboard(text:  []const u8) !void {
    // get length of password as multiple of 4 as lcb.clipboard_opts_x11.transfer_size requests
    var transfer_size: u32 = @intCast(text.len);
    const deltaSize: u32 = 4 - (transfer_size % 4);

    // we divide the max int u32 (4_294_967_295) by 2 because in reality the length of lcb.clipboard_set_text_ex is a i32
    if (text.len + deltaSize > (4_294_967_295/2)) { 
        return ClipboardError.TransferSizeTooLarge;
    }
    transfer_size += deltaSize;

    var opts = lcb.clipboard_opts {
        .win32 = lcb.clipboard_opts_win32 {
            .max_retries = 0, // uses default
            .retry_delay = 0 // uses default
        },
        .x11 = lcb.clipboard_opts_x11 {
            .action_timeout = 5, // 5ms
            .transfer_size = transfer_size, // assuming this is size of data being passed to clipboard
            .display_name = null // uses default
        },
        .user_calloc_fn = null, // uses default
        .user_free_fn = null, // uses default
        .user_malloc_fn = null, // uses default
        .user_realloc_fn = null // uses default
    };
    const cb: ?*lcb.clipboard_c = lcb.clipboard_new(&opts);
    defer lcb.clipboard_free(cb);

    if (cb == null) {
        return ClipboardError.NewClipboardFailed;
    }
    
    // as mentioned in generatePassword() there is a null termination problem I couldn't figure out
    // so adding a blank character and then removing 1 from text.len seemed to work without cutting off any characters
    if (!lcb.clipboard_set_text_ex(cb, text.ptr, @intCast(text.len-1), lcb.LCB_CLIPBOARD)) {
        return ClipboardError.ClipboardSetTextFailed;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const generatorSettings = try loadSettings(allocator);
    defer generatorSettings.deinit();

    const password: []const u8 = try generatePassword(allocator, generatorSettings);
    defer allocator.free(password);

    try logPassword(allocator, password);

    try copyToClipboard(password);
}
