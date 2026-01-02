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

#include <Metal_Sampler.hxx>
#include <Metal_Context.hxx>
#include <Standard_Assert.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Sampler, Metal_Resource)

// =======================================================================
// function : toMetalMinMagFilter
// purpose  : Convert filter to Metal filter
// =======================================================================
static MTLSamplerMinMagFilter toMetalMinMagFilter(Graphic3d_TypeOfTextureFilter theFilter)
{
  switch (theFilter)
  {
    case Graphic3d_TOTF_NEAREST: return MTLSamplerMinMagFilterNearest;
    case Graphic3d_TOTF_BILINEAR:
    case Graphic3d_TOTF_TRILINEAR:
    default:                     return MTLSamplerMinMagFilterLinear;
  }
}

// =======================================================================
// function : toMetalMipFilter
// purpose  : Convert mip filter to Metal mip filter
// =======================================================================
static MTLSamplerMipFilter toMetalMipFilter(Graphic3d_TypeOfTextureFilter theFilter)
{
  switch (theFilter)
  {
    case Graphic3d_TOTF_NEAREST:  return MTLSamplerMipFilterNearest;
    case Graphic3d_TOTF_BILINEAR: return MTLSamplerMipFilterNearest;
    case Graphic3d_TOTF_TRILINEAR:return MTLSamplerMipFilterLinear;
    default:                      return MTLSamplerMipFilterNotMipmapped;
  }
}

// =======================================================================
// function : toMetalAddressMode
// purpose  : Convert repeat flag to Metal address mode
// =======================================================================
static MTLSamplerAddressMode toMetalAddressMode(bool theRepeat)
{
  return theRepeat ? MTLSamplerAddressModeRepeat : MTLSamplerAddressModeClampToEdge;
}

// =======================================================================
// function : Metal_Sampler
// purpose  : Constructor
// =======================================================================
Metal_Sampler::Metal_Sampler()
: mySampler(nil)
{
  //
}

// =======================================================================
// function : ~Metal_Sampler
// purpose  : Destructor
// =======================================================================
Metal_Sampler::~Metal_Sampler()
{
  // Release any remaining resources
  if (mySampler != nil)
  {
    mySampler = nil;
  }
}

// =======================================================================
// function : Create (from params)
// purpose  : Create sampler from texture parameters
// =======================================================================
bool Metal_Sampler::Create(Metal_Context* theCtx,
                           const occ::handle<Graphic3d_TextureParams>& theParams)
{
  if (theParams.IsNull())
  {
    // Create default sampler with repeat mode
    return Create(theCtx,
                  Graphic3d_TOTF_TRILINEAR,
                  Graphic3d_TOTF_BILINEAR,
                  Graphic3d_TOTF_TRILINEAR,
                  true,  // repeat U
                  true,  // repeat V
                  16);
  }

  // For environment maps, use clamp mode; otherwise use IsRepeat() setting
  bool aRepeat = theParams->IsRepeat()
              && theParams->TextureUnit() != Graphic3d_TextureUnit_EnvMap;

  return Create(theCtx,
                theParams->Filter(),
                theParams->Filter(),
                theParams->Filter(),
                aRepeat,
                aRepeat,
                theParams->AnisoFilter() == Graphic3d_LOTA_OFF ? 1 : 16);
}

// =======================================================================
// function : Create (explicit)
// purpose  : Create sampler with explicit settings
// =======================================================================
bool Metal_Sampler::Create(Metal_Context* theCtx,
                           Graphic3d_TypeOfTextureFilter theMinFilter,
                           Graphic3d_TypeOfTextureFilter theMagFilter,
                           Graphic3d_TypeOfTextureFilter theMipFilter,
                           bool theRepeatU,
                           bool theRepeatV,
                           int theAnisotropy)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    return false;
  }

  MTLSamplerDescriptor* aDesc = [[MTLSamplerDescriptor alloc] init];
  aDesc.minFilter = toMetalMinMagFilter(theMinFilter);
  aDesc.magFilter = toMetalMinMagFilter(theMagFilter);
  aDesc.mipFilter = toMetalMipFilter(theMipFilter);
  aDesc.sAddressMode = toMetalAddressMode(theRepeatU);
  aDesc.tAddressMode = toMetalAddressMode(theRepeatV);
  aDesc.rAddressMode = MTLSamplerAddressModeClampToEdge;
  aDesc.maxAnisotropy = std::max(1, std::min(16, theAnisotropy));
  aDesc.normalizedCoordinates = YES;
  aDesc.lodMinClamp = 0.0f;
  aDesc.lodMaxClamp = FLT_MAX;

  id<MTLDevice> aDevice = theCtx->Device();
  mySampler = [aDevice newSamplerStateWithDescriptor:aDesc];

  return mySampler != nil;
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Sampler::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  if (mySampler != nil)
  {
    mySampler = nil;
  }
}
