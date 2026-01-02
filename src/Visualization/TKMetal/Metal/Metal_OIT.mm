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

#import "Metal_OIT.hxx"
#import "Metal_Context.hxx"
#import "Metal_Texture.hxx"

#import <Metal/Metal.h>
#import <simd/simd.h>

IMPLEMENT_STANDARD_RTTIEXT(Metal_OIT, Metal_Resource)

namespace
{
  //! Shader source for weighted blended OIT compositing
  static const char* THE_WEIGHTED_COMPOSITE_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut weightedCompositeVertex(uint vertexID [[vertex_id]])
{
  // Full-screen triangle
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

fragment float4 weightedCompositeFragment(
  VertexOut in [[stage_in]],
  texture2d<float> accumTexture [[texture(0)]],
  texture2d<float> weightTexture [[texture(1)]])
{
  constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest);

  float4 accum = accumTexture.sample(texSampler, in.texCoord);
  float weight = weightTexture.sample(texSampler, in.texCoord).r;

  // Prevent division by zero
  float3 color = accum.rgb / max(weight, 0.00001);
  float alpha = accum.a;

  // Pre-multiplied alpha output for blending
  return float4(color * (1.0 - alpha), alpha);
}
)";

  //! Shader source for depth peeling blend pass
  static const char* THE_PEELING_BLEND_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut peelingBlendVertex(uint vertexID [[vertex_id]])
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

fragment float4 peelingBlendFragment(
  VertexOut in [[stage_in]],
  texture2d<float> backColorTexture [[texture(0)]])
{
  constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest);

  float4 backColor = backColorTexture.sample(texSampler, in.texCoord);

  // Discard fully transparent pixels
  if (backColor.a == 0.0) {
    discard_fragment();
  }

  return backColor;
}
)";

  //! Shader source for depth peeling final flush
  static const char* THE_PEELING_FLUSH_SHADER = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut peelingFlushVertex(uint vertexID [[vertex_id]])
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

fragment float4 peelingFlushFragment(
  VertexOut in [[stage_in]],
  texture2d<float> frontColorTexture [[texture(0)]],
  texture2d<float> blendBackTexture [[texture(1)]])
{
  constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest);

  float4 frontColor = frontColorTexture.sample(texSampler, in.texCoord);
  float4 backColor = blendBackTexture.sample(texSampler, in.texCoord);

  // Combine front and back colors
  float alphaMult = 1.0 - frontColor.a;
  float3 finalColor = frontColor.rgb + alphaMult * backColor.rgb;
  float finalAlpha = frontColor.a + backColor.a;

  return float4(finalColor, finalAlpha);
}
)";
}

//=================================================================================================

Metal_OIT::Metal_OIT()
: myAccumTexture(nil),
  myWeightTexture(nil),
  myCompositePipeline(nil),
  myBlendBackTexture(nil),
  myPeelingBlendPipeline(nil),
  myPeelingFlushPipeline(nil),
  myMethod(Metal_OITMethod_None),
  myWidth(0),
  myHeight(0),
  mySampleCount(1),
  myDepthFactor(0.0f),
  myNbPeelingLayers(4),
  myCurrentPeelingPass(0),
  myPeelingReadIndex(0),
  myIsInitialized(false),
  myEstimatedSize(0)
{
  for (int i = 0; i < 2; ++i)
  {
    myPeelingDepth[i] = nil;
    myPeelingFrontColor[i] = nil;
    myPeelingBackColor[i] = nil;
  }
}

//=================================================================================================

Metal_OIT::~Metal_OIT()
{
  Release(nullptr);
}

//=================================================================================================

void Metal_OIT::Release(Metal_Context* /*theCtx*/)
{
  myAccumTexture = nil;
  myWeightTexture = nil;
  myCompositePipeline = nil;
  myBlendBackTexture = nil;
  myPeelingBlendPipeline = nil;
  myPeelingFlushPipeline = nil;

  for (int i = 0; i < 2; ++i)
  {
    myPeelingDepth[i] = nil;
    myPeelingFrontColor[i] = nil;
    myPeelingBackColor[i] = nil;
  }

  myIsInitialized = false;
  myEstimatedSize = 0;
}

