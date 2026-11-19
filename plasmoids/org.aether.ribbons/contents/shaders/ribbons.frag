#version 440
// Aether Ribbons: two swooping bands of light crossing over a deep field - the top-left one and the
// bottom-right one - drawn analytically at the screen's own resolution (no image anywhere), so the
// seams stay one pixel sharp at any size. The accent and the mode come in as uniforms; `time` lets
// the ribbons sway slowly and the light drift along them.
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

// Each seam is a cubic Bezier in screen fractions (x of the width, y of the height, y down),
// traced from the reference composition. Endpoints sit off-screen so no line ends in view.
const vec2 P[32] = vec2[](
    vec2(-0.0234, 0.3333), vec2(0.1297, 0.2114), vec2(0.2814, 0.0893), vec2(0.4375, -0.0208),   // 0 top-left band, upper edge
    vec2(0.2344, -0.0347), vec2(0.1644, 0.1685), vec2(0.1009, 0.4561), vec2(-0.0234, 0.5625),   // 1 top-left, falling across it
    vec2(-0.0234, 0.3681), vec2(0.1720, 0.2902), vec2(0.3623, 0.1776), vec2(0.5625, 0.1319),   // 2 top-left band, lower edge
    vec2(0.2188, 1.0417), vec2(0.4802, 0.8182), vec2(0.7707, 0.7536), vec2(1.0312, 0.5250),    // 3 bottom-right, the long seam
    vec2(1.0234, 0.2778), vec2(0.8133, 0.5126), vec2(0.8418, 0.7997), vec2(0.5781, 1.0417),    // 4 bottom-right, falling across it
    vec2(0.5469, 0.6250), vec2(0.7132, 0.5569), vec2(0.8800, 0.4954), vec2(1.0312, 0.3472),    // 5 bottom-right, the fold above
    vec2(-0.0234, 0.5694), vec2(0.2303, 0.5757), vec2(0.3202, 0.6621), vec2(0.5469, 0.7986),   // 6 the swell through the middle
    vec2(-0.0234, 0.9236), vec2(0.0665, 0.8069), vec2(0.1900, 0.9205), vec2(0.2500, 1.0556)    // 7 bottom-left fold
);
// Per seam: brightness, where along it the light peaks (0..1), how far the peak spreads.
const vec3 S[8] = vec3[](
    vec3(1.00, 0.42, 0.28), vec3(1.00, 0.30, 0.30), vec3(0.16, 0.25, 0.35), vec3(1.00, 0.74, 0.26),
    vec3(1.00, 0.36, 0.28), vec3(0.22, 0.60, 0.50), vec3(0.18, 0.30, 0.60), vec3(0.30, 0.30, 0.50)
);
const int COARSE = 16, FINE = 12;

// Seam k's four control points in screen space, all four wandering: the inner two on wide slow
// circles (~65 px of travel at 1080p), the off-screen ends on smaller ones (~24 px) so the seams
// also slide along the screen's edges. The pace never changes, only the length of the walk, and
// nothing repeats in step — under ~1 px a tick at 10 Hz.
void controls(int k, out vec2 c0, out vec2 c1, out vec2 c2, out vec2 c3) {
    vec2 ar = vec2(aspect, 1.0);
    float f = float(k);
    vec2 w0 = 0.022 * vec2(sin(time * 0.090 + f * 3.1 + 0.6), cos(time * 0.115 + f * 2.2 + 1.4));
    vec2 w1 = 0.060 * vec2(sin(time * 0.170 + f * 1.7), cos(time * 0.130 + f * 2.3));
    vec2 w2 = 0.060 * vec2(sin(time * 0.150 + f * 2.9 + 1.0), cos(time * 0.115 + f * 1.1 + 2.0));
    vec2 w3 = 0.022 * vec2(sin(time * 0.105 + f * 1.3 + 2.8), cos(time * 0.087 + f * 3.4 + 0.2));
    c0 = (P[k * 4] + w0) * ar;
    c1 = (P[k * 4 + 1] + w1) * ar;
    c2 = (P[k * 4 + 2] + w2) * ar;
    c3 = (P[k * 4 + 3] + w3) * ar;
}

