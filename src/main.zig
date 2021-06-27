const std = @import("std");
const tractor = @import("tractor.zig");

const clibs = @import("clibs.zig");
const ray = clibs.ray;
const chip = clibs.chipmunk;

fn makeTexture() ray.RenderTexture2D {
    var tex = ray.LoadRenderTexture(8, 8);
    ray.BeginTextureMode(tex);
    ray.ClearBackground(ray.BLANK);
    ray.DrawCircle(4, 4, 4.0, ray.WHITE);
    ray.EndTextureMode();

    return tex;
}

const bg_png = @embedFile("../resources/bg.png");
const fg_png = @embedFile("../resources/fg.png");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = &arena.allocator;

    //try tractor.queryTractor();
    //try tractor.runnin();

    _ = tractor.tractorLogin(allocator) catch |e| {
        switch (e) {
            error.FailedToPerformRequest => {
                std.debug.print("Could not connect to Tractor\n", .{});
                return;
            },
            else => return e,
        }
    };

    try vis(allocator);

    return;
}

fn spawnNewObjects(
    space: *chip.cpSpace,
    rand: *std.rand.Random,
    looks: *Looks,
    ctx: *tractor.ThreadContext,
) u32 {
    if (!@atomicLoad(bool, &ctx.is_ready, .SeqCst)) {
        return 0;
    }

    var active = @atomicRmw(u32, &ctx.msgs.active, .Xchg, 0, .SeqCst);
    var blocked = @atomicRmw(u32, &ctx.msgs.blocked, .Xchg, 0, .SeqCst);
    var err = @atomicRmw(u32, &ctx.msgs.err, .Xchg, 0, .SeqCst);
    var done = @atomicRmw(u32, &ctx.msgs.done, .Xchg, 0, .SeqCst);
    @atomicStore(bool, &ctx.is_ready, false, .SeqCst);

    const radius: f64 = 4;
    const mass: f64 = 1;
    var moment = chip.cpMomentForCircle(mass, 0, radius, chip.cpvzero);

    var i: usize = 0;
    while (i < active) : (i += 1) {
        var x_pos = @intToFloat(f64, rand.intRangeAtMost(u32, 65, 265));
        var y_pos = @intToFloat(f64, rand.uintLessThan(u32, 35));

        var body = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(body, chip.cpv(x_pos, 610 + y_pos));
        chip.cpBodySetUserData(body, @ptrCast(*c_void, &looks.active));

        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(body, radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.5);
        chip.cpShapeSetElasticity(shape, 0.2);
        chip.cpShapeSetFilter(shape, active_filter);
    }

    i = 0;
    while (i < blocked) : (i += 1) {
        var x_pos = @intToFloat(f64, rand.intRangeAtMost(u32, 65, 265));
        var y_pos = @intToFloat(f64, rand.uintLessThan(u32, 35));

        var body = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(body, chip.cpv(x_pos, 610 + y_pos));
        chip.cpBodySetUserData(body, @ptrCast(*c_void, &looks.blocked));

        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(body, radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.5);
        chip.cpShapeSetElasticity(shape, 0.2);
        chip.cpShapeSetFilter(shape, blocked_filter);
    }

    i = 0;
    while (i < done) : (i += 1) {
        var x_pos = @intToFloat(f64, rand.intRangeAtMost(u32, 245, 340));
        var y_pos = @intToFloat(f64, rand.uintLessThan(u32, 20));

        var body = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(body, chip.cpv(x_pos, 600 - 400 + y_pos));
        chip.cpBodySetUserData(body, @ptrCast(*c_void, &looks.done));

        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(body, radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.5);
        chip.cpShapeSetElasticity(shape, 0.2);
        chip.cpShapeSetFilter(shape, done_filter);
    }

    i = 0;
    while (i < err) : (i += 1) {
        var x_pos = @intToFloat(f64, rand.intRangeAtMost(u32, 330, 470));
        var y_pos = @intToFloat(f64, rand.uintLessThan(u32, 30));

        var body = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(body, chip.cpv(x_pos, 600 - 475 + y_pos));
        chip.cpBodySetUserData(body, @ptrCast(*c_void, &looks.err));

        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(body, radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.5);
        chip.cpShapeSetElasticity(shape, 0.2);
        chip.cpShapeSetFilter(shape, chip.CP_SHAPE_FILTER_NONE);
    }

    return active + err + blocked + done;
}

