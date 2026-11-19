#version 440
// Aether Ink: ink in still water - drawn analytically at the screen's own resolution (no image
// anywhere). Two dark masses billow around off-centre pivots, their edges torn by a slow domain
// warp so the boundary diffuses like pigment finding its way; a breathing pool of light keeps the
// centre clear under the mark. The accent and the mode come in as uniforms; `time` billows the ink,
// a few pixels a second, sub-pixel a tick.
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

// Lattice value noise, two octaves - the water the ink spreads in.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float water(vec2 p) { return 0.65 * vnoise(p) + 0.35 * vnoise(p * 2.13 + 7.7); }

// The pivot one mass hangs about, drifting on a slow circle - the two against each other.
vec2 pivot(int k) {
    float f = float(k);
    return vec2(k == 0 ? 0.38 : 0.66, k == 0 ? 0.40 : 0.66)
         + 0.06 * vec2(sin(time * 0.047 + f * 2.9), cos(time * 0.039 + f * 1.7 + 0.8));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);

    // The water itself creeps: a domain warp drifting with time tears every edge it touches.
    vec2 warp = vec2(water(uv * 3.0 + vec2(time * 0.010, -time * 0.007)),
                     water(uv * 3.0 + vec2(-time * 0.008, time * 0.012) + 4.2)) - 0.5;
    vec2 q = uv + 0.11 * warp;

    // Two masses: a noisy radius around a drifting pivot, dense at the heart and fraying at the
    // rim, where a faint band marks the front the pigment is finding its way through.
    float ink = 0.0, front = 0.0;
    for (int k = 0; k < 2; ++k) {
        vec2 p = pivot(k);
        float d = length(q - p);
        float field = d + 0.26 * (water(q * 2.4 + float(k) * 3.1 + time * 0.006) - 0.5);
        float m = 1.0 - smoothstep(0.10, 0.42, field);
        ink = max(ink, m * (k == 0 ? 0.90 : 0.65));
        front = max(front, m * (1.0 - m) * 4.0 * (k == 0 ? 0.90 : 0.50));
    }

    // Everything breathes together, about the span of a breath, a few percent at most.
    ink *= 1.0 + 0.05 * sin(time * 0.42);

    // The centre stays clear: a breathing pool of light under the mark.
    float r = length(uv * vec2(aspect, 1.0) - vec2(0.5 * aspect, 0.5));
    float pool = 0.16 * exp(-r / 0.34);

    // A broad sheen crosses the whole field once a minute: light through the water.
    float sheen = 0.05 * pow(max(sin(dot(uv, vec2(0.85, 0.45)) * 1.7 - time * 0.09 + 0.7), 0.0), 2.5);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.03, 0.0), hue(acc, 0.06, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    night = mix(night, hue(acc, 0.015, 0.0), clamp(ink * 0.75, 0.0, 0.8));   // the ink, a shade darker than the field
    vec3 light = acc * (front * 0.05 + pool * 0.55 + sheen);
    night += vec3(1.0) - exp(-light * 1.4);
    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.66, 0.0), hue(acc, 0.80, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    day = mix(day, hue(acc, 0.28, 0.0), clamp(ink * 0.55, 0.0, 0.7));
    day = mix(day, hue(acc, 0.45, 0.0), clamp(front * 0.12, 0.0, 0.2));
    day = mix(day, hue(acc, 0.88, 0.0), clamp(pool * 0.8, 0.0, 0.5));
    day = mix(day, hue(acc, 0.92, 0.0), clamp(sheen * 3.0, 0.0, 0.12));
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
