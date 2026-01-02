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

#include <Metal_ShadowMap.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_ShadowMap, Metal_Resource)

// =======================================================================
// function : Metal_ShadowMap
// purpose  : Constructor
// =======================================================================
Metal_ShadowMap::Metal_ShadowMap(Metal_Context* theContext, int theSize)
: myContext(theContext),
  mySize(theSize),
  myBias(0.005f),
  myIsValid(false),
  myDepthTexture(nil),
  myRenderPassDesc(nil)
{
  myLightSpaceMatrix.InitIdentity();
  init();
}

// =======================================================================
// function : ~Metal_ShadowMap
// purpose  : Destructor
// =======================================================================
Metal_ShadowMap::~Metal_ShadowMap()
{
  Release();
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_ShadowMap::Release()
{
  myDepthTexture = nil;
  myRenderPassDesc = nil;
  myIsValid = false;
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
Standard_Size Metal_ShadowMap::EstimatedDataSize() const
{
  if (!myIsValid)
  {
    return 0;
  }
  // Depth32Float = 4 bytes per pixel
  return static_cast<Standard_Size>(mySize) * mySize * 4;
}

// =======================================================================
// function : init
// purpose  : Initialize shadow map resources
// =======================================================================
bool Metal_ShadowMap::init()
{
  if (myContext == nullptr || !myContext->IsValid())
  {
    return false;
  }

  id<MTLDevice> aDevice = myContext->Device();
  if (aDevice == nil)
  {
    return false;
  }

  // Create depth texture descriptor
  MTLTextureDescriptor* aTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                      width:mySize
                                                                                     height:mySize
                                                                                  mipmapped:NO];
  aTexDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  aTexDesc.storageMode = MTLStorageModePrivate;

  myDepthTexture = [aDevice newTextureWithDescriptor:aTexDesc];
  if (myDepthTexture == nil)
  {
    return false;
  }
  myDepthTexture.label = @"ShadowMap";

  // Create render pass descriptor for shadow map rendering
  myRenderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];

  // No color attachment - depth only
  myRenderPassDesc.depthAttachment.texture = myDepthTexture;
  myRenderPassDesc.depthAttachment.loadAction = MTLLoadActionClear;
  myRenderPassDesc.depthAttachment.storeAction = MTLStoreActionStore;
  myRenderPassDesc.depthAttachment.clearDepth = 1.0;

  myIsValid = true;
  return true;
}

// =======================================================================
// function : ComputeLightSpaceMatrix
// purpose  : Compute light-space view-projection matrix
// =======================================================================
void Metal_ShadowMap::ComputeLightSpaceMatrix(
  const occ::handle<Graphic3d_CLight>& theLight,
  const Graphic3d_Vec3& theSceneMin,
  const Graphic3d_Vec3& theSceneMax)
{
  if (theLight.IsNull())
  {
    myLightSpaceMatrix.InitIdentity();
    return;
  }

  myLightSource = theLight;

  // Compute scene center and radius
  Graphic3d_Vec3 aCenter = (theSceneMin + theSceneMax) * 0.5f;
  Graphic3d_Vec3 aExtent = theSceneMax - theSceneMin;
  float aRadius = aExtent.GetMaxComponent() * 0.5f * 1.5f; // Add margin

  // Get light direction (for directional lights)
  Graphic3d_Vec3 aLightDir;
  if (theLight->Type() == Graphic3d_TypeOfLightSource_Directional)
  {
    // Direction is from light toward scene
    aLightDir = -Graphic3d_Vec3(
      static_cast<float>(theLight->Direction().X()),
      static_cast<float>(theLight->Direction().Y()),
      static_cast<float>(theLight->Direction().Z())
    );
    aLightDir.Normalize();
  }
  else if (theLight->Type() == Graphic3d_TypeOfLightSource_Positional ||
           theLight->Type() == Graphic3d_TypeOfLightSource_Spot)
  {
    // Direction from light position to scene center
    Graphic3d_Vec3 aLightPos(
      static_cast<float>(theLight->Position().X()),
      static_cast<float>(theLight->Position().Y()),
      static_cast<float>(theLight->Position().Z())
    );
    aLightDir = aCenter - aLightPos;
    aLightDir.Normalize();
  }
  else
  {
    // Ambient or other - use default direction
    aLightDir = Graphic3d_Vec3(0.0f, -1.0f, 0.0f);
  }

  // Compute light position (for view matrix)
  Graphic3d_Vec3 aLightPos = aCenter - aLightDir * aRadius * 2.0f;

  // Compute up vector (perpendicular to light direction)
  Graphic3d_Vec3 aUp(0.0f, 1.0f, 0.0f);
  if (std::abs(aLightDir.y()) > 0.99f)
  {
    aUp = Graphic3d_Vec3(0.0f, 0.0f, 1.0f);
  }

  // Compute view matrix (look-at)
  Graphic3d_Vec3 aZAxis = -aLightDir;
  aZAxis.Normalize();
  Graphic3d_Vec3 aXAxis = aUp.Crossed(aZAxis);
  aXAxis.Normalize();
  Graphic3d_Vec3 aYAxis = aZAxis.Crossed(aXAxis);

  NCollection_Mat4<float> aViewMat;
  aViewMat.SetRow(0, Graphic3d_Vec4(aXAxis.x(), aXAxis.y(), aXAxis.z(), -aXAxis.Dot(aLightPos)));
  aViewMat.SetRow(1, Graphic3d_Vec4(aYAxis.x(), aYAxis.y(), aYAxis.z(), -aYAxis.Dot(aLightPos)));
  aViewMat.SetRow(2, Graphic3d_Vec4(aZAxis.x(), aZAxis.y(), aZAxis.z(), -aZAxis.Dot(aLightPos)));
  aViewMat.SetRow(3, Graphic3d_Vec4(0.0f, 0.0f, 0.0f, 1.0f));

  // Compute orthographic projection matrix
  float aNear = 0.1f;
  float aFar = aRadius * 4.0f;
  float aOrthoSize = aRadius;

  NCollection_Mat4<float> aProjMat;
  aProjMat.InitIdentity();
  aProjMat.SetValue(0, 0, 1.0f / aOrthoSize);
  aProjMat.SetValue(1, 1, 1.0f / aOrthoSize);
  aProjMat.SetValue(2, 2, -1.0f / (aFar - aNear));
  aProjMat.SetValue(2, 3, -aNear / (aFar - aNear));

  // Combine view and projection
  myLightSpaceMatrix = aProjMat * aViewMat;
}
