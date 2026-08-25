#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_strength;
uniform float u_corner_radius;
uniform float u_ring_width;
uniform sampler2D u_texture_input;

out vec4 frag_color;

float roundedBoxSdf(vec2 point, vec2 halfSize, float radius) {
  vec2 corner = abs(point) - halfSize + radius;
  return length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
}

vec2 roundedBoxNormal(vec2 point, vec2 halfSize, float radius) {
  vec2 direction = vec2(
    point.x < 0.0 ? -1.0 : 1.0,
    point.y < 0.0 ? -1.0 : 1.0
  );
  vec2 corner = abs(point) - halfSize + radius;
  vec2 cornerNormal = max(corner, vec2(0.0)) * direction;

  if (cornerNormal.x > 0.0 || cornerNormal.y > 0.0) {
    return normalize(cornerNormal);
  }

  return corner.x > corner.y ? vec2(direction.x, 0.0) : vec2(0.0, direction.y);
}

void main() {
  vec2 localUv = FlutterFragCoord().xy / u_size;
  vec2 point = (localUv - 0.5) * u_size;
  vec2 halfSize = u_size * 0.5;
  float edgeDistance = max(-roundedBoxSdf(point, halfSize, u_corner_radius), 0.0);
  float edgeWeight = 1.0 - smoothstep(0.0, u_ring_width, edgeDistance);
  vec2 normal = roundedBoxNormal(point, halfSize, u_corner_radius);
  vec2 offset = normal * u_strength * edgeWeight * edgeWeight / u_size;
  vec2 sampleUv = localUv;

#ifdef IMPELLER_TARGET_OPENGLES
  sampleUv.y = 1.0 - sampleUv.y;
  offset.y = -offset.y;
#endif

  sampleUv = clamp(sampleUv - offset, vec2(0.0), vec2(1.0));
  frag_color = texture(u_texture_input, sampleUv);
}