fn cullShape(space: ?*chip.cpSpace, shape: ?*c_void, data: ?*c_void) callconv(.C) void {
    _ = data;
    chip.cpSpaceRemoveShape(space, @ptrCast(*chip.cpShape, shape));
    chip.cpShapeFree(@ptrCast(*chip.cpShape, shape));
}

fn cullBody(space: ?*chip.cpSpace, body: ?*c_void, data: ?*c_void) callconv(.C) void {
    _ = data;
    chip.cpSpaceRemoveBody(space, @ptrCast(*chip.cpBody, body));
    chip.cpBodyFree(@ptrCast(*chip.cpBody, body));
}

fn postCullShapeWrapper(body: ?*chip.cpBody, shape: ?*chip.cpShape, data: ?*c_void) callconv(.C) void {
    _ = data;
    var space = chip.cpBodyGetSpace(body);
    _ = chip.cpSpaceAddPostStepCallback(space, cullShape, shape, null);
}

fn drawShapes(body: ?*chip.cpBody, data: ?*c_void) callconv(.C) void {
    var body_data = chip.cpBodyGetUserData(body);
    // No color info means not "renderable"
    if (body_data == null) return;

    var look = @ptrCast(*Look, chip.cpBodyGetUserData(body).?).*;

    var pos = chip.cpBodyGetPosition(body);
    var space = chip.cpBodyGetSpace(body);
    if (pos.y < -10 or (pos.y < (600 - 350) and look.state == 0)) {
        chip.cpBodyEachShape(body, postCullShapeWrapper, null);
        _ = chip.cpSpaceAddPostStepCallback(space, cullBody, body, null);
    }
    var tex: *ray.Texture = @ptrCast(*ray.Texture, @alignCast(4, data));
    ray.DrawTexture(tex.*, @floatToInt(i32, pos.x), 600 - @floatToInt(i32, pos.y), look.color);
}

const Look = struct {
    color: ray.Color,
    state: u8,
};

const Looks = struct {
    active: Look,
    done: Look,
    err: Look,
    blocked: Look,
};

const active_mask: u32 = 0b1;
const blocked_mask: u32 = 0b10;
const active_ramp_mask: u32 = 0b100;
const blocked_ramp_mask: u32 = 0b1000;
const done_mask: u32 = 0b10000;

const active_ramp_filter = chip.cpShapeFilter{
    .group = chip.CP_NO_GROUP,
    .categories = active_ramp_mask,
    .mask = active_mask,
};

const blocked_ramp_filter = chip.cpShapeFilter{
    .group = chip.CP_NO_GROUP,
    .categories = blocked_ramp_mask,
    .mask = blocked_mask,
};

const active_filter = chip.cpShapeFilter{
    .group = chip.CP_NO_GROUP,
    .categories = active_mask,
    .mask = active_mask | blocked_mask | active_ramp_mask,
};

const blocked_filter = chip.cpShapeFilter{
    .group = chip.CP_NO_GROUP,
    .categories = blocked_mask,
    .mask = active_mask | blocked_mask | blocked_ramp_mask,
};

const done_filter = chip.cpShapeFilter{
    .group = chip.CP_NO_GROUP,
    .categories = done_mask,
    .mask = done_mask,
};

