#include <flutter/runtime_effect.glsl>

uniform float uWidth;
uniform float uHeight;
uniform float uSunLat;
uniform float uSunLon;
uniform float uCenterLat;
uniform float uCenterLon;
uniform float uScale;
uniform sampler2D uNightLights;

out vec4 fragColor;

const float PI = 3.14159265358979323846;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 offset = fragCoord - vec2(uWidth * 0.5, uHeight * 0.5);

    float sinCenterLat = clamp(sin(uCenterLat), -0.9999, 0.9999);
    float centerMercY  = 0.5 * log((1.0 + sinCenterLat) / (1.0 - sinCenterLat));

    float mercY = centerMercY - offset.y / uScale;
    float lon   = uCenterLon  + offset.x / uScale;
    float lat   = 2.0 * atan(exp(mercY)) - PI * 0.5;

    float dLon = mod((lon - uSunLon) + PI, 2.0 * PI) - PI;

    float cosZenith = sin(uSunLat) * sin(lat)
                    + cos(uSunLat) * cos(lat) * cos(dLon);
    float elevRad = asin(clamp(cosZenith, -1.0, 1.0));

    float dayEdge   =  5.0 * PI / 180.0;
    float nightEdge = -12.0 * PI / 180.0;
    float t = clamp((dayEdge - elevRad) / (dayEdge - nightEdge), 0.0, 1.0);
    float opacity = 0.70 * t * t * t;

    if (opacity <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float u = (lon + PI) / (2.0 * PI);
    float v = (PI * 0.5 - lat) / PI;
    vec4 lights = texture(uNightLights, vec2(fract(u), clamp(v, 0.0, 1.0)));

    float lum = dot(lights.rgb, vec3(0.2126, 0.7152, 0.0722));
    float lightsVis = clamp(lum * 5.0, 0.0, 1.0) * opacity;

    vec3 darkColor  = vec3(0.0, 0.0, 0.005);
    vec3 cityLights = vec3(1.0, 0.88, 0.60) * lights.r * 1.8;
    vec3 outRgb     = mix(darkColor, cityLights, lightsVis);
    float outAlpha  = max(opacity, lightsVis * 0.9);

    fragColor = vec4(outRgb, outAlpha);
}
