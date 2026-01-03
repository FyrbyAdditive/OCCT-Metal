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

#include "Metal_PostProcess.hxx"
#include "Metal_Context.hxx"

#import <Metal/Metal.h>

IMPLEMENT_STANDARD_RTTIEXT(Metal_PostProcess, Standard_Transient)

namespace
{
  //! Post-processing shader source code.
  static NSString* PostProcessShaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

// Fullscreen triangle vertex output
struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

// Fullscreen triangle - covers screen with single triangle
vertex VertexOut postProcessVertex(uint vertexID [[vertex_id]]) {
  VertexOut out;
  // Generate fullscreen triangle
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(3.0, -1.0),
    float2(-1.0, 3.0)
  };
  float2 texCoords[3] = {
    float2(0.0, 1.0),
    float2(2.0, 1.0),
    float2(0.0, -1.0)
  };
  out.position = float4(positions[vertexID], 0.0, 1.0);
  out.texCoord = texCoords[vertexID];
  return out;
}

// Post-processing parameters buffer
struct PostProcessParams {
  int   effects;           // Bitmask of enabled effects
  int   toneMappingMethod; // 0=disabled, 1=filmic
  float exposure;          // Exposure value
  float whitePoint;        // White point for filmic
  float gamma;             // Gamma correction value
  int   fxaaQuality;       // FXAA quality (0=low, 1=med, 2=high)
  float vignetteIntensity; // Vignette intensity
  float vignetteRadius;    // Vignette radius
  float2 texelSize;        // 1.0 / texture size
};

// Effect bit flags (must match Metal_PostProcessEffect enum)
constant int EFFECT_FXAA = 1;
constant int EFFECT_TONEMAPPING = 2;
constant int EFFECT_VIGNETTE = 4;
constant int EFFECT_GAMMA = 8;

//==============================================================================
// FXAA - Fast Approximate Anti-Aliasing
//==============================================================================

// FXAA luminance calculation
float fxaaLuma(float3 color) {
  return dot(color, float3(0.299, 0.587, 0.114));
}