vec2 bez(vec2 c0, vec2 c1, vec2 c2, vec2 c3, float t) {
    float u = 1.0 - t;
    return u * u * u * c0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * c3;
}

// Signed distance to seam k in height units (positive on the right hand of its direction, which is
// below for the left-to-right ones) and where along it the nearest point lies. A coarse pass finds
// the nearest stretch, a fine one measures it.
vec2 seam(int k, vec2 p) {
    vec2 c0, c1, c2, c3;
    controls(k, c0, c1, c2, c3);
    float best = 1e9;
    int near = 0;
    vec2 a = c0;
    for (int s = 1; s <= COARSE; ++s) {
        vec2 b = bez(c0, c1, c2, c3, float(s) / float(COARSE));
        vec2 ab = b - a, ap = p - a;
        float d = length(ap - ab * clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0));
        if (d < best) { best = d; near = s - 1; }
        a = b;
    }
    float t0 = max(float(near) - 0.5, 0.0) / float(COARSE), t1 = min(float(near) + 1.5, float(COARSE)) / float(COARSE);
    float side = 1.0, at = 0.0;
    best = 1e9;
    a = bez(c0, c1, c2, c3, t0);
    for (int s = 1; s <= FINE; ++s) {
        float tb = mix(t0, t1, float(s) / float(FINE));
        vec2 b = bez(c0, c1, c2, c3, tb);
        vec2 ab = b - a, ap = p - a;
        float h = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
        float d = length(ap - ab * h);
        if (d < best) {
            best = d;
            side = ab.x * ap.y - ab.y * ap.x < 0.0 ? -1.0 : 1.0;
            at = mix(t0, t1, (float(s - 1) + h) / float(FINE));
        }
        a = b;
    }
    return vec2(best * side, at);
}

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

