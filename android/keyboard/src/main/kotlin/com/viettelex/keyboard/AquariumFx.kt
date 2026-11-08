package com.viettelex.keyboard

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Theme "Bể cá" (11/2026, Plus): hiệu ứng "Cho cá ăn" (id fishfeed) + cảnh bể (motif "aquarium" — [ThemeScene]).
// Hàm thuần song sinh iOS/Keyboard/AquariumFx.swift — CÙNG SỐ (test chéo hai nền tảng). Toạ độ dp.
//  • 3…6 chú cá vector bơi chậm SAU hàng phím; mỗi phím thả một viên thức ăn tại phím, viên chìm dần; chú cá RẢNH gần nhất
//    (hết rảnh ⇒ gần nhất) lái tới ăn.
//  • Tổng số viên đã ăn (bộ đếm theo máy, "aquariumFood") ⇒ cá lớn dần (trần +30 %); mỗi 500 viên thêm một chú (trần 6).
//    Ghi tối đa mỗi 5 s + lúc ẩn bàn phím ([PersistGate]).
//  • Mô phỏng chỉ khi đang gõ; nghỉ 3 s ⇒ dừng hẳn (không hẹn khung hình). Mảng cố định — không cấp phát mỗi khung.
object AquariumFx {
    const val BASE_FISH = 3
    const val MAX_FISH = 6
    const val PELLETS_PER_FISH = 500
    const val GROWTH_CAP = 1500.0
    const val GROWTH_MAX = 0.3
    const val FISH_LENGTH = 20.0
    const val FISH_HEIGHT = 10.0
    const val MAX_SPEED = 46.0
    const val WANDER_SPEED = 14.0
    const val MAX_FORCE = 90.0
    const val ARRIVE_RADIUS = 24.0
    const val EAT_RADIUS = 7.0
    const val SINK_SPEED = 22.0
    const val PELLET_RADIUS = 2.0
    const val PELLET_LIFE = 6.0
    const val MAX_PELLETS = 8
    const val PELLET_SWAY = 1.5
    const val IDLE_AFTER = 3.0
    const val PERSIST_INTERVAL = 5.0
    const val TICK = 1.0 / 30
    const val SAND_HEIGHT = 10.0
    const val MARGIN = 12.0
    const val WAYPOINT_REACH = 6.0
    const val STORAGE_KEY = "aquariumFood"
    val SIZE_FACTORS = doubleArrayOf(1.0, 0.85, 1.1, 0.9, 1.05, 0.95)
    val COLORS = intArrayOf(0xFF8C42, 0xFFD23F, 0x4FC3F7, 0xF06292, 0x9CCC65, 0xFFF3E0)
    const val PELLET_COLOR = 0xC8843A

    fun fishCount(eaten: Int): Int = min(MAX_FISH, BASE_FISH + max(eaten, 0) / PELLETS_PER_FISH)
    fun growth(eaten: Int): Double = 1 + GROWTH_MAX * min(max(eaten, 0).toDouble(), GROWTH_CAP) / GROWTH_CAP

    data class Region(val minX: Double, val minY: Double, val maxX: Double, val maxY: Double)

    /** Vùng bơi: dưới 1/4 trên (thanh gợi ý), trên lớp cát, chừa lề. */
    fun region(minX: Double, top: Double, width: Double, height: Double): Region =
        Region(minX + MARGIN, top + height * 0.25, minX + width - MARGIN, max(top + height * 0.25 + 1, top + height - SAND_HEIGHT - 6))

    /** Đáy viên thức ăn chìm tới = đáy vùng bơi (ngay trên cát — cá luôn với tới). */
    fun floorY(r: Region): Double = r.maxY

    data class Fish(
        var x: Double, var y: Double, var vx: Double = 0.0, var vy: Double = 0.0,
        var target: Int = -1, var wx: Double, var wy: Double, var seed: Int, var hop: Int = 0,
    )

    data class Pellet(var x0: Double = 0.0, var x: Double = 0.0, var y: Double = 0.0, var age: Double = 0.0, var alive: Boolean = false)

    /** Điểm lượn thứ [k] của cá [seed] trong vùng (tất định). */
    fun waypoint(seed: Int, k: Int, r: Region): Pair<Double, Double> {
        val s = fxStep(fxStep(fxSeed(seed * 977 + k * 131 + 17)))
        val t = fxStep(fxStep(s))
        return Pair(r.minX + (r.maxX - r.minX) * fxValue(s), r.minY + (r.maxY - r.minY) * fxValue(t))
    }

    /** Một bước lái tới (tx, ty) — iOS AquariumFx.steer y hệt (trả bản sao mới; World dùng [steerInPlace]). */
    fun steer(f: Fish, tx: Double, ty: Double, dt: Double, limit: Double, arrive: Boolean, r: Region): Fish =
        f.copy().also { steerInPlace(it, tx, ty, dt, limit, arrive, r) }