// FXAA implementation (quality preset based)
float3 applyFXAA(texture2d<float> tex, sampler samp, float2 uv, float2 texelSize, int quality) {
  // Sample center and neighbors
  float3 rgbM = tex.sample(samp, uv).rgb;
  float3 rgbN = tex.sample(samp, uv + float2(0.0, -texelSize.y)).rgb;
  float3 rgbS = tex.sample(samp, uv + float2(0.0, texelSize.y)).rgb;
  float3 rgbE = tex.sample(samp, uv + float2(texelSize.x, 0.0)).rgb;
  float3 rgbW = tex.sample(samp, uv + float2(-texelSize.x, 0.0)).rgb;

  // Calculate luminance
  float lumaM = fxaaLuma(rgbM);
  float lumaN = fxaaLuma(rgbN);
  float lumaS = fxaaLuma(rgbS);
  float lumaE = fxaaLuma(rgbE);
  float lumaW = fxaaLuma(rgbW);

  // Find min/max luma
  float lumaMin = min(lumaM, min(min(lumaN, lumaS), min(lumaE, lumaW)));
  float lumaMax = max(lumaM, max(max(lumaN, lumaS), max(lumaE, lumaW)));

  // Calculate contrast
  float lumaRange = lumaMax - lumaMin;

  // Edge threshold based on quality
  float edgeThreshold = (quality == 0) ? 0.166 : (quality == 1) ? 0.125 : 0.063;
  float edgeThresholdMin = 0.0312;

  // Skip anti-aliasing if contrast is too low
  if (lumaRange < max(edgeThresholdMin, lumaMax * edgeThreshold)) {
    return rgbM;
  }

  // Sample corners for better edge detection
  float3 rgbNW = tex.sample(samp, uv + float2(-texelSize.x, -texelSize.y)).rgb;
  float3 rgbNE = tex.sample(samp, uv + float2(texelSize.x, -texelSize.y)).rgb;
  float3 rgbSW = tex.sample(samp, uv + float2(-texelSize.x, texelSize.y)).rgb;
  float3 rgbSE = tex.sample(samp, uv + float2(texelSize.x, texelSize.y)).rgb;

  float lumaNW = fxaaLuma(rgbNW);
  float lumaNE = fxaaLuma(rgbNE);
  float lumaSW = fxaaLuma(rgbSW);
  float lumaSE = fxaaLuma(rgbSE);

  // Determine edge direction
  float edgeHorz = abs(lumaNW + lumaN * 2.0 + lumaNE - lumaSW - lumaS * 2.0 - lumaSE);
  float edgeVert = abs(lumaNW + lumaW * 2.0 + lumaSW - lumaNE - lumaE * 2.0 - lumaSE);
  bool isHorizontal = edgeHorz >= edgeVert;

  // Select edge endpoints
  float luma1 = isHorizontal ? lumaN : lumaW;
  float luma2 = isHorizontal ? lumaS : lumaE;
  float gradient1 = abs(luma1 - lumaM);
  float gradient2 = abs(luma2 - lumaM);

  // Choose steeper side
  bool is1Steeper = gradient1 >= gradient2;
  float gradientScaled = 0.25 * max(gradient1, gradient2);

  // Calculate step direction
  float stepLength = isHorizontal ? texelSize.y : texelSize.x;
  if (!is1Steeper) stepLength = -stepLength;

  // Subpixel offset
  float lumaLocalAverage = 0.5 * (luma1 + luma2);
  float subpixelOffset = saturate(abs(lumaLocalAverage - lumaM) / lumaRange);
  subpixelOffset = (-2.0 * subpixelOffset + 3.0) * subpixelOffset * subpixelOffset;
  float subpixelOffsetFinal = subpixelOffset * subpixelOffset * 0.75;

  // Calculate final UV offset
  float2 uvOffset = uv;
  if (isHorizontal) {
    uvOffset.y += stepLength * subpixelOffsetFinal;
  } else {
    uvOffset.x += stepLength * subpixelOffsetFinal;
  }

  // Blend based on quality
  float3 rgbFinal = tex.sample(samp, uvOffset).rgb;
  if (quality >= 1) {
    rgbFinal = mix(rgbM, rgbFinal, 0.5 + subpixelOffsetFinal * 0.5);
  }

  return rgbFinal;
}

//==============================================================================
// Tone Mapping
//==============================================================================

// Reinhard tone mapping
float3 reinhardToneMapping(float3 hdr, float exposure) {
  float3 mapped = hdr * exposure;
  return mapped / (mapped + 1.0);
}

// Filmic tone mapping (ACES approximation)
float3 filmicToneMapping(float3 hdr, float exposure, float whitePoint) {
  float3 x = hdr * exposure;

  // ACES filmic curve parameters
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;

  float3 mapped = saturate((x * (a * x + b)) / (x * (c * x + d) + e));

  // White point adjustment
  float3 white = float3(whitePoint);
  float3 whiteScale = 1.0 / saturate((white * (a * white + b)) / (white * (c * white + d) + e));

  return mapped * whiteScale;
}

//==============================================================================
// Vignette
//==============================================================================

float3 applyVignette(float3 color, float2 uv, float intensity, float radius) {
  float2 center = float2(0.5, 0.5);
  float dist = length(uv - center);
  float vignette = smoothstep(radius, radius - intensity, dist);
  return color * vignette;
}

//==============================================================================
// Gamma Correction
//==============================================================================

float3 applyGamma(float3 color, float gamma) {
  return pow(color, float3(1.0 / gamma));
}

//==============================================================================
// Combined Post-Processing Fragment Shader
//==============================================================================

