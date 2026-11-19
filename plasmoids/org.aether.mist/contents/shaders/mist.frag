#version 440
// Aether Mist: slow banks of fog drifting over a deep field - drawn analytically at the screen's own
// resolution (no image anywhere), so the fog stays seamless at any size. Five banks on different
// depths, each a breathing centre line with a soft falloff and a density that patches and clears
// along it. The accent and the mode come in as uniforms; `time` drifts the banks, a few pixels a
// second, sub-pixel a tick.
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

// Per bank: centre height, half-thickness, pace, brightness - the high veil, the broad middle bank,
// the low bank, the ground mist, and a thin counter-bank drifting against them.
const vec4 B[5] = vec4[](
    vec4(0.22, 0.16, 1.00, 0.34),
    vec4(0.42, 0.22, 0.60, 0.50),
    vec4(0.61, 0.17, 0.80, 0.40),
    vec4(0.84, 0.26, 0.45, 0.55),
    vec4(0.32, 0.09, 1.20, 0.22)
);

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);

    // Each bank: a centre line that rolls like a slow wave and rises and sinks as a whole, a
    // Gaussian falloff around it, and a density that patches and clears as two slow waves scroll
    // against each other along it. Nothing moves faster than a few pixels a second.
    float fog = 0.0, fine = 0.0;
    for (int k = 0; k < 5; ++k) {
        vec4 b = B[k];
        float f = float(k);
        float y = b.x
                + 0.045 * b.z * sin(uv.x * (1.7 + 0.3 * f) + time * 0.050 + f * 2.1)
                + 0.028 * b.z * sin(uv.x * (3.1 - 0.2 * f) - time * 0.037 + f * 1.3 + 1.0)
                + 0.016 * sin(time * 0.11 + f * 2.6);
        float band = exp(-pow((uv.y - y) / b.y, 2.0));
        float patchy = 0.55 + 0.45 * sin(uv.x * (2.3 + 0.7 * f) + time * 0.055 * b.z + f * 1.9)
                               * cos(uv.x * 0.9 - time * 0.021 * b.z + f * 0.7);
        float g = band * patchy;
        fog += b.w * g;
        if (k == 4) fine = g;
    }
    fog = clamp(fog, 0.0, 1.2);

    // Everything breathes together, about the span of a breath, a few percent at most.
    fog *= 1.0 + 0.05 * sin(time * 0.40);

    // A broad sheen crosses the whole field once a minute: light through the fog.
    float sheen = 0.06 * pow(max(sin(dot(uv, vec2(0.8, 0.4)) * 1.6 - time * 0.08 + 1.3), 0.0), 2.5);

    // The centre is a touch lighter, under the mark.
    float r = length(uv * vec2(aspect, 1.0) - vec2(0.5 * aspect, 0.5));
    float pool = 0.14 * exp(-r / 0.38);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.03, 0.0), hue(acc, 0.06, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    vec3 light = acc * (fog * 0.14 + pool * 0.30 + sheen)
               + mix(acc, vec3(1.0), 0.30) * (fog * 0.12 + fine * 0.06);
    night += vec3(1.0) - exp(-light * 1.4);
    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.66, 0.0), hue(acc, 0.80, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    day = mix(day, hue(acc, 0.82, 0.0), clamp(fog * 0.8, 0.0, 0.7));
    day = mix(day, hue(acc, 0.90, 0.0), clamp(pool * 0.8, 0.0, 0.5));
    day = mix(day, hue(acc, 0.92, 0.0), clamp(sheen * 3.0, 0.0, 0.12));
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
