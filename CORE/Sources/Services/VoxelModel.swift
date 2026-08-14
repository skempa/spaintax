import UIKit

/// Voxel extraction: turns the player's 2D drawing into a solid 3D voxel
/// model. Same algorithm as the web prototype, so creatures look identical
/// across both:
///
///  1. Rasterise the drawing onto an N×N grid.
///  2. Flood-fill from the border — cells unreachable from outside are
///     interior, so a plain outline becomes a solid body.
///  3. Interior cells take the colour of the nearest drawn cell, softened.
///  4. A distance transform inflates depth: cells deep inside the
///     silhouette grow thicker, giving a puffy, rounded 3D form.
struct VoxelCell {
    var x: Int
    var y: Int
    /// Half-thickness of this column in grid units (world = × cellSize).
    var halfDepth: Float
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

struct VoxelGrid {
    var n: Int
    var cells: [VoxelCell]
    var minX: Int, maxX: Int, minY: Int, maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

enum VoxelExtractor {

    // MARK: - Drawing → voxels

    static func fromDrawing(_ image: UIImage, gridSize n: Int = 36) -> VoxelGrid? {
        guard let cg = image.cgImage,
              let ctx = CGContext(
                data: nil, width: n, height: n,
                bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        ctx.interpolationQuality = .medium
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let scale = min(CGFloat(n) / iw, CGFloat(n) / ih) * 0.94
        let dw = iw * scale, dh = ih * scale
        ctx.draw(cg, in: CGRect(x: (CGFloat(n) - dw) / 2, y: (CGFloat(n) - dh) / 2, width: dw, height: dh))
        guard let raw = ctx.data else { return nil }
        let px = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)

        var drawn = [Bool](repeating: false, count: n * n)
        var color = [SIMD3<Float>?](repeating: nil, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                // CGContext rows are bottom-up; flip so grid matches the drawing.
                let i = ((n - 1 - y) * n + x) * 4
                let a = Float(px[i + 3])
                guard a > 60 else { continue }
                let idx = y * n + x
                drawn[idx] = true
                // Un-premultiply.
                let inv = 255.0 / max(a, 1)
                color[idx] = SIMD3(min(Float(px[i]) * inv, 255),
                                   min(Float(px[i + 1]) * inv, 255),
                                   min(Float(px[i + 2]) * inv, 255))
            }
        }

        // Flood-fill exterior.
        var outside = [Bool](repeating: false, count: n * n)
        var stack: [(Int, Int)] = []
        for i in 0..<n { stack.append((i, 0)); stack.append((i, n - 1)); stack.append((0, i)); stack.append((n - 1, i)) }
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < n, y < n else { continue }
            let idx = y * n + x
            if outside[idx] || drawn[idx] { continue }
            outside[idx] = true
            stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
        }

        var solid = [Bool](repeating: false, count: n * n)
        var any = false
        for i in 0..<(n * n) where drawn[i] || !outside[i] { solid[i] = true; any = true }
        guard any else { return nil }

        // Interior colour = nearest drawn colour (multi-source BFS), softened.
        var frontier: [Int] = (0..<(n * n)).filter { drawn[$0] }
        var seen = drawn
        while !frontier.isEmpty {
            var next: [Int] = []
            for idx in frontier {
                let x = idx % n, y = idx / n
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                    let n2 = ny * n + nx
                    guard !seen[n2], solid[n2] else { continue }
                    seen[n2] = true
                    if let c = color[idx] {
                        color[n2] = SIMD3(min(c.x * 0.92 + 22, 255), min(c.y * 0.92 + 22, 255), min(c.z * 0.92 + 22, 255))
                    }
                    next.append(n2)
                }
            }
            frontier = next
        }

