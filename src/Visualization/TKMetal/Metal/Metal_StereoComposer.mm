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

#include <Metal_StereoComposer.hxx>
#include <Metal_Context.hxx>
#include <Metal_FrameBuffer.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_StereoComposer, Standard_Transient)

// Stereo composition shaders
static const char* STEREO_SHADER_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

struct StereoUniforms {
  float4x4 anaglyphLeft;   // Left eye color filter
  float4x4 anaglyphRight;  // Right eye color filter
  float2   texOffset;      // Texture offset for smooth interlacing
  int      reverseStereo;  // Swap left/right
  int      padding;
};

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

// Full-screen triangle vertex shader
vertex VertexOut stereoVertex(uint vid [[vertex_id]]) {
  VertexOut out;
  out.texCoord = float2((vid << 1) & 2, vid & 2);
  out.position = float4(out.texCoord * 2.0 - 1.0, 0.0, 1.0);
  out.texCoord.y = 1.0 - out.texCoord.y;  // Flip Y for Metal coordinates
  return out;
}

// Anaglyph stereo composition
fragment float4 anaglyphFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  float4 colorL = leftTex.sample(samp, in.texCoord);
  float4 colorR = rightTex.sample(samp, in.texCoord);

  if (uniforms.reverseStereo != 0) {
    float4 temp = colorL;
    colorL = colorR;
    colorR = temp;
  }

  // Apply anaglyph color matrices
  float4 resultL = uniforms.anaglyphLeft * colorL;
  float4 resultR = uniforms.anaglyphRight * colorR;

  return resultL + resultR;
}

// Row-interlaced stereo (for passive 3D displays)
fragment float4 rowInterlacedFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  // Get pixel row
  int row = int(in.position.y);
  bool isEvenRow = (row % 2) == 0;

  // Apply smooth interlacing offset
  float2 texCoordSmooth = in.texCoord - uniforms.texOffset;

  float4 colorL = leftTex.sample(samp, isEvenRow ? in.texCoord : texCoordSmooth);
  float4 colorR = rightTex.sample(samp, isEvenRow ? texCoordSmooth : in.texCoord);

  bool useLeft = (uniforms.reverseStereo != 0) ? !isEvenRow : isEvenRow;
  return useLeft ? colorL : colorR;
}

// Column-interlaced stereo
fragment float4 colInterlacedFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  int col = int(in.position.x);
  bool isEvenCol = (col % 2) == 0;

  float2 texCoordSmooth = in.texCoord - float2(uniforms.texOffset.x, 0.0);

  float4 colorL = leftTex.sample(samp, isEvenCol ? in.texCoord : texCoordSmooth);
  float4 colorR = rightTex.sample(samp, isEvenCol ? texCoordSmooth : in.texCoord);

  bool useLeft = (uniforms.reverseStereo != 0) ? !isEvenCol : isEvenCol;
  return useLeft ? colorL : colorR;
}

// Chessboard stereo (for DLP 3D displays)
fragment float4 chessboardFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  int row = int(in.position.y);
  int col = int(in.position.x);
  bool isEvenRow = (row % 2) == 0;
  bool isEvenCol = (col % 2) == 0;

  // Chessboard pattern: same parity = left eye
  bool isLeftPixel = (isEvenRow == isEvenCol);

  float4 colorL = leftTex.sample(samp, in.texCoord);
  float4 colorR = rightTex.sample(samp, in.texCoord);

  bool useLeft = (uniforms.reverseStereo != 0) ? !isLeftPixel : isLeftPixel;
  return useLeft ? colorL : colorR;
}

// Side-by-side stereo (horizontal pair)
fragment float4 sideBySideFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  float2 texCoord = in.texCoord;
  texCoord.x *= 2.0;  // Scale X to 0-2 range

  bool isRightHalf = texCoord.x > 1.0;
  if (isRightHalf) {
    texCoord.x -= 1.0;
  }

  float4 colorL = leftTex.sample(samp, texCoord);
  float4 colorR = rightTex.sample(samp, texCoord);

  bool useLeft = (uniforms.reverseStereo != 0) ? isRightHalf : !isRightHalf;
  return useLeft ? colorL : colorR;
}

// Over-under stereo (vertical pair)
fragment float4 overUnderFragment(
  VertexOut in [[stage_in]],
  texture2d<float> leftTex [[texture(0)]],
  texture2d<float> rightTex [[texture(1)]],
  sampler samp [[sampler(0)]],
  constant StereoUniforms& uniforms [[buffer(0)]])
{
  float2 texCoord = in.texCoord;
  texCoord.y *= 2.0;  // Scale Y to 0-2 range

  bool isBottomHalf = texCoord.y > 1.0;
  if (isBottomHalf) {
    texCoord.y -= 1.0;
  }

  float4 colorL = leftTex.sample(samp, texCoord);
  float4 colorR = rightTex.sample(samp, texCoord);

  bool useLeft = (uniforms.reverseStereo != 0) ? isBottomHalf : !isBottomHalf;
  return useLeft ? colorL : colorR;
}
)";