//=================================================================================================

size_t Metal_OIT::EstimatedDataSize() const
{
  return myEstimatedSize;
}

//=================================================================================================

bool Metal_OIT::Init(Metal_Context* theCtx,
                     Metal_OITMethod theMethod,
                     int theWidth,
                     int theHeight,
                     int theSampleCount)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  // Release existing resources if method or sample count changed
  if (myMethod != theMethod || mySampleCount != theSampleCount)
  {
    Release(theCtx);
  }

  myMethod = theMethod;
  myWidth = theWidth;
  myHeight = theHeight;
  mySampleCount = theSampleCount;

  if (theMethod == Metal_OITMethod_None)
  {
    myIsInitialized = true;
    return true;
  }

  bool aResult = false;
  if (theMethod == Metal_OITMethod_WeightedBlended)
  {
    aResult = initWeightedBlended(theCtx);
  }
  else if (theMethod == Metal_OITMethod_DepthPeeling)
  {
    aResult = initDepthPeeling(theCtx);
  }

  myIsInitialized = aResult;
  return aResult;
}

//=================================================================================================

bool Metal_OIT::Resize(Metal_Context* theCtx,
                       int theWidth,
                       int theHeight)
{
  if (theWidth == myWidth && theHeight == myHeight)
  {
    return true;
  }

  return Init(theCtx, myMethod, theWidth, theHeight, mySampleCount);
}

//=================================================================================================

bool Metal_OIT::initWeightedBlended(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();

  // Create accumulation texture (RGBA16Float)
  MTLTextureDescriptor* anAccumDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                         width:myWidth
                                                                                        height:myHeight
                                                                                     mipmapped:NO];
  anAccumDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  anAccumDesc.storageMode = MTLStorageModePrivate;

  if (mySampleCount > 1)
  {
    anAccumDesc.textureType = MTLTextureType2DMultisample;
    anAccumDesc.sampleCount = mySampleCount;
  }

  myAccumTexture = [aDevice newTextureWithDescriptor:anAccumDesc];
  if (myAccumTexture == nil)
  {
    return false;
  }
  myAccumTexture.label = @"OIT_Accumulation";

  // Create weight texture (R16Float for revealage)
  MTLTextureDescriptor* aWeightDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Float
                                                                                         width:myWidth
                                                                                        height:myHeight
                                                                                     mipmapped:NO];
  aWeightDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  aWeightDesc.storageMode = MTLStorageModePrivate;

  if (mySampleCount > 1)
  {
    aWeightDesc.textureType = MTLTextureType2DMultisample;
    aWeightDesc.sampleCount = mySampleCount;
  }

  myWeightTexture = [aDevice newTextureWithDescriptor:aWeightDesc];
  if (myWeightTexture == nil)
  {
    return false;
  }
  myWeightTexture.label = @"OIT_Weight";

  // Calculate estimated memory
  size_t aBytesPerPixel = 8 + 2; // RGBA16Float + R16Float
  myEstimatedSize = myWidth * myHeight * aBytesPerPixel * mySampleCount;

  // Create compositing pipeline
  if (!createWeightedCompositePipeline(theCtx))
  {
    return false;
  }

  return true;
}

//=================================================================================================

