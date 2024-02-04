const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{}); // replace with a for loop
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "passwordgen",
        .root_source_file = .{.path = "program.zig"},
        .target = target,
        .optimize = optimize
    });
    exe.linkLibC();
    exe.addIncludePath(std.build.LazyPath.relative("include"));
    exe.addCSourceFile(.{
        .file = std.build.LazyPath.relative("src/clipboard_cocoa.c"),
        .flags = &.{}
    });
    exe.addCSourceFile(.{
        .file = std.build.LazyPath.relative("src/clipboard_common.c"),
        .flags = &.{}
    });
    exe.addCSourceFile(.{
        .file = std.build.LazyPath.relative("src/clipboard_win32.c"),
        .flags = &.{}
    });
    exe.addCSourceFile(.{
        .file = std.build.LazyPath.relative("src/clipboard_x11.c"),
        .flags = &.{}
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}