#version 440
// Aether Dune: dunes at dusk - drawn analytically at the screen's own resolution (no image anywhere).
// Four ridges, far to near, each folded to a knife-edge crest; a sun just under the horizon lights
// the faces turned toward it and burns a fine line along the crests nearest it, and the far dunes
// sink into the haze of its glow. The accent and the mode come in as uniforms; `time` lets the
// sand creep, a few pixels a second.
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

// Gradient noise: smooth, with no lattice blocks.
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
// Per dune, far to near: base height, crest amplitude, wavelength (noise cells per height unit).
const vec3 D[4] = vec3[](
    vec3(0.575, 0.040, 1.30),
    vec3(0.665, 0.060, 0.95),
    vec3(0.780, 0.085, 0.70),
    vec3(0.915, 0.110, 0.50)
);

// The ridge of dune k at x (height units): two octaves of noise folded with abs(), so the crests
// come to a knife edge and the troughs stay broad, the way wind leaves sand. The dunes creep
// sideways at their own pace and the noise beneath them slowly turns, so they morph as they go.
float ridge(float x, int k) {
    vec3 d = D[k];
    float f = float(k);
    float drift = time * (0.0040 + 0.0016 * f);
    float n = gnoise(vec2(x * d.z + drift + f * 13.1, f * 7.7 + time * 0.0050))
            + 0.45 * gnoise(vec2(x * d.z * 2.3 - 0.6 * drift + f * 3.3, f * 2.9 - time * 0.0040));
    return d.x - d.y * (1.0 - 1.7 * abs(n));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);
    float x = uv.x * aspect, y = uv.y;

    // The light: a sun just under the far horizon, a little right of the mark.
    vec2 sun = vec2(0.60 * aspect, D[0].x + 0.02);
    float toSun = length((vec2(x, y) - sun) * vec2(0.55, 1.0));

    // The sky: deep above, warming into a glow band behind the far ridge.
    float horizon = exp(-max(D[0].x - y, 0.0) / 0.10);
    float halo = exp(-toSun / 0.22);
    float sheen = 0.06 * pow(max(sin(dot(uv, vec2(0.9, 0.5)) * 1.8 - time * 0.10 + 1.0), 0.0), 2.5);

    vec3 night = mix(hue(acc, 0.025, 0.0), hue(acc, 0.06, 0.0), smoothstep(0.0, D[0].x, y));
    night += vec3(1.0) - exp(-(acc * (horizon * 0.30 + halo * 0.55 + sheen) + mix(acc, vec3(1.0), 0.5) * halo * halo * 0.35) * 1.4);
    vec3 day = mix(hue(acc, 0.72, 0.0), hue(acc, 0.86, 0.0), smoothstep(0.0, D[0].x, y));
    day = mix(day, hue(acc, 0.95, 0.0), clamp(horizon * 0.45 + halo * 0.6, 0.0, 0.8));
    day = mix(day, hue(acc, 0.92, 0.0), clamp(sheen * 3.0, 0.0, 0.12));

    // The dunes, far to near. Each covers what is behind it with an edge one pixel soft; its face
    // is lit where the slope turns toward the sun and fades into the body below the crest; the
    // farther ones sink into the haze of the glow.
    float e = 0.012;
    for (int k = 0; k < 4; ++k) {
        float f = float(k);
        float yk = ridge(x, k);
        float below = y - yk;
        // The slope is read a little up-wind as the face falls away, so the line between light and
        // shadow runs down the slip face on a slant instead of dropping straight from the crest.
        float xs = x + 0.55 * max(below, 0.0) * sign(x - sun.x);
        float slope = (ridge(xs + e, k) - ridge(xs - e, k)) / (2.0 * e);   // > 0: falls away to the right
        float lit = smoothstep(-0.20, 0.35, (sun.x - x) * -slope / max(abs(sun.x - x), 0.05));
        float cover = smoothstep(-px, px, below);
        float face = lit * exp(-below / (0.03 + 0.025 * f));
        float near = exp(-length((vec2(x, yk) - sun) * vec2(0.6, 1.0)) / 0.45);   // crests near the sun burn
        float haze = 1.0 - f / 3.0;                                              // 1 far .. 0 near
        float crest = exp(-pow(below / (1.4 * px), 2.0)) * (0.35 + 0.65 * lit) * (0.4 + 0.6 * near);

        vec3 sandN = mix(hue(acc, 0.030 + 0.012 * (3.0 - f), 0.0), hue(acc, 0.085, 0.0), haze * 0.55);
        sandN += vec3(1.0) - exp(-acc * (face * (0.10 + 0.30 * near) + haze * horizon * 0.10) * 1.4);
        night = mix(night, sandN, cover);
        night += mix(acc, vec3(1.0), 0.35) * crest * (0.30 + 0.25 * f / 3.0);

        vec3 sandD = mix(hue(acc, 0.56 - 0.07 * f, 0.0), hue(acc, 0.74, 0.0), haze * 0.45);
        sandD = mix(sandD, hue(acc, 0.82 - 0.04 * f, 0.0), clamp(face * (0.35 + 0.4 * near), 0.0, 0.7));
        day = mix(day, sandD, cover);
        day = mix(day, hue(acc, 0.95, 0.0), clamp(crest * 0.45, 0.0, 0.5));
    }

    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
