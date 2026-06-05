const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "worm-game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link raylib and system libraries through the root module
    exe.root_module.linkSystemLibrary("raylib", .{});
    exe.root_module.linkSystemLibrary("m", .{});
    exe.root_module.linkSystemLibrary("pthread", .{});
    exe.root_module.linkSystemLibrary("dl", .{});
    exe.root_module.linkSystemLibrary("rt", .{});

    // Link C library
    exe.root_module.link_libc = true;

    // FreeBSD specific paths for raylib
    exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);
}
