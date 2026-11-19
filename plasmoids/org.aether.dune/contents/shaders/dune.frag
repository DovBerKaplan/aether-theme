#version 440
// Aether Dune: layered ridgelines under a deep sky - drawn analytically at the screen's own
// resolution (no image anywhere). Four dunes ride slow traveling swells, each nearer one a shade
// darker than the one behind it; the sky keeps a sheen that crosses once a minute, and the nearest
// crest catches a fine edge of light. The accent and the mode come in as uniforms; `time` rolls the
// dunes, a few pixels a second, sub-pixel a tick.
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

// Per dune, far to near: base height, swell amplitude, pace, wavelength.
const vec4 D[4] = vec4[](
    vec4(0.46, 0.016, 0.70, 3.2),
    vec4(0.60, 0.021, 0.55, 2.3),
    vec4(0.74, 0.026, 0.42, 1.6),
    vec4(0.88, 0.032, 0.30, 1.1)
);

// The ridge of dune k: two swells crossing - one traveling, one breathing in place - so the shape
// morphs instead of sliding, and nothing repeats in step.
float ridge(vec2 uv, int k) {
    vec4 d = D[k];
    float f = float(k);
    return d.x
         + d.y * sin(uv.x * d.w + time * (0.045 + 0.012 * f) + f * 2.3)
                * (0.7 + 0.3 * sin(uv.x * (d.w * 0.53) - time * 0.028 + f * 1.1 + 0.5))
         + d.y * 0.4 * sin(uv.x * (d.w * 2.6) - time * (0.030 + 0.010 * f) + f * 3.7);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);

    // Where each ridge sits at this pixel's x (four evaluations, no loops that vary).
    float y0 = ridge(uv, 0), y1 = ridge(uv, 1), y2 = ridge(uv, 2), y3 = ridge(uv, 3);

    // Sky features: a sheen crossing once a minute, the centre lifted under the mark.
    float sheen = 0.08 * pow(max(sin(dot(uv, vec2(0.9, 0.5)) * 1.8 - time * 0.10 + 1.0), 0.0), 2.5);
    float r = length(uv * vec2(aspect, 1.0) - vec2(0.5 * aspect, 0.5));
    float pool = 0.12 * exp(-r / 0.36);

    // The nearest crest catches a fine edge of light; the second ridge a whisper of one.
    float rim3 = exp(-pow((uv.y - y3) / (1.8 * px), 2.0)) * step(uv.y, y3 + 1.8 * px);
    float rim1 = exp(-pow((uv.y - y1) / (1.8 * px), 2.0)) * step(uv.y, y1 + 1.8 * px);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.03, 0.0), hue(acc, 0.06, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    vec3 light = acc * (sheen + pool * 0.5);
    night += vec3(1.0) - exp(-light * 1.4);
    // The dunes, far to near, each a shade deeper than the one behind it.
    if (uv.y > y0) night = mix(night, hue(acc, 0.050, 0.0), 0.88);
    if (uv.y > y1) night = mix(night, hue(acc, 0.041, 0.0), 0.88);
    if (uv.y > y2) night = mix(night, hue(acc, 0.032, 0.0), 0.88);
    if (uv.y > y3) night = mix(night, hue(acc, 0.022, 0.0), 0.90);
    night += acc * (rim3 * 0.45 + rim1 * 0.30);   // the crests catch the light, sky side only
    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.66, 0.0), hue(acc, 0.80, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    day = mix(day, hue(acc, 0.90, 0.0), clamp(sheen * 2.5, 0.0, 0.15));
    day = mix(day, hue(acc, 0.86, 0.0), clamp(pool * 0.8, 0.0, 0.5));
    if (uv.y > y0) day = mix(day, hue(acc, 0.52, 0.0), 0.85);
    if (uv.y > y1) day = mix(day, hue(acc, 0.44, 0.0), 0.85);
    if (uv.y > y2) day = mix(day, hue(acc, 0.37, 0.0), 0.85);
    if (uv.y > y3) day = mix(day, hue(acc, 0.30, 0.0), 0.85);
    day = mix(day, hue(acc, 0.94, 0.0), clamp(rim3 * 0.5 + rim1 * 0.3, 0.0, 0.3));
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
