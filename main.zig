const std = @import("std");
// Import raylib via C import
const ray = @cImport({
    @cInclude("raylib.h");
});

const GRID_SIZE: i32 = 20;
const SCREEN_WIDTH: i32 = 800;
const SCREEN_HEIGHT: i32 = 700;
const COLS: i32 = SCREEN_WIDTH / GRID_SIZE;
const ROWS: i32 = (SCREEN_HEIGHT - 100) / GRID_SIZE;

// Pre-computed direction arrays for BFS (moved outside loop for performance)
const BFS_DIRS = [_]Vec2i{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 1, .y = 0 } };
const POSSIBLE_DIRS = [_]Vec2i{ .{ .x = 0, .y = -1 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = 1, .y = 0 } };

const Vec2i = struct {
    x: i32,
    y: i32,

    pub inline fn equals(self: Vec2i, other: Vec2i) bool {
        return self.x == other.x and self.y == other.y;
    }

    // Inline wrap function using modulo (faster than conditionals)
    pub inline fn wrapped(self: Vec2i) Vec2i {
        return .{
            .x = if (self.x < 0) COLS - 1 else if (self.x >= COLS) 0 else self.x,
            .y = if (self.y < 0) ROWS - 1 else if (self.y >= ROWS) 0 else self.y,
        };
    }
};

/// A robust Circular Buffer (Deque) implementation.
/// head: index of the first element (the worm's head).
/// tail: index of the last element (the worm's tail).
pub fn WormDeque(comptime T: type) type {
    return struct {
        items: []T,
        head: usize,
        tail: usize,
        count: usize,
        capacity: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !@This() {
            const items = try allocator.alloc(T, capacity);
            return .{
                .items = items,
                .head = 0,
                .tail = 0,
                .count = 0,
                .capacity = capacity,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }

        pub inline fn push_front(self: *@This(), item: T) void {
            if (self.count == self.capacity) return;

            if (self.count == 0) {
                self.head = 0;
                self.tail = 0;
            } else {
                if (self.head == 0) {
                    self.head = self.capacity - 1;
                } else {
                    self.head -= 1;
                }
            }

            self.items[self.head] = item;
            self.count += 1;
        }

        pub fn pop_back(self: *@This()) ?T {
            if (self.count == 0) return null;

            const item = self.items[self.tail];
            if (self.count == 1) {
                self.head = 0;
                self.tail = 0;
                self.count = 0;
            } else {
                if (self.tail == 0) {
                    self.tail = self.capacity - 1;
                } else {
                    self.tail -= 1;
                }
                self.count -= 1;
            }
            return item;
        }

        pub inline fn get(self: *@This(), index: usize) T {
            const actual_idx = (self.head + index) & (self.capacity - 1);
            return self.items[actual_idx];
        }

        pub fn clear(self: *@This()) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }
    };
}

