#version 440
// The desktop label's ink: black over a bright wallpaper, white over a dark one. `source` is the
// label drawn white (its alpha is the glyphs); `backdrop` is the wallpaper under the label shrunk
// to a few pixels on the GPU. Their mean luma picks the ink, through a narrow smoothstep so a
// drifting wallpaper fades the ink rather than flipping it. A soft halo in the opposite tone, one
// pixel down and right like Plasma's shadow, keeps the edges readable on busy fields.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;      // one logical pixel of `source`, in texture units
    float seen;      // 1 once `backdrop` holds the wallpaper; 0 keeps Plasma's white ink
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D backdrop;

void main()
{
    float l = 0.0;
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 2; ++j) {
            l += dot(texture(backdrop, vec2((float(i) + 0.5) / 4.0, (float(j) + 0.5) / 2.0)).rgb, vec3(0.299, 0.587, 0.114));
        }
    }
    float k = seen * smoothstep(0.52, 0.60, l / 8.0);   // 0 white ink .. 1 black ink

    float a = texture(source, qt_TexCoord0).a;
    vec2 c = qt_TexCoord0 - texel;   // the halo sits one pixel down and right
    float s = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            s += texture(source, c + vec2(float(x), float(y)) * texel * 1.2).a * (x == 0 && y == 0 ? 0.24 : (x == 0 || y == 0 ? 0.12 : 0.07));
        }
    }
    float h = clamp(s * 1.6, 0.0, 1.0) * mix(0.85, 0.5, k) * (1.0 - a);
    // Premultiplied: ink where the glyphs are, the halo (black under white ink, white under black) around them.
    fragColor = vec4(vec3(1.0 - k) * a + vec3(k) * h, a + h) * qt_Opacity;
}
