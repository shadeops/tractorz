const std = @import("std");

fn buildCmake(b: *std.build.Builder, repo: []const u8) void {
    var build_buffer: [32]u8 = undefined;
    var src_buffer: [32]u8 = undefined;
    const raylib_cmake = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "-B",
        std.fmt.bufPrint(build_buffer[0..], "ext/{s}/build", .{repo}) catch unreachable,
        "-S",
        std.fmt.bufPrint(src_buffer[0..], "ext/{s}", .{repo}) catch unreachable,
        "-DOpenGL_GL_PREFERENCE=GLVND",
        "-DCMAKE_BUILD_TYPE=Release",
    });
    raylib_cmake.step.make() catch {};

    const raylib_build = b.addSystemCommand(&[_][]const u8{
        "cmake",
        "--build",
        std.fmt.bufPrint(build_buffer[0..], "ext/{s}/build", .{repo}) catch unreachable,
    });
    raylib_build.step.make() catch {};
}

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    //buildCmake(b, "raylib");
    //buildCmake(b, "Chipmunk2D");

    const exe = b.addExecutable("tractorz", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addIncludeDir("ext/Chipmunk2D/include");
    exe.addIncludeDir("/usr/include/x86_64-linux-gnu");
    exe.addLibPath("ext/Chipmunk2D/build/src");
    exe.addLibPath("ext/raylib/build/raylib");
    exe.linkSystemLibraryName("chipmunk");
    exe.linkSystemLibraryName("raylib");
    exe.linkSystemLibraryName("curl");
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run Tests");
    const tests = b.addTest("src/tractor.zig");
    tests.setBuildMode(mode);
    tests.addIncludeDir("ext/Chipmunk2D/include");
    tests.addIncludeDir("/usr/include/x86_64-linux-gnu");
    tests.addLibPath("ext/Chipmunk2D/build/src");
    tests.addLibPath("ext/raylib/build/raylib");
    tests.linkSystemLibraryName("chipmunk");
    tests.linkSystemLibraryName("raylib");
    tests.linkSystemLibraryName("curl");
    tests.linkLibC();
    test_step.dependOn(&tests.step);
}