bool Metal_OIT::initDepthPeeling(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();

  // Create ping-pong textures
  for (int i = 0; i < 2; ++i)
  {
    // Depth texture (RG32Float for min/max depth)
    MTLTextureDescriptor* aDepthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG32Float
                                                                                           width:myWidth
                                                                                          height:myHeight
                                                                                       mipmapped:NO];
    aDepthDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    aDepthDesc.storageMode = MTLStorageModePrivate;

    myPeelingDepth[i] = [aDevice newTextureWithDescriptor:aDepthDesc];
    if (myPeelingDepth[i] == nil)
    {
      return false;
    }
    myPeelingDepth[i].label = [NSString stringWithFormat:@"OIT_PeelingDepth_%d", i];

    // Front color texture (RGBA16Float)
    MTLTextureDescriptor* aFrontDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                           width:myWidth
                                                                                          height:myHeight
                                                                                       mipmapped:NO];
    aFrontDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    aFrontDesc.storageMode = MTLStorageModePrivate;

    myPeelingFrontColor[i] = [aDevice newTextureWithDescriptor:aFrontDesc];
    if (myPeelingFrontColor[i] == nil)
    {
      return false;
    }
    myPeelingFrontColor[i].label = [NSString stringWithFormat:@"OIT_PeelingFront_%d", i];

    // Back color texture (RGBA16Float)
    MTLTextureDescriptor* aBackDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          width:myWidth
                                                                                         height:myHeight
                                                                                      mipmapped:NO];
    aBackDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    aBackDesc.storageMode = MTLStorageModePrivate;

    myPeelingBackColor[i] = [aDevice newTextureWithDescriptor:aBackDesc];
    if (myPeelingBackColor[i] == nil)
    {
      return false;
    }
    myPeelingBackColor[i].label = [NSString stringWithFormat:@"OIT_PeelingBack_%d", i];
  }

  // Blend back accumulation texture
  MTLTextureDescriptor* aBlendDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                         width:myWidth
                                                                                        height:myHeight
                                                                                     mipmapped:NO];
  aBlendDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  aBlendDesc.storageMode = MTLStorageModePrivate;

  myBlendBackTexture = [aDevice newTextureWithDescriptor:aBlendDesc];
  if (myBlendBackTexture == nil)
  {
    return false;
  }
  myBlendBackTexture.label = @"OIT_BlendBack";

  // Calculate estimated memory
  // 2 * (RG32Float + RGBA16Float + RGBA16Float) + RGBA16Float
  size_t aBytesPerPixel = 2 * (8 + 8 + 8) + 8;
  myEstimatedSize = myWidth * myHeight * aBytesPerPixel;

  // Create pipelines
  if (!createPeelingCompositePipeline(theCtx))
  {
    return false;
  }

  return true;
}

//=================================================================================================

bool Metal_OIT::createWeightedCompositePipeline(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();

  NSError* anError = nil;
  id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_WEIGHTED_COMPOSITE_SHADER]
                                                  options:nil
                                                    error:&anError];
  if (aLibrary == nil)
  {
    NSLog(@"Metal_OIT: Failed to compile weighted composite shader: %@", anError);
    return false;
  }

  id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"weightedCompositeVertex"];
  id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"weightedCompositeFragment"];

  MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
  aPipelineDesc.label = @"OIT_WeightedComposite";
  aPipelineDesc.vertexFunction = aVertexFunc;
  aPipelineDesc.fragmentFunction = aFragmentFunc;
  aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

  // Blend: result = src * ONE_MINUS_SRC_ALPHA + dst * SRC_ALPHA
  aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
  aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorSourceAlpha;
  aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
  aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorSourceAlpha;
  aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

  myCompositePipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                error:&anError];
  if (myCompositePipeline == nil)
  {
    NSLog(@"Metal_OIT: Failed to create weighted composite pipeline: %@", anError);
    return false;
  }

  return true;
}

//=================================================================================================

bool Metal_OIT::createPeelingCompositePipeline(Metal_Context* theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();
  NSError* anError = nil;

  // Blend pipeline
  {
    id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_PEELING_BLEND_SHADER]
                                                    options:nil
                                                      error:&anError];
    if (aLibrary == nil)
    {
      NSLog(@"Metal_OIT: Failed to compile peeling blend shader: %@", anError);
      return false;
    }

    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"peelingBlendVertex"];
    id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"peelingBlendFragment"];

    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.label = @"OIT_PeelingBlend";
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.fragmentFunction = aFragmentFunc;
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;

    // Blend with alpha
    aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
    aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

    myPeelingBlendPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                     error:&anError];
    if (myPeelingBlendPipeline == nil)
    {
      NSLog(@"Metal_OIT: Failed to create peeling blend pipeline: %@", anError);
      return false;
    }
  }

  // Flush pipeline
  {
    id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:[NSString stringWithUTF8String:THE_PEELING_FLUSH_SHADER]
                                                    options:nil
                                                      error:&anError];
    if (aLibrary == nil)
    {
      NSLog(@"Metal_OIT: Failed to compile peeling flush shader: %@", anError);
      return false;
    }

    id<MTLFunction> aVertexFunc = [aLibrary newFunctionWithName:@"peelingFlushVertex"];
    id<MTLFunction> aFragmentFunc = [aLibrary newFunctionWithName:@"peelingFlushFragment"];

    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.label = @"OIT_PeelingFlush";
    aPipelineDesc.vertexFunction = aVertexFunc;
    aPipelineDesc.fragmentFunction = aFragmentFunc;
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    // Blend: src * ONE + dst * ONE_MINUS_SRC_ALPHA
    aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
    aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

    myPeelingFlushPipeline = [aDevice newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                     error:&anError];
    if (myPeelingFlushPipeline == nil)
    {
      NSLog(@"Metal_OIT: Failed to create peeling flush pipeline: %@", anError);
      return false;
    }
  }

  return true;
}

