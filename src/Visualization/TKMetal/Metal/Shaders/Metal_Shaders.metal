// Copyright (c) 2024 OPEN CASCADE SAS
//
// This file is part of Open CASCADE Technology software library.
//
// Basic Metal shaders for OpenCASCADE rendering.

#include <metal_stdlib>
using namespace metal;

// Uniform buffer structure - must match C++ side
struct Uniforms
{
  float4x4 modelViewMatrix;
  float4x4 projectionMatrix;
  float4   color;
};

// Vertex input structure
struct VertexIn
{
  float3 position [[attribute(0)]];
  float3 normal   [[attribute(1)]];
};

// Vertex output / Fragment input structure
struct VertexOut
{
  float4 position [[position]];
  float3 normal;
  float3 viewPosition;
};

// Basic vertex shader - transforms vertices
vertex VertexOut vertex_basic(
  const device float3* positions [[buffer(0)]],
  constant Uniforms& uniforms    [[buffer(1)]],
  uint vid                       [[vertex_id]])
{
  VertexOut out;

  float4 worldPos = float4(positions[vid], 1.0);
  float4 viewPos = uniforms.modelViewMatrix * worldPos;

  out.position = uniforms.projectionMatrix * viewPos;
  out.viewPosition = viewPos.xyz;
  out.normal = float3(0.0, 0.0, 1.0); // Default normal

  return out;
}

// Vertex shader with normals
vertex VertexOut vertex_with_normals(
  const device float3* positions [[buffer(0)]],
  const device float3* normals   [[buffer(1)]],
  constant Uniforms& uniforms    [[buffer(2)]],
  uint vid                       [[vertex_id]])
{
  VertexOut out;

  float4 worldPos = float4(positions[vid], 1.0);
  float4 viewPos = uniforms.modelViewMatrix * worldPos;

  out.position = uniforms.projectionMatrix * viewPos;
  out.viewPosition = viewPos.xyz;

  // Transform normal to view space (using upper 3x3 of modelView matrix)
  float3x3 normalMatrix = float3x3(
    uniforms.modelViewMatrix[0].xyz,
    uniforms.modelViewMatrix[1].xyz,
    uniforms.modelViewMatrix[2].xyz
  );
  out.normal = normalize(normalMatrix * normals[vid]);

  return out;
}

// Solid color fragment shader
fragment float4 fragment_solid_color(
  VertexOut in                [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  return uniforms.color;
}

// Simple Phong-like shading fragment shader
fragment float4 fragment_phong(
  VertexOut in                [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  // Fixed light direction (head light)
  float3 lightDir = normalize(float3(0.0, 0.0, 1.0));

  // Normal in view space
  float3 N = normalize(in.normal);

  // View direction (camera is at origin in view space)
  float3 V = normalize(-in.viewPosition);

  // Diffuse lighting
  float NdotL = max(dot(N, lightDir), 0.0);

  // Ambient term
  float ambient = 0.2;

  // Combine
  float lighting = ambient + (1.0 - ambient) * NdotL;

  float4 color = uniforms.color;
  color.rgb *= lighting;

  return color;
}

// Wireframe/edge fragment shader - just outputs solid color
fragment float4 fragment_edge(
  VertexOut in                [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  return uniforms.color;
}
