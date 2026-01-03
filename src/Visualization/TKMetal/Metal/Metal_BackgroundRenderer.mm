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
#import <simd/simd.h>

#include <Metal_BackgroundRenderer.hxx>
#include <Metal_Context.hxx>
#include <Metal_Texture.hxx>
#include <Metal_Workspace.hxx>

namespace
{
  //! Gradient/solid background shader.
  static const char* THE_BACKGROUND_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct BackgroundUniforms {
  float4 color1;
  float4 color2;
  float2 textureScale;
  float2 textureOffset;
  int    gradientType;  // 0=solid, 1=horizontal, 2=vertical, 3=diagonal1, 4=diagonal2, 5=corner
  int    hasTexture;
  int    padding[2];
};

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

// Full-screen triangle (3 vertices covering entire screen)
vertex VertexOut backgroundVertex(uint vertexID [[vertex_id]])
{
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2( 3.0, -1.0),
    float2(-1.0,  3.0)
  };

  float2 texCoords[3] = {
    float2(0.0, 1.0),
    float2(2.0, 1.0),
    float2(0.0, -1.0)
  };

  VertexOut out;
  out.position = float4(positions[vertexID], 0.0, 1.0);
  out.texCoord = texCoords[vertexID];
  return out;
}

fragment float4 backgroundFragment(
  VertexOut in [[stage_in]],
  constant BackgroundUniforms& uniforms [[buffer(0)]],
  texture2d<float> backgroundTexture [[texture(0)]],
  sampler textureSampler [[sampler(0)]])
{
  float2 uv = in.texCoord;

  // Apply texture transform
  uv = uv * uniforms.textureScale + uniforms.textureOffset;

  // If we have a texture, sample it
  if (uniforms.hasTexture) {
    return backgroundTexture.sample(textureSampler, uv);
  }

  // Calculate gradient factor based on type
  float t = 0.0;
  switch (uniforms.gradientType) {
    case 0: // Solid - use color1
      return uniforms.color1;

    case 1: // Horizontal
      t = in.texCoord.x;
      break;

    case 2: // Vertical
      t = 1.0 - in.texCoord.y;
      break;

    case 3: // Diagonal 1 (top-left to bottom-right)
      t = (in.texCoord.x + (1.0 - in.texCoord.y)) * 0.5;
      break;

    case 4: // Diagonal 2 (top-right to bottom-left)
      t = ((1.0 - in.texCoord.x) + (1.0 - in.texCoord.y)) * 0.5;
      break;

    case 5: // Corner (4-corner blend)
      {
        float u = in.texCoord.x;
        float v = 1.0 - in.texCoord.y;
        // Bilinear interpolation from 4 corners
        // For simplicity, use color1 at bottom-left, color2 at top-right
        t = (u + v) * 0.5;
      }
      break;

    default:
      return uniforms.color1;
  }

  // Linear interpolation between colors
  return mix(uniforms.color1, uniforms.color2, t);
}
)";

  //! Cubemap background shader.
  static const char* THE_CUBEMAP_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct CubemapUniforms {
  float4x4 inverseViewProjection;
};

struct VertexOut {
  float4 position [[position]];
  float3 direction;
};

vertex VertexOut cubemapVertex(
  uint vertexID [[vertex_id]],
  constant CubemapUniforms& uniforms [[buffer(0)]])
{
  // Full-screen triangle
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2( 3.0, -1.0),
    float2(-1.0,  3.0)
  };

  VertexOut out;
  out.position = float4(positions[vertexID], 0.9999, 1.0);

  // Compute world direction from screen position
  float4 clipPos = float4(positions[vertexID], 1.0, 1.0);
  float4 worldPos = uniforms.inverseViewProjection * clipPos;
  out.direction = worldPos.xyz / worldPos.w;

  return out;
}

