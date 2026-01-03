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

#import "Metal_CappingAlgo.hxx"
#import "Metal_Context.hxx"

#import <Metal/Metal.h>
#import <simd/simd.h>
#include <cmath>

IMPLEMENT_STANDARD_RTTIEXT(Metal_CappingPlaneResource, Metal_Resource)
IMPLEMENT_STANDARD_RTTIEXT(Metal_CappingAlgo, Standard_Transient)

namespace
{
  //! Shader source for stencil mask generation (geometry rendering without color output).
  static const char* THE_STENCIL_GEN_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
  float4x4 modelViewProjection;
  float4   clipPlane;
};

struct VertexIn {
  float3 position [[attribute(0)]];
};

struct VertexOut {
  float4 position [[position]];
  float  clipDistance;
};

vertex VertexOut stencilGenVertex(
  VertexIn in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]])
{
  VertexOut out;
  float4 worldPos = float4(in.position, 1.0);
  out.position = uniforms.modelViewProjection * worldPos;

  // Calculate clip distance for the capping plane
  out.clipDistance = dot(worldPos, uniforms.clipPlane);

  return out;
}

fragment void stencilGenFragment(VertexOut in [[stage_in]])
{
  // Clip fragments on wrong side of plane
  if (in.clipDistance < 0.0) {
    discard_fragment();
  }
  // No color output - only stencil operations
}
)";

  //! Shader source for capping plane rendering.
  static const char* THE_CAPPING_RENDER_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
  float4x4 modelViewProjection;
  float4   planeOrientation[4];  // Orientation matrix rows
  float4   cappingColor;
  float4   lightDir;
};

struct VertexOut {
  float4 position [[position]];
  float3 normal;
  float2 texCoord;
};

vertex VertexOut cappingRenderVertex(
  uint vertexID [[vertex_id]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  // Generate infinite plane vertices
  // Large quad centered at origin, will be transformed by orientation matrix
  float2 positions[4] = {
    float2(-10000.0, -10000.0),
    float2( 10000.0, -10000.0),
    float2(-10000.0,  10000.0),
    float2( 10000.0,  10000.0)
  };

  // Triangle strip: 0, 1, 2, 3
  float2 pos = positions[vertexID];

  // Build orientation matrix
  float4x4 orientation = float4x4(
    uniforms.planeOrientation[0],
    uniforms.planeOrientation[1],
    uniforms.planeOrientation[2],
    uniforms.planeOrientation[3]
  );

  // Transform vertex by orientation (plane lies in XZ plane initially)
  float4 localPos = float4(pos.x, 0.0, pos.y, 1.0);
  float4 worldPos = orientation * localPos;

  VertexOut out;
  out.position = uniforms.modelViewProjection * worldPos;
  out.normal = normalize((orientation * float4(0.0, 1.0, 0.0, 0.0)).xyz);
  out.texCoord = pos * 0.001; // Scale for potential texture mapping

  return out;
}

fragment float4 cappingRenderFragment(
  VertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(0)]])
{
  // Simple lighting
  float3 lightDir = normalize(uniforms.lightDir.xyz);
  float NdotL = max(dot(in.normal, lightDir), 0.0);
  float ambient = 0.3;
  float diffuse = 0.7 * NdotL;

  float3 color = uniforms.cappingColor.rgb * (ambient + diffuse);
  return float4(color, uniforms.cappingColor.a);
}
)";

  //! Size of infinite plane (large enough to fill view).
  static const float THE_PLANE_SIZE = 10000.0f;
}

//=================================================================================================
// Metal_CappingPlaneResource
//=================================================================================================

Metal_CappingPlaneResource::Metal_CappingPlaneResource(const Handle(Graphic3d_ClipPlane)& thePlane)
: myPlane(thePlane),
  myVertexBuffer(nil),
  myVertexCount(0),
  myEstimatedSize(0)
{
  memset(myOrientation, 0, sizeof(myOrientation));
  myOrientation[0] = 1.0f;
  myOrientation[5] = 1.0f;
  myOrientation[10] = 1.0f;
  myOrientation[15] = 1.0f;
}

//=================================================================================================

Metal_CappingPlaneResource::~Metal_CappingPlaneResource()
{
  Release(nullptr);
}

//=================================================================================================

void Metal_CappingPlaneResource::Release(Metal_Context* /*theCtx*/)
{
  myVertexBuffer = nil;
  myVertexCount = 0;
  myEstimatedSize = 0;
}

//=================================================================================================

void Metal_CappingPlaneResource::Update(Metal_Context* theCtx)
{
  if (myPlane.IsNull())
  {
    return;
  }

  // Build geometry if needed
  if (myVertexBuffer == nil)
  {
    buildGeometry(theCtx);
  }

  // Update orientation from plane equation
  updateOrientation();
}

//=================================================================================================