fragment float4 postProcessCombined(
  VertexOut in [[stage_in]],
  texture2d<float> sourceTexture [[texture(0)]],
  sampler texSampler [[sampler(0)]],
  constant PostProcessParams& params [[buffer(0)]]
) {
  float2 uv = in.texCoord;
  float3 color;

  // Apply FXAA if enabled
  if (params.effects & EFFECT_FXAA) {
    color = applyFXAA(sourceTexture, texSampler, uv, params.texelSize, params.fxaaQuality);
  } else {
    color = sourceTexture.sample(texSampler, uv).rgb;
  }

  // Apply tone mapping if enabled
  if (params.effects & EFFECT_TONEMAPPING) {
    if (params.toneMappingMethod == 1) {
      color = filmicToneMapping(color, params.exposure, params.whitePoint);
    } else {
      color = reinhardToneMapping(color, params.exposure);
    }
  }

  // Apply vignette if enabled
  if (params.effects & EFFECT_VIGNETTE) {
    color = applyVignette(color, uv, params.vignetteIntensity, params.vignetteRadius);
  }

  // Apply gamma correction if enabled
  if (params.effects & EFFECT_GAMMA) {
    color = applyGamma(color, params.gamma);
  }

  return float4(color, 1.0);
}

//==============================================================================
// Individual Effect Fragment Shaders (for separate passes)
//==============================================================================

// FXAA only
fragment float4 postProcessFXAA(
  VertexOut in [[stage_in]],
  texture2d<float> sourceTexture [[texture(0)]],
  sampler texSampler [[sampler(0)]],
  constant PostProcessParams& params [[buffer(0)]]
) {
  float3 color = applyFXAA(sourceTexture, texSampler, in.texCoord, params.texelSize, params.fxaaQuality);
  return float4(color, 1.0);
}

// Tone mapping only
fragment float4 postProcessToneMapping(
  VertexOut in [[stage_in]],
  texture2d<float> sourceTexture [[texture(0)]],
  sampler texSampler [[sampler(0)]],
  constant PostProcessParams& params [[buffer(0)]]
) {
  float3 color = sourceTexture.sample(texSampler, in.texCoord).rgb;

  if (params.toneMappingMethod == 1) {
    color = filmicToneMapping(color, params.exposure, params.whitePoint);
  } else {
    color = reinhardToneMapping(color, params.exposure);
  }

  // Also apply gamma when tone mapping
  if (params.effects & EFFECT_GAMMA) {
    color = applyGamma(color, params.gamma);
  }

  return float4(color, 1.0);
}

)";

  //! GPU parameters structure (must match shader)
  struct PostProcessGPUParams {
    int   effects;
    int   toneMappingMethod;
    float exposure;
    float whitePoint;
    float gamma;
    int   fxaaQuality;
    float vignetteIntensity;
    float vignetteRadius;
    float texelSizeX;
    float texelSizeY;
  };
}

// =======================================================================
// function : Metal_PostProcess
// purpose  : Constructor
// =======================================================================
Metal_PostProcess::Metal_PostProcess()
: myLibrary(nil),
  mySampler(nil),
  myFXAAPipeline(nil),
  myToneMappingPipeline(nil),
  myCombinedPipeline(nil),
  myParams(),
  myEffects(0),
  myIsValid(false)
{
  //
}

// =======================================================================
// function : ~Metal_PostProcess
// purpose  : Destructor
// =======================================================================
Metal_PostProcess::~Metal_PostProcess()
{
  // Resources released when ARC deallocates
}