fragment float4 cubemapFragment(
  VertexOut in [[stage_in]],
  texturecube<float> envMap [[texture(0)]],
  sampler envSampler [[sampler(0)]])
{
  float3 dir = normalize(in.direction);
  return envMap.sample(envSampler, dir);
}
)";

  // Pipeline state cache
  static id<MTLRenderPipelineState> theGradientPipeline = nil;
  static id<MTLRenderPipelineState> theCubemapPipeline = nil;
  static id<MTLSamplerState> theBackgroundSampler = nil;

  bool ensurePipelines(Metal_Context* theCtx)
  {
    if (theGradientPipeline != nil)
    {
      return true;
    }

    id<MTLDevice> aDevice = theCtx->Device();
    NSError* anError = nil;

    // Compile gradient shader
    id<MTLLibrary> aGradientLib = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_BACKGROUND_SHADER]
                                                         options:nil
                                                           error:&anError];
    if (aGradientLib == nil)
    {
      NSLog(@"Metal_BackgroundRenderer: Failed to compile gradient shader: %@", anError);
      return false;
    }

    id<MTLFunction> aGradVertFunc = [aGradientLib newFunctionWithName:@"backgroundVertex"];
    id<MTLFunction> aGradFragFunc = [aGradientLib newFunctionWithName:@"backgroundFragment"];

    MTLRenderPipelineDescriptor* aGradPipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aGradPipeDesc.label = @"BackgroundGradient";
    aGradPipeDesc.vertexFunction = aGradVertFunc;
    aGradPipeDesc.fragmentFunction = aGradFragFunc;
    aGradPipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aGradPipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    theGradientPipeline = [aDevice newRenderPipelineStateWithDescriptor:aGradPipeDesc error:&anError];
    if (theGradientPipeline == nil)
    {
      NSLog(@"Metal_BackgroundRenderer: Failed to create gradient pipeline: %@", anError);
      return false;
    }

    // Compile cubemap shader
    id<MTLLibrary> aCubemapLib = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_CUBEMAP_SHADER]
                                                        options:nil
                                                          error:&anError];
    if (aCubemapLib == nil)
    {
      NSLog(@"Metal_BackgroundRenderer: Failed to compile cubemap shader: %@", anError);
      return false;
    }

    id<MTLFunction> aCubeVertFunc = [aCubemapLib newFunctionWithName:@"cubemapVertex"];
    id<MTLFunction> aCubeFragFunc = [aCubemapLib newFunctionWithName:@"cubemapFragment"];

    MTLRenderPipelineDescriptor* aCubePipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aCubePipeDesc.label = @"BackgroundCubemap";
    aCubePipeDesc.vertexFunction = aCubeVertFunc;
    aCubePipeDesc.fragmentFunction = aCubeFragFunc;
    aCubePipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aCubePipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    theCubemapPipeline = [aDevice newRenderPipelineStateWithDescriptor:aCubePipeDesc error:&anError];
    if (theCubemapPipeline == nil)
    {
      NSLog(@"Metal_BackgroundRenderer: Failed to create cubemap pipeline: %@", anError);
      return false;
    }

    // Create sampler state
    MTLSamplerDescriptor* aSamplerDesc = [[MTLSamplerDescriptor alloc] init];
    aSamplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    aSamplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    aSamplerDesc.sAddressMode = MTLSamplerAddressModeRepeat;
    aSamplerDesc.tAddressMode = MTLSamplerAddressModeRepeat;
    theBackgroundSampler = [aDevice newSamplerStateWithDescriptor:aSamplerDesc];

    return true;
  }

  int gradientTypeToInt(Aspect_GradientFillMethod theMethod)
  {
    switch (theMethod)
    {
      case Aspect_GradientFillMethod_None:       return 0;
      case Aspect_GradientFillMethod_Horizontal: return 1;
      case Aspect_GradientFillMethod_Vertical:   return 2;
      case Aspect_GradientFillMethod_Diagonal1:  return 3;
      case Aspect_GradientFillMethod_Diagonal2:  return 4;
      case Aspect_GradientFillMethod_Corner1:
      case Aspect_GradientFillMethod_Corner2:
      case Aspect_GradientFillMethod_Corner3:
      case Aspect_GradientFillMethod_Corner4:    return 5;
      default: return 0;
    }
  }
}

