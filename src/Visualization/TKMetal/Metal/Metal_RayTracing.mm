// Copyright (c) 2024 OPEN CASCADE SAS
//
// This file is part of Open CASCADE Technology software library.
//
// This library is free software; you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License version 2.1 as published
// by the Free Software Foundation, with special exception defined in the file
// OCCT_LGPL_EXCEPTION.txt. Consult the file LICENSE_LGPL_21.txt included in OCCT
// distribution for complete text of the license and disclaimer of any warranty.
//
// Alternatively, this file may be used under the terms of Open CASCADE
// commercial license or contractual agreement.

#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

#include <Metal_RayTracing.hxx>
#include <Metal_Context.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_RayTracing, Standard_Transient)

// Ray tracing shaders using Metal Performance Shaders
static const char* RAYTRACING_SHADER_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

// Match the C++ structures
struct RaytraceMaterial {
  float4 ambient;
  float4 diffuse;      // RGB + textureId
  float4 specular;     // RGB + shininess
  float4 emission;
  float4 reflection;
  float4 refraction;
  float4 transparency; // alpha, transparency, IOR, 1/IOR
};

struct RaytraceLight {
  float4 emission;     // RGB + intensity
  float4 position;     // XYZ + type (0=directional, 1=point)
};

struct CameraParams {
  float3 origin;
  float3 lookAt;
  float3 up;
  float  fov;
  float2 resolution;
  int    maxBounces;
  int    shadowsEnabled;
  int    reflectionsEnabled;
  int    lightCount;
};

// Ray structure for MPS
struct Ray {
  packed_float3 origin;
  float minDistance;
  packed_float3 direction;
  float maxDistance;
};

// Intersection result from MPS
struct Intersection {
  float distance;
  int primitiveIndex;
  float2 coordinates;
};