// =======================================================================
// function : Init
// purpose  : Initialize post-processing resources
// =======================================================================
bool Metal_PostProcess::Init(Metal_Context* theCtx)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  id<MTLDevice> device = theCtx->Device();
  NSError* error = nil;

  // Compile shader library
  myLibrary = [device newLibraryWithSource:PostProcessShaderSource
                                   options:nil
                                     error:&error];
  if (myLibrary == nil)
  {
    NSLog(@"Metal_PostProcess: Failed to compile shaders: %@", error);
    return false;
  }

  // Create sampler state
  MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
  samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
  samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
  mySampler = [device newSamplerStateWithDescriptor:samplerDesc];

  // Get shader functions
  id<MTLFunction> vertexFunc = [myLibrary newFunctionWithName:@"postProcessVertex"];
  id<MTLFunction> fxaaFunc = [myLibrary newFunctionWithName:@"postProcessFXAA"];
  id<MTLFunction> tonemapFunc = [myLibrary newFunctionWithName:@"postProcessToneMapping"];
  id<MTLFunction> combinedFunc = [myLibrary newFunctionWithName:@"postProcessCombined"];

  if (vertexFunc == nil || combinedFunc == nil)
  {
    NSLog(@"Metal_PostProcess: Failed to get shader functions");
    return false;
  }

  // Create pipeline descriptor
  MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineDesc.vertexFunction = vertexFunc;
  pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

  // Create FXAA pipeline
  if (fxaaFunc != nil)
  {
    pipelineDesc.fragmentFunction = fxaaFunc;
    pipelineDesc.label = @"FXAA Pipeline";
    myFXAAPipeline = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (myFXAAPipeline == nil)
    {
      NSLog(@"Metal_PostProcess: Failed to create FXAA pipeline: %@", error);
    }
  }

  // Create tone mapping pipeline
  if (tonemapFunc != nil)
  {
    pipelineDesc.fragmentFunction = tonemapFunc;
    pipelineDesc.label = @"Tone Mapping Pipeline";
    myToneMappingPipeline = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (myToneMappingPipeline == nil)
    {
      NSLog(@"Metal_PostProcess: Failed to create tone mapping pipeline: %@", error);
    }
  }

  // Create combined pipeline
  pipelineDesc.fragmentFunction = combinedFunc;
  pipelineDesc.label = @"Combined Post-Process Pipeline";
  myCombinedPipeline = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
  if (myCombinedPipeline == nil)
  {
    NSLog(@"Metal_PostProcess: Failed to create combined pipeline: %@", error);
    return false;
  }

  myIsValid = true;
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_PostProcess::Release(Metal_Context* theCtx)
{
  (void)theCtx;
  myLibrary = nil;
  mySampler = nil;
  myFXAAPipeline = nil;
  myToneMappingPipeline = nil;
  myCombinedPipeline = nil;
  myIsValid = false;
}

// =======================================================================
// function : Apply
// purpose  : Apply post-processing effects
// =======================================================================
void Metal_PostProcess::Apply(Metal_Context* theCtx,
                              id<MTLCommandBuffer> theCommandBuffer,
                              id<MTLTexture> theSource,
                              id<MTLTexture> theTarget)
{
  if (!myIsValid || theCommandBuffer == nil || theSource == nil || theTarget == nil)
  {
    return;
  }

  // If no effects enabled, just blit
  if (myEffects == 0)
  {
    id<MTLBlitCommandEncoder> blit = [theCommandBuffer blitCommandEncoder];
    [blit copyFromTexture:theSource toTexture:theTarget];
    [blit endEncoding];
    return;
  }

  // Create render pass descriptor
  MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  passDesc.colorAttachments[0].texture = theTarget;
  passDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> encoder = [theCommandBuffer renderCommandEncoderWithDescriptor:passDesc];
  if (encoder == nil)
  {
    return;
  }

  [encoder setLabel:@"Post-Processing"];

  // Set up GPU parameters
  PostProcessGPUParams gpuParams;
  gpuParams.effects = myEffects;
  gpuParams.toneMappingMethod = (myParams.ToneMappingMethod == Graphic3d_ToneMappingMethod_Filmic) ? 1 : 0;
  gpuParams.exposure = myParams.Exposure;
  gpuParams.whitePoint = myParams.WhitePoint;
  gpuParams.gamma = myParams.Gamma;
  gpuParams.fxaaQuality = myParams.FXAAQuality;
  gpuParams.vignetteIntensity = myParams.VignetteIntensity;
  gpuParams.vignetteRadius = myParams.VignetteRadius;
  gpuParams.texelSizeX = 1.0f / (float)theSource.width;
  gpuParams.texelSizeY = 1.0f / (float)theSource.height;

  // Set pipeline and resources
  [encoder setRenderPipelineState:myCombinedPipeline];
  [encoder setFragmentTexture:theSource atIndex:0];
  [encoder setFragmentSamplerState:mySampler atIndex:0];
  [encoder setFragmentBytes:&gpuParams length:sizeof(gpuParams) atIndex:0];

  // Draw fullscreen triangle
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [encoder endEncoding];
}

