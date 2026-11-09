import SpriteKit
import simd

/// Shared SKShaders. Per-sprite values travel as SKAttributes, so every sprite
/// using a shader still batches into one draw call per texture atlas.
@MainActor
enum Shaders {
    /// Status tint: mixes the sprite towards `a_tint.rgb` by `a_tint.a`. Unlike
    /// `colorBlendFactor` (multiplicative), this can brighten, so a hit flash is
    /// actually white and frost reads as icy. Textures are premultiplied.
    static let status: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 c = SKDefaultShading();
            gl_FragColor = vec4(mix(c.rgb, a_tint.rgb * c.a, a_tint.a), c.a);
        }
        """)
        s.attributes = [SKAttribute(name: "a_tint", type: .vectorFloat4)]
        return s
    }()

    /// Dissolve: texels whose noise value is below `a_dissolve` (0…1) vanish,
    /// with a glowing ember rim along the edge. Used on dying enemies.
    static let dissolve: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec4 c = SKDefaultShading();
            vec2 cell = floor(v_tex_coord * 700.0);
            float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
            float d = a_dissolve;
            if (n < d) {
                gl_FragColor = vec4(0.0);
            } else {
                float rim = 1.0 - smoothstep(d, d + 0.12, n);
                vec3 hot = vec3(1.0, 0.55, 0.18) * c.a;
                gl_FragColor = vec4(mix(c.rgb, hot, rim * step(0.001, d)), c.a);
            }
        }
        """)
        s.attributes = [SKAttribute(name: "a_dissolve", type: .float)]
        return s
    }()

    static func setTint(_ node: SKSpriteNode, _ c: SIMD4<Float>) {
        node.setValue(SKAttributeValue(vectorFloat4: c), forAttribute: "a_tint")
    }

    static func setDissolve(_ node: SKSpriteNode, _ v: Float) {
        node.setValue(SKAttributeValue(float: v), forAttribute: "a_dissolve")
    }
}