// =======================================================================
// function : Metal_StereoComposer
// purpose  : Constructor
// =======================================================================
Metal_StereoComposer::Metal_StereoComposer()
: myLibrary(nil),
  mySampler(nil),
  myPipelineAnaglyph(nil),
  myPipelineRowInterlaced(nil),
  myPipelineColInterlaced(nil),
  myPipelineChessboard(nil),
  myPipelineSideBySide(nil),
  myPipelineOverUnder(nil),
  myIsValid(false)
{
}

// =======================================================================
// function : ~Metal_StereoComposer
// purpose  : Destructor
// =======================================================================
Metal_StereoComposer::~Metal_StereoComposer()
{
  Release(nullptr);
}

// =======================================================================
// function : Init
// purpose  : Initialize stereo composition resources
// =======================================================================
bool Metal_StereoComposer::Init(Metal_Context* theCtx)
{
  Release(theCtx);

  if (theCtx == nullptr)
  {
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Compile shader library
  NSError* anError = nil;
  MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
  anOptions.fastMathEnabled = YES;

  myLibrary = [aDevice newLibraryWithSource:@(STEREO_SHADER_SOURCE)
                                    options:anOptions
                                      error:&anError];
  if (myLibrary == nil)
  {
    Message::SendFail() << "Metal_StereoComposer: shader compilation failed - "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Create sampler
  MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
  samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
  samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
  mySampler = [aDevice newSamplerStateWithDescriptor:samplerDesc];

  myIsValid = true;
  return true;
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_StereoComposer::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  myLibrary = nil;
  mySampler = nil;
  myPipelineAnaglyph = nil;
  myPipelineRowInterlaced = nil;
  myPipelineColInterlaced = nil;
  myPipelineChessboard = nil;
  myPipelineSideBySide = nil;
  myPipelineOverUnder = nil;
  myIsValid = false;
}

// =======================================================================
// function : getPipeline
// purpose  : Get or create pipeline for stereo mode
// =======================================================================
id<MTLRenderPipelineState> Metal_StereoComposer::getPipeline(Metal_Context* theCtx,
                                                              Graphic3d_StereoMode theMode,
                                                              MTLPixelFormat theTargetFormat)
{
  id<MTLRenderPipelineState>* aPipelinePtr = nullptr;
  NSString* aFragmentName = nil;

  switch (theMode)
  {
    case Graphic3d_StereoMode_Anaglyph:
      aPipelinePtr = &myPipelineAnaglyph;
      aFragmentName = @"anaglyphFragment";
      break;
    case Graphic3d_StereoMode_RowInterlaced:
      aPipelinePtr = &myPipelineRowInterlaced;
      aFragmentName = @"rowInterlacedFragment";
      break;
    case Graphic3d_StereoMode_ColumnInterlaced:
      aPipelinePtr = &myPipelineColInterlaced;
      aFragmentName = @"colInterlacedFragment";
      break;
    case Graphic3d_StereoMode_ChessBoard:
      aPipelinePtr = &myPipelineChessboard;
      aFragmentName = @"chessboardFragment";
      break;
    case Graphic3d_StereoMode_SideBySide:
      aPipelinePtr = &myPipelineSideBySide;
      aFragmentName = @"sideBySideFragment";
      break;
    case Graphic3d_StereoMode_OverUnder:
      aPipelinePtr = &myPipelineOverUnder;
      aFragmentName = @"overUnderFragment";
      break;
    default:
      // QuadBuffer, SoftPageFlip, OpenVR - use anaglyph as fallback
      aPipelinePtr = &myPipelineAnaglyph;
      aFragmentName = @"anaglyphFragment";
      break;
  }

  // Return cached pipeline if available
  if (*aPipelinePtr != nil)
  {
    return *aPipelinePtr;
  }

  // Create new pipeline
  id<MTLDevice> aDevice = theCtx->Device();
  id<MTLFunction> aVertexFunc = [myLibrary newFunctionWithName:@"stereoVertex"];
  id<MTLFunction> aFragmentFunc = [myLibrary newFunctionWithName:aFragmentName];

  if (aVertexFunc == nil || aFragmentFunc == nil)
  {
    Message::SendFail() << "Metal_StereoComposer: shader functions not found";
    return nil;
  }

  MTLRenderPipelineDescriptor* aDesc = [[MTLRenderPipelineDescriptor alloc] init];
  aDesc.vertexFunction = aVertexFunc;
  aDesc.fragmentFunction = aFragmentFunc;
  aDesc.colorAttachments[0].pixelFormat = theTargetFormat;

  NSError* anError = nil;
  *aPipelinePtr = [aDevice newRenderPipelineStateWithDescriptor:aDesc error:&anError];

  if (*aPipelinePtr == nil)
  {
    Message::SendFail() << "Metal_StereoComposer: pipeline creation failed - "
                        << [[anError localizedDescription] UTF8String];
    return nil;
  }

  return *aPipelinePtr;
}

// =======================================================================
// function : Compose
// purpose  : Compose stereo image from left/right textures
// =======================================================================
void Metal_StereoComposer::Compose(Metal_Context* theCtx,
                                   id<MTLCommandBuffer> theCommandBuffer,
                                   id<MTLTexture> theLeftEye,
                                   id<MTLTexture> theRightEye,
                                   id<MTLTexture> theTarget,
                                   Graphic3d_StereoMode theMode,
                                   bool theReverseStereo,
                                   const NCollection_Mat4<float>& theAnaglyphLeft,
                                   const NCollection_Mat4<float>& theAnaglyphRight,
                                   bool theSmoothInterlacing)
{
  if (!myIsValid || theCommandBuffer == nil || theLeftEye == nil || theRightEye == nil)
  {
    return;
  }

  MTLPixelFormat aTargetFormat = (theTarget != nil) ? [theTarget pixelFormat] : MTLPixelFormatBGRA8Unorm;
  id<MTLRenderPipelineState> aPipeline = getPipeline(theCtx, theMode, aTargetFormat);
  if (aPipeline == nil)
  {
    return;
  }

  // Setup render pass
  MTLRenderPassDescriptor* aPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
  aPassDesc.colorAttachments[0].texture = theTarget;
  aPassDesc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  aPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  id<MTLRenderCommandEncoder> anEncoder = [theCommandBuffer renderCommandEncoderWithDescriptor:aPassDesc];
  if (anEncoder == nil)
  {
    return;
  }

  [anEncoder setRenderPipelineState:aPipeline];

  // Setup uniforms
  Metal_StereoUniforms aUniforms;
  aUniforms.AnaglyphLeft = theAnaglyphLeft;
  aUniforms.AnaglyphRight = theAnaglyphRight;
  aUniforms.ReverseStereo = theReverseStereo ? 1 : 0;
  aUniforms.Padding = 0;

  if (theSmoothInterlacing)
  {
    // Small texture offset for antialiasing on interlaced displays
    float texelSizeY = 1.0f / static_cast<float>([theLeftEye height]);
    float texelSizeX = 1.0f / static_cast<float>([theLeftEye width]);
    aUniforms.TexOffset[0] = texelSizeX * 0.5f;
    aUniforms.TexOffset[1] = texelSizeY * 0.5f;
  }
  else
  {
    aUniforms.TexOffset[0] = 0.0f;
    aUniforms.TexOffset[1] = 0.0f;
  }

  // Bind resources
  [anEncoder setFragmentBytes:&aUniforms length:sizeof(aUniforms) atIndex:0];
  [anEncoder setFragmentTexture:theLeftEye atIndex:0];
  [anEncoder setFragmentTexture:theRightEye atIndex:1];
  [anEncoder setFragmentSamplerState:mySampler atIndex:0];

  // Draw full-screen triangle
  [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

  [anEncoder endEncoding];
}

// =======================================================================
// function : Compose (with frame buffer wrappers)
// purpose  : Compose stereo image from frame buffer wrappers
// =======================================================================
void Metal_StereoComposer::Compose(Metal_Context* theCtx,
                                   const occ::handle<Metal_FrameBuffer>& theLeftEye,
                                   const occ::handle<Metal_FrameBuffer>& theRightEye,
                                   const occ::handle<Metal_FrameBuffer>& theTarget,
                                   Graphic3d_StereoMode theMode,
                                   bool theReverseStereo,
                                   const NCollection_Mat4<float>& theAnaglyphLeft,
                                   const NCollection_Mat4<float>& theAnaglyphRight,
                                   bool theSmoothInterlacing)
{
  if (theCtx == nullptr || theLeftEye.IsNull() || theRightEye.IsNull())
  {
    return;
  }

  id<MTLCommandBuffer> aCmdBuffer = theCtx->CurrentCommandBuffer();
  if (aCmdBuffer == nil)
  {
    return;
  }

  id<MTLTexture> aLeftTex = theLeftEye->ColorTexture()->Texture();
  id<MTLTexture> aRightTex = theRightEye->ColorTexture()->Texture();
  id<MTLTexture> aTargetTex = theTarget.IsNull() ? nil : theTarget->ColorTexture()->Texture();

  Compose(theCtx, aCmdBuffer, aLeftTex, aRightTex, aTargetTex,
          theMode, theReverseStereo, theAnaglyphLeft, theAnaglyphRight,
          theSmoothInterlacing);
}