void Metal_CappingPlaneResource::buildGeometry(Metal_Context* theCtx)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return;
  }

  // Simple quad vertices (will be transformed by orientation matrix in shader)
  // Using triangle strip: 4 vertices for a quad
  float vertices[] = {
    -THE_PLANE_SIZE, 0.0f, -THE_PLANE_SIZE,
     THE_PLANE_SIZE, 0.0f, -THE_PLANE_SIZE,
    -THE_PLANE_SIZE, 0.0f,  THE_PLANE_SIZE,
     THE_PLANE_SIZE, 0.0f,  THE_PLANE_SIZE
  };

  myVertexBuffer = [theCtx->Device() newBufferWithBytes:vertices
                                                 length:sizeof(vertices)
                                                options:MTLResourceStorageModeShared];
  myVertexCount = 4;
  myEstimatedSize = sizeof(vertices);
}

//=================================================================================================

void Metal_CappingPlaneResource::updateOrientation()
{
  if (myPlane.IsNull())
  {
    return;
  }

  // Get plane equation: Ax + By + Cz + D = 0
  const NCollection_Vec4<double>& anEq = myPlane->GetEquation();
  float A = static_cast<float>(anEq.x());
  float B = static_cast<float>(anEq.y());
  float C = static_cast<float>(anEq.z());
  float D = static_cast<float>(anEq.w());

  // Plane normal
  float normLen = std::sqrt(A*A + B*B + C*C);
  if (normLen < 1e-6f)
  {
    return;
  }

  float nx = A / normLen;
  float ny = B / normLen;
  float nz = C / normLen;

  // Point on plane (closest to origin)
  float dist = -D / normLen;
  float px = nx * dist;
  float py = ny * dist;
  float pz = nz * dist;

  // Create orthonormal basis for the plane
  // Choose a non-parallel vector to compute tangent
  float ax, ay, az;
  if (std::abs(ny) < 0.9f)
  {
    // Use world Y as reference
    ax = 0.0f; ay = 1.0f; az = 0.0f;
  }
  else
  {
    // Use world X as reference
    ax = 1.0f; ay = 0.0f; az = 0.0f;
  }

  // Compute tangent (right vector)
  float tx = ay * nz - az * ny;
  float ty = az * nx - ax * nz;
  float tz = ax * ny - ay * nx;
  float tLen = std::sqrt(tx*tx + ty*ty + tz*tz);
  tx /= tLen; ty /= tLen; tz /= tLen;

  // Compute bitangent (forward vector)
  float bx = ny * tz - nz * ty;
  float by = nz * tx - nx * tz;
  float bz = nx * ty - ny * tx;

  // Build 4x4 orientation matrix (column-major for Metal)
  // Columns: tangent, normal, bitangent, translation
  myOrientation[0] = tx;  myOrientation[4] = nx;  myOrientation[8]  = bx;  myOrientation[12] = px;
  myOrientation[1] = ty;  myOrientation[5] = ny;  myOrientation[9]  = by;  myOrientation[13] = py;
  myOrientation[2] = tz;  myOrientation[6] = nz;  myOrientation[10] = bz;  myOrientation[14] = pz;
  myOrientation[3] = 0.0f; myOrientation[7] = 0.0f; myOrientation[11] = 0.0f; myOrientation[15] = 1.0f;
}

//=================================================================================================
// Metal_CappingAlgo
//=================================================================================================

Metal_CappingAlgo::Metal_CappingAlgo()
: myStencilGenPipeline(nil),
  myStencilRenderPipeline(nil),
  myStencilGenDepthState(nil),
  myStencilRenderDepthState(nil),
  myIsInitialized(false)
{
}

//=================================================================================================

Metal_CappingAlgo::~Metal_CappingAlgo()
{
  Release(nullptr);
}

//=================================================================================================

void Metal_CappingAlgo::Release(Metal_Context* theCtx)
{
  // Release plane resources
  for (NCollection_DataMap<Standard_Address, Handle(Metal_CappingPlaneResource)>::Iterator anIter(myPlaneResources);
       anIter.More(); anIter.Next())
  {
    if (!anIter.Value().IsNull())
    {
      anIter.Value()->Release(theCtx);
    }
  }
  myPlaneResources.Clear();

  myStencilGenPipeline = nil;
  myStencilRenderPipeline = nil;
  myStencilGenDepthState = nil;
  myStencilRenderDepthState = nil;
  myIsInitialized = false;
}

//=================================================================================================

bool Metal_CappingAlgo::Init(Metal_Context* theCtx)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  if (myIsInitialized)
  {
    return true;
  }

  if (!createPipelines(theCtx))
  {
    return false;
  }

  if (!createDepthStencilStates(theCtx))
  {
    return false;
  }

  myIsInitialized = true;
  return true;
}

//=================================================================================================

