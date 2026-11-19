#version 440
// Aether Aurora: a curtain of light across the night sky - drawn analytically at the screen's own
// resolution (no image anywhere). Two curtains, far and near; each hangs from a slow sinuous hem that
// ends on a sharp bright edge, rays rising from it irregular in spacing and height, the light turning
// from the accent at the hem toward a neighbouring hue as it climbs. A sparse field of stars sits
// behind them. The accent and the mode come in as uniforms; `time` sways the curtains, a few pixels
// a second.
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
// The accent turned around the colour wheel (YIQ rotation) - the curtain's upper fringe.
vec3 turn(vec3 c, float a) {
    vec3 yiq = mat3(0.299, 0.596, 0.211, 0.587, -0.274, -0.523, 0.114, -0.322, 0.312) * c;
    yiq.yz = mat2(cos(a), sin(a), -sin(a), cos(a)) * yiq.yz;
    return clamp(mat3(1.0, 1.0, 1.0, 0.956, -0.272, -1.106, 0.621, -0.647, 1.703) * yiq, 0.0, 1.0);
}

// Per curtain, far to near: hem height at the left edge, its rise across the screen (the arc sweeps
// from low on the left to high on the right), ray height, strength.
const vec4 C[2] = vec4[](
    vec4(0.42, 0.30, 0.07, 0.40),
    vec4(0.72, 0.42, 0.10, 1.00)
);

// One curtain at this pixel: the hem is a slow sinuous line across the sky; above it rays of light
// rise, irregular in spacing and height, fading as they climb; below it the light ends on a sharp,
// bright edge. Returns (light, how high up the curtain - 0 at the hem).
vec2 curtain(vec2 p, int k) {
    vec4 c = C[k];
    float f = float(k);
    float t = time * 0.022;
    float u = p.x / aspect;
    float hem = c.x - c.y * u + 0.10 * u * (u - 1.0) * 4.0 * (1.0 - 0.5 * f)   // the arc, bowed
              + 0.110 * gnoise(vec2(p.x * 0.85 + t + f * 7.1, f * 3.3))        // its folds
              + 0.025 * gnoise(vec2(p.x * 3.1 - 1.3 * t + f * 1.7, f * 5.9 + 0.4 * t));
    float h = hem - p.y;                                 // height above the hem
    // Rays lean a little as they rise; three scales so no spacing repeats.
    float rx = p.x + 0.35 * h;
    float ray = 0.50 * gnoise(vec2(rx * 14.0 + 2.0 * t, f * 9.1 + time * 0.045))
              + 0.30 * gnoise(vec2(rx * 37.0 - 3.0 * t, f * 4.7 - time * 0.060))
              + 0.20 * gnoise(vec2(rx * 90.0 + 5.0 * t, f * 2.3 + time * 0.08));
    ray = clamp(0.45 + 1.8 * ray, 0.0, 1.0);
    ray *= ray;
    // The curtain folds and thins along its length.
    float along = 0.35 + 0.65 * smoothstep(-0.30, 0.35, gnoise(vec2(p.x * 1.4 - 0.8 * t + f * 11.0, f * 6.1 + 0.3 * t)));
    float tall = c.z * (0.45 + 1.1 * ray) * (0.6 + 0.4 * along);
    float up = exp(-pow(max(h, 0.0) / tall, 1.4));
    float edge = smoothstep(mix(-0.035, -2.0 * px, f), mix(0.01, px, f), h);   // the near edge sharp, the far one soft
    float hemline = exp(-pow(h / (3.5 * px), 2.0)) * (0.3 + 0.7 * ray) * along * f;   // only the near curtain draws its hem   // brightest right at it
    float glowDown = exp(-max(-h, 0.0) / 0.020) * (1.0 - edge) * 0.06;   // a whisper below
    return vec2(c.w * along * ((0.04 + 0.96 * ray) * up * edge + 0.6 * hemline + glowDown), clamp(h / 0.16, 0.0, 1.0));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);
    vec2 p = uv * vec2(aspect, 1.0);
    vec3 top = hue(turn(acc, 0.9), 0.55, 0.6);           // the fringe, a turn of the wheel away

    vec2 a0 = curtain(p, 0), a1 = curtain(p, 1);
    // Everything breathes together, about the span of a breath, a few percent at most.
    float breath = 1.0 + 0.05 * sin(time * 0.42);
    vec3 aur = (mix(acc, top, a0.y) * a0.x * 0.6 + mix(mix(acc, vec3(1.0), 0.25), top, a1.y) * a1.x) * breath;

    // Stars: one cell in a grid of them carries a point, a few hundred over the screen, dimmed where
    // the curtain shines.
    vec2 cell = floor(p * 90.0);
    float sh = fract(sin(dot(cell, vec2(41.3, 289.1))) * 43758.5453);
    vec2 sp = (cell + 0.2 + 0.6 * vec2(fract(sh * 13.7), fract(sh * 71.3))) / 90.0;
    float star = step(0.975, sh) * exp(-pow(length(p - sp) / (0.9 * px), 2.0)) * (0.3 + 0.7 * fract(sh * 7.1));
    star *= (1.0 - smoothstep(0.65, 1.0, uv.y)) * (1.0 - clamp(a1.x + a0.x, 0.0, 1.0));

    float r = length(p - vec2(0.5 * aspect, 0.5));
    float pool = 0.08 * exp(-r / 0.40);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.040, 0.0), hue(acc, 0.018, 0.0), smoothstep(0.1, 1.0, uv.y));
    vec3 light = aur * 0.55 + acc * pool + vec3(0.45) * star;
    night += vec3(1.0) - exp(-light * 1.4);
    night *= 1.0 - 0.30 * pow(length(uv - vec2(0.5, 0.5)) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.86, 0.0), hue(acc, 0.76, 0.0), smoothstep(0.1, 1.0, uv.y));
    day = mix(day, hue(acc, 0.92, 0.0), clamp(pool * 3.0, 0.0, 0.3));
    float ink = clamp(a0.x * 0.6 + a1.x, 0.0, 1.0);
    day = mix(day, hue(mix(acc, top, 0.5 * (a0.y + a1.y)), 0.45, 0.0), clamp(ink * 0.80, 0.0, 0.75));
    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour

    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
