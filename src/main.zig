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
  
    var space = chip.cpSpaceNew();
    chip.cpSpaceSetGravity(space, gravity);
 
    var ground = chip.cpSpaceGetStaticBody(space);
    var ground_shape_a = chip.cpSegmentShapeNew(ground, chip.cpv(-20, 300), chip.cpv(450, 100), 10);
    var ground_shape_b = chip.cpSegmentShapeNew(ground, chip.cpv(350, 0), chip.cpv(820, 200), 10);
    chip.cpShapeSetFriction(ground_shape_a, 1);
    chip.cpShapeSetFriction(ground_shape_b, 1);
    chip.cpShapeSetElasticity(ground_shape_a, 0.9);
    chip.cpShapeSetElasticity(ground_shape_b, 0.9);
    
    _ = chip.cpSpaceAddShape(space, ground_shape_a);
    _ = chip.cpSpaceAddShape(space, ground_shape_b);
  
    const radius: f64 = 2;
    const mass: f64 = 1;
  
    var moment = chip.cpMomentForCircle(mass, 0, radius, chip.cpvzero);
 
    var balls: [100] *chip.cpBody = undefined;
    var ball_shapes: [100] *chip.cpShape = undefined;
    var inc: f32 = 10;

    var i: usize = 0;
    while (i < 100) : (i+=1) {
        balls[i] = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment)) orelse unreachable;
        chip.cpBodySetPosition(balls[i], chip.cpv(@intToFloat(f32,i*8), 600));
    
        var shape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(balls[i], radius, chip.cpvzero));
        chip.cpShapeSetFriction(shape, 0.7);
        chip.cpShapeSetElasticity(shape, 0.2);
        ball_shapes[i] = shape orelse unreachable;
    }

    var ballBody = chip.cpSpaceAddBody(space, chip.cpBodyNew(mass, moment));
    chip.cpBodySetPosition(ballBody, chip.cpv(300, 600));
  
    var ballShape = chip.cpSpaceAddShape(space, chip.cpCircleShapeNew(ballBody, radius, chip.cpvzero));
    chip.cpShapeSetFriction(ballShape, 0.7);
    chip.cpShapeSetElasticity(ballShape, 1);
    chip.cpSpaceSetDamping(space, 0.9);

    var timeStep: f64 = 1.0/60.0;

    var removed = false;
    while (!ray.WindowShouldClose()) {
        var pos = chip.cpBodyGetPosition(ballBody);

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);

        ray.DrawTexture(tex.texture, @floatToInt(i32, pos.x), 600-@floatToInt(i32,pos.y), ray.WHITE);
      
        i = 0;
        for (balls) |ball| {
            if (i>50 and removed) break;
            pos = chip.cpBodyGetPosition(ball);
            ray.DrawTexture(tex.texture, @floatToInt(i32, pos.x), 600-@floatToInt(i32,pos.y), ray.RED);
            i+=1;
        }

        ray.DrawFPS(10,10);

        ray.EndDrawing();

        if ( ray.GetTime() > 10.0 and !removed) {
            removed = true;
            i = 50;
            while (i<100) : ( i+=1 ) {
                chip.cpSpaceRemoveShape(space, ball_shapes[i]);
                chip.cpSpaceRemoveBody(space, balls[i]);
            }
        } 

        chip.cpSpaceStep(space, timeStep);
    }

}