// Generate primary rays from camera
kernel void rayGen(
  device Ray* rays [[buffer(0)]],
  constant CameraParams& camera [[buffer(1)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;

  // Compute ray direction
  float3 forward = normalize(camera.lookAt - camera.origin);
  float3 right = normalize(cross(forward, camera.up));
  float3 up = cross(right, forward);

  float aspectRatio = camera.resolution.x / camera.resolution.y;
  float halfHeight = tan(camera.fov * 0.5);
  float halfWidth = aspectRatio * halfHeight;

  float u = (float(gid.x) + 0.5) / camera.resolution.x * 2.0 - 1.0;
  float v = (float(gid.y) + 0.5) / camera.resolution.y * 2.0 - 1.0;

  float3 direction = normalize(forward + u * halfWidth * right - v * halfHeight * up);

  rays[rayIndex].origin = camera.origin;
  rays[rayIndex].minDistance = 0.001;
  rays[rayIndex].direction = direction;
  rays[rayIndex].maxDistance = INFINITY;
}

// Generate shadow rays from hit points toward a specific light
kernel void shadowRayGenForLight(
  device Ray* shadowRays [[buffer(0)]],
  device const Intersection* primaryIntersections [[buffer(1)]],
  device const Ray* primaryRays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  constant float3* vertices [[buffer(4)]],
  constant uint* indices [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int& lightIndex [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = primaryIntersections[rayIndex];

  // Default: invalid shadow ray (no hit on primary)
  shadowRays[rayIndex].origin = float3(0.0);
  shadowRays[rayIndex].minDistance = -1.0;  // Mark as invalid
  shadowRays[rayIndex].direction = float3(0.0, 1.0, 0.0);
  shadowRays[rayIndex].maxDistance = 0.0;

  if (isect.distance < 0.0) {
    return;  // No primary hit, no shadow ray needed
  }

  RaytraceLight light = lights[lightIndex];

  // Compute hit point
  float3 hitPoint = float3(primaryRays[rayIndex].origin) +
                    isect.distance * float3(primaryRays[rayIndex].direction);

  // Compute light direction and distance
  float3 lightDir;
  float maxDist;

  if (light.position.w < 0.5) {
    // Directional light - ray goes to infinity
    lightDir = normalize(-light.position.xyz);
    maxDist = 1e38;
  } else {
    // Point light - ray goes to light position
    float3 toLight = light.position.xyz - hitPoint;
    float dist = length(toLight);
    lightDir = toLight / dist;
    maxDist = dist - 0.001;  // Stop just before light
  }

  // Offset origin slightly to avoid self-intersection
  float3 shadowOrigin = hitPoint + lightDir * 0.01;

  shadowRays[rayIndex].origin = shadowOrigin;
  shadowRays[rayIndex].minDistance = 0.001;
  shadowRays[rayIndex].direction = lightDir;
  shadowRays[rayIndex].maxDistance = maxDist;
}

// Shade intersections with per-light shadow support
kernel void shade(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  constant float3* vertices [[buffer(3)]],
  constant uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  device const Intersection* shadowIntersections [[buffer(8)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];
  uint pixelCount = uint(camera.resolution.x) * uint(camera.resolution.y);

  float4 color;

  if (isect.distance < 0.0) {
    // No hit - background gradient
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    // Hit - compute shading
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    // Compute normal
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    // Hit point
    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    // Material lookup using per-triangle material index buffer
    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    // Flip normal if backface
    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Start with emission (self-illumination)
    float3 totalLight = mat.emission.rgb;

    // Add ambient contribution
    totalLight += mat.ambient.rgb * 0.15;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        // Directional light
        lightDir = normalize(-light.position.xyz);
      } else {
        // Point light
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      // Per-light shadow test: shadow intersections packed as [light0 pixels][light1 pixels]...
      float shadowFactor = 1.0;
      if (camera.shadowsEnabled > 0) {
        uint shadowIdx = i * pixelCount + rayIndex;
        Intersection shadowIsect = shadowIntersections[shadowIdx];
        if (shadowIsect.distance > 0.0) {
          shadowFactor = 0.0;
        }
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += shadowFactor * diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      // Specular (Blinn-Phong) - also affected by shadow
      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += shadowFactor * mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    // Apply transparency (alpha from transparency.x, opacity = 1 - transparency.y)
    float alpha = mat.transparency.x;
    float opacity = 1.0 - mat.transparency.y;

    // Clamp final color
    color = float4(clamp(totalLight, 0.0, 1.0), alpha * opacity);
  }

  output.write(color, gid);
}

// Shade without shadows (fallback)
kernel void shadeNoShadow(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  constant float3* vertices [[buffer(3)]],
  constant uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) {
    return;
  }

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    float3 totalLight = mat.emission.rgb;
    totalLight += mat.ambient.rgb * 0.2;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.1 * dist * dist);
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    float alpha = mat.transparency.x;
    float opacity = 1.0 - mat.transparency.y;
    color = float4(clamp(totalLight, 0.0, 1.0), alpha * opacity);
  }

  output.write(color, gid);
}

// Phase 5: Generate reflection rays from hit points
kernel void reflectionRayGen(
  device Ray* reflectionRays [[buffer(0)]],
  device const Intersection* intersections [[buffer(1)]],
  device const Ray* incomingRays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  constant float3* vertices [[buffer(4)]],
  constant uint* indices [[buffer(5)]],
  constant RaytraceMaterial* materials [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  // Default: invalid ray
  reflectionRays[rayIndex].origin = float3(0.0);
  reflectionRays[rayIndex].minDistance = -1.0;
  reflectionRays[rayIndex].direction = float3(0.0, 1.0, 0.0);
  reflectionRays[rayIndex].maxDistance = 0.0;

  if (isect.distance < 0.0) return;

  // Get material
  uint triIndex = uint(isect.primitiveIndex);
  int matIdx = materialIndices[triIndex];
  RaytraceMaterial mat = materials[matIdx];

  // Only reflect if material is reflective
  float reflectivity = mat.reflection.w;
  if (reflectivity < 0.01) return;

  // Compute hit point and normal
  uint i0 = indices[triIndex * 3 + 0];
  uint i1 = indices[triIndex * 3 + 1];
  uint i2 = indices[triIndex * 3 + 2];

  float3 v0 = vertices[i0];
  float3 v1 = vertices[i1];
  float3 v2 = vertices[i2];

  float3 edge1 = v1 - v0;
  float3 edge2 = v2 - v0;
  float3 normal = normalize(cross(edge1, edge2));

  float3 hitPoint = float3(incomingRays[rayIndex].origin) +
                    isect.distance * float3(incomingRays[rayIndex].direction);
  float3 inDir = normalize(float3(incomingRays[rayIndex].direction));

  // Flip normal if backface
  if (dot(normal, inDir) > 0.0) {
    normal = -normal;
  }

  // Reflect direction
  float3 reflectDir = reflect(inDir, normal);

  // Offset origin to avoid self-intersection
  float3 reflectOrigin = hitPoint + normal * 0.01;

  reflectionRays[rayIndex].origin = reflectOrigin;
  reflectionRays[rayIndex].minDistance = 0.001;
  reflectionRays[rayIndex].direction = reflectDir;
  reflectionRays[rayIndex].maxDistance = 1e38;
}

// Phase 5: Compute color for reflection bounce
kernel void computeBounceColor(
  device float4* bounceColors [[buffer(0)]],
  device const Intersection* intersections [[buffer(1)]],
  device const Ray* rays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  device const float3* vertices [[buffer(4)]],
  device const uint* indices [[buffer(5)]],
  constant RaytraceMaterial* materials [[buffer(6)]],
  constant RaytraceLight* lights [[buffer(7)]],
  device const int* materialIndices [[buffer(8)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    // Sky color for missed reflection rays
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.2, 0.2, 0.25), float3(0.6, 0.8, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Simple lighting for reflections
    float3 totalLight = mat.emission.rgb + mat.ambient.rgb * 0.2;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = -rayDir;
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float spec = pow(NdotH, max(mat.specular.w, 1.0));
      totalLight += mat.specular.rgb * light.emission.rgb * spec * attenuation * 0.5;
    }

    color = float4(clamp(totalLight, 0.0, 1.0), 1.0);
  }

  bounceColors[rayIndex] = color;
}

// Phase 5: Shade with reflections
kernel void shadeWithReflections(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  device const float3* vertices [[buffer(3)]],
  device const uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  device const int* materialIndices [[buffer(7)]],
  device const Intersection* shadowIntersections [[buffer(8)]],
  device const float4* reflectionColors [[buffer(9)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  uint pixelCount = uint(camera.resolution.x) * uint(camera.resolution.y);
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Base lighting
    float3 totalLight = mat.emission.rgb + mat.ambient.rgb * 0.15;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      // Shadow
      float shadowFactor = 1.0;
      if (camera.shadowsEnabled > 0) {
        uint shadowIdx = i * pixelCount + rayIndex;
        Intersection shadowIsect = shadowIntersections[shadowIdx];
        if (shadowIsect.distance > 0.0) {
          shadowFactor = 0.0;
        }
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += shadowFactor * diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += shadowFactor * mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    // Add reflection contribution
    float reflectivity = mat.reflection.w;
    if (camera.reflectionsEnabled > 0 && reflectivity > 0.01) {
      float3 reflectionColor = reflectionColors[rayIndex].rgb;
      float3 tint = mat.reflection.rgb;
      totalLight = totalLight * (1.0 - reflectivity) + reflectionColor * tint * reflectivity;
    }

    color = float4(clamp(totalLight, 0.0, 1.0), 1.0);
  }

  output.write(color, gid);
}

// Phase 6: Fresnel coefficient calculation (dielectric)
inline float fresnelDielectric(float cosThetaI, float etaI, float etaT) {
  cosThetaI = clamp(cosThetaI, -1.0f, 1.0f);

  // Potentially swap indices of refraction
  bool entering = cosThetaI > 0.0f;
  if (!entering) {
    float tmp = etaI;
    etaI = etaT;
    etaT = tmp;
    cosThetaI = abs(cosThetaI);
  }

  // Compute cosThetaT using Snell's law
  float sinThetaI = sqrt(max(0.0f, 1.0f - cosThetaI * cosThetaI));
  float sinThetaT = etaI / etaT * sinThetaI;

  // Total internal reflection
  if (sinThetaT >= 1.0f) {
    return 1.0f;
  }

  float cosThetaT = sqrt(max(0.0f, 1.0f - sinThetaT * sinThetaT));

  float Rparl = ((etaT * cosThetaI) - (etaI * cosThetaT)) /
                ((etaT * cosThetaI) + (etaI * cosThetaT));
  float Rperp = ((etaI * cosThetaI) - (etaT * cosThetaT)) /
                ((etaI * cosThetaI) + (etaT * cosThetaT));

  return (Rparl * Rparl + Rperp * Rperp) / 2.0f;
}

// Phase 6: Compute refraction direction
inline bool refractRay(float3 I, float3 N, float eta, thread float3& T) {
  float NdotI = dot(N, I);
  float k = 1.0f - eta * eta * (1.0f - NdotI * NdotI);
  if (k < 0.0f) {
    return false;  // Total internal reflection
  }
  T = eta * I - (eta * NdotI + sqrt(k)) * N;
  return true;
}

// Phase 8: Interpolate UV coordinates using barycentric coordinates
inline float2 interpolateUV(
  constant float2* texCoords,
  uint i0, uint i1, uint i2,
  float2 barycentrics)
{
  float2 uv0 = texCoords[i0];
  float2 uv1 = texCoords[i1];
  float2 uv2 = texCoords[i2];
  float w = 1.0f - barycentrics.x - barycentrics.y;
  return w * uv0 + barycentrics.x * uv1 + barycentrics.y * uv2;
}

// Phase 8: Sample diffuse texture with material texture ID
inline float4 sampleDiffuseTexture(
  texture2d_array<float> textures,
  sampler texSampler,
  float2 uv,
  int textureId)
{
  if (textureId < 0) {
    return float4(1.0f);  // No texture, return white
  }
  return textures.sample(texSampler, uv, textureId);
}

// Phase 8: Sample and decode normal map
inline float3 sampleNormalMap(
  texture2d_array<float> normalMaps,
  sampler texSampler,
  float2 uv,
  int textureId,
  float3 geometricNormal,
  float3 edge1,
  float3 edge2,
  float2 deltaUV1,
  float2 deltaUV2)
{
  if (textureId < 0) {
    return geometricNormal;  // No normal map
  }

  // Sample normal map (stored as RGB, need to decode)
  float3 normalSample = normalMaps.sample(texSampler, uv, textureId).rgb;
  normalSample = normalSample * 2.0f - 1.0f;  // Decode from [0,1] to [-1,1]

  // Compute TBN matrix
  float f = 1.0f / (deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y + 0.0001f);
  float3 tangent = normalize(f * (deltaUV2.y * edge1 - deltaUV1.y * edge2));
  float3 bitangent = normalize(f * (-deltaUV2.x * edge1 + deltaUV1.x * edge2));
  float3 normal = normalize(geometricNormal);

  // Gram-Schmidt orthogonalize
  tangent = normalize(tangent - dot(tangent, normal) * normal);
  bitangent = cross(normal, tangent);

  // Transform normal from tangent space to world space
  float3x3 TBN = float3x3(tangent, bitangent, normal);
  return normalize(TBN * normalSample);
}

// Phase 6: Generate refraction rays from hit points
kernel void refractionRayGen(
  device Ray* refractionRays [[buffer(0)]],
  device const Intersection* intersections [[buffer(1)]],
  device const Ray* incomingRays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  constant float3* vertices [[buffer(4)]],
  constant uint* indices [[buffer(5)]],
  constant RaytraceMaterial* materials [[buffer(6)]],
  constant int* materialIndices [[buffer(7)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  // Default: invalid ray
  refractionRays[rayIndex].origin = float3(0.0);
  refractionRays[rayIndex].minDistance = -1.0;
  refractionRays[rayIndex].direction = float3(0.0, 1.0, 0.0);
  refractionRays[rayIndex].maxDistance = 0.0;

  if (isect.distance < 0.0) return;

  // Get material
  uint triIndex = uint(isect.primitiveIndex);
  int matIdx = materialIndices[triIndex];
  RaytraceMaterial mat = materials[matIdx];

  // Only refract if material is transparent (transparency.y > 0)
  float transparency = mat.transparency.y;
  if (transparency < 0.01) return;

  // Get IOR from transparency.z (default to 1.5 for glass)
  float ior = mat.transparency.z;
  if (ior < 1.0) ior = 1.5;

  // Compute hit point and normal
  uint i0 = indices[triIndex * 3 + 0];
  uint i1 = indices[triIndex * 3 + 1];
  uint i2 = indices[triIndex * 3 + 2];

  float3 v0 = vertices[i0];
  float3 v1 = vertices[i1];
  float3 v2 = vertices[i2];

  float3 edge1 = v1 - v0;
  float3 edge2 = v2 - v0;
  float3 normal = normalize(cross(edge1, edge2));

  float3 hitPoint = float3(incomingRays[rayIndex].origin) +
                    isect.distance * float3(incomingRays[rayIndex].direction);
  float3 inDir = normalize(float3(incomingRays[rayIndex].direction));

  // Determine if entering or exiting
  bool entering = dot(normal, inDir) < 0.0;
  float3 faceNormal = entering ? normal : -normal;
  float eta = entering ? (1.0 / ior) : ior;

  // Compute refracted direction
  float3 refractDir;
  if (!refractRay(inDir, faceNormal, eta, refractDir)) {
    // Total internal reflection - generate reflection ray instead
    refractDir = reflect(inDir, faceNormal);
  }

  // Offset origin to avoid self-intersection (in refraction direction)
  float3 refractOrigin = hitPoint - faceNormal * 0.01;

  refractionRays[rayIndex].origin = refractOrigin;
  refractionRays[rayIndex].minDistance = 0.001;
  refractionRays[rayIndex].direction = normalize(refractDir);
  refractionRays[rayIndex].maxDistance = 1e38;
}

// Phase 6: Compute color for refraction rays
kernel void computeRefractionColor(
  device float4* refractionColors [[buffer(0)]],
  device const Intersection* intersections [[buffer(1)]],
  device const Ray* rays [[buffer(2)]],
  constant CameraParams& camera [[buffer(3)]],
  device const float3* vertices [[buffer(4)]],
  device const uint* indices [[buffer(5)]],
  constant RaytraceMaterial* materials [[buffer(6)]],
  constant RaytraceLight* lights [[buffer(7)]],
  device const int* materialIndices [[buffer(8)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    // Sky color for rays that escape
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.2, 0.2, 0.25), float3(0.6, 0.8, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Simple lighting for refracted view
    float3 totalLight = mat.emission.rgb + mat.ambient.rgb * 0.2;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = -rayDir;
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float spec = pow(NdotH, max(mat.specular.w, 1.0));
      totalLight += mat.specular.rgb * light.emission.rgb * spec * attenuation * 0.5;
    }

    color = float4(clamp(totalLight, 0.0, 1.0), 1.0);
  }

  refractionColors[rayIndex] = color;
}

// Phase 6: Full shading with reflections and refractions
kernel void shadeWithAll(
  texture2d<float, access::write> output [[texture(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  device const float3* vertices [[buffer(3)]],
  device const uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  device const int* materialIndices [[buffer(7)]],
  device const Intersection* shadowIntersections [[buffer(8)]],
  device const float4* reflectionColors [[buffer(9)]],
  device const float4* refractionColors [[buffer(10)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  uint pixelCount = uint(camera.resolution.x) * uint(camera.resolution.y);
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];
    float3 diffuseColor = mat.diffuse.rgb;

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Base lighting
    float3 totalLight = mat.emission.rgb + mat.ambient.rgb * 0.15;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      // Shadow
      float shadowFactor = 1.0;
      if (camera.shadowsEnabled > 0) {
        uint shadowIdx = i * pixelCount + rayIndex;
        Intersection shadowIsect = shadowIntersections[shadowIdx];
        if (shadowIsect.distance > 0.0) {
          shadowFactor = 0.0;
        }
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += shadowFactor * diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += shadowFactor * mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    // Get material properties
    float reflectivity = mat.reflection.w;
    float transparency = mat.transparency.y;
    float ior = mat.transparency.z;
    if (ior < 1.0) ior = 1.5;

    // Compute Fresnel for transparent materials
    float fresnel = 0.0;
    if (transparency > 0.01) {
      float cosTheta = abs(dot(rayDir, faceNormal));
      fresnel = fresnelDielectric(cosTheta, 1.0, ior);
    }

    // Mix reflection and refraction based on Fresnel
    float3 finalColor;

    if (transparency > 0.01) {
      // For transparent materials: Fresnel determines reflection vs refraction
      // No direct surface shading - light passes through or reflects
      float3 reflColor = reflectionColors[rayIndex].rgb;
      float3 refrColor = refractionColors[rayIndex].rgb;
      float3 reflTint = mat.reflection.rgb;
      float3 refrTint = mat.refraction.rgb;
      if (length(refrTint) < 0.01) refrTint = float3(1.0);

      // Fresnel blend: reflected portion + transmitted portion = 1
      float reflWeight = fresnel;
      float refrWeight = 1.0 - fresnel;

      // Blend reflection and refraction, with a small amount of surface color
      float surfaceWeight = (1.0 - transparency) * 0.5;
      finalColor = reflColor * reflTint * reflWeight +
                   refrColor * refrTint * refrWeight * transparency +
                   totalLight * surfaceWeight;
    }
    else if (camera.reflectionsEnabled > 0 && reflectivity > 0.01) {
      // Opaque reflective material
      float3 reflColor = reflectionColors[rayIndex].rgb;
      float3 tint = mat.reflection.rgb;
      finalColor = totalLight * (1.0 - reflectivity) + reflColor * tint * reflectivity;
    }
    else {
      // Opaque non-reflective material
      finalColor = totalLight;
    }

    color = float4(clamp(finalColor, 0.0, 1.0), 1.0);
  }

  output.write(color, gid);
}

// ==========================================================================
// Phase 9: Path Tracing Functions and Kernels
// ==========================================================================

// PCG random - fast high-quality RNG
inline uint pcg_hash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

inline float random_float(thread uint& seed) {
    seed = pcg_hash(seed);
    return float(seed) / float(0xffffffffu);
}

inline float2 random_float2(thread uint& seed) {
    return float2(random_float(seed), random_float(seed));
}

// Cosine-weighted hemisphere sampling (importance sampling for diffuse)
inline float3 sample_cosine_hemisphere(float2 u, float3 normal) {
    float r = sqrt(u.x);
    float theta = 2.0f * M_PI_F * u.y;

    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(max(0.0f, 1.0f - u.x));

    // Build orthonormal basis from normal
    float3 up = abs(normal.y) < 0.999f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);

    return tangent * x + bitangent * y + normal * z;
}

// Phase 9: Camera parameters extended with frame index for accumulation
struct PathTraceCameraParams {
    float3 origin;
    float3 forward;
    float3 right;
    float3 up;
    float fov;
    float2 resolution;
    int maxBounces;
    int shadowsEnabled;
    int reflectionsEnabled;
    int lightCount;
    uint frameIndex;    // Frame counter for accumulation
};

// Phase 9: Generate jittered rays for path tracing
kernel void pathTraceRayGen(
    device Ray* rays [[buffer(0)]],
    constant PathTraceCameraParams& camera [[buffer(1)]],
    device uint* rngSeeds [[buffer(2)]],
    uint2 tid [[thread_position_in_grid]])
{
    if (tid.x >= uint(camera.resolution.x) || tid.y >= uint(camera.resolution.y)) return;

    uint idx = tid.y * uint(camera.resolution.x) + tid.x;

    // Initialize or advance RNG state
    uint seed = rngSeeds[idx];
    if (camera.frameIndex == 0) {
        // First frame - initialize with pixel position and frame index
        seed = pcg_hash(tid.x + tid.y * uint(camera.resolution.x) + camera.frameIndex * 1337u);
    }

    // Jitter for anti-aliasing
    float2 jitter = random_float2(seed);
    float u = (float(tid.x) + jitter.x) / camera.resolution.x * 2.0f - 1.0f;
    float v = (float(tid.y) + jitter.y) / camera.resolution.y * 2.0f - 1.0f;

    float aspectRatio = camera.resolution.x / camera.resolution.y;
    float halfHeight = tan(camera.fov * 0.5f);
    float halfWidth = aspectRatio * halfHeight;

    float3 direction = normalize(camera.forward + u * halfWidth * camera.right - v * halfHeight * camera.up);

    rays[idx].origin = camera.origin;
    rays[idx].minDistance = 0.001f;
    rays[idx].direction = direction;
    rays[idx].maxDistance = INFINITY;

    // Save RNG state
    rngSeeds[idx] = seed;
}

// Phase 9: Path tracing kernel - traces rays and computes radiance with progressive accumulation
kernel void pathTrace(
    texture2d<float, access::read_write> output [[texture(0)]],
    device const Intersection* intersections [[buffer(0)]],
    device const Ray* rays [[buffer(1)]],
    constant PathTraceCameraParams& camera [[buffer(2)]],
    constant float3* vertices [[buffer(3)]],
    constant uint* indices [[buffer(4)]],
    constant RaytraceMaterial* materials [[buffer(5)]],
    constant int* materialIndices [[buffer(6)]],
    constant RaytraceLight* lights [[buffer(7)]],
    device uint* rngSeeds [[buffer(8)]],
    uint2 tid [[thread_position_in_grid]])
{
    if (tid.x >= uint(camera.resolution.x) || tid.y >= uint(camera.resolution.y)) return;

    uint idx = tid.y * uint(camera.resolution.x) + tid.x;
    Intersection isect = intersections[idx];

    // Get RNG state
    uint seed = rngSeeds[idx];

    float3 radiance = float3(0.0f);
    float3 throughput = float3(1.0f);

    // Current ray
    float3 rayOrigin = float3(rays[idx].origin);
    float3 rayDir = normalize(float3(rays[idx].direction));

    // Path tracing - primary ray only (for now, multi-bounce would need iterative tracing)
    if (isect.distance < 0.0f) {
        // Miss - sky color
        float t = 0.5f * (rayDir.y + 1.0f);
        radiance = throughput * mix(float3(0.5f, 0.7f, 1.0f), float3(0.8f, 0.9f, 1.0f), t) * 0.5f;
    }
    else {
        // Get hit information
        uint triIdx = uint(isect.primitiveIndex);
        uint i0 = indices[triIdx * 3 + 0];
        uint i1 = indices[triIdx * 3 + 1];
        uint i2 = indices[triIdx * 3 + 2];

        float3 v0 = vertices[i0];
        float3 v1 = vertices[i1];
        float3 v2 = vertices[i2];

        float2 bary = isect.coordinates;
        float3 hitPoint = v0 * (1.0f - bary.x - bary.y) + v1 * bary.x + v2 * bary.y;

        float3 edge1 = v1 - v0;
        float3 edge2 = v2 - v0;
        float3 normal = normalize(cross(edge1, edge2));

        // Flip normal if backface
        if (dot(normal, rayDir) > 0.0f) {
            normal = -normal;
        }

        // Get material
        int matIdx = materialIndices[triIdx];
        RaytraceMaterial mat = materials[matIdx];
        float3 albedo = mat.diffuse.rgb;

        // Add emission
        radiance += throughput * mat.emission.rgb;

        // Direct lighting (next event estimation)
        for (int l = 0; l < camera.lightCount; l++) {
            RaytraceLight light = lights[l];
            float3 lightDir;
            float attenuation = 1.0f;

            if (light.position.w < 0.5f) {
                // Directional light
                lightDir = normalize(-light.position.xyz);
            } else {
                // Point light
                float3 toLight = light.position.xyz - hitPoint;
                float lightDist = length(toLight);
                lightDir = toLight / lightDist;
                attenuation = 1.0f / (1.0f + 0.05f * lightDist * lightDist);
            }

            float NdotL = max(dot(normal, lightDir), 0.0f);
            if (NdotL > 0.0f) {
                // Diffuse contribution (no shadow test in this pass)
                radiance += throughput * albedo * light.emission.rgb * light.emission.w * NdotL * attenuation / M_PI_F;
            }
        }
    }

    // Save RNG state
    rngSeeds[idx] = seed;

    // Progressive accumulation - read previous accumulated value
    float3 prevColor = float3(0.0f);
    if (camera.frameIndex > 0) {
        // Read previous accumulated color (in linear space)
        float4 prev = output.read(tid);
        // Convert from gamma back to linear for accumulation
        prevColor = pow(prev.rgb, float3(2.2f));
    }

    // Running average: new = old * (n/(n+1)) + sample * (1/(n+1))
    float weight = 1.0f / float(camera.frameIndex + 1);
    float3 accumulatedColor = prevColor * (1.0f - weight) + radiance * weight;

    // Write to output with gamma correction
    float3 displayColor = pow(accumulatedColor, float3(1.0f / 2.2f));
    output.write(float4(saturate(displayColor), 1.0f), tid);
}

// Phase 8: Full shading with textures, reflections, and refractions
kernel void shadeWithTextures(
  texture2d<float, access::write> output [[texture(0)]],
  texture2d_array<float> diffuseTextures [[texture(1)]],
  texture2d_array<float> normalTextures [[texture(2)]],
  sampler texSampler [[sampler(0)]],
  device const Intersection* intersections [[buffer(0)]],
  device const Ray* rays [[buffer(1)]],
  constant CameraParams& camera [[buffer(2)]],
  device const float3* vertices [[buffer(3)]],
  device const uint* indices [[buffer(4)]],
  constant RaytraceMaterial* materials [[buffer(5)]],
  constant RaytraceLight* lights [[buffer(6)]],
  device const int* materialIndices [[buffer(7)]],
  device const Intersection* shadowIntersections [[buffer(8)]],
  device const float4* reflectionColors [[buffer(9)]],
  device const float4* refractionColors [[buffer(10)]],
  constant float2* texCoords [[buffer(11)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= uint(camera.resolution.x) || gid.y >= uint(camera.resolution.y)) return;

  uint rayIndex = gid.y * uint(camera.resolution.x) + gid.x;
  uint pixelCount = uint(camera.resolution.x) * uint(camera.resolution.y);
  Intersection isect = intersections[rayIndex];

  float4 color;

  if (isect.distance < 0.0) {
    float3 dir = normalize(rays[rayIndex].direction);
    float t = 0.5 * (dir.y + 1.0);
    color = float4(mix(float3(0.1, 0.1, 0.15), float3(0.5, 0.7, 1.0), t), 1.0);
  }
  else {
    uint triIndex = uint(isect.primitiveIndex);
    uint i0 = indices[triIndex * 3 + 0];
    uint i1 = indices[triIndex * 3 + 1];
    uint i2 = indices[triIndex * 3 + 2];

    float3 v0 = vertices[i0];
    float3 v1 = vertices[i1];
    float3 v2 = vertices[i2];

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 geometricNormal = normalize(cross(edge1, edge2));

    float3 hitPoint = rays[rayIndex].origin + isect.distance * rays[rayIndex].direction;

    int matIdx = materialIndices[triIndex];
    RaytraceMaterial mat = materials[matIdx];

    // Phase 8: Interpolate UV coordinates from barycentric coords
    float2 uv = interpolateUV(texCoords, i0, i1, i2, isect.coordinates);

    // Get texture IDs from material (stored in diffuse.w)
    int diffuseTexId = int(mat.diffuse.w);
    int normalTexId = -1;  // Could be stored in another field if needed

    // Sample diffuse texture
    float4 texColor = sampleDiffuseTexture(diffuseTextures, texSampler, uv, diffuseTexId);
    float3 diffuseColor = mat.diffuse.rgb * texColor.rgb;

    // Phase 8: Sample normal map if available
    float2 uv0 = texCoords[i0];
    float2 uv1 = texCoords[i1];
    float2 uv2 = texCoords[i2];
    float2 deltaUV1 = uv1 - uv0;
    float2 deltaUV2 = uv2 - uv0;

    float3 normal = sampleNormalMap(normalTextures, texSampler, uv, normalTexId,
                                    geometricNormal, edge1, edge2, deltaUV1, deltaUV2);

    float3 rayDir = normalize(float3(rays[rayIndex].direction));
    float3 faceNormal = dot(normal, rayDir) < 0.0 ? normal : -normal;

    // Base lighting
    float3 totalLight = mat.emission.rgb + mat.ambient.rgb * 0.15;

    for (int i = 0; i < camera.lightCount; ++i) {
      RaytraceLight light = lights[i];
      float3 lightDir;
      float attenuation = 1.0;

      if (light.position.w < 0.5) {
        lightDir = normalize(-light.position.xyz);
      } else {
        float3 toLight = light.position.xyz - hitPoint;
        float dist = length(toLight);
        lightDir = toLight / dist;
        attenuation = 1.0 / (1.0 + 0.05 * dist * dist);
      }

      // Shadow
      float shadowFactor = 1.0;
      if (camera.shadowsEnabled > 0) {
        uint shadowIdx = i * pixelCount + rayIndex;
        Intersection shadowIsect = shadowIntersections[shadowIdx];
        if (shadowIsect.distance > 0.0) {
          shadowFactor = 0.0;
        }
      }

      float NdotL = max(dot(faceNormal, lightDir), 0.0);
      totalLight += shadowFactor * diffuseColor * light.emission.rgb * light.emission.w * NdotL * attenuation;

      float3 viewDir = normalize(camera.origin - hitPoint);
      float3 halfDir = normalize(lightDir + viewDir);
      float NdotH = max(dot(faceNormal, halfDir), 0.0);
      float shininess = max(mat.specular.w, 1.0);
      float spec = pow(NdotH, shininess);
      totalLight += shadowFactor * mat.specular.rgb * light.emission.rgb * spec * attenuation;
    }

    // Get material properties
    float reflectivity = mat.reflection.w;
    float transparency = mat.transparency.y;
    float ior = mat.transparency.z;
    if (ior < 1.0) ior = 1.5;

    // Compute Fresnel for transparent materials
    float fresnel = 0.0;
    if (transparency > 0.01) {
      float cosTheta = abs(dot(rayDir, faceNormal));
      fresnel = fresnelDielectric(cosTheta, 1.0, ior);
    }

    // Mix reflection and refraction based on Fresnel
    float3 finalColor;

    if (transparency > 0.01) {
      float3 reflColor = reflectionColors[rayIndex].rgb;
      float3 refrColor = refractionColors[rayIndex].rgb;
      float3 reflTint = mat.reflection.rgb;
      float3 refrTint = mat.refraction.rgb;
      if (length(refrTint) < 0.01) refrTint = float3(1.0);

      float reflWeight = fresnel;
      float refrWeight = 1.0 - fresnel;

      float surfaceWeight = (1.0 - transparency) * 0.5;
      finalColor = reflColor * reflTint * reflWeight +
                   refrColor * refrTint * refrWeight * transparency +
                   totalLight * surfaceWeight;
    }
    else if (camera.reflectionsEnabled > 0 && reflectivity > 0.01) {
      float3 reflColor = reflectionColors[rayIndex].rgb;
      float3 tint = mat.reflection.rgb;
      finalColor = totalLight * (1.0 - reflectivity) + reflColor * tint * reflectivity;
    }
    else {
      finalColor = totalLight;
    }

    // Apply texture alpha
    color = float4(clamp(finalColor, 0.0, 1.0), texColor.a);
  }

  output.write(color, gid);
}
)";

// =======================================================================
// function : Metal_RayTracing
// purpose  : Constructor
// =======================================================================
Metal_RayTracing::Metal_RayTracing()
: myAccelerationStructure(nil),
  myRayIntersector(nil),
  myRayGenPipeline(nil),
  myShadePipeline(nil),
  myShadeNoShadowPipeline(nil),
  myShadowRayGenPipeline(nil),
  myReflectionRayGenPipeline(nil),
  myBounceColorPipeline(nil),
  myShadeWithReflectionsPipeline(nil),
  myRefractionRayGenPipeline(nil),
  myRefractionColorPipeline(nil),
  myShadeWithAllPipeline(nil),
  myVertexBuffer(nil),
  myIndexBuffer(nil),
  myMaterialBuffer(nil),
  myMaterialIndexBuffer(nil),
  myLightBuffer(nil),
  myRayBuffer(nil),
  myIntersectionBuffer(nil),
  myShadowRayBuffer(nil),
  myShadowIntersectionBuffer(nil),
  myReflectionRayBuffer(nil),
  myReflectionIntersectionBuffer(nil),
  myBounceColorBuffer(nil),
  myTexCoordBuffer(nil),
  myRefractionRayBuffer(nil),
  myRefractionRayBuffer2(nil),
  myRefractionIntersectionBuffer(nil),
  myRefractionIntersectionBuffer2(nil),
  myRefractionColorBuffer(nil),
  myDiffuseTextureArray(nil),
  myNormalTextureArray(nil),
  myTextureSampler(nil),
  myShaderLibrary(nil),
  myShadeWithTexturesPipeline(nil),
  myPathTraceRayGenPipeline(nil),
  myPathTracePipeline(nil),
  myAccumulatePipeline(nil),
  myAccumulationBuffer(nil),
  myRandomSeedBuffer(nil),
  myVertexCount(0),
  myTriangleCount(0),
  myMaterialCount(0),
  myLightCount(0),
  myMaxBounces(3),
  myShadowsEnabled(true),
  myReflectionsEnabled(true),
  myRefractionsEnabled(true),
  myTexturingEnabled(false),
  myPathTracingEnabled(false),
  myIsValid(false),
  myFrameIndex(0)
{
}

// =======================================================================
// function : ~Metal_RayTracing
// purpose  : Destructor
// =======================================================================
Metal_RayTracing::~Metal_RayTracing()
{
  Release(nullptr);
}

// =======================================================================
// function : IsSupported
// purpose  : Check if ray tracing is supported
// =======================================================================
bool Metal_RayTracing::IsSupported(Metal_Context* theCtx)
{
  if (theCtx == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Check for MPS ray tracing support (requires macOS 10.14+ / iOS 12+)
  // and Metal GPU Family Apple 4 or later
  if (@available(macOS 10.14, iOS 12, *))
  {
    // MPS ray tracing is available
    return true;
  }

  return false;
}

// =======================================================================
// function : Init
// purpose  : Initialize ray tracing resources
// =======================================================================
bool Metal_RayTracing::Init(Metal_Context* theCtx)
{
  Release(theCtx);

  if (!IsSupported(theCtx))
  {
    Message::SendWarning() << "Metal_RayTracing: ray tracing not supported on this device";
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  // Compile shaders
  NSError* anError = nil;
  MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
  anOptions.fastMathEnabled = YES;

  myShaderLibrary = [aDevice newLibraryWithSource:@(RAYTRACING_SHADER_SOURCE)
                                          options:anOptions
                                            error:&anError];
  if (myShaderLibrary == nil)
  {
    Message::SendFail() << "Metal_RayTracing: shader compilation failed - "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Create ray generation pipeline
  id<MTLFunction> aRayGenFunc = [myShaderLibrary newFunctionWithName:@"rayGen"];
  if (aRayGenFunc != nil)
  {
    myRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aRayGenFunc error:&anError];
    if (myRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: rayGen pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shading pipeline (with shadow support)
  id<MTLFunction> aShadeFunc = [myShaderLibrary newFunctionWithName:@"shade"];
  if (aShadeFunc != nil)
  {
    myShadePipeline = [aDevice newComputePipelineStateWithFunction:aShadeFunc error:&anError];
    if (myShadePipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shade pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shading pipeline without shadow (fallback)
  id<MTLFunction> aShadeNoShadowFunc = [myShaderLibrary newFunctionWithName:@"shadeNoShadow"];
  if (aShadeNoShadowFunc != nil)
  {
    myShadeNoShadowPipeline = [aDevice newComputePipelineStateWithFunction:aShadeNoShadowFunc error:&anError];
    if (myShadeNoShadowPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadeNoShadow pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create shadow ray generation pipeline (per-light)
  id<MTLFunction> aShadowRayGenFunc = [myShaderLibrary newFunctionWithName:@"shadowRayGenForLight"];
  if (aShadowRayGenFunc != nil)
  {
    myShadowRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aShadowRayGenFunc error:&anError];
    if (myShadowRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadowRayGenForLight pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 5: Create reflection ray generation pipeline
  id<MTLFunction> aReflectionRayGenFunc = [myShaderLibrary newFunctionWithName:@"reflectionRayGen"];
  if (aReflectionRayGenFunc != nil)
  {
    myReflectionRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aReflectionRayGenFunc error:&anError];
    if (myReflectionRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: reflectionRayGen pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 5: Create bounce color pipeline
  id<MTLFunction> aBounceColorFunc = [myShaderLibrary newFunctionWithName:@"computeBounceColor"];
  if (aBounceColorFunc != nil)
  {
    myBounceColorPipeline = [aDevice newComputePipelineStateWithFunction:aBounceColorFunc error:&anError];
    if (myBounceColorPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: computeBounceColor pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 5: Create shade with reflections pipeline
  id<MTLFunction> aShadeWithReflFunc = [myShaderLibrary newFunctionWithName:@"shadeWithReflections"];
  if (aShadeWithReflFunc != nil)
  {
    myShadeWithReflectionsPipeline = [aDevice newComputePipelineStateWithFunction:aShadeWithReflFunc error:&anError];
    if (myShadeWithReflectionsPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadeWithReflections pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 6: Create refraction ray generation pipeline
  id<MTLFunction> aRefractionRayGenFunc = [myShaderLibrary newFunctionWithName:@"refractionRayGen"];
  if (aRefractionRayGenFunc != nil)
  {
    myRefractionRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aRefractionRayGenFunc error:&anError];
    if (myRefractionRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: refractionRayGen pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 6: Create refraction color pipeline
  id<MTLFunction> aRefractionColorFunc = [myShaderLibrary newFunctionWithName:@"computeRefractionColor"];
  if (aRefractionColorFunc != nil)
  {
    myRefractionColorPipeline = [aDevice newComputePipelineStateWithFunction:aRefractionColorFunc error:&anError];
    if (myRefractionColorPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: computeRefractionColor pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 6: Create full shade pipeline (reflections + refractions)
  id<MTLFunction> aShadeWithAllFunc = [myShaderLibrary newFunctionWithName:@"shadeWithAll"];
  if (aShadeWithAllFunc != nil)
  {
    myShadeWithAllPipeline = [aDevice newComputePipelineStateWithFunction:aShadeWithAllFunc error:&anError];
    if (myShadeWithAllPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadeWithAll pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 8: Create textured shade pipeline
  id<MTLFunction> aShadeWithTexturesFunc = [myShaderLibrary newFunctionWithName:@"shadeWithTextures"];
  if (aShadeWithTexturesFunc != nil)
  {
    myShadeWithTexturesPipeline = [aDevice newComputePipelineStateWithFunction:aShadeWithTexturesFunc error:&anError];
    if (myShadeWithTexturesPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: shadeWithTextures pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 8: Create texture sampler
  MTLSamplerDescriptor* aSamplerDesc = [[MTLSamplerDescriptor alloc] init];
  aSamplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
  aSamplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
  aSamplerDesc.mipFilter = MTLSamplerMipFilterLinear;
  aSamplerDesc.sAddressMode = MTLSamplerAddressModeRepeat;
  aSamplerDesc.tAddressMode = MTLSamplerAddressModeRepeat;
  myTextureSampler = [aDevice newSamplerStateWithDescriptor:aSamplerDesc];

  // Phase 9: Create path tracing ray generation pipeline
  id<MTLFunction> aPathTraceRayGenFunc = [myShaderLibrary newFunctionWithName:@"pathTraceRayGen"];
  if (aPathTraceRayGenFunc != nil)
  {
    myPathTraceRayGenPipeline = [aDevice newComputePipelineStateWithFunction:aPathTraceRayGenFunc error:&anError];
    if (myPathTraceRayGenPipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: pathTraceRayGen pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Phase 9: Create path tracing kernel pipeline
  id<MTLFunction> aPathTraceFunc = [myShaderLibrary newFunctionWithName:@"pathTrace"];
  if (aPathTraceFunc != nil)
  {
    myPathTracePipeline = [aDevice newComputePipelineStateWithFunction:aPathTraceFunc error:&anError];
    if (myPathTracePipeline == nil)
    {
      Message::SendFail() << "Metal_RayTracing: pathTrace pipeline failed - "
                          << [[anError localizedDescription] UTF8String];
      return false;
    }
  }

  // Create ray intersector
  myRayIntersector = [[MPSRayIntersector alloc] initWithDevice:aDevice];
  myRayIntersector.rayDataType = MPSRayDataTypeOriginMinDistanceDirectionMaxDistance;
  myRayIntersector.rayStride = sizeof(float) * 8;  // origin(3) + min(1) + dir(3) + max(1)
  myRayIntersector.intersectionDataType = MPSIntersectionDataTypeDistancePrimitiveIndexCoordinates;

  myIsValid = true;
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_RayTracing::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  myAccelerationStructure = nil;
  myRayIntersector = nil;
  myRayGenPipeline = nil;
  myShadePipeline = nil;
  myShadeNoShadowPipeline = nil;
  myShadowRayGenPipeline = nil;
  myReflectionRayGenPipeline = nil;
  myBounceColorPipeline = nil;
  myShadeWithReflectionsPipeline = nil;
  myRefractionRayGenPipeline = nil;
  myRefractionColorPipeline = nil;
  myShadeWithAllPipeline = nil;
  myShadeWithTexturesPipeline = nil;
  myPathTraceRayGenPipeline = nil;
  myPathTracePipeline = nil;
  myAccumulatePipeline = nil;
  myVertexBuffer = nil;
  myIndexBuffer = nil;
  myMaterialBuffer = nil;
  myMaterialIndexBuffer = nil;
  myLightBuffer = nil;
  myRayBuffer = nil;
  myIntersectionBuffer = nil;
  myShadowRayBuffer = nil;
  myShadowIntersectionBuffer = nil;
  myReflectionRayBuffer = nil;
  myReflectionIntersectionBuffer = nil;
  myBounceColorBuffer = nil;
  myTexCoordBuffer = nil;
  myRefractionRayBuffer = nil;
  myRefractionRayBuffer2 = nil;
  myRefractionIntersectionBuffer = nil;
  myRefractionIntersectionBuffer2 = nil;
  myRefractionColorBuffer = nil;
  myDiffuseTextureArray = nil;
  myNormalTextureArray = nil;
  myTextureSampler = nil;
  myAccumulationBuffer = nil;
  myRandomSeedBuffer = nil;
  myShaderLibrary = nil;

  myVertexCount = 0;
  myTriangleCount = 0;
  myMaterialCount = 0;
  myLightCount = 0;
  myIsValid = false;
  myFrameIndex = 0;
}

// =======================================================================
// function : BuildAccelerationStructure
// purpose  : Build BVH from triangle geometry
// =======================================================================
bool Metal_RayTracing::BuildAccelerationStructure(
  Metal_Context* theCtx,
  const float* theVertices,
  int theVertexCount,
  const uint32_t* theIndices,
  int theTriangleCount)
{
  if (!myIsValid || theCtx == nullptr || theVertices == nullptr || theIndices == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  // Create vertex buffer
  size_t aVertexSize = static_cast<size_t>(theVertexCount) * 3 * sizeof(float);
  myVertexBuffer = [aDevice newBufferWithBytes:theVertices
                                        length:aVertexSize
                                       options:MTLResourceStorageModeShared];

  // Create index buffer
  size_t anIndexSize = static_cast<size_t>(theTriangleCount) * 3 * sizeof(uint32_t);
  myIndexBuffer = [aDevice newBufferWithBytes:theIndices
                                       length:anIndexSize
                                      options:MTLResourceStorageModeShared];

  myVertexCount = theVertexCount;
  myTriangleCount = theTriangleCount;

  // Build acceleration structure
  myAccelerationStructure = [[MPSTriangleAccelerationStructure alloc] initWithDevice:aDevice];
  myAccelerationStructure.vertexBuffer = myVertexBuffer;
  myAccelerationStructure.vertexStride = sizeof(float) * 3;
  myAccelerationStructure.indexBuffer = myIndexBuffer;
  myAccelerationStructure.indexType = MPSDataTypeUInt32;
  myAccelerationStructure.triangleCount = static_cast<NSUInteger>(theTriangleCount);

  // Rebuild the acceleration structure
  [myAccelerationStructure rebuild];

  return true;
}

// =======================================================================
// function : SetMaterials
// purpose  : Set materials for ray tracing
// =======================================================================
void Metal_RayTracing::SetMaterials(Metal_Context* theCtx,
                                    const Metal_RaytraceMaterial* theMaterials,
                                    int theMaterialCount)
{
  if (!myIsValid || theCtx == nullptr || theMaterials == nullptr || theMaterialCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theMaterialCount) * sizeof(Metal_RaytraceMaterial);
  myMaterialBuffer = [aDevice newBufferWithBytes:theMaterials
                                          length:aSize
                                         options:MTLResourceStorageModeShared];
  myMaterialCount = theMaterialCount;
}

// =======================================================================
// function : SetMaterialIndices
// purpose  : Set per-triangle material indices
// =======================================================================
void Metal_RayTracing::SetMaterialIndices(Metal_Context* theCtx,
                                          const int32_t* theMaterialIndices,
                                          int theTriangleCount)
{
  if (!myIsValid || theCtx == nullptr || theMaterialIndices == nullptr || theTriangleCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theTriangleCount) * sizeof(int32_t);
  myMaterialIndexBuffer = [aDevice newBufferWithBytes:theMaterialIndices
                                               length:aSize
                                              options:MTLResourceStorageModeShared];
}

// =======================================================================
// function : SetLights
// purpose  : Set lights for ray tracing
// =======================================================================
void Metal_RayTracing::SetLights(Metal_Context* theCtx,
                                 const Metal_RaytraceLight* theLights,
                                 int theLightCount)
{
  if (!myIsValid || theCtx == nullptr || theLights == nullptr || theLightCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theLightCount) * sizeof(Metal_RaytraceLight);
  myLightBuffer = [aDevice newBufferWithBytes:theLights
                                       length:aSize
                                      options:MTLResourceStorageModeShared];
  myLightCount = theLightCount;
}

// =======================================================================
// function : SetTexCoords
// purpose  : Set per-vertex texture coordinates (Phase 7)
// =======================================================================
void Metal_RayTracing::SetTexCoords(Metal_Context* theCtx,
                                    const float* theTexCoords,
                                    int theVertexCount)
{
  if (!myIsValid || theCtx == nullptr || theTexCoords == nullptr || theVertexCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  size_t aSize = static_cast<size_t>(theVertexCount) * 2 * sizeof(float);
  myTexCoordBuffer = [aDevice newBufferWithBytes:theTexCoords
                                          length:aSize
                                         options:MTLResourceStorageModeShared];
}

// =======================================================================
// function : SetDiffuseTextures
// purpose  : Set diffuse texture array (Phase 8)
// =======================================================================
void Metal_RayTracing::SetDiffuseTextures(Metal_Context* theCtx,
                                          NSArray<id<MTLTexture>>* theTextures)
{
  if (!myIsValid || theCtx == nullptr || theTextures == nil || [theTextures count] == 0)
  {
    myDiffuseTextureArray = nil;
    return;
  }

  // For now, just store the first texture or create a texture array
  // In a full implementation, we'd create a proper texture2d_array
  id<MTLDevice> aDevice = theCtx->Device();

  // Get dimensions from first texture
  id<MTLTexture> aFirstTex = theTextures[0];
  NSUInteger aWidth = [aFirstTex width];
  NSUInteger aHeight = [aFirstTex height];
  NSUInteger aCount = [theTextures count];

  // Create texture array descriptor
  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType2DArray;
  aDesc.pixelFormat = [aFirstTex pixelFormat];
  aDesc.width = aWidth;
  aDesc.height = aHeight;
  aDesc.arrayLength = aCount;
  aDesc.usage = MTLTextureUsageShaderRead;
  aDesc.storageMode = MTLStorageModePrivate;

  myDiffuseTextureArray = [aDevice newTextureWithDescriptor:aDesc];

  // Copy each texture into the array (would need a blit encoder in practice)
  // For simplicity, this is a placeholder - real implementation would copy texture data
}

// =======================================================================
// function : SetNormalTextures
// purpose  : Set normal map texture array (Phase 8)
// =======================================================================
void Metal_RayTracing::SetNormalTextures(Metal_Context* theCtx,
                                         NSArray<id<MTLTexture>>* theTextures)
{
  if (!myIsValid || theCtx == nullptr || theTextures == nil || [theTextures count] == 0)
  {
    myNormalTextureArray = nil;
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();

  // Get dimensions from first texture
  id<MTLTexture> aFirstTex = theTextures[0];
  NSUInteger aWidth = [aFirstTex width];
  NSUInteger aHeight = [aFirstTex height];
  NSUInteger aCount = [theTextures count];

  // Create texture array descriptor
  MTLTextureDescriptor* aDesc = [[MTLTextureDescriptor alloc] init];
  aDesc.textureType = MTLTextureType2DArray;
  aDesc.pixelFormat = [aFirstTex pixelFormat];
  aDesc.width = aWidth;
  aDesc.height = aHeight;
  aDesc.arrayLength = aCount;
  aDesc.usage = MTLTextureUsageShaderRead;
  aDesc.storageMode = MTLStorageModePrivate;

  myNormalTextureArray = [aDevice newTextureWithDescriptor:aDesc];
}

// =======================================================================
// function : Trace
// purpose  : Perform ray tracing
// =======================================================================
void Metal_RayTracing::Trace(Metal_Context* theCtx,
                             id<MTLCommandBuffer> theCommandBuffer,
                             id<MTLTexture> theOutputTexture,
                             const NCollection_Vec3<float>& theCameraOrigin,
                             const NCollection_Vec3<float>& theCameraLookAt,
                             const NCollection_Vec3<float>& theCameraUp,
                             float theFov)
{
  if (!myIsValid || theCommandBuffer == nil || theOutputTexture == nil)
  {
    return;
  }

  if (myAccelerationStructure == nil || myTriangleCount <= 0)
  {
    return;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  NSUInteger aWidth = [theOutputTexture width];
  NSUInteger aHeight = [theOutputTexture height];
  NSUInteger aRayCount = aWidth * aHeight;

  // Ensure ray and intersection buffers are large enough
  size_t aRayBufferSize = aRayCount * sizeof(float) * 8;
  size_t aIntersectionBufferSize = aRayCount * sizeof(float) * 4;  // distance + primitiveIndex + uv

  if (myRayBuffer == nil || [myRayBuffer length] < aRayBufferSize)
  {
    myRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                       options:MTLResourceStorageModePrivate];
  }

  if (myIntersectionBuffer == nil || [myIntersectionBuffer length] < aIntersectionBufferSize)
  {
    myIntersectionBuffer = [aDevice newBufferWithLength:aIntersectionBufferSize
                                                options:MTLResourceStorageModePrivate];
  }

  // Shadow ray buffers (only if shadows enabled and we have lights)
  // Shadow intersections are packed: [light0 all pixels][light1 all pixels]...
  bool aUseShadows = myShadowsEnabled && myLightCount > 0 && myShadowRayGenPipeline != nil;
  if (aUseShadows)
  {
    if (myShadowRayBuffer == nil || [myShadowRayBuffer length] < aRayBufferSize)
    {
      myShadowRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                               options:MTLResourceStorageModePrivate];
    }

    // Need space for shadow intersections for ALL lights
    size_t aShadowIntersectionSize = aIntersectionBufferSize * static_cast<size_t>(myLightCount);
    if (myShadowIntersectionBuffer == nil || [myShadowIntersectionBuffer length] < aShadowIntersectionSize)
    {
      myShadowIntersectionBuffer = [aDevice newBufferWithLength:aShadowIntersectionSize
                                                        options:MTLResourceStorageModePrivate];
    }
  }

  // Phase 5: Reflection buffers (only if reflections enabled and we have the pipeline)
  bool aUseReflections = myReflectionsEnabled && myReflectionRayGenPipeline != nil;
  size_t aColorBufferSize = aRayCount * sizeof(float) * 4;
  if (aUseReflections)
  {
    if (myReflectionRayBuffer == nil || [myReflectionRayBuffer length] < aRayBufferSize)
    {
      myReflectionRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                                   options:MTLResourceStorageModePrivate];
    }
    if (myReflectionIntersectionBuffer == nil || [myReflectionIntersectionBuffer length] < aIntersectionBufferSize)
    {
      myReflectionIntersectionBuffer = [aDevice newBufferWithLength:aIntersectionBufferSize
                                                            options:MTLResourceStorageModePrivate];
    }
    if (myBounceColorBuffer == nil || [myBounceColorBuffer length] < aColorBufferSize)
    {
      myBounceColorBuffer = [aDevice newBufferWithLength:aColorBufferSize
                                                 options:MTLResourceStorageModePrivate];
    }
  }

  // Phase 6: Refraction buffers (only if refractions enabled and we have the pipeline)
  // We need 2 bounce buffers for solid glass objects (enter + exit)
  bool aUseRefractions = myRefractionsEnabled && myRefractionRayGenPipeline != nil;
  if (aUseRefractions)
  {
    if (myRefractionRayBuffer == nil || [myRefractionRayBuffer length] < aRayBufferSize)
    {
      myRefractionRayBuffer = [aDevice newBufferWithLength:aRayBufferSize
                                                   options:MTLResourceStorageModePrivate];
    }
    if (myRefractionRayBuffer2 == nil || [myRefractionRayBuffer2 length] < aRayBufferSize)
    {
      myRefractionRayBuffer2 = [aDevice newBufferWithLength:aRayBufferSize
                                                    options:MTLResourceStorageModePrivate];
    }
    if (myRefractionIntersectionBuffer == nil || [myRefractionIntersectionBuffer length] < aIntersectionBufferSize)
    {
      myRefractionIntersectionBuffer = [aDevice newBufferWithLength:aIntersectionBufferSize
                                                            options:MTLResourceStorageModePrivate];
    }
    if (myRefractionIntersectionBuffer2 == nil || [myRefractionIntersectionBuffer2 length] < aIntersectionBufferSize)
    {
      myRefractionIntersectionBuffer2 = [aDevice newBufferWithLength:aIntersectionBufferSize
                                                             options:MTLResourceStorageModePrivate];
    }
    if (myRefractionColorBuffer == nil || [myRefractionColorBuffer length] < aColorBufferSize)
    {
      myRefractionColorBuffer = [aDevice newBufferWithLength:aColorBufferSize
                                                     options:MTLResourceStorageModePrivate];
    }
  }

  // Phase 9: Path tracing mode - uses progressive accumulation with jittered rays
  bool aUsePathTracing = myPathTracingEnabled && myPathTraceRayGenPipeline != nil && myPathTracePipeline != nil;
  if (aUsePathTracing)
  {
    // Allocate random seed buffer for per-pixel RNG state
    size_t aSeedBufferSize = aRayCount * sizeof(uint32_t);
    if (myRandomSeedBuffer == nil || [myRandomSeedBuffer length] < aSeedBufferSize)
    {
      myRandomSeedBuffer = [aDevice newBufferWithLength:aSeedBufferSize
                                                options:MTLResourceStorageModePrivate];
    }

    // Path trace camera parameters (extended with forward/right/up vectors and frame index)
    struct PathTraceCameraParams {
      simd_float3 origin;
      simd_float3 forward;
      simd_float3 right;
      simd_float3 up;
      float fov;
      simd_float2 resolution;
      int maxBounces;
      int shadowsEnabled;
      int reflectionsEnabled;
      int lightCount;
      uint32_t frameIndex;
    } aPTCameraParams;

    // Compute camera basis vectors
    simd_float3 aOrigin = simd_make_float3(theCameraOrigin.x(), theCameraOrigin.y(), theCameraOrigin.z());
    simd_float3 aLookAt = simd_make_float3(theCameraLookAt.x(), theCameraLookAt.y(), theCameraLookAt.z());
    simd_float3 aUp = simd_make_float3(theCameraUp.x(), theCameraUp.y(), theCameraUp.z());
    simd_float3 aForward = simd_normalize(aLookAt - aOrigin);
    simd_float3 aRight = simd_normalize(simd_cross(aForward, aUp));
    simd_float3 aCamUp = simd_cross(aRight, aForward);

    aPTCameraParams.origin = aOrigin;
    aPTCameraParams.forward = aForward;
    aPTCameraParams.right = aRight;
    aPTCameraParams.up = aCamUp;
    aPTCameraParams.fov = theFov;
    aPTCameraParams.resolution = simd_make_float2(static_cast<float>(aWidth), static_cast<float>(aHeight));
    aPTCameraParams.maxBounces = myMaxBounces;
    aPTCameraParams.shadowsEnabled = myShadowsEnabled ? 1 : 0;
    aPTCameraParams.reflectionsEnabled = myReflectionsEnabled ? 1 : 0;
    aPTCameraParams.lightCount = myLightCount;
    aPTCameraParams.frameIndex = myFrameIndex;

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);

    // Step 1: Generate jittered rays for this frame
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myPathTraceRayGenPipeline];
      [anEncoder setBuffer:myRayBuffer offset:0 atIndex:0];
      [anEncoder setBytes:&aPTCameraParams length:sizeof(aPTCameraParams) atIndex:1];
      [anEncoder setBuffer:myRandomSeedBuffer offset:0 atIndex:2];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }

    // Step 2: Intersect primary rays with geometry
    [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                       intersectionType:MPSIntersectionTypeNearest
                                              rayBuffer:myRayBuffer
                                        rayBufferOffset:0
                                     intersectionBuffer:myIntersectionBuffer
                               intersectionBufferOffset:0
                                               rayCount:aRayCount
                                  accelerationStructure:myAccelerationStructure];

    // Step 3: Path trace shading with progressive accumulation
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myPathTracePipeline];
      [anEncoder setTexture:theOutputTexture atIndex:0];
      [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:0];
      [anEncoder setBuffer:myRayBuffer offset:0 atIndex:1];
      [anEncoder setBytes:&aPTCameraParams length:sizeof(aPTCameraParams) atIndex:2];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:3];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myLightBuffer offset:0 atIndex:7];
      [anEncoder setBuffer:myRandomSeedBuffer offset:0 atIndex:8];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }

    // Increment frame index for next accumulation
    myFrameIndex++;
    return;
  }

  // Camera parameters
  struct CameraParams {
    simd_float3 origin;
    simd_float3 lookAt;
    simd_float3 up;
    float fov;
    simd_float2 resolution;
    int maxBounces;
    int shadowsEnabled;
    int reflectionsEnabled;
    int lightCount;
  } aCameraParams;

  aCameraParams.origin = simd_make_float3(theCameraOrigin.x(), theCameraOrigin.y(), theCameraOrigin.z());
  aCameraParams.lookAt = simd_make_float3(theCameraLookAt.x(), theCameraLookAt.y(), theCameraLookAt.z());
  aCameraParams.up = simd_make_float3(theCameraUp.x(), theCameraUp.y(), theCameraUp.z());
  aCameraParams.fov = theFov;
  aCameraParams.resolution = simd_make_float2(static_cast<float>(aWidth), static_cast<float>(aHeight));
  aCameraParams.maxBounces = myMaxBounces;
  aCameraParams.shadowsEnabled = aUseShadows ? 1 : 0;
  aCameraParams.reflectionsEnabled = myReflectionsEnabled ? 1 : 0;
  aCameraParams.lightCount = myLightCount;

  // Step 1: Generate rays
  {
    id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
    [anEncoder setComputePipelineState:myRayGenPipeline];
    [anEncoder setBuffer:myRayBuffer offset:0 atIndex:0];
    [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:1];

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);
    [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
    [anEncoder endEncoding];
  }

  // Step 2: Intersect primary rays with geometry
  [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                     intersectionType:MPSIntersectionTypeNearest
                                            rayBuffer:myRayBuffer
                                      rayBufferOffset:0
                                   intersectionBuffer:myIntersectionBuffer
                             intersectionBufferOffset:0
                                             rayCount:aRayCount
                                accelerationStructure:myAccelerationStructure];

  // Step 3: Generate and intersect shadow rays for each light
  if (aUseShadows)
  {
    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);

    for (int aLightIdx = 0; aLightIdx < myLightCount; ++aLightIdx)
    {
      // 3a: Generate shadow rays from hit points toward this light
      {
        id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
        [anEncoder setComputePipelineState:myShadowRayGenPipeline];
        [anEncoder setBuffer:myShadowRayBuffer offset:0 atIndex:0];
        [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:1];
        [anEncoder setBuffer:myRayBuffer offset:0 atIndex:2];
        [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
        [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
        [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
        [anEncoder setBuffer:myLightBuffer offset:0 atIndex:6];
        [anEncoder setBytes:&aLightIdx length:sizeof(aLightIdx) atIndex:7];
        [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
        [anEncoder endEncoding];
      }

      // 3b: Intersect shadow rays, store at offset for this light
      size_t aShadowOffset = static_cast<size_t>(aLightIdx) * aIntersectionBufferSize;
      [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                         intersectionType:MPSIntersectionTypeAny
                                                rayBuffer:myShadowRayBuffer
                                          rayBufferOffset:0
                                       intersectionBuffer:myShadowIntersectionBuffer
                                 intersectionBufferOffset:aShadowOffset
                                                 rayCount:aRayCount
                                    accelerationStructure:myAccelerationStructure];
    }
  }

  // Step 4: Generate and trace reflection rays (Phase 5)
  if (aUseReflections)
  {
    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);

    // 4a: Generate reflection rays from primary hits
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myReflectionRayGenPipeline];
      [anEncoder setBuffer:myReflectionRayBuffer offset:0 atIndex:0];
      [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:1];
      [anEncoder setBuffer:myRayBuffer offset:0 atIndex:2];
      [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:7];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }

    // 4b: Intersect reflection rays
    [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                       intersectionType:MPSIntersectionTypeNearest
                                              rayBuffer:myReflectionRayBuffer
                                        rayBufferOffset:0
                                     intersectionBuffer:myReflectionIntersectionBuffer
                               intersectionBufferOffset:0
                                               rayCount:aRayCount
                                  accelerationStructure:myAccelerationStructure];

    // 4c: Compute colors for what reflections hit
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myBounceColorPipeline];
      [anEncoder setBuffer:myBounceColorBuffer offset:0 atIndex:0];
      [anEncoder setBuffer:myReflectionIntersectionBuffer offset:0 atIndex:1];
      [anEncoder setBuffer:myReflectionRayBuffer offset:0 atIndex:2];
      [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myLightBuffer offset:0 atIndex:7];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:8];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }
  }

  // Step 5: Generate and trace refraction rays (Phase 6)
  // For solid glass objects, rays must enter AND exit the surface (2 bounces)
  if (aUseRefractions)
  {
    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);

    // 5a: Generate first refraction rays (entering glass from primary hits)
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myRefractionRayGenPipeline];
      [anEncoder setBuffer:myRefractionRayBuffer offset:0 atIndex:0];
      [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:1];
      [anEncoder setBuffer:myRayBuffer offset:0 atIndex:2];
      [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:7];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }

    // 5b: Intersect first refraction rays (find exit point inside glass)
    [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                       intersectionType:MPSIntersectionTypeNearest
                                              rayBuffer:myRefractionRayBuffer
                                        rayBufferOffset:0
                                     intersectionBuffer:myRefractionIntersectionBuffer
                               intersectionBufferOffset:0
                                               rayCount:aRayCount
                                  accelerationStructure:myAccelerationStructure];

    // 5c: Generate second refraction rays (exiting glass)
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myRefractionRayGenPipeline];
      [anEncoder setBuffer:myRefractionRayBuffer2 offset:0 atIndex:0];  // output to buffer2
      [anEncoder setBuffer:myRefractionIntersectionBuffer offset:0 atIndex:1];  // first bounce intersections
      [anEncoder setBuffer:myRefractionRayBuffer offset:0 atIndex:2];  // first bounce rays as incoming
      [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:7];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }

    // 5d: Intersect second refraction rays (find what's behind the glass)
    [myRayIntersector encodeIntersectionToCommandBuffer:theCommandBuffer
                                       intersectionType:MPSIntersectionTypeNearest
                                              rayBuffer:myRefractionRayBuffer2
                                        rayBufferOffset:0
                                     intersectionBuffer:myRefractionIntersectionBuffer2
                               intersectionBufferOffset:0
                                               rayCount:aRayCount
                                  accelerationStructure:myAccelerationStructure];

    // 5e: Compute colors for what the exited rays hit
    {
      id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];
      [anEncoder setComputePipelineState:myRefractionColorPipeline];
      [anEncoder setBuffer:myRefractionColorBuffer offset:0 atIndex:0];
      [anEncoder setBuffer:myRefractionIntersectionBuffer2 offset:0 atIndex:1];  // second bounce intersections
      [anEncoder setBuffer:myRefractionRayBuffer2 offset:0 atIndex:2];  // second bounce rays
      [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:3];
      [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:4];
      [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:5];
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:6];
      [anEncoder setBuffer:myLightBuffer offset:0 atIndex:7];
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:8];
      [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
      [anEncoder endEncoding];
    }
  }

  // Step 6: Shade intersections
  bool aUseTextures = myTexturingEnabled && myShadeWithTexturesPipeline != nil
                      && myTexCoordBuffer != nil && myDiffuseTextureArray != nil;

  {
    id<MTLComputeCommandEncoder> anEncoder = [theCommandBuffer computeCommandEncoder];

    if (aUseTextures)
    {
      // Phase 8: Use textured shader with all features
      [anEncoder setComputePipelineState:myShadeWithTexturesPipeline];
    }
    else if (aUseReflections && aUseRefractions)
    {
      // Use full shade kernel with reflections + refractions (Phase 6)
      [anEncoder setComputePipelineState:myShadeWithAllPipeline];
    }
    else if (aUseReflections)
    {
      // Use shade kernel with reflection support
      [anEncoder setComputePipelineState:myShadeWithReflectionsPipeline];
    }
    else if (aUseShadows)
    {
      // Use shade kernel with shadow support
      [anEncoder setComputePipelineState:myShadePipeline];
    }
    else
    {
      // Use shade kernel without shadow support
      [anEncoder setComputePipelineState:myShadeNoShadowPipeline];
    }

    [anEncoder setTexture:theOutputTexture atIndex:0];

    // Phase 8: Bind textures and sampler for textured shading
    if (aUseTextures)
    {
      [anEncoder setTexture:myDiffuseTextureArray atIndex:1];
      if (myNormalTextureArray != nil)
      {
        [anEncoder setTexture:myNormalTextureArray atIndex:2];
      }
      [anEncoder setSamplerState:myTextureSampler atIndex:0];
    }

    [anEncoder setBuffer:myIntersectionBuffer offset:0 atIndex:0];
    [anEncoder setBuffer:myRayBuffer offset:0 atIndex:1];
    [anEncoder setBytes:&aCameraParams length:sizeof(aCameraParams) atIndex:2];
    [anEncoder setBuffer:myVertexBuffer offset:0 atIndex:3];
    [anEncoder setBuffer:myIndexBuffer offset:0 atIndex:4];

    if (myMaterialBuffer != nil)
    {
      [anEncoder setBuffer:myMaterialBuffer offset:0 atIndex:5];
    }

    if (myLightBuffer != nil)
    {
      [anEncoder setBuffer:myLightBuffer offset:0 atIndex:6];
    }

    // Material index buffer (per-triangle material lookup)
    if (myMaterialIndexBuffer != nil)
    {
      [anEncoder setBuffer:myMaterialIndexBuffer offset:0 atIndex:7];
    }
    else
    {
      // Fallback: all triangles use material 0
      static int32_t aZeroIndex = 0;
      [anEncoder setBytes:&aZeroIndex length:sizeof(aZeroIndex) atIndex:7];
    }

    // Shadow intersection buffer (only used if shadows enabled)
    if (aUseShadows || aUseReflections || aUseRefractions || aUseTextures)
    {
      [anEncoder setBuffer:myShadowIntersectionBuffer offset:0 atIndex:8];
    }

    // Reflection color buffer (only used if reflections enabled)
    if (aUseReflections || aUseTextures)
    {
      [anEncoder setBuffer:myBounceColorBuffer offset:0 atIndex:9];
    }

    // Refraction color buffer (only used if refractions enabled)
    if (aUseRefractions || aUseTextures)
    {
      [anEncoder setBuffer:myRefractionColorBuffer offset:0 atIndex:10];
    }

    // Phase 8: Texture coordinate buffer
    if (aUseTextures)
    {
      [anEncoder setBuffer:myTexCoordBuffer offset:0 atIndex:11];
    }

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aThreadgroups = MTLSizeMake((aWidth + 7) / 8, (aHeight + 7) / 8, 1);
    [anEncoder dispatchThreadgroups:aThreadgroups threadsPerThreadgroup:aThreadgroupSize];
    [anEncoder endEncoding];
  }
}