// =======================================================================
// function : ApplyFXAA
// purpose  : Apply FXAA anti-aliasing only
// =======================================================================
void Metal_PostProcess::ApplyFXAA(Metal_Context* theCtx,
                                  id<MTLCommandBuffer> theCommandBuffer,
                                  id<MTLTexture> theSource,
                                  id<MTLTexture> theTarget)
{
  if (!myIsValid || myFXAAPipeline == nil || theCommandBuffer == nil)
  {
    return;
  }

  MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  passDesc.colorAttachments[0].texture = theTarget;
  passDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> encoder = [theCommandBuffer renderCommandEncoderWithDescriptor:passDesc];
  if (encoder == nil)
  {
    return;
  }

  [encoder setLabel:@"FXAA"];

  PostProcessGPUParams gpuParams;
  gpuParams.effects = Metal_PostProcessEffect_FXAA;
  gpuParams.fxaaQuality = myParams.FXAAQuality;
  gpuParams.texelSizeX = 1.0f / (float)theSource.width;
  gpuParams.texelSizeY = 1.0f / (float)theSource.height;

  [encoder setRenderPipelineState:myFXAAPipeline];
  [encoder setFragmentTexture:theSource atIndex:0];
  [encoder setFragmentSamplerState:mySampler atIndex:0];
  [encoder setFragmentBytes:&gpuParams length:sizeof(gpuParams) atIndex:0];

  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [encoder endEncoding];
}

// =======================================================================
// function : ApplyToneMapping
// purpose  : Apply tone mapping and color grading
// =======================================================================
void Metal_PostProcess::ApplyToneMapping(Metal_Context* theCtx,
                                         id<MTLCommandBuffer> theCommandBuffer,
                                         id<MTLTexture> theSource,
                                         id<MTLTexture> theTarget)
{
  if (!myIsValid || myToneMappingPipeline == nil || theCommandBuffer == nil)
  {
    return;
  }

  MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  passDesc.colorAttachments[0].texture = theTarget;
  passDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> encoder = [theCommandBuffer renderCommandEncoderWithDescriptor:passDesc];
  if (encoder == nil)
  {
    return;
  }

  [encoder setLabel:@"Tone Mapping"];

  PostProcessGPUParams gpuParams;
  gpuParams.effects = Metal_PostProcessEffect_ToneMapping | Metal_PostProcessEffect_GammaCorrection;
  gpuParams.toneMappingMethod = (myParams.ToneMappingMethod == Graphic3d_ToneMappingMethod_Filmic) ? 1 : 0;
  gpuParams.exposure = myParams.Exposure;
  gpuParams.whitePoint = myParams.WhitePoint;
  gpuParams.gamma = myParams.Gamma;
  gpuParams.texelSizeX = 1.0f / (float)theSource.width;
  gpuParams.texelSizeY = 1.0f / (float)theSource.height;

  [encoder setRenderPipelineState:myToneMappingPipeline];
  [encoder setFragmentTexture:theSource atIndex:0];
  [encoder setFragmentSamplerState:mySampler atIndex:0];
  [encoder setFragmentBytes:&gpuParams length:sizeof(gpuParams) atIndex:0];

  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [encoder endEncoding];
}
