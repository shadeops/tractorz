const std = @import("std");
const tractor = @import("tractor.zig");

const clibs = @import("clibs.zig");
const ray = clibs.ray;
const chip = clibs.chipmunk;

fn makeTexture() ray.RenderTexture2D {

    var tex = ray.LoadRenderTexture(4,4);
    ray.BeginTextureMode(tex);
    ray.ClearBackground(ray.BLACK);
    ray.DrawCircle(2,2,2.0, ray.WHITE);
    ray.EndTextureMode();

    return tex;
}

pub fn main() anyerror!void {

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    //try tractor.fetchURL();
    //try tractor.runnin();

    try vis();

    return;

}

fn spawnNewObjects(space: *chip.cpSpace, rand: *std.rand.Random, ctx: *tractor.ThreadContext) u32 {

    if (!@atomicLoad(bool, &ctx.is_ready, .SeqCst)) {
        return 0;
    }
    
    var count = @atomicRmw(u32, &ctx.count, .Xchg, 0, .SeqCst);
    @atomicStore(bool, &ctx.is_ready, false, .SeqCst);

    std.debug.print("{}\n", .{count});
    
    const radius: f64 = 2;
    const mass: f64 = 1;
    var moment = chip.cpMomentForCircle(mass, 0, radius, chip.cpvzero);

    var i: usize = 0;
    while (i < count) : (i+=1) {

        var x_pos = @intToFloat(f64, rand.uintLessThan(u32, 800));
        var y_pos = @intToFloat(f64, rand.uintLessThan(u32, 30));

        var body = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(body, chip.cpv(x_pos, 610+y_pos));
    
        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(body, radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.7);
        chip.cpShapeSetElasticity(shape, 0.2);
    }

    return count;
}

fn cullShape(space: ?*chip.cpSpace, shape: ?* c_void, data: ?* c_void) callconv(.C) void {
    chip.cpSpaceRemoveShape(space, @ptrCast(* chip.cpShape, shape));
    chip.cpShapeFree(@ptrCast(* chip.cpShape, shape));
}

fn cullBody(space: ?*chip.cpSpace, body: ?* c_void, data: ?* c_void) callconv(.C) void {
    chip.cpSpaceRemoveBody(space, @ptrCast(* chip.cpBody, body));
    chip.cpBodyFree(@ptrCast(* chip.cpBody, body));
}

fn postCullShapeWrapper(body: ?*chip.cpBody, shape: ?* chip.cpShape, data: ?* c_void)  callconv(.C) void {
    var space = chip.cpBodyGetSpace(body);
    var success = chip.cpSpaceAddPostStepCallback(space, cullShape, shape, null);
}

fn drawShapes(body: ?* chip.cpBody, data: ?* c_void) callconv(.C) void {
    var pos = chip.cpBodyGetPosition(body);
    var space = chip.cpBodyGetSpace(body);
    if ( pos.y < -10 ) {
        chip.cpBodyEachShape(body, postCullShapeWrapper, null);
        var success = chip.cpSpaceAddPostStepCallback(space, cullBody, body, null);
    }

    var tex: *ray.Texture = @ptrCast(* ray.Texture, @alignCast(4, data));
    ray.DrawTexture(tex.*, @floatToInt(i32, pos.x), 600-@floatToInt(i32,pos.y), ray.RED);
}

fn vis() !void {

    ray.InitWindow(800, 600, "tractorz");
    defer ray.CloseWindow();
    
    var tex = makeTexture();
    defer ray.UnloadRenderTexture(tex);

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = &prng.random;

    ray.SetTargetFPS(60);

    const gravity = chip.cpv(0, -100);
  
    var space = chip.cpSpaceNew() orelse return;
    chip.cpSpaceSetGravity(space, gravity);
    chip.cpSpaceSetDamping(space, 0.9);
 
    var ground = chip.cpSpaceGetStaticBody(space);
    var ground_shape_a = chip.cpSegmentShapeNew(ground, chip.cpv(-20, 300), chip.cpv(450, 100), 10);
    var ground_shape_b = chip.cpSegmentShapeNew(ground, chip.cpv(350, 0), chip.cpv(820, 200), 10);
    chip.cpShapeSetFriction(ground_shape_a, 1);
    chip.cpShapeSetFriction(ground_shape_b, 1);
    chip.cpShapeSetElasticity(ground_shape_a, 0.9);
    chip.cpShapeSetElasticity(ground_shape_b, 0.9);
    
    _ = chip.cpSpaceAddShape(space, ground_shape_a);
    _ = chip.cpSpaceAddShape(space, ground_shape_b);
  
    const timeStep: f64 = 1.0/60.0;
    
    var ctx: tractor.ThreadContext = .{
        .count = 0,
        .is_ready = false,
    };
    var thread = try tractor.startListener(&ctx);

    _ = spawnNewObjects(space, rand, &ctx);

    var i: u32 = 0;

    while (!ray.WindowShouldClose()) {
        
        _ = spawnNewObjects(space, rand, &ctx);

        chip.cpSpaceStep(space, timeStep);

        chip.cpSpaceEachBody(space, drawShapes, &tex.texture); 
        
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
    
        i = 0;
        //for (balls) |ball| {
        //    if (i>50 and removed) break;
        //    pos = chip.cpBodyGetPosition(ball);
        //    ray.DrawTexture(tex.texture, @floatToInt(i32, pos.x), 600-@floatToInt(i32,pos.y), ray.RED);
        //    i+=1;
        //}

        ray.DrawFPS(10,10);

        ray.EndDrawing();

        //while (i<100) : ( i+=1 ) {
        //    chip.cpSpaceRemoveShape(space, ball_shapes[i]);
        //    chip.cpSpaceRemoveBody(space, balls[i]);
        //}

    }

}