pub fn main() !void {
    // Initialize Allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize Window
    ray.InitWindow(@intCast(SCREEN_WIDTH), @intCast(SCREEN_HEIGHT), "Zig Worm Game - Optimized & Autoplay");
    defer ray.CloseWindow();
    ray.SetTargetFPS(60);

    // Game State
    var worm = try WormDeque(Vec2i).init(allocator, 2048);
    defer worm.deinit(allocator);

    // Occupancy Grid for O(1) collision detection
    var grid = [_][COLS]bool{[_]bool{false} ** COLS} ** ROWS;

    const start_segments = [_]Vec2i{ .{ .x = 10, .y = 10 }, .{ .x = 9, .y = 10 }, .{ .x = 8, .y = 10 } };

    const reset_game = struct {
        fn apply(w: *WormDeque(Vec2i), g: *[ROWS][COLS]bool) void {
            w.clear();
            // Clear grid
            for (0..ROWS) |y| {
                for (0..COLS) |x| {
                    g[y][x] = false;
                }
            }
            // To ensure (10,10) is at index 0 (the head), we push the tail segments first.
            // We push 8, then 9, then 10.
            for (0..start_segments.len) |i| {
                const seg = start_segments[start_segments.len - 1 - i];
                w.push_front(seg);
                g[@intCast(seg.y)][@intCast(seg.x)] = true;
            }
        }
    };
    reset_game.apply(&worm, &grid);

    var direction = Vec2i{ .x = 1, .y = 0 };
    var next_direction = direction;

    var food = Vec2i{ .x = 5, .y = 5 };
    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var frame_count: u32 = 0;
    const base_speed: u32 = 8;
    var score: u32 = 0;

    var game_over = false;
    var paused = false;
    var autoplay_enabled = false;
    var score_buf: [32]u8 = undefined;

    // Reusable BFS buffers (avoid allocation every frame)
    var bfs_visited = [_][COLS]u8{[_]u8{0} ** COLS} ** ROWS;
    var bfs_queue: [COLS * ROWS]Vec2i = undefined;
    var bfs_visit_counter: u8 = 1;

    while (!ray.WindowShouldClose()) {
        // 1. Input Handling
        if (ray.IsKeyPressed(ray.KEY_A)) {
            autoplay_enabled = !autoplay_enabled;
        }
        if (ray.IsKeyPressed(ray.KEY_SPACE)) {
            paused = !paused;
        }
        if (ray.IsKeyPressed(ray.KEY_ESCAPE)) {
            break;
        }

        if (paused) {
            // Do nothing
        } else if (autoplay_enabled and !game_over) {
            // Autoplay Logic (Greedy Heuristic)
            const head = worm.get(0);

            var best_dir: ?Vec2i = null;
            var min_dist: i32 = 9999;

            // Cache tail position once (avoid repeated worm.get calls)
            const tail_idx = worm.count - 1;
            const tail_pos = if (worm.count > 0) worm.get(tail_idx) else Vec2i{ .x = 0, .y = 0 };

            for (POSSIBLE_DIRS) |d| {
                // 1. Avoid 180 degree turns
                if (d.x == -direction.x and d.y == -direction.y) continue;

                // 2. Calculate potential new head with inline wrap
                const new_pos = (Vec2i{ .x = head.x + d.x, .y = head.y + d.y }).wrapped();
                const nx = new_pos.x;
                const ny = new_pos.y;

                // 3. Check if valid move (doesn't hit self)
                if (!grid[@intCast(ny)][@intCast(nx)]) {
                    // Flood-fill to check for reachability (reuse global buffers)
                    var reachable: i32 = 0;
                    var q_head: usize = 0;
                    var q_tail: usize = 0;
                    bfs_visit_counter +%= 1;

                    bfs_queue[q_tail] = Vec2i{ .x = nx, .y = ny };
                    q_tail += 1;
                    bfs_visited[@intCast(ny)][@intCast(nx)] = bfs_visit_counter;

                    while (q_head < q_tail) {
                        const curr = bfs_queue[q_head];
                        q_head += 1;
                        reachable += 1;

                        // Early exit: if we've found enough space, stop searching
                        if (reachable > worm.count) break;

                        // Use pre-computed BFS_DIRS (moved outside loop)
                        for (BFS_DIRS) |cd| {
                            const next = (Vec2i{ .x = curr.x + cd.x, .y = curr.y + cd.y }).wrapped();
                            const cx = next.x;
                            const cy = next.y;

                            // Treat the tail as a safe spot because it will move (use cached tail_pos)
                            const is_tail = (cx == tail_pos.x and cy == tail_pos.y);
                            if ((!grid[@intCast(cy)][@intCast(cx)] or is_tail) and bfs_visited[@intCast(cy)][@intCast(cx)] != bfs_visit_counter) {
                                bfs_visited[@intCast(cy)][@intCast(cx)] = bfs_visit_counter;
                                bfs_queue[q_tail] = Vec2i{ .x = cx, .y = cy };
                                q_tail += 1;
                            }
                        }
                    }

                    // Only consider moves that provide enough space to move
                    if (reachable >= worm.count) {
                        const dist: i32 = @intCast(@abs(food.x - nx) + @abs(food.y - ny));
                        if (dist < min_dist) {
                            min_dist = dist;
                            best_dir = d;
                        }
                    } else if (best_dir == null) {
                        // Fallback: if no "safe" move found, pick the one with most reachability
                        if (reachable > 0) {
                            best_dir = d;
                        }
                    }
                }
            }

            if (best_dir) |bd| {
                next_direction = bd;
            }
        } else if (!game_over and !paused) {
            // Manual Input Handling
            if (ray.IsKeyPressed(ray.KEY_UP)) {
                if (direction.y == 0) next_direction = Vec2i{ .x = 0, .y = -1 };
            } else if (ray.IsKeyPressed(ray.KEY_DOWN)) {
                if (direction.y == 0) next_direction = Vec2i{ .x = 0, .y = 1 };
            } else if (ray.IsKeyPressed(ray.KEY_LEFT)) {
                if (direction.x == 0) next_direction = Vec2i{ .x = -1, .y = 0 };
            } else if (ray.IsKeyPressed(ray.KEY_RIGHT)) {
                if (direction.x == 0) next_direction = Vec2i{ .x = 1, .y = 0 };
            }
        }

        if (game_over) {
            if (ray.IsKeyPressed(ray.KEY_R)) {
                reset_game.apply(&worm, &grid);
                direction = Vec2i{ .x = 1, .y = 0 };
                next_direction = direction;
                score = 0;
                game_over = false;
            }
        } else if (!paused) {
            // 2. Update Logic
            const speed = @max(2, @as(i32, @intCast(base_speed)) - @as(i32, @intCast(score / 20)));
            frame_count += 1;
            if (frame_count >= @as(u32, @intCast(speed))) {
                direction = next_direction;
                frame_count = 0;

                const current_head = worm.get(0);
                const new_head = (Vec2i{
                    .x = current_head.x + direction.x,
                    .y = current_head.y + direction.y,
                }).wrapped();

                // Check Collision: Self (O(1) using grid)
                if (grid[@intCast(new_head.y)][@intCast(new_head.x)]) {
                    game_over = true;
                } else {
                    // Check Collision: Food
                    if (new_head.equals(food)) {
                        // Grow: Add new head, don't remove tail
                        worm.push_front(new_head);
                        grid[@intCast(new_head.y)][@intCast(new_head.x)] = true;

                        const speed_multiplier = 10;
                        score += @as(u32, @intCast(speed_multiplier));

                        food.x = random.intRangeLessThan(i32, 0, COLS);
                        food.y = random.intRangeLessThan(i32, 0, ROWS);
                        while (grid[@intCast(food.y)][@intCast(food.x)]) {
                            food.x = random.intRangeLessThan(i32, 0, COLS);
                            food.y = random.intRangeLessThan(i32, 0, ROWS);
                        }
                    } else {
                        // Normal move: Add new head, remove tail
                        worm.push_front(new_head);
                        grid[@intCast(new_head.y)][@intCast(new_head.x)] = true;

                        if (worm.pop_back()) |tail| {
                            grid[@intCast(tail.y)][@intCast(tail.x)] = false;
                        }
                    }
                }
            }
        }

        // 3. Drawing
        ray.BeginDrawing();
        defer ray.EndDrawing();
        ray.ClearBackground(ray.RAYWHITE);

        if (game_over) {
            ray.DrawText("GAME OVER!", @intCast(SCREEN_WIDTH / 4), @intCast(SCREEN_HEIGHT / 2 - 40), 40, ray.RED);
            const final_score_text = std.fmt.bufPrintZ(&score_buf, "Final Score: {d}", .{score}) catch "Score: Error";
            ray.DrawText(final_score_text.ptr, @intCast(SCREEN_WIDTH / 4), @intCast(SCREEN_HEIGHT / 2 + 10), 20, ray.DARKGRAY);
            ray.DrawText("Press 'R' to Restart", @intCast(SCREEN_WIDTH / 4), @intCast(SCREEN_HEIGHT / 2 + 40), 20, ray.DARKGRAY);
        } else if (paused) {
            ray.DrawText("PAUSED", @intCast(SCREEN_WIDTH / 2 - 50), @intCast(SCREEN_HEIGHT / 2 - 20), 40, ray.YELLOW);
        } else {
            // Draw Food
            ray.DrawRectangle(
                @intCast(food.x * GRID_SIZE),
                @intCast(food.y * GRID_SIZE),
                @intCast(GRID_SIZE),
                @intCast(GRID_SIZE),
                ray.RED,
            );

            // Draw Worm (batch by color for better performance)
            if (worm.count > 0) {
                // Draw head first
                const head = worm.get(0);
                ray.DrawRectangle(
                    @intCast(head.x * GRID_SIZE),
                    @intCast(head.y * GRID_SIZE),
                    @intCast(GRID_SIZE),
                    @intCast(GRID_SIZE),
                    ray.DARKGREEN,
                );
                // Draw body segments in batch (all same color)
                var i: usize = 1;
                while (i < worm.count) : (i += 1) {
                    const segment = worm.get(i);
                    ray.DrawRectangle(
                        @intCast(segment.x * GRID_SIZE),
                        @intCast(segment.y * GRID_SIZE),
                        @intCast(GRID_SIZE),
                        @intCast(GRID_SIZE),
                        ray.GREEN,
                    );
                }
            }

            // Draw UI Panel
            ray.DrawRectangle(0, SCREEN_HEIGHT - 100, SCREEN_WIDTH, 100, ray.LIGHTGRAY);
            ray.DrawText("Use Arrow Keys to Move", 10, SCREEN_HEIGHT - 90, 20, ray.DARKGRAY);
            if (autoplay_enabled) {
                ray.DrawText("AUTOPLAY: ON (Press 'A' to toggle)", 10, SCREEN_HEIGHT - 65, 20, ray.BLUE);
            } else {
                ray.DrawText("AUTOPLAY: OFF (Press 'A' to toggle)", 10, SCREEN_HEIGHT - 65, 20, ray.DARKGRAY);
            }
            ray.DrawText("Press 'Space' to Pause, 'ESC' to Quit", 10, SCREEN_HEIGHT - 40, 20, ray.DARKGRAY);
            const score_text = std.fmt.bufPrintZ(&score_buf, "Score: {d}", .{score}) catch "Score: Error";
            ray.DrawText(score_text.ptr, 400, SCREEN_HEIGHT - 90, 20, ray.BLACK);
        }

        ray.DrawFPS(SCREEN_WIDTH - 100, SCREEN_HEIGHT - 30);
    }
}