// =======================================================================
// function : Render
// purpose  : Render background
// =======================================================================
void Metal_BackgroundRenderer::Render(Metal_Workspace* theWorkspace,
                                       int theWidth,
                                       int theHeight)
{
  if (theWorkspace == nullptr || myFillMethod == FillMethod_None)
  {
    return;
  }

  (void)theWidth;
  (void)theHeight;

  const occ::handle<Metal_Context>& aCtx = theWorkspace->GetContext();
  if (aCtx.IsNull() || aCtx->Device() == nil)
  {
    return;
  }

  if (!ensurePipelines(aCtx.get()))
  {
    return;
  }

  id<MTLRenderCommandEncoder> anEncoder = theWorkspace->ActiveEncoder();
  if (anEncoder == nil)
  {
    return;
  }

  // Disable depth write for background
  [anEncoder setDepthStencilState:nil];
  [anEncoder setCullMode:MTLCullModeNone];

  if (myFillMethod == FillMethod_Cubemap && !myCubemap.IsNull())
  {
    // Render cubemap background
    [anEncoder setRenderPipelineState:theCubemapPipeline];

    // Get inverse view-projection matrix from workspace
    // For now, use identity (would need view matrix from camera)
    simd_float4x4 aInvVP = matrix_identity_float4x4;

    [anEncoder setVertexBytes:&aInvVP length:sizeof(aInvVP) atIndex:0];
    [anEncoder setFragmentTexture:myCubemap->Texture() atIndex:0];
    [anEncoder setFragmentSamplerState:theBackgroundSampler atIndex:0];

    [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  }
  else
  {
    // Render gradient/solid/textured background
    [anEncoder setRenderPipelineState:theGradientPipeline];

    struct BackgroundUniforms {
      simd_float4 color1;
      simd_float4 color2;
      simd_float2 textureScale;
      simd_float2 textureOffset;
      int         gradientType;
      int         hasTexture;
      int         padding[2];
    } aUniforms;

    aUniforms.color1 = simd_make_float4(myColor1.r(), myColor1.g(), myColor1.b(), myColor1.a());
    aUniforms.color2 = simd_make_float4(myColor2.r(), myColor2.g(), myColor2.b(), myColor2.a());
    aUniforms.textureScale = simd_make_float2(myTextureScale.x(), myTextureScale.y());
    aUniforms.textureOffset = simd_make_float2(myTextureOffset.x(), myTextureOffset.y());
    aUniforms.hasTexture = (myFillMethod == FillMethod_Texture && !myTexture.IsNull()) ? 1 : 0;

    if (myFillMethod == FillMethod_Solid)
    {
      aUniforms.gradientType = 0;
    }
    else if (myFillMethod == FillMethod_Gradient)
    {
      aUniforms.gradientType = gradientTypeToInt(myGradientMethod);
    }
    else
    {
      aUniforms.gradientType = 0;
    }

    [anEncoder setFragmentBytes:&aUniforms length:sizeof(aUniforms) atIndex:0];

    if (aUniforms.hasTexture)
    {
      [anEncoder setFragmentTexture:myTexture->Texture() atIndex:0];
    }
    [anEncoder setFragmentSamplerState:theBackgroundSampler atIndex:0];

    [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  }

  myIsDirty = false;
}

// =======================================================================
// function : Release
// purpose  : Release resources
// =======================================================================
void Metal_BackgroundRenderer::Release(Metal_Context* theCtx)
{
  if (!myTexture.IsNull())
  {
    myTexture->Release(theCtx);
    myTexture.Nullify();
  }
  if (!myCubemap.IsNull())
  {
    myCubemap->Release(theCtx);
    myCubemap.Nullify();
  }
}
