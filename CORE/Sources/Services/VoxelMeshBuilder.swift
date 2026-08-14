import UIKit
import RealityKit

/// Builds a single RealityKit mesh from a VoxelGrid: one box column per
/// cell, hidden faces culled, every vertex UV-mapped to a per-cell colour
/// texture. The result is a genuine 3D model of the player's drawing that
/// stands in their room — no billboards.
enum VoxelMeshBuilder {

    /// Returns a ModelEntity whose feet sit at local y = 0, centred on x/z,
    /// scaled so the model is `targetHeight` metres tall.
    static func entity(for grid: VoxelGrid, targetHeight: Float) throws -> ModelEntity {
        let s: Float = 1.0 / Float(max(grid.width, grid.height))   // cell size, pre-scale

        // Column lookup for face culling.
        var depthAt = [Float](repeating: 0, count: grid.n * grid.n)
        for c in grid.cells { depthAt[c.y * grid.n + c.x] = c.halfDepth }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                  normal: SIMD3<Float>, uv: SIMD2<Float>) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c, d])
            normals.append(contentsOf: [normal, normal, normal, normal])
            uvs.append(contentsOf: [uv, uv, uv, uv])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        let midX = Float(grid.minX + grid.maxX + 1) / 2
        for cell in grid.cells {
            let hd = cell.halfDepth * s * 0.9
            let x0 = (Float(cell.x) - midX) * s
            let x1 = x0 + s
            // Grid y grows downward; world y grows upward.
            let y0 = Float(grid.maxY - cell.y) * s
            let y1 = y0 + s
            let z0 = -hd, z1 = hd
            let uv = SIMD2(Float(cell.x) + 0.5, Float(cell.y) + 0.5) / Float(grid.n)
            // RealityKit texture V runs bottom-up.
            let tuv = SIMD2(uv.x, 1 - uv.y)

            func neighbourDepth(_ dx: Int, _ dy: Int) -> Float {
                let nx = cell.x + dx, ny = cell.y + dy
                guard nx >= 0, ny >= 0, nx < grid.n, ny < grid.n else { return 0 }
                return depthAt[ny * grid.n + nx]
            }

            // Front / back always visible.
            quad(SIMD3(x0, y0, z1), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1),
                 normal: SIMD3(0, 0, 1), uv: tuv)
            quad(SIMD3(x1, y0, z0), SIMD3(x0, y0, z0), SIMD3(x0, y1, z0), SIMD3(x1, y1, z0),
                 normal: SIMD3(0, 0, -1), uv: tuv)
            // Sides only where exposed (neighbour missing or thinner).
            if neighbourDepth(1, 0) < cell.halfDepth {
                quad(SIMD3(x1, y0, z1), SIMD3(x1, y0, z0), SIMD3(x1, y1, z0), SIMD3(x1, y1, z1),
                     normal: SIMD3(1, 0, 0), uv: tuv)
            }
            if neighbourDepth(-1, 0) < cell.halfDepth {
                quad(SIMD3(x0, y0, z0), SIMD3(x0, y0, z1), SIMD3(x0, y1, z1), SIMD3(x0, y1, z0),
                     normal: SIMD3(-1, 0, 0), uv: tuv)
            }
            // Grid -y is world up.
            if neighbourDepth(0, -1) < cell.halfDepth {
                quad(SIMD3(x0, y1, z1), SIMD3(x1, y1, z1), SIMD3(x1, y1, z0), SIMD3(x0, y1, z0),
                     normal: SIMD3(0, 1, 0), uv: tuv)
            }
            if neighbourDepth(0, 1) < cell.halfDepth {
                quad(SIMD3(x0, y0, z0), SIMD3(x1, y0, z0), SIMD3(x1, y0, z1), SIMD3(x0, y0, z1),
                     normal: SIMD3(0, -1, 0), uv: tuv)
            }
        }

        var descriptor = MeshDescriptor(name: "voxel-creature")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])

        var material = PhysicallyBasedMaterial()
        material.roughness = 0.85
        material.metallic = 0.0
        if let texture = try? colorTexture(for: grid) {
            material.baseColor = .init(texture: .init(texture))
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Normalise: feet at y=0, target height in metres.
        let modelHeight = Float(grid.height) * s
        let scale = targetHeight / max(modelHeight, 0.001)
        entity.scale = SIMD3(repeating: scale)
        return entity
    }

    /// N×N cell-colour texture, upscaled with nearest-neighbour so voxel
    /// colours stay crisp.
    private static func colorTexture(for grid: VoxelGrid) throws -> TextureResource {
        let n = grid.n, up = 8
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for c in grid.cells {
            let i = (c.y * n + c.x) * 4
            pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b; pixels[i + 3] = 255
        }
        guard let small = CGContext(
            data: &pixels, width: n, height: n,
            bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { throw VoxelError.textureFailed }

        guard let ctx = CGContext(
            data: nil, width: n * up, height: n * up,
            bitsPerComponent: 8, bytesPerRow: n * up * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw VoxelError.textureFailed }
        ctx.interpolationQuality = .none
        ctx.draw(small, in: CGRect(x: 0, y: 0, width: n * up, height: n * up))
        guard let cg = ctx.makeImage() else { throw VoxelError.textureFailed }
        return try TextureResource.generate(from: cg, options: .init(semantic: .color))
    }

    enum VoxelError: Error { case textureFailed }
}