    /** Như [steer] nhưng sửa thẳng [f] (không cấp phát mỗi khung). */
    fun steerInPlace(f: Fish, tx: Double, ty: Double, dt: Double, limit: Double, arrive: Boolean, r: Region) {
        val dx = tx - f.x; val dy = ty - f.y; val d = hypot(dx, dy)
        val speed = if (arrive && d < ARRIVE_RADIUS) limit * max(d / ARRIVE_RADIUS, 0.25) else limit
        val ex = if (d > 1e-6) dx / d * speed else 0.0
        val ey = if (d > 1e-6) dy / d * speed else 0.0
        var ax = ex - f.vx; var ay = ey - f.vy
        val a = hypot(ax, ay); val amax = MAX_FORCE * dt
        if (a > amax) { ax *= amax / a; ay *= amax / a }
        val ox = f.x; val oy = f.y
        f.vx += ax; f.vy += ay
        val v = hypot(f.vx, f.vy)
        if (v > limit) { f.vx *= limit / v; f.vy *= limit / v }
        f.x = min(max(ox + f.vx * dt, r.minX), r.maxX)
        f.y = min(max(oy + f.vy * dt, r.minY), r.maxY)
    }

    /** Chú cá đi ăn viên ở (px, py): cá rảnh gần nhất; không ai rảnh ⇒ gần nhất. Rỗng ⇒ −1. */
    fun nearestFish(fish: List<Fish>, count: Int, px: Double, py: Double): Int {
        var best = -1; var bestD = Double.POSITIVE_INFINITY; var bestFree = -1; var bestFreeD = Double.POSITIVE_INFINITY
        for (i in 0 until min(count, fish.size)) {
            val d = hypot(fish[i].x - px, fish[i].y - py)
            if (d < bestD) { bestD = d; best = i }
            if (fish[i].target < 0 && d < bestFreeD) { bestFreeD = d; bestFree = i }
        }
        return if (bestFree >= 0) bestFree else best
    }

    /** Viên thức ăn sau [dt]: chìm tới [floor], lắc ngang nhẹ, già đi; quá [PELLET_LIFE] ⇒ tan. */
    fun sink(p: Pellet, dt: Double, floor: Double): Pellet = p.copy().also { sinkInPlace(it, dt, floor) }

    fun sinkInPlace(p: Pellet, dt: Double, floor: Double) {
        if (!p.alive) return
        p.age += dt
        p.y = min(p.y + SINK_SPEED * dt, floor)
        p.x = p.x0 + PELLET_SWAY * sin(2 * Math.PI * 0.8 * p.age)
        if (p.age >= PELLET_LIFE) p.alive = false
    }

    fun eats(f: Fish, p: Pellet, scale: Double): Boolean = p.alive && hypot(f.x - p.x, f.y - p.y) <= EAT_RADIUS * scale

    /** Ghi bộ đếm: tối đa mỗi [PERSIST_INTERVAL] giây khi có thay đổi; [flush] (ẩn bàn phím) ghi ngay nếu còn bẩn. */
    class PersistGate {
        var lastSave = -Double.MAX_VALUE
            private set
        var dirty = false
            private set
        fun note() { dirty = true }
        fun shouldSave(now: Double): Boolean {
            if (!dirty || now - lastSave < PERSIST_INTERVAL) return false
            lastSave = now; dirty = false
            return true
        }
        fun flush(now: Double): Boolean {
            if (!dirty) return false
            lastSave = now; dirty = false
            return true
        }
    }

    /** Thế giới bể cá (thuần, mảng cố định). [eaten] = tổng đã ăn (cả từ lần trước, nạp từ bộ nhớ). */
    class World(eaten: Int, minX: Double, top: Double, width: Double, height: Double) {
        val fish = ArrayList<Fish>(MAX_FISH)
        val pellets = Array(MAX_PELLETS) { Pellet() }
        var eaten: Int = max(eaten, 0)
            private set
        val region: Region = region(minX, top, width, height)
        val floor: Double = floorY(region)
        private var cursor = 0

        init { ensureFish() }

        val count: Int get() = fish.size
        val scale: Double get() = growth(eaten)
        fun scale(i: Int): Double = scale * SIZE_FACTORS[i % SIZE_FACTORS.size]

        /** Thêm cá tới đủ fishCount(eaten): chú mới xuất phát ở điểm lượn 0 của mình. */
        fun ensureFish() {
            while (fish.size < fishCount(eaten)) {
                val i = fish.size
                val p = waypoint(i, 0, region)
                val w = waypoint(i, 1, region)
                fish.add(Fish(x = p.first, y = p.second, wx = w.first, wy = w.second, seed = i, hop = 1))
            }
        }