//=================================================================================================

void Metal_OIT::BeginAccumulation(Metal_Context* theCtx)
{
  if (!myIsInitialized || myMethod == Metal_OITMethod_None)
  {
    return;
  }

  myCurrentPeelingPass = 0;
  myPeelingReadIndex = 1; // Start reading from 1, writing to 0

  // Clear textures would be done by the render pass that uses them
}

//=================================================================================================

bool Metal_OIT::NextPeelingPass(Metal_Context* theCtx)
{
  if (myMethod != Metal_OITMethod_DepthPeeling)
  {
    return false;
  }

  myCurrentPeelingPass++;
  myPeelingReadIndex = 1 - myPeelingReadIndex; // Swap ping-pong

  return myCurrentPeelingPass < myNbPeelingLayers;
}

//=================================================================================================

void Metal_OIT::EndAccumulationAndComposite(Metal_Context* theCtx,
                                             id<MTLTexture> theTargetTexture)
{
  if (!myIsInitialized || myMethod == Metal_OITMethod_None)
  {
    return;
  }

  if (myMethod == Metal_OITMethod_WeightedBlended)
  {
    compositeWeightedBlended(theCtx, theTargetTexture);
  }
  else if (myMethod == Metal_OITMethod_DepthPeeling)
  {
    compositeDepthPeeling(theCtx, theTargetTexture);
  }
}

//=================================================================================================

void Metal_OIT::compositeWeightedBlended(Metal_Context* theCtx,
                                          id<MTLTexture> theTargetTexture)
{
  id<MTLCommandBuffer> aCommandBuffer = [theCtx->CommandQueue() commandBuffer];
  aCommandBuffer.label = @"OIT_WeightedComposite";

  MTLRenderPassDescriptor* aPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  aPassDesc.colorAttachments[0].texture = theTargetTexture;
  aPassDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
  aPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> anEncoder = [aCommandBuffer renderCommandEncoderWithDescriptor:aPassDesc];
  anEncoder.label = @"OIT_WeightedComposite";

  [anEncoder setRenderPipelineState:myCompositePipeline];
  [anEncoder setFragmentTexture:myAccumTexture atIndex:0];
  [anEncoder setFragmentTexture:myWeightTexture atIndex:1];

  // Draw full-screen triangle
  [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [anEncoder endEncoding];
  [aCommandBuffer commit];
}

//=================================================================================================

void Metal_OIT::compositeDepthPeeling(Metal_Context* theCtx,
                                       id<MTLTexture> theTargetTexture)
{
  id<MTLCommandBuffer> aCommandBuffer = [theCtx->CommandQueue() commandBuffer];
  aCommandBuffer.label = @"OIT_PeelingFlush";

  MTLRenderPassDescriptor* aPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  aPassDesc.colorAttachments[0].texture = theTargetTexture;
  aPassDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
  aPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> anEncoder = [aCommandBuffer renderCommandEncoderWithDescriptor:aPassDesc];
  anEncoder.label = @"OIT_PeelingFlush";

  int aReadIndex = myPeelingReadIndex;

  [anEncoder setRenderPipelineState:myPeelingFlushPipeline];
  [anEncoder setFragmentTexture:myPeelingFrontColor[aReadIndex] atIndex:0];
  [anEncoder setFragmentTexture:myBlendBackTexture atIndex:1];

  // Draw full-screen triangle
  [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [anEncoder endEncoding];
  [aCommandBuffer commit];
}