fn vis(allocator: *std.mem.Allocator) !void {
    ray.SetTraceLogLevel(ray.LOG_ERROR);
    ray.InitWindow(800, 600, "tractorz");
    defer ray.CloseWindow();

    var tex = makeTexture();
    defer ray.UnloadRenderTexture(tex);

    //var background = ray.LoadTexture("resources/bg.png");
    //defer ray.UnloadTexture(background);
    //var foreground = ray.LoadTexture("resources/fg.png");
    //defer ray.UnloadTexture(foreground);
    var foreground_img = ray.LoadImageFromMemory(".png", fg_png, fg_png.len);
    var foreground = ray.LoadTextureFromImage(foreground_img);
    var background_img = ray.LoadImageFromMemory(".png", bg_png, bg_png.len);
    var background = ray.LoadTextureFromImage(background_img);

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = &prng.random;

    var looks = Looks{
        .active = .{ .color = ray.LIME, .state = 0 },
        .done = .{ .color = ray.SKYBLUE, .state = 1 },
        .err = .{ .color = ray.RED, .state = 2 },
        .blocked = .{ .color = ray.ORANGE, .state = 3 },
    };

    ray.SetTargetFPS(60);

    const gravity = chip.cpv(0, -100);

    var space = chip.cpSpaceNew() orelse return;
    chip.cpSpaceSetGravity(space, gravity);
    //chip.cpSpaceSetDamping(space, 0.9);

    var static_body = chip.cpSpaceGetStaticBody(space);

    var active_ramp_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(50, 600 - 155), chip.cpv(330, 600 - 200), 10);
    chip.cpShapeSetFriction(active_ramp_shape, 0.5);
    chip.cpShapeSetElasticity(active_ramp_shape, 0.9);
    chip.cpShapeSetFilter(active_ramp_shape, active_ramp_filter);
    _ = chip.cpSpaceAddShape(space, active_ramp_shape);

    var active_farm_l_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(330, 600 - 280), chip.cpv(370, 600 - 320), 8);
    chip.cpShapeSetFriction(active_farm_l_shape, 0.5);
    chip.cpShapeSetElasticity(active_farm_l_shape, 1.0);
    chip.cpShapeSetFilter(active_farm_l_shape, active_ramp_filter);
    _ = chip.cpSpaceAddShape(space, active_farm_l_shape);

    var active_farm_r_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(430, 600 - 320), chip.cpv(470, 600 - 280), 8);
    chip.cpShapeSetFriction(active_farm_r_shape, 0.5);
    chip.cpShapeSetElasticity(active_farm_r_shape, 1.0);
    chip.cpShapeSetFilter(active_farm_r_shape, active_ramp_filter);
    _ = chip.cpSpaceAddShape(space, active_farm_r_shape);

    var ramp_pad_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(50, 600 - 150), chip.cpv(50, 600 - 120), 3);
    chip.cpShapeSetFriction(ramp_pad_shape, 0.5);
    chip.cpShapeSetElasticity(ramp_pad_shape, 0.9);
    chip.cpShapeSetFilter(ramp_pad_shape, .{
        .group = chip.CP_NO_GROUP,
        .categories = active_ramp_mask | blocked_ramp_mask,
        .mask = active_mask | blocked_mask,
    });
    _ = chip.cpSpaceAddShape(space, ramp_pad_shape);

    var blocked_ramp_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(50, 600 - 155), chip.cpv(820, 600 - 278), 10);
    chip.cpShapeSetFriction(blocked_ramp_shape, 0.5);
    chip.cpShapeSetElasticity(blocked_ramp_shape, 0.9);
    chip.cpShapeSetFilter(blocked_ramp_shape, blocked_ramp_filter);
    _ = chip.cpSpaceAddShape(space, blocked_ramp_shape);

    var done_ramp_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(0, 600 - 490), chip.cpv(380, 600 - 422), 10);
    chip.cpShapeSetElasticity(done_ramp_shape, 0.9);
    chip.cpShapeSetFriction(done_ramp_shape, 0.3);
    chip.cpShapeSetFilter(done_ramp_shape, done_filter);
    _ = chip.cpSpaceAddShape(space, done_ramp_shape);

    var done_ramp_pad_shape = chip.cpSegmentShapeNew(static_body, chip.cpv(380, 600 - 420), chip.cpv(380, 600 - 360), 10);
    chip.cpShapeSetElasticity(done_ramp_pad_shape, 0.9);
    chip.cpShapeSetFriction(done_ramp_pad_shape, 0.3);
    chip.cpShapeSetFilter(done_ramp_pad_shape, done_filter);
    _ = chip.cpSpaceAddShape(space, done_ramp_pad_shape);

    const timeStep: f64 = 1.0 / 60.0;

    var ctx: tractor.ThreadContext = .{
        .allocator = allocator,
        .msgs = tractor.Messages{},
        .is_ready = false,
    };
    _ = try tractor.startListener(&ctx);

    _ = spawnNewObjects(space, rand, &looks, &ctx);

    var show_fps = false;
    var hide_fg = false;

    while (!ray.WindowShouldClose()) {
        _ = spawnNewObjects(space, rand, &looks, &ctx);

        chip.cpSpaceStep(space, timeStep);

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        ray.DrawTexture(background, 0, 0, ray.WHITE);

        chip.cpSpaceEachBody(space, drawShapes, &tex.texture);

        if (!hide_fg) {
            ray.DrawTexture(foreground, 0, 0, ray.WHITE);
        }
        if (show_fps) {
            ray.DrawFPS(10, 10);
        }

        ray.EndDrawing();
        if (ray.IsKeyPressed(0x46)) show_fps = !show_fps;
        if (ray.IsKeyPressed(0x48)) hide_fg = !hide_fg;
    }
}