        /** Thả viên tại (x, y) — kẹp vào vùng ngang; giao cho chú cá gần nhất. Trả chỉ số viên. */
        fun drop(x: Double, y: Double): Int {
            val k = cursor
            cursor = (cursor + 1) % pellets.size
            for (f in fish) if (f.target == k) f.target = -1   // viên cũ bị thay
            val px = min(max(x, region.minX), region.maxX)
            val p = pellets[k]
            p.x0 = px; p.x = px; p.y = min(y, floor); p.age = 0.0; p.alive = true
            val f = nearestFish(fish, fish.size, px, p.y)
            if (f >= 0) fish[f].target = k
            return k
        }

        /** Một bước mô phỏng — trả số viên vừa ăn. */
        fun step(dt: Double): Int {
            for (p in pellets) if (p.alive) sinkInPlace(p, dt, floor)
            var ate = 0
            for (i in fish.indices) {
                val f = fish[i]
                val t = f.target
                if (t >= 0 && pellets[t].alive) {
                    // Đuổi viên đang chìm: KHÔNG chậm lại khi tới gần (viên chìm 22 dp/s — chậm lại thì không bắt kịp).
                    steerInPlace(f, pellets[t].x, pellets[t].y, dt, MAX_SPEED, false, region)
                    if (eats(f, pellets[t], scale(i))) {
                        pellets[t].alive = false
                        f.target = -1
                        ate++
                    }
                } else {
                    f.target = -1
                    steerInPlace(f, f.wx, f.wy, dt, WANDER_SPEED, true, region)
                    if (hypot(f.wx - f.x, f.wy - f.y) < WAYPOINT_REACH) {
                        f.hop++
                        val w = waypoint(f.seed, f.hop, region)
                        f.wx = w.first; f.wy = w.second
                    }
                }
            }
            // Viên khác bị ăn ké (cá đi ngang qua) — cũng tính.
            for (i in fish.indices) {
                for (k in pellets.indices) {
                    if (eats(fish[i], pellets[k], scale(i))) {
                        pellets[k].alive = false
                        ate++
                        for (j in fish.indices) if (fish[j].target == k) fish[j].target = -1
                    }
                }
            }
            if (ate > 0) { eaten += ate; ensureFish() }
            return ate
        }

        /** Cá quay mặt sang trái (lật hình) khi vận tốc ngang âm rõ rệt. */
        fun facesLeft(i: Int): Boolean = fish[i].vx < -0.5
    }
}

/** Cảnh bể (motif "aquarium"): vệt nắng xiên, lớp cát lượn ở đáy, rong — iOS AquariumScene y hệt (dp). */
object AquariumScene {
    const val RAY_COUNT = 4
    const val SAND_HEIGHT = AquariumFx.SAND_HEIGHT
    const val SAND_COLOR = 0xC9B07A
    const val SAND_ALPHA = 0.55
    const val WEED_COLOR = 0x2F8F5B
    const val WEED_ALPHA = 0.6
    const val WEED_WIDTH = 3.0
    val WEED_X = doubleArrayOf(0.06, 0.19, 0.37, 0.58, 0.81, 0.94)
    val WEED_H = doubleArrayOf(30.0, 22.0, 36.0, 26.0, 38.0, 24.0)

    /** Vệt nắng: tứ giác (4 điểm) từ mép trên xiên xuống 75 % chiều cao. */
    fun rays(w: Double, h: Double): List<List<Pair<Double, Double>>> = (0 until RAY_COUNT).map { i ->
        val x0 = w * (0.12 + 0.24 * i); val rw = w * 0.07; val skew = w * 0.1
        listOf(Pair(x0, 0.0), Pair(x0 + rw, 0.0), Pair(min(x0 + rw + skew, w), h * 0.75), Pair(min(x0 + skew, w), h * 0.75))
    }

    /** Mép trên lớp cát (điểm cách 8 dp) — lượn nhẹ. */
    fun sandTop(w: Double, h: Double): List<Pair<Double, Double>> {
        val out = ArrayList<Pair<Double, Double>>()
        var x = 0.0
        while (x <= w) { out.add(Pair(x, h - SAND_HEIGHT + 2 * sin(x / 37))); x += 8.0 }
        if (out.lastOrNull()?.first != w) out.add(Pair(w, h - SAND_HEIGHT + 2 * sin(w / 37)))
        return out
    }

    /** Rong: gốc (x0, y0) → điểm điều khiển (cx, cy) → ngọn (x1, y1) — mảng 6 số. */
    fun weeds(w: Double, h: Double): List<DoubleArray> = WEED_X.indices.map { i ->
        val x = w * WEED_X[i]; val y0 = h - 3; val hh = min(WEED_H[i], h * 0.4)
        val lean = if (i % 2 == 0) 5.0 else -5.0
        doubleArrayOf(x, y0, x - lean, y0 - hh * 0.5, x + lean * 0.6, y0 - hh)
    }
}
