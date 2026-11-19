#version 440
// Aether Ink: pigment let into still water - drawn analytically at the screen's own resolution (no
// image anywhere). A nested domain warp gives the billows their folded, smoke-like body; where the
// pigment's front crosses itself a fine vein of light runs along it. Two pours, from the upper left
// and the lower right, leave the centre clear under the mark. At night the pigment glows in the
// accent; by day it is dark ink on pale paper. `time` lets the water creep, a few pixels a second.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 accent;     // the island's accent
    float dark;      // 1 = the dark field, 0 = the light one; in between while switching
    float aspect;    // width / height
    float px;        // one pixel in height units
    float time;      // seconds; 0 holds the composition still
};

// The accent's hue at another lightness, its saturation raised to at least `vivid` - a muted accent
// still has to glow.
vec3 hue(vec3 c, float l, float vivid) {
    float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
    float cl = 0.5 * (mx + mn), sl = max(1e-3, cl < 0.5 ? cl : 1.0 - cl);
    vec3 sat = (c - vec3(cl)) / sl;
    float s = (mx - mn) / (2.0 * sl);
    sat *= max(s, vivid) / max(s, 1e-3);
    return clamp(vec3(l) + sat * (l < 0.5 ? l : 1.0 - l), 0.0, 1.0);
}

// Gradient noise (no lattice blocks) and five rotated octaves of it.
vec2 grad(vec2 i) {   // a trig-free hash (Hoskins) to a direction in the unit square
    vec3 h = fract(vec3(i.xyx) * vec3(0.1031, 0.1030, 0.0973));
    h += dot(h, h.yzx + 33.33);
    return fract((h.xx + h.yz) * h.zy) * 2.0 - 1.0;
}
float gnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(dot(grad(i), f), dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}
const mat2 ROT = mat2(0.80, 0.60, -0.60, 0.80);
float fbm(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; ++i) {
        s += a * gnoise(p);
        p = ROT * p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return s;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);
    vec2 p = uv * vec2(aspect, 1.0);

    // The water folds over itself: a warp of a warp (q, then r), each layer creeping on its own
    // slow current, so the billows turn instead of sliding.
    float t = time * 0.012;
    vec2 b = p * 0.85;
    vec2 q = vec2(fbm(b + vec2(0.0, t)), fbm(b + vec2(5.2, 1.3) - 0.7 * t));
    vec2 r = vec2(fbm(b + 2.6 * q + vec2(1.7, 9.2) + 0.15 * t), fbm(b + 2.6 * q + vec2(8.3, 2.8) - 0.12 * t));
    float f = fbm(b + 2.4 * r);

    // Two pours, the upper left and the lower right, their reach torn by the warp; the centre
    // stays clear.
    vec2 c = vec2(0.5 * aspect, 0.5);
    float a1 = length((p - vec2(0.05 * aspect, 0.05)) * vec2(0.85, 1.0));
    float a2 = length((p - vec2(0.97 * aspect, 0.98)) * vec2(0.85, 1.0));
    float reach = max(1.0 - smoothstep(0.25, 0.95, a1 + 0.45 * r.x),
                      1.0 - smoothstep(0.25, 0.90, a2 + 0.45 * r.y));
    reach *= smoothstep(0.16, 0.42, length(p - c) + 0.18 * q.x);

    // The pigment: dense where the folded field is high, its body shaded by how far it has been
    // carried (|r|), so every billow has a lit side and a shadowed one.
    float e = f + 0.40 * reach - 0.15;
    float ink = smoothstep(-0.25, 0.35, e) * reach;
    float body = clamp(0.35 + 1.6 * length(r) - 0.6 * q.y, 0.0, 1.4);
    // The front: a hairline of light where the pigment meets clear water - the field's own level
    // line, so it curls and frays with every billow.
    float vein = pow(clamp(1.0 - abs(e + 0.02) / 0.010, 0.0, 1.0), 2.0) * smoothstep(0.25, 0.7, reach);

    // Everything breathes together, about the span of a breath, a few percent at most.
    float breath = 1.0 + 0.05 * sin(time * 0.42);
    ink *= breath;

    // The centre lifts a touch, under the mark.
    float pool = 0.12 * exp(-length(p - c) / 0.34);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.025, 0.0), hue(acc, 0.05, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    vec3 light = acc * (ink * body * 0.55 + pool * 0.45)
               + mix(acc, vec3(1.0), 0.35) * (vein * 0.45 + ink * ink * body * 0.12);
    night += vec3(1.0) - exp(-light * 1.4);
    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.80, 0.0), hue(acc, 0.90, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    day = mix(day, hue(acc, 0.94, 0.0), clamp(pool * 1.5, 0.0, 0.4));
    day = mix(day, hue(acc, mix(0.62, 0.30, clamp(body * 0.7, 0.0, 1.0)), 0.0), clamp(ink * 0.85, 0.0, 0.85));
    day = mix(day, hue(acc, 0.22, 0.0), clamp(vein * 0.5, 0.0, 0.5));
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
