#version 440
// Aether Mist: fog lying over low ground, lit from behind - drawn analytically at the screen's own
// resolution (no image anywhere). Three banks, far to near, of warped noise stretched along the
// ground; a low light right of the mark glows through them, so the fog brightens as it nears the
// light, and where a bank thins the light catches a fine wisp. The accent and the mode come in as
// uniforms; `time` drifts the banks at their own paces, a few pixels a second.
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

// Per layer, far to near: scale (the far fog finer), the height its bank lies at, how deep the bank
// is, how fast it drifts.
const vec4 L[3] = vec4[](
    vec4(2.6, 0.47, 0.11, 0.016),
    vec4(1.6, 0.63, 0.13, 0.026),
    vec4(0.9, 0.82, 0.16, 0.040)
);

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);
    vec2 p = uv * vec2(aspect, 1.0);

    // The light: low behind the fog, right of the mark - a tight core and a wide bloom.
    vec2 sun = vec2(0.66 * aspect, 0.60);
    float dsun = length((p - sun) * vec2(0.7, 1.0));
    float core = exp(-dsun / 0.07), bloom = exp(-dsun / 0.45);

    vec3 night = mix(hue(acc, 0.015, 0.0), hue(acc, 0.035, 0.0), smoothstep(0.0, 0.7, uv.y));
    night += vec3(1.0) - exp(-(acc * (bloom * 0.35) + mix(acc, vec3(1.0), 0.5) * core * 0.45) * 1.4);
    vec3 day = mix(hue(acc, 0.60, 0.0), hue(acc, 0.76, 0.0), smoothstep(0.0, 0.7, uv.y));
    day = mix(day, hue(acc, 0.96, 0.0), clamp(bloom * 0.5 + core * 0.6, 0.0, 0.85));

    // The fog, far to near: each layer a bank of warped noise stretched along the ground, drifting
    // at its own pace (nearer is faster - the parallax), lit by how close it lies to the light.
    // Where a layer thins, its rim catches a little more of the light.
    float wisps = 0.0;
    for (int k = 0; k < 3; ++k) {
        vec4 l = L[k];
        float f = float(k);
        vec2 b = vec2(p.x * l.x * 0.55, p.y * l.x * 1.6);
        b.x += time * l.w + f * 17.3;
        vec2 w = vec2(fbm(b * 0.7 + vec2(0.0, time * 0.012) + f * 3.1), fbm(b * 0.7 + vec2(5.2, -time * 0.010) + f * 1.7));
        float dens = fbm(b + 1.6 * w);
        float bank = exp(-pow((uv.y - l.y - 0.06 * w.y) / l.z, 2.0));
        float fog = smoothstep(-0.12, 0.38, 1.4 * dens + 0.30 * bank - 0.12) * bank;
        float lit = 0.15 + 1.1 * bloom + 1.6 * core;
        float edge = exp(-pow((1.4 * dens + 0.30 * bank - 0.02) / 0.05, 2.0)) * bank;

        vec3 fogN = hue(acc, 0.07 + 0.03 * f, 0.0) + mix(acc, vec3(1.0), 0.25 + 0.10 * f) * lit * (0.22 + 0.08 * f);
        night = mix(night, fogN, clamp(fog * (0.65 + 0.15 * f), 0.0, 0.92));
        wisps += edge * lit * (0.3 + 0.25 * f);

        vec3 fogD = mix(hue(acc, 0.86 - 0.02 * f, 0.0), vec3(1.0), clamp(lit * 0.45, 0.0, 0.85));
        day = mix(day, fogD, clamp(fog * (0.70 + 0.15 * f), 0.0, 0.92));
    }
    // Everything breathes together, about the span of a breath, a few percent at most.
    wisps *= 1.0 + 0.06 * sin(time * 0.42);
    night += mix(acc, vec3(1.0), 0.4) * wisps * 0.10;
    day = mix(day, hue(acc, 0.52, 0.0), clamp(wisps * 0.04, 0.0, 0.15));

    // The centre lifts a touch, under the mark.
    float pool = 0.08 * exp(-length(p - vec2(0.5 * aspect, 0.5)) / 0.34);
    night += acc * pool * 0.4;

    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