bool Metal_CappingAlgo::createPipelines(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();
  NSError* anError = nil;

  // Stencil generation pipeline (no color output)
  {
    id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_STENCIL_GEN_SHADER]
                                                    options:nil
                                                      error:&anError];
    if (aLibrary == nil)
    {
      NSLog(@"Metal_CappingAlgo: Failed to compile stencil gen shader: %@", anError);
      return false;
    }

    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"stencilGenVertex"];
    id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"stencilGenFragment"];

    // Vertex descriptor for position-only input
    MTLVertexDescriptor* aVertexDesc = [[MTLVertexDescriptor alloc] init];
    aVertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    aVertexDesc.attributes[0].offset = 0;
    aVertexDesc.attributes[0].bufferIndex = 0;
    aVertexDesc.layouts[0].stride = sizeof(float) * 3;

    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.label = @"CappingStencilGen";
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.fragmentFunction = aFragmentFunc;
    aPipelineDesc.vertexDescriptor = aVertexDesc;

    // No color output for stencil generation
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aPipelineDesc.colorAttachments[0].writeMask = MTLColorWriteMaskNone;

    aPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    aPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    myStencilGenPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                   error:&anError];
    if (myStencilGenPipeline == nil)
    {
      NSLog(@"Metal_CappingAlgo: Failed to create stencil gen pipeline: %@", anError);
      return false;
    }
  }

  // Capping render pipeline
  {
    id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_CAPPING_RENDER_SHADER]
                                                    options:nil
                                                      error:&anError];
    if (aLibrary == nil)
    {
      NSLog(@"Metal_CappingAlgo: Failed to compile capping render shader: %@", anError);
      return false;
    }

    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"cappingRenderVertex"];
    id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"cappingRenderFragment"];

    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.label = @"CappingRender";
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.fragmentFunction = aFragmentFunc;

    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aPipelineDesc.colorAttachments[0].blendingEnabled = NO;

    aPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    aPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    myStencilRenderPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                      error:&anError];
    if (myStencilRenderPipeline == nil)
    {
      NSLog(@"Metal_CappingAlgo: Failed to create capping render pipeline: %@", anError);
      return false;
    }
  }

  return true;
}

//=================================================================================================

bool Metal_CappingAlgo::createDepthStencilStates(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();

  // Stencil generation state: invert stencil on all operations
  {
    MTLDepthStencilDescriptor* aDesc = [[MTLDepthStencilDescriptor alloc] init];
    aDesc.depthCompareFunction = MTLCompareFunctionAlways; // Ignore depth
    aDesc.depthWriteEnabled = NO;

    MTLStencilDescriptor* aStencilDesc = [[MTLStencilDescriptor alloc] init];
    aStencilDesc.stencilCompareFunction = MTLCompareFunctionAlways;
    aStencilDesc.stencilFailureOperation = MTLStencilOperationKeep;
    aStencilDesc.depthFailureOperation = MTLStencilOperationInvert;
    aStencilDesc.depthStencilPassOperation = MTLStencilOperationInvert;
    aStencilDesc.readMask = 0x01;
    aStencilDesc.writeMask = 0x01;

    aDesc.frontFaceStencil = aStencilDesc;
    aDesc.backFaceStencil = aStencilDesc;

    myStencilGenDepthState = [aDevice newDepthStencilStateWithDescriptor:aDesc];
    if (myStencilGenDepthState == nil)
    {
      return false;
    }
  }

  // Stencil render state: only render where stencil == 1
  {
    MTLDepthStencilDescriptor* aDesc = [[MTLDepthStencilDescriptor alloc] init];
    aDesc.depthCompareFunction = MTLCompareFunctionLess;
    aDesc.depthWriteEnabled = YES;

    MTLStencilDescriptor* aStencilDesc = [[MTLStencilDescriptor alloc] init];
    aStencilDesc.stencilCompareFunction = MTLCompareFunctionEqual;
    aStencilDesc.stencilFailureOperation = MTLStencilOperationKeep;
    aStencilDesc.depthFailureOperation = MTLStencilOperationKeep;
    aStencilDesc.depthStencilPassOperation = MTLStencilOperationKeep;
    aStencilDesc.readMask = 0x01;
    aStencilDesc.writeMask = 0x00;

    aDesc.frontFaceStencil = aStencilDesc;
    aDesc.backFaceStencil = aStencilDesc;

    myStencilRenderDepthState = [aDevice newDepthStencilStateWithDescriptor:aDesc];
    if (myStencilRenderDepthState == nil)
    {
      return false;
    }
  }

  return true;
}

//=================================================================================================

Handle(Metal_CappingPlaneResource) Metal_CappingAlgo::GetPlaneResource(
  Metal_Context* theCtx,
  const Handle(Graphic3d_ClipPlane)& thePlane)
{
  if (thePlane.IsNull())
  {
    return Handle(Metal_CappingPlaneResource)();
  }

  Standard_Address aKey = thePlane.get();
  Handle(Metal_CappingPlaneResource) aResource;

  if (myPlaneResources.Find(aKey, aResource))
  {
    aResource->Update(theCtx);
    return aResource;
  }

  // Create new resource
  aResource = new Metal_CappingPlaneResource(thePlane);
  aResource->Update(theCtx);
  myPlaneResources.Bind(aKey, aResource);

  return aResource;
}
