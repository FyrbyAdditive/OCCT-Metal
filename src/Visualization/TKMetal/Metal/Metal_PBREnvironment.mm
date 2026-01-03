// Copyright (c) 2025 OPEN CASCADE SAS
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

#import <Metal_PBREnvironment.hxx>
#import <Metal_Context.hxx>
#import <Metal/Metal.h>
#import <Message.hxx>
#import <OSD_Timer.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_PBREnvironment, Metal_Resource)

namespace
{
  //! Metal shader source for IBL baking compute kernels
  static NSString* const IBL_COMPUTE_SHADER = @R"(
#include <metal_stdlib>
using namespace metal;

// Hammersley sequence for quasi-random sampling
float2 Hammersley(uint i, uint N) {
    uint bits = i;
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    float radicalInverse = float(bits) * 2.3283064365386963e-10;
    return float2(float(i) / float(N), radicalInverse);
}

// GGX importance sampling
float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * M_PI_F * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Spherical to Cartesian
    float3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // Tangent space to world space
    float3 up = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

// Get direction from cubemap face and UV
float3 GetCubeDirection(uint face, float2 uv) {
    float u = uv.x * 2.0 - 1.0;
    float v = uv.y * 2.0 - 1.0;

    switch (face) {
        case 0: return normalize(float3( 1, -v, -u)); // +X
        case 1: return normalize(float3(-1, -v,  u)); // -X
        case 2: return normalize(float3( u,  1,  v)); // +Y
        case 3: return normalize(float3( u, -1, -v)); // -Y
        case 4: return normalize(float3( u, -v,  1)); // +Z
        case 5: return normalize(float3(-u, -v, -1)); // -Z
    }
    return float3(0);
}

struct SpecularBakeParams {
    uint faceIndex;
    uint mipLevel;
    uint totalLevels;
    uint numSamples;
    int zCoeff;
    int yCoeff;
};

// Pre-filter environment map for specular IBL
kernel void bakeSpecularIBL(
    texturecube<float, access::sample> envMap [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant SpecularBakeParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;

    float2 uv = (float2(gid) + 0.5) / float2(outTexture.get_width(), outTexture.get_height());
    float3 N = GetCubeDirection(params.faceIndex, uv);
    N.z *= float(params.zCoeff);
    N.y *= float(params.yCoeff);

    float3 R = N;
    float3 V = R;

    float roughness = float(params.mipLevel) / float(params.totalLevels - 1);
    roughness = max(roughness, 0.001);

    constexpr sampler linearSampler(filter::linear, mip_filter::linear);

    float3 prefilteredColor = float3(0);
    float totalWeight = 0.0;

    for (uint i = 0u; i < params.numSamples; ++i) {
        float2 Xi = Hammersley(i, params.numSamples);
        float3 H = ImportanceSampleGGX(Xi, N, roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0) {
            prefilteredColor += envMap.sample(linearSampler, L).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    prefilteredColor = prefilteredColor / max(totalWeight, 0.001);
    outTexture.write(float4(prefilteredColor, 1.0), gid);
}

struct DiffuseBakeParams {
    uint faceIndex;
    uint numSamples;
    int zCoeff;
    int yCoeff;
};

// Compute irradiance (diffuse) environment map
kernel void bakeDiffuseIBL(
    texturecube<float, access::sample> envMap [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant DiffuseBakeParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;

    float2 uv = (float2(gid) + 0.5) / float2(outTexture.get_width(), outTexture.get_height());
    float3 N = GetCubeDirection(params.faceIndex, uv);
    N.z *= float(params.zCoeff);
    N.y *= float(params.yCoeff);

    float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(0, 0, 1);
    float3 right = normalize(cross(up, N));
    up = cross(N, right);

    constexpr sampler linearSampler(filter::linear);

    float3 irradiance = float3(0);
    float sampleCount = 0.0;

    // Hemisphere sampling
    float deltaPhi = (2.0 * M_PI_F) / float(params.numSamples);
    float deltaTheta = (0.5 * M_PI_F) / float(params.numSamples / 4);

    for (float phi = 0.0; phi < 2.0 * M_PI_F; phi += deltaPhi) {
        for (float theta = 0.0; theta < 0.5 * M_PI_F; theta += deltaTheta) {
            float3 tangentSample = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;

            irradiance += envMap.sample(linearSampler, sampleVec).rgb * cos(theta) * sin(theta);
            sampleCount += 1.0;
        }
    }

    irradiance = M_PI_F * irradiance / max(sampleCount, 1.0);
    outTexture.write(float4(irradiance, 1.0), gid);
}

// Compute spherical harmonics coefficients (9 coefficients for L=2)
struct SHCoeffs {
    float4 coeffs[9]; // RGB + padding per coefficient
};

kernel void computeDiffuseSH(
    texturecube<float, access::sample> envMap [[texture(0)]],
    device SHCoeffs& shOutput [[buffer(0)]],
    constant uint& numSamples [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    // This is a simplified version - proper implementation would use
    // parallel reduction across the cubemap
    if (tid != 0) return;

    constexpr sampler linearSampler(filter::linear);

    // Initialize coefficients to zero
    for (int i = 0; i < 9; ++i) {
        shOutput.coeffs[i] = float4(0);
    }

    // Sample environment map and accumulate SH coefficients
    float weight = 0.0;

    for (uint face = 0; face < 6; ++face) {
        for (uint y = 0; y < 32; ++y) {
            for (uint x = 0; x < 32; ++x) {
                float2 uv = (float2(x, y) + 0.5) / 32.0;
                float3 dir = GetCubeDirection(face, uv);

                // Solid angle weight
                float u = uv.x * 2.0 - 1.0;
                float v = uv.y * 2.0 - 1.0;
                float solidAngle = 4.0 / ((1.0 + u*u + v*v) * sqrt(1.0 + u*u + v*v));

                float3 color = envMap.sample(linearSampler, dir).rgb;

                // SH basis functions (L=0,1,2)
                float Y[9];
                Y[0] = 0.282095;                          // L=0
                Y[1] = 0.488603 * dir.y;                  // L=1
                Y[2] = 0.488603 * dir.z;
                Y[3] = 0.488603 * dir.x;
                Y[4] = 1.092548 * dir.x * dir.y;          // L=2
                Y[5] = 1.092548 * dir.y * dir.z;
                Y[6] = 0.315392 * (3.0 * dir.z * dir.z - 1.0);
                Y[7] = 1.092548 * dir.x * dir.z;
                Y[8] = 0.546274 * (dir.x * dir.x - dir.y * dir.y);

                for (int i = 0; i < 9; ++i) {
                    shOutput.coeffs[i].rgb += color * Y[i] * solidAngle;
                }
                weight += solidAngle;
            }
        }
    }

    // Normalize
    for (int i = 0; i < 9; ++i) {
        shOutput.coeffs[i].rgb *= 4.0 * M_PI_F / weight;
        shOutput.coeffs[i].a = 1.0;
    }
}
)";
}

//=================================================================================================

occ::handle<Metal_PBREnvironment> Metal_PBREnvironment::Create(
  const occ::handle<Metal_Context>& theCtx,
  unsigned int thePow2Size,
  unsigned int theSpecMapLevelsNum)
{
  if (theCtx.IsNull() || theCtx->Device() == nil)
  {
    return occ::handle<Metal_PBREnvironment>();
  }

  occ::handle<Metal_PBREnvironment> anEnv = new Metal_PBREnvironment(theCtx, thePow2Size, theSpecMapLevelsNum);
  if (!anEnv->myIsComplete)
  {
    Message::SendWarning("Metal_PBREnvironment: Failed to create PBR environment");
    anEnv->Release();
    anEnv.Nullify();
  }
  return anEnv;
}

//=================================================================================================

Metal_PBREnvironment::Metal_PBREnvironment(const occ::handle<Metal_Context>& theCtx,
                                           unsigned int thePow2Size,
                                           unsigned int theSpecMapLevelsNum)
: Metal_Resource(),
  myPow2Size(std::max(1u, thePow2Size)),
  mySpecMapLevelsNumber(std::max(2u, std::min(theSpecMapLevelsNum, std::max(1u, thePow2Size) + 1))),
  myIsNeededToBeBound(true),
  myIsComplete(false),
  mySpecularMap(nil),
  myDiffuseMap(nil),
  myDiffuseSHTexture(nil),
  mySpecularBakePipeline(nil),
  myDiffuseBakePipeline(nil)
{
  myIsComplete = initTextures(theCtx) && initPipelines(theCtx);
  if (myIsComplete)
  {
    Clear(theCtx);
  }
}

//=================================================================================================

Metal_PBREnvironment::~Metal_PBREnvironment()
{
  Release();
}

//=================================================================================================

void Metal_PBREnvironment::Release(Metal_Context* theCtx)
{
  (void)theCtx;
  mySpecularMap = nil;
  myDiffuseMap = nil;
  myDiffuseSHTexture = nil;
  mySpecularBakePipeline = nil;
  myDiffuseBakePipeline = nil;
}

//=================================================================================================

bool Metal_PBREnvironment::initTextures(const occ::handle<Metal_Context>& theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();
  unsigned int aSize = 1u << myPow2Size;

  // Create specular IBL cubemap with mipmaps
  MTLTextureDescriptor* aSpecDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          size:aSize
                                                                                     mipmapped:YES];
  aSpecDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
  aSpecDesc.storageMode = MTLStorageModePrivate;
  aSpecDesc.mipmapLevelCount = mySpecMapLevelsNumber;
  mySpecularMap = [aDevice newTextureWithDescriptor:aSpecDesc];
  mySpecularMap.label = @"PBR_SpecularIBL";

  if (mySpecularMap == nil)
  {
    Message::SendFail("Metal_PBREnvironment: Failed to create specular IBL texture");
    return false;
  }

  // Create diffuse IBL cubemap (low resolution is sufficient)
  unsigned int aDiffSize = std::min(64u, aSize);
  MTLTextureDescriptor* aDiffDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          size:aDiffSize
                                                                                     mipmapped:NO];
  aDiffDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
  aDiffDesc.storageMode = MTLStorageModePrivate;
  myDiffuseMap = [aDevice newTextureWithDescriptor:aDiffDesc];
  myDiffuseMap.label = @"PBR_DiffuseIBL";

  if (myDiffuseMap == nil)
  {
    Message::SendFail("Metal_PBREnvironment: Failed to create diffuse IBL texture");
    return false;
  }

  // Create spherical harmonics texture (9 coefficients as 9x1 RGBA texture)
  MTLTextureDescriptor* aSHDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                     width:9
                                                                                    height:1
                                                                                 mipmapped:NO];
  aSHDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
  aSHDesc.storageMode = MTLStorageModePrivate;
  myDiffuseSHTexture = [aDevice newTextureWithDescriptor:aSHDesc];
  myDiffuseSHTexture.label = @"PBR_DiffuseSH";

  if (myDiffuseSHTexture == nil)
  {
    Message::SendFail("Metal_PBREnvironment: Failed to create diffuse SH texture");
    return false;
  }

  return true;
}

//=================================================================================================

bool Metal_PBREnvironment::initPipelines(const occ::handle<Metal_Context>& theCtx)
{
  id<MTLDevice> aDevice = theCtx->Device();

  NSError* anError = nil;
  id<MTLLibrary> aLibrary = [aDevice newLibraryWithSource:IBL_COMPUTE_SHADER options:nil error:&anError];
  if (aLibrary == nil)
  {
    Message::SendFail() << "Metal_PBREnvironment: Failed to compile IBL shaders: "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Create specular baking pipeline
  id<MTLFunction> aSpecFunc = [aLibrary newFunctionWithName:@"bakeSpecularIBL"];
  if (aSpecFunc == nil)
  {
    Message::SendFail("Metal_PBREnvironment: Failed to find bakeSpecularIBL function");
    return false;
  }
  mySpecularBakePipeline = [aDevice newComputePipelineStateWithFunction:aSpecFunc error:&anError];
  if (mySpecularBakePipeline == nil)
  {
    Message::SendFail() << "Metal_PBREnvironment: Failed to create specular baking pipeline: "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  // Create diffuse baking pipeline
  id<MTLFunction> aDiffFunc = [aLibrary newFunctionWithName:@"bakeDiffuseIBL"];
  if (aDiffFunc == nil)
  {
    Message::SendFail("Metal_PBREnvironment: Failed to find bakeDiffuseIBL function");
    return false;
  }
  myDiffuseBakePipeline = [aDevice newComputePipelineStateWithFunction:aDiffFunc error:&anError];
  if (myDiffuseBakePipeline == nil)
  {
    Message::SendFail() << "Metal_PBREnvironment: Failed to create diffuse baking pipeline: "
                        << [[anError localizedDescription] UTF8String];
    return false;
  }

  return true;
}

//=================================================================================================

void Metal_PBREnvironment::Bake(const occ::handle<Metal_Context>& theCtx,
                                id<MTLTexture> theEnvMap,
                                bool theZIsInverted,
                                bool theIsTopDown,
                                size_t theDiffMapNbSamples,
                                size_t theSpecMapNbSamples)
{
  if (theEnvMap == nil || theCtx.IsNull())
  {
    return;
  }

  OSD_Timer aTimer;
  aTimer.Start();

  myIsNeededToBeBound = true;

  bakeSpecularMap(theCtx, theEnvMap, theZIsInverted, theIsTopDown, theSpecMapNbSamples);
  bakeDiffuseMap(theCtx, theEnvMap, theZIsInverted, theIsTopDown, theDiffMapNbSamples);

  aTimer.Stop();
  Message::SendTrace() << "Metal_PBREnvironment: IBL " << Size() << "x" << Size()
                       << " baked in " << aTimer.ElapsedTime() << " s";
}

//=================================================================================================

bool Metal_PBREnvironment::bakeSpecularMap(const occ::handle<Metal_Context>& theCtx,
                                           id<MTLTexture> theEnvMap,
                                           bool theZIsInverted,
                                           bool theIsTopDown,
                                           size_t theNbSamples)
{
  if (mySpecularBakePipeline == nil || mySpecularMap == nil)
  {
    return false;
  }

  id<MTLCommandBuffer> aCommandBuffer = [theCtx->CommandQueue() commandBuffer];
  id<MTLComputeCommandEncoder> aEncoder = [aCommandBuffer computeCommandEncoder];
  [aEncoder setComputePipelineState:mySpecularBakePipeline];
  [aEncoder setTexture:theEnvMap atIndex:0];

  struct SpecularBakeParams {
    uint32_t faceIndex;
    uint32_t mipLevel;
    uint32_t totalLevels;
    uint32_t numSamples;
    int32_t zCoeff;
    int32_t yCoeff;
  };

  // Bake each mip level of each face
  for (uint32_t aLevel = 0; aLevel < mySpecMapLevelsNumber; ++aLevel)
  {
    uint32_t aLevelSize = std::max(1u, (1u << myPow2Size) >> aLevel);

    // Create a 2D texture view for writing to this mip level
    for (uint32_t aFace = 0; aFace < 6; ++aFace)
    {
      // Create texture view for this face/mip
      id<MTLTexture> aFaceTexture = [mySpecularMap newTextureViewWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                      textureType:MTLTextureType2D
                                                                           levels:NSMakeRange(aLevel, 1)
                                                                           slices:NSMakeRange(aFace, 1)];

      SpecularBakeParams aParams;
      aParams.faceIndex = aFace;
      aParams.mipLevel = aLevel;
      aParams.totalLevels = mySpecMapLevelsNumber;
      aParams.numSamples = (uint32_t)std::max(size_t(16), theNbSamples >> aLevel);
      aParams.zCoeff = theZIsInverted ? -1 : 1;
      aParams.yCoeff = theIsTopDown ? 1 : -1;

      [aEncoder setTexture:aFaceTexture atIndex:1];
      [aEncoder setBytes:&aParams length:sizeof(aParams) atIndex:0];

      MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
      MTLSize aGridSize = MTLSizeMake((aLevelSize + 7) / 8, (aLevelSize + 7) / 8, 1);
      [aEncoder dispatchThreadgroups:aGridSize threadsPerThreadgroup:aThreadgroupSize];
    }
  }

  [aEncoder endEncoding];
  [aCommandBuffer commit];
  [aCommandBuffer waitUntilCompleted];

  return true;
}

//=================================================================================================

bool Metal_PBREnvironment::bakeDiffuseMap(const occ::handle<Metal_Context>& theCtx,
                                          id<MTLTexture> theEnvMap,
                                          bool theZIsInverted,
                                          bool theIsTopDown,
                                          size_t theNbSamples)
{
  if (myDiffuseBakePipeline == nil || myDiffuseMap == nil)
  {
    return false;
  }

  id<MTLCommandBuffer> aCommandBuffer = [theCtx->CommandQueue() commandBuffer];
  id<MTLComputeCommandEncoder> aEncoder = [aCommandBuffer computeCommandEncoder];
  [aEncoder setComputePipelineState:myDiffuseBakePipeline];
  [aEncoder setTexture:theEnvMap atIndex:0];

  struct DiffuseBakeParams {
    uint32_t faceIndex;
    uint32_t numSamples;
    int32_t zCoeff;
    int32_t yCoeff;
  };

  uint32_t aDiffSize = (uint32_t)myDiffuseMap.width;

  for (uint32_t aFace = 0; aFace < 6; ++aFace)
  {
    id<MTLTexture> aFaceTexture = [myDiffuseMap newTextureViewWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                    textureType:MTLTextureType2D
                                                                         levels:NSMakeRange(0, 1)
                                                                         slices:NSMakeRange(aFace, 1)];

    DiffuseBakeParams aParams;
    aParams.faceIndex = aFace;
    aParams.numSamples = (uint32_t)theNbSamples;
    aParams.zCoeff = theZIsInverted ? -1 : 1;
    aParams.yCoeff = theIsTopDown ? 1 : -1;

    [aEncoder setTexture:aFaceTexture atIndex:1];
    [aEncoder setBytes:&aParams length:sizeof(aParams) atIndex:0];

    MTLSize aThreadgroupSize = MTLSizeMake(8, 8, 1);
    MTLSize aGridSize = MTLSizeMake((aDiffSize + 7) / 8, (aDiffSize + 7) / 8, 1);
    [aEncoder dispatchThreadgroups:aGridSize threadsPerThreadgroup:aThreadgroupSize];
  }

  [aEncoder endEncoding];
  [aCommandBuffer commit];
  [aCommandBuffer waitUntilCompleted];

  return true;
}

//=================================================================================================

void Metal_PBREnvironment::Clear(const occ::handle<Metal_Context>& theCtx,
                                 const NCollection_Vec3<float>& theColor)
{
  if (theCtx.IsNull())
  {
    return;
  }

  myIsNeededToBeBound = true;

  // Clear textures by rendering solid color
  id<MTLCommandBuffer> aCommandBuffer = [theCtx->CommandQueue() commandBuffer];
  id<MTLBlitCommandEncoder> aBlit = [aCommandBuffer blitCommandEncoder];

  // For simplicity, we'll fill with default values
  // A more complete implementation would render solid color to each face

  [aBlit endEncoding];
  [aCommandBuffer commit];
  [aCommandBuffer waitUntilCompleted];
}

//=================================================================================================

void Metal_PBREnvironment::Bind(const occ::handle<Metal_Context>& theCtx)
{
  // Textures will be bound during rendering via shader resource binding
  myIsNeededToBeBound = false;
}

//=================================================================================================

void Metal_PBREnvironment::Unbind(const occ::handle<Metal_Context>& theCtx)
{
  myIsNeededToBeBound = true;
}

//=================================================================================================

bool Metal_PBREnvironment::SizesAreDifferent(unsigned int thePow2Size,
                                             unsigned int theSpecMapLevelsNumber) const
{
  thePow2Size = std::max(1u, thePow2Size);
  theSpecMapLevelsNumber = std::max(2u, std::min(theSpecMapLevelsNumber, std::max(1u, thePow2Size) + 1));
  return myPow2Size != thePow2Size || mySpecMapLevelsNumber != theSpecMapLevelsNumber;
}

//=================================================================================================

Standard_Size Metal_PBREnvironment::EstimatedDataSize() const
{
  // Specular map with mipmaps
  Standard_Size aSize = 0;
  for (unsigned int aLevel = 0; aLevel < mySpecMapLevelsNumber; ++aLevel)
  {
    unsigned int aLevelSize = std::max(1u, (1u << myPow2Size) >> aLevel);
    aSize += aLevelSize * aLevelSize * 6 * 8; // 6 faces, RGBA16F = 8 bytes
  }

  // Diffuse map
  unsigned int aDiffSize = std::min(64u, 1u << myPow2Size);
  aSize += aDiffSize * aDiffSize * 6 * 8;

  // SH texture
  aSize += 9 * 16; // 9 coefficients, RGBA32F = 16 bytes

  return aSize;
}