float side(float sd) { return smoothstep(-0.004, 0.004, sd); }   // soft "on the positive side"

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * vec2(aspect, 1.0);
    vec3 acc = hue(accent.rgb, clamp(0.5 * (max(accent.r, max(accent.g, accent.b)) + min(accent.r, min(accent.g, accent.b))), 0.45, 0.6), 0.8);

    vec2 q[8];
    float halo = 0.0, core = 0.0, peak[8];
    for (int k = 0; k < 8; ++k) {
        q[k] = seam(k, p);
        vec3 s = S[k];
        // The light wanders wide along each seam — over half its length; every seam carries a
        // tighter spark counter-drifting against it, and the two long ones a third, slower light
        // besides: three lights passing each other under the silk.
        float centre = s.y + 0.28 * sin(time * 0.18 + float(k) * 1.3);
        float glow = exp(-pow((q[k].y - centre) / s.z, 2.0));
        float far = s.y - 0.24 * sin(time * 0.11 + float(k) * 0.9 + 2.2);
        float spark = (k == 0 || k == 1 || k == 3 || k == 4 ? 0.35 : 0.22)
                    * exp(-pow((q[k].y - far) / (s.z * 0.6), 2.0));
        float third = 0.0;
        if (k == 0 || k == 3) {
            float away = s.y + 0.18 * sin(time * 0.09 + float(k) * 2.6 + 4.0);
            third = 0.30 * exp(-pow((q[k].y - away) / (s.z * 0.8), 2.0));
        }
        peak[k] = s.x * (0.15 + 0.70 * glow + spark + third);
        // Seams 2, 5 and 6 begin or end in view: their tips reach far out of, and back into, the dark.
        if (k == 2) peak[k] *= smoothstep(1.0 + 0.12 * sin(time * 0.20 + 1.1), 0.6, q[k].y);
        if (k == 5) peak[k] *= smoothstep(0.0 - 0.12 * sin(time * 0.16 + 2.4), 0.35, q[k].y);
        if (k == 6) peak[k] *= smoothstep(1.0 + 0.12 * sin(time * 0.22 + 0.4), 0.6, q[k].y);
        float d = abs(q[k].x), w = 1.1 * px;
        float shim = 1.0 + 0.10 * sin(time * 0.9 + float(k) * 2.1);   // silk catching the light
        core += peak[k] * shim * exp(-(d * d) / (w * w));
        halo += peak[k] * (0.35 * exp(-d / (2.5 * px)) + 0.06 * exp(-d / 0.02));   // a fine edge, not a glow
    }
    // The fabric: translucent sheets trailing the seams, brightest along them, each clipped by the
    // seam that folds over it.
    float d0 = q[0].x, d1 = q[1].x, d2 = q[2].x, d3 = q[3].x, d4 = q[4].x, d5 = q[5].x, d6 = q[6].x, d7 = q[7].x;
    float sheet = 0.0;
    sheet += side(d1) * (0.30 + 0.70 * peak[1]) * exp(-d1 / 0.20) * 0.9;                  // left of 1
    sheet += side(d0) * side(-d2) * (0.30 + 0.70 * peak[0]) * exp(-d0 / 0.09);           // between 0 and 2
    sheet += side(-d0) * side(d1) * 0.6 * exp(-abs(d0) / 0.12) * peak[0];                // the glow above 0, within 1
    sheet += side(-d4) * side(-d3) * (0.30 + 0.70 * peak[4]) * exp(d4 / 0.16);           // right of 4, above 3
    sheet += side(d3) * side(d4) * (0.30 + 0.70 * peak[3]) * exp(-d3 / 0.20) * 0.9;      // below 3, left of 4
    sheet += side(d5) * side(-d3) * 1.6 * peak[5] * exp(-d5 / 0.20);                              // under the fold
    sheet += side(d6) * 1.4 * peak[6] * exp(-d6 / 0.30);                                          // under the swell
    sheet += side(d7) * 0.55 * exp(-d7 / 0.10);                                          // bottom-left fold

    // Where two seams cross, a faint brightening; the crossings pulse in turns, handing light over.
    float bloom = exp(-(abs(d0) + abs(d1)) / 0.045) * (1.0 + 0.50 * sin(time * 0.50))
                + exp(-(abs(d3) + abs(d4)) / 0.045) * (1.0 + 0.50 * sin(time * 0.50 + 3.14159));

    // Everything lit breathes together, about the span of a breath, a few percent at most.
    float breath = 1.0 + 0.060 * sin(time * 0.42);
    sheet *= breath;
    core *= breath;
    halo *= breath;

    // And a broad sheen crosses the whole field once a minute: light through water.
    float sheen = 0.10 * pow(max(sin(dot(uv, vec2(0.9, 0.5)) * 1.8 - time * 0.10 + 1.0), 0.0), 2.5);

    // The centre is a touch lighter, under the logo.
    float r = length(p - vec2(0.5 * aspect, 0.5));
    float pool = 0.18 * exp(-r / 0.35);

    // Both fields are drawn and mixed by `dark`, so a mode switch can fade from one to the other.
    vec3 night = mix(hue(acc, 0.03, 0.0), hue(acc, 0.06, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    vec3 light = acc * (sheet * 0.6 + bloom * 0.15 + pool * 0.3 + halo * 0.6 + sheen)
               + mix(acc, vec3(1.0), 0.25) * core * 0.55;
    night += vec3(1.0) - exp(-light * 1.4);
    night *= 1.0 - 0.30 * pow(length(uv - 0.5) * 1.25, 2.4);   // vignette

    vec3 day = mix(hue(acc, 0.66, 0.0), hue(acc, 0.80, 0.0), smoothstep(1.0, 0.0, length(uv - vec2(0.5, 0.5)) * 1.5));
    day = mix(day, hue(acc, 0.56, 0.0), clamp(sheet * 0.6, 0.0, 0.7));
    day = mix(day, hue(acc, 0.86, 0.0), clamp(pool * 0.8, 0.0, 0.6));
    day = mix(day, hue(acc, 0.48, 0.0), clamp(bloom * 0.15, 0.0, 0.2));
    day = mix(day, hue(acc, 0.42, 0.0), clamp(halo * 0.5, 0.0, 0.6));
    day = mix(day, hue(acc, 0.30, 0.0), clamp(core * 0.6, 0.0, 0.7));
    day = mix(day, hue(acc, 0.90, 0.0), clamp(sheen * 3.0, 0.0, 0.12));

    day = mix(vec3(dot(day, vec3(0.299, 0.587, 0.114))), day, 0.5);   // daylight is softer: half the colour
    vec3 col = mix(day, night, clamp(dark, 0.0, 1.0));
    // A whisper of dither keeps the long gradients from banding.
    float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