        // Distance transform from the silhouette edge.
        var dist = [Int](repeating: 0, count: n * n)
        var edgeSeen = [Bool](repeating: false, count: n * n)
        frontier = []
        for idx in 0..<(n * n) where solid[idx] {
            let x = idx % n, y = idx / n
            let isEdge = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].contains { (nx, ny) in
                nx < 0 || ny < 0 || nx >= n || ny >= n || !solid[ny * n + nx]
            }
            if isEdge { frontier.append(idx); edgeSeen[idx] = true; dist[idx] = 1 }
        }
        var d = 1
        while !frontier.isEmpty {
            d += 1
            var next: [Int] = []
            for idx in frontier {
                let x = idx % n, y = idx / n
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                    let n2 = ny * n + nx
                    guard solid[n2], !edgeSeen[n2] else { continue }
                    edgeSeen[n2] = true; dist[n2] = d; next.append(n2)
                }
            }
            frontier = next
        }

        var cells: [VoxelCell] = []
        var minX = n, maxX = 0, minY = n, maxY = 0
        for idx in 0..<(n * n) where solid[idx] {
            let x = idx % n, y = idx / n
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            let c = color[idx] ?? SIMD3(200, 200, 210)
            cells.append(VoxelCell(
                x: x, y: y,
                halfDepth: max(0.8, sqrt(Float(dist[idx])) * 1.4),
                r: UInt8(c.x), g: UInt8(c.y), b: UInt8(c.z)
            ))
        }
        return VoxelGrid(n: n, cells: cells, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    // MARK: - Enemy blobs

    /// Procedural voxel blob for an enemy kind (deterministic per kind).
    static func enemyBlob(for kind: EnemyKind) -> VoxelGrid {
        let radius = kind == .shrineWarden ? 8 : 6
        let n = radius * 2 + 1
        let palette = palette(for: kind)
        var rng = Mulberry(seed: UInt32(kind.rawValue.count * 1013 + kind.baseHealth))
        var cells: [VoxelCell] = []
        var minX = n, maxX = 0, minY = n, maxY = 0

        for y in -radius...radius {
            for x in -radius...radius {
                let fx = Float(x) / Float(radius)
                let fy = Float(y) / (Float(radius) * (kind == .shrineWarden ? 1.15 : 0.9))
                let wobble = 0.16 * sin(Float(x) * 1.7 + Float(y) * 2.3) + (rng.next() - 0.5) * 0.1
                guard fx * fx + fy * fy + wobble < 0.86 else { continue }
                let base = palette[min(1, Int(rng.next() * 2))]
                let gx = x + radius, gy = y + radius
                minX = min(minX, gx); maxX = max(maxX, gx)
                minY = min(minY, gy); maxY = max(maxY, gy)
                cells.append(VoxelCell(
                    x: gx, y: gy,
                    halfDepth: max(0.8, sqrt(max(0, 0.86 - (fx * fx + fy * fy))) * Float(radius) * 0.45),
                    r: base.0, g: base.1, b: base.2
                ))
            }
        }
        // The Warden gets golden horns.
        if kind == .shrineWarden {
            for i in 0..<4 {
                let gy = radius - 4 - i
                minY = min(minY, gy)
                cells.append(VoxelCell(x: radius - 4, y: gy, halfDepth: 0.8, r: 242, g: 210, b: 75))
                cells.append(VoxelCell(x: radius + 4, y: gy, halfDepth: 0.8, r: 242, g: 210, b: 75))
            }
        }
        return VoxelGrid(n: n, cells: cells, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private static func palette(for kind: EnemyKind) -> [(UInt8, UInt8, UInt8)] {
        switch kind {
        case .mosskit:      return [(82, 192, 99), (59, 143, 74), (122, 219, 139)]
        case .emberling:    return [(242, 104, 60), (196, 68, 32), (242, 210, 75)]
        case .stonehusk:    return [(138, 147, 166), (92, 102, 122), (179, 186, 201)]
        case .riftling:     return [(155, 89, 208), (110, 53, 160), (224, 123, 224)]
        case .shrineWarden: return [(90, 58, 140), (58, 34, 96), (242, 210, 75)]
        }
    }
}

/// Small deterministic PRNG (xorshift32) so enemy shapes are stable.
struct Mulberry {
    private var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 1 : seed }
    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(state) / Float(UInt32.max)
    }
}
