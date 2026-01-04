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

#include <Metal_ShaderManager.hxx>
#include <Metal_Context.hxx>
#include <Graphic3d_ClipPlane.hxx>
#include <Graphic3d_CLight.hxx>
#include <Message.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_ShaderManager, Graphic3d_ShaderManager)

// =======================================================================
// function : Metal_ShaderManager
// purpose  : Constructor
// =======================================================================
Metal_ShaderManager::Metal_ShaderManager(Metal_Context* theCtx)
: Graphic3d_ShaderManager(Aspect_GraphicsLibrary_Metal),
  myContext(theCtx),
  myShadingModel(Graphic3d_TypeOfShadingModel_Phong),
  myShaderLibrary(nil)
{
  myProjectionMatrix.InitIdentity();
  myProjectionMatrixInverse.InitIdentity();
  myViewMatrix.InitIdentity();
  myModelMatrix.InitIdentity();

  // Initialize material with defaults
  memset(&myMaterial, 0, sizeof(myMaterial));
  myMaterial.Ambient[0] = 0.1f; myMaterial.Ambient[1] = 0.1f;
  myMaterial.Ambient[2] = 0.1f; myMaterial.Ambient[3] = 1.0f;
  myMaterial.Diffuse[0] = 0.8f; myMaterial.Diffuse[1] = 0.8f;
  myMaterial.Diffuse[2] = 0.8f; myMaterial.Diffuse[3] = 1.0f;
  myMaterial.Specular[0] = 1.0f; myMaterial.Specular[1] = 1.0f;
  myMaterial.Specular[2] = 1.0f; myMaterial.Specular[3] = 1.0f;
  myMaterial.Shininess = 32.0f;
  myMaterial.Transparency = 1.0f;

  myObjectColor[0] = 1.0f;
  myObjectColor[1] = 1.0f;
  myObjectColor[2] = 1.0f;
  myObjectColor[3] = 1.0f;

  // Initialize lighting uniforms
  memset(&myLightUniforms, 0, sizeof(myLightUniforms));
  myLightUniforms.AmbientColor[0] = 0.1f;
  myLightUniforms.AmbientColor[1] = 0.1f;
  myLightUniforms.AmbientColor[2] = 0.1f;
  myLightUniforms.AmbientColor[3] = 1.0f;

  // Initialize clipping uniforms
  memset(&myClipPlaneUniforms, 0, sizeof(myClipPlaneUniforms));

  // Initialize line uniforms
  memset(&myLineUniforms, 0, sizeof(myLineUniforms));
  myLineUniforms.Width = 1.0f;
  myLineUniforms.Feather = 1.0f;
  myLineUniforms.Pattern = 0xFFFF;  // solid line
  myLineUniforms.Factor = 1;
  myLineUniforms.Viewport[0] = 800.0f;
  myLineUniforms.Viewport[1] = 600.0f;

  // Initialize hatch uniforms
  memset(&myHatchUniforms, 0, sizeof(myHatchUniforms));
  myHatchUniforms.HatchType = 0;    // no hatching
  myHatchUniforms.Spacing = 8.0f;
  myHatchUniforms.LineWidth = 1.0f;
  myHatchUniforms.Angle = 0.0f;
  myHatchUniforms.Viewport[0] = 800.0f;
  myHatchUniforms.Viewport[1] = 600.0f;

  // Create shader library
  createShaderLibrary();
}

// =======================================================================
// function : ~Metal_ShaderManager
// purpose  : Destructor
// =======================================================================
Metal_ShaderManager::~Metal_ShaderManager()
{
  Release();
}

// =======================================================================
// function : Release
// purpose  : Release all resources
// =======================================================================
void Metal_ShaderManager::Release()
{
  myPipelineCache.Clear();
  myDepthStencilCache.Clear();
  myShaderLibrary = nil;
}

// =======================================================================
// function : SetMaterial
// purpose  : Set current material
// =======================================================================
void Metal_ShaderManager::SetMaterial(const Metal_ShaderMaterial& theMat)
{
  myMaterial = theMat;
}

// =======================================================================
// function : SetMaterialUniforms
// purpose  : Set comprehensive material uniforms from Metal_Material
// =======================================================================
void Metal_ShaderManager::SetMaterialUniforms(const Metal_Material& theMaterial,
                                               float theAlphaCutoff,
                                               bool theToDistinguish,
                                               bool theIsPBR)
{
  // Copy front common material
  const Metal_MaterialCommon& aFrontCommon = theMaterial.Common[0];
  myMaterialUniforms.FrontCommon.Diffuse[0] = aFrontCommon.Diffuse.r();
  myMaterialUniforms.FrontCommon.Diffuse[1] = aFrontCommon.Diffuse.g();
  myMaterialUniforms.FrontCommon.Diffuse[2] = aFrontCommon.Diffuse.b();
  myMaterialUniforms.FrontCommon.Diffuse[3] = aFrontCommon.Diffuse.a();
  myMaterialUniforms.FrontCommon.Emission[0] = aFrontCommon.Emission.r();
  myMaterialUniforms.FrontCommon.Emission[1] = aFrontCommon.Emission.g();
  myMaterialUniforms.FrontCommon.Emission[2] = aFrontCommon.Emission.b();
  myMaterialUniforms.FrontCommon.Emission[3] = aFrontCommon.Emission.a();
  myMaterialUniforms.FrontCommon.SpecularShininess[0] = aFrontCommon.SpecularShininess.r();
  myMaterialUniforms.FrontCommon.SpecularShininess[1] = aFrontCommon.SpecularShininess.g();
  myMaterialUniforms.FrontCommon.SpecularShininess[2] = aFrontCommon.SpecularShininess.b();
  myMaterialUniforms.FrontCommon.SpecularShininess[3] = aFrontCommon.SpecularShininess.a();
  myMaterialUniforms.FrontCommon.Ambient[0] = aFrontCommon.Ambient.r();
  myMaterialUniforms.FrontCommon.Ambient[1] = aFrontCommon.Ambient.g();
  myMaterialUniforms.FrontCommon.Ambient[2] = aFrontCommon.Ambient.b();
  myMaterialUniforms.FrontCommon.Ambient[3] = aFrontCommon.Ambient.a();

  // Copy back common material
  const Metal_MaterialCommon& aBackCommon = theMaterial.Common[1];
  myMaterialUniforms.BackCommon.Diffuse[0] = aBackCommon.Diffuse.r();
  myMaterialUniforms.BackCommon.Diffuse[1] = aBackCommon.Diffuse.g();
  myMaterialUniforms.BackCommon.Diffuse[2] = aBackCommon.Diffuse.b();
  myMaterialUniforms.BackCommon.Diffuse[3] = aBackCommon.Diffuse.a();
  myMaterialUniforms.BackCommon.Emission[0] = aBackCommon.Emission.r();
  myMaterialUniforms.BackCommon.Emission[1] = aBackCommon.Emission.g();
  myMaterialUniforms.BackCommon.Emission[2] = aBackCommon.Emission.b();
  myMaterialUniforms.BackCommon.Emission[3] = aBackCommon.Emission.a();
  myMaterialUniforms.BackCommon.SpecularShininess[0] = aBackCommon.SpecularShininess.r();
  myMaterialUniforms.BackCommon.SpecularShininess[1] = aBackCommon.SpecularShininess.g();
  myMaterialUniforms.BackCommon.SpecularShininess[2] = aBackCommon.SpecularShininess.b();
  myMaterialUniforms.BackCommon.SpecularShininess[3] = aBackCommon.SpecularShininess.a();
  myMaterialUniforms.BackCommon.Ambient[0] = aBackCommon.Ambient.r();
  myMaterialUniforms.BackCommon.Ambient[1] = aBackCommon.Ambient.g();
  myMaterialUniforms.BackCommon.Ambient[2] = aBackCommon.Ambient.b();
  myMaterialUniforms.BackCommon.Ambient[3] = aBackCommon.Ambient.a();

  // Copy front PBR material
  const Metal_MaterialPBR& aFrontPBR = theMaterial.Pbr[0];
  myMaterialUniforms.FrontPBR.BaseColor[0] = aFrontPBR.BaseColor.r();
  myMaterialUniforms.FrontPBR.BaseColor[1] = aFrontPBR.BaseColor.g();
  myMaterialUniforms.FrontPBR.BaseColor[2] = aFrontPBR.BaseColor.b();
  myMaterialUniforms.FrontPBR.BaseColor[3] = aFrontPBR.BaseColor.a();
  myMaterialUniforms.FrontPBR.EmissionIOR[0] = aFrontPBR.EmissionIOR.r();
  myMaterialUniforms.FrontPBR.EmissionIOR[1] = aFrontPBR.EmissionIOR.g();
  myMaterialUniforms.FrontPBR.EmissionIOR[2] = aFrontPBR.EmissionIOR.b();
  myMaterialUniforms.FrontPBR.EmissionIOR[3] = aFrontPBR.EmissionIOR.a();
  myMaterialUniforms.FrontPBR.Params[0] = aFrontPBR.Params.r();
  myMaterialUniforms.FrontPBR.Params[1] = aFrontPBR.Params.g();
  myMaterialUniforms.FrontPBR.Params[2] = aFrontPBR.Params.b();
  myMaterialUniforms.FrontPBR.Params[3] = aFrontPBR.Params.a();

  // Copy back PBR material
  const Metal_MaterialPBR& aBackPBR = theMaterial.Pbr[1];
  myMaterialUniforms.BackPBR.BaseColor[0] = aBackPBR.BaseColor.r();
  myMaterialUniforms.BackPBR.BaseColor[1] = aBackPBR.BaseColor.g();
  myMaterialUniforms.BackPBR.BaseColor[2] = aBackPBR.BaseColor.b();
  myMaterialUniforms.BackPBR.BaseColor[3] = aBackPBR.BaseColor.a();
  myMaterialUniforms.BackPBR.EmissionIOR[0] = aBackPBR.EmissionIOR.r();
  myMaterialUniforms.BackPBR.EmissionIOR[1] = aBackPBR.EmissionIOR.g();
  myMaterialUniforms.BackPBR.EmissionIOR[2] = aBackPBR.EmissionIOR.b();
  myMaterialUniforms.BackPBR.EmissionIOR[3] = aBackPBR.EmissionIOR.a();
  myMaterialUniforms.BackPBR.Params[0] = aBackPBR.Params.r();
  myMaterialUniforms.BackPBR.Params[1] = aBackPBR.Params.g();
  myMaterialUniforms.BackPBR.Params[2] = aBackPBR.Params.b();
  myMaterialUniforms.BackPBR.Params[3] = aBackPBR.Params.a();

  // Set control parameters
  myMaterialUniforms.IsPBR = theIsPBR ? 1 : 0;
  myMaterialUniforms.ToDistinguish = theToDistinguish ? 1 : 0;
  myMaterialUniforms.AlphaCutoff = theAlphaCutoff;
}

// =======================================================================
// function : UpdateLightSources
// purpose  : Update light sources from Graphic3d light set
// =======================================================================
void Metal_ShaderManager::UpdateLightSources(const occ::handle<Graphic3d_LightSet>& theLights)
{
  memset(&myLightUniforms, 0, sizeof(myLightUniforms));
  myLightUniforms.AmbientColor[0] = 0.0f;
  myLightUniforms.AmbientColor[1] = 0.0f;
  myLightUniforms.AmbientColor[2] = 0.0f;
  myLightUniforms.AmbientColor[3] = 1.0f;

  if (theLights.IsNull())
  {
    return;
  }

  int aLightIndex = 0;
  for (Graphic3d_LightSet::Iterator aLightIter(theLights, Graphic3d_LightSet::IterationFilter_ExcludeDisabled);
       aLightIter.More() && aLightIndex < Metal_MaxLights;
       aLightIter.Next())
  {
    const occ::handle<Graphic3d_CLight>& aLight = aLightIter.Value();
    if (aLight.IsNull())
    {
      continue;
    }

    // Handle ambient light separately
    if (aLight->Type() == Graphic3d_TypeOfLightSource_Ambient)
    {
      const NCollection_Vec4<float>& aColor = aLight->PackedColor();
      myLightUniforms.AmbientColor[0] += aColor.r() * aLight->Intensity();
      myLightUniforms.AmbientColor[1] += aColor.g() * aLight->Intensity();
      myLightUniforms.AmbientColor[2] += aColor.b() * aLight->Intensity();
      continue;
    }

    Metal_ShaderLightSource& aLightParams = myLightUniforms.Lights[aLightIndex];

    // Color and intensity
    const NCollection_Vec4<float>& aColor = aLight->PackedColor();
    aLightParams.Color[0] = aColor.r();
    aLightParams.Color[1] = aColor.g();
    aLightParams.Color[2] = aColor.b();
    aLightParams.Color[3] = aLight->Intensity();

    // Light type in parameters
    aLightParams.Parameters[2] = static_cast<float>(aLight->Type());
    aLightParams.Parameters[3] = 1.0f; // enabled

    // Headlight flag
    aLightParams.Position[3] = aLight->IsHeadlight() ? 1.0f : 0.0f;

    switch (aLight->Type())
    {
      case Graphic3d_TypeOfLightSource_Directional:
      {
        // Direction in Position (normalized)
        const NCollection_Vec4<float>& aDirRange = aLight->PackedDirectionRange();
        gp_Dir aDir = (aDirRange.x() == 0.0f && aDirRange.y() == 0.0f && aDirRange.z() == 0.0f)
                        ? -gp_Dir(0.0, 0.0, 1.0)
                        : gp_Dir(aDirRange.x(), aDirRange.y(), aDirRange.z());
        aLightParams.Position[0] = static_cast<float>(aDir.X());
        aLightParams.Position[1] = static_cast<float>(aDir.Y());
        aLightParams.Position[2] = static_cast<float>(aDir.Z());
        break;
      }
      case Graphic3d_TypeOfLightSource_Positional:
      {
        const gp_Pnt& aPos = aLight->Position();
        aLightParams.Position[0] = static_cast<float>(aPos.X());
        aLightParams.Position[1] = static_cast<float>(aPos.Y());
        aLightParams.Position[2] = static_cast<float>(aPos.Z());
        aLightParams.Direction[3] = aLight->PackedDirectionRange().w(); // range
        break;
      }
      case Graphic3d_TypeOfLightSource_Spot:
      {
        const gp_Pnt& aPos = aLight->Position();
        aLightParams.Position[0] = static_cast<float>(aPos.X());
        aLightParams.Position[1] = static_cast<float>(aPos.Y());
        aLightParams.Position[2] = static_cast<float>(aPos.Z());

        // Spot direction
        const NCollection_Vec4<float>& aDirRange = aLight->PackedDirectionRange();
        aLightParams.Direction[0] = aDirRange.x();
        aLightParams.Direction[1] = aDirRange.y();
        aLightParams.Direction[2] = aDirRange.z();
        aLightParams.Direction[3] = aDirRange.w(); // range

        // Spot parameters
        const NCollection_Vec4<float>& aParams = aLight->PackedParams();
        aLightParams.Parameters[0] = aParams.x(); // cos(cutoff angle)
        aLightParams.Parameters[1] = aParams.y(); // exponent
        break;
      }
      default:
        break;
    }

    ++aLightIndex;
  }

  myLightUniforms.LightCount = aLightIndex;
}

// =======================================================================
// function : UpdateClippingPlanes
// purpose  : Update clipping planes
// =======================================================================
void Metal_ShaderManager::UpdateClippingPlanes(const Graphic3d_SequenceOfHClipPlane& thePlanes)
{
  memset(&myClipPlaneUniforms, 0, sizeof(myClipPlaneUniforms));

  int aPlaneIndex = 0;
  for (Graphic3d_SequenceOfHClipPlane::Iterator aPlaneIter(thePlanes);
       aPlaneIter.More() && aPlaneIndex < Metal_MaxClipPlanes;
       aPlaneIter.Next())
  {
    const occ::handle<Graphic3d_ClipPlane>& aPlane = aPlaneIter.Value();
    if (aPlane.IsNull() || !aPlane->IsOn())
    {
      continue;
    }

    const NCollection_Vec4<double>& anEq = aPlane->GetEquation();
    myClipPlaneUniforms.Planes[aPlaneIndex][0] = static_cast<float>(anEq.x());
    myClipPlaneUniforms.Planes[aPlaneIndex][1] = static_cast<float>(anEq.y());
    myClipPlaneUniforms.Planes[aPlaneIndex][2] = static_cast<float>(anEq.z());
    myClipPlaneUniforms.Planes[aPlaneIndex][3] = static_cast<float>(anEq.w());
    ++aPlaneIndex;
  }

  myClipPlaneUniforms.PlaneCount = aPlaneIndex;
}

// =======================================================================
// function : GetProgram
// purpose  : Get or create shader program
// =======================================================================
bool Metal_ShaderManager::GetProgram(Graphic3d_TypeOfShadingModel theModel,
                                      int theBits,
                                      __strong id<MTLRenderPipelineState>& thePipeline,
                                      __strong id<MTLDepthStencilState>& theDepthStencil)
{
  Metal_ShaderProgramKey aKey(theModel, theBits);

  // Use local __strong variables for ARC compatibility with NCollection_DataMap::Find
  __strong id<MTLRenderPipelineState> aCachedPipeline = nil;
  __strong id<MTLDepthStencilState> aCachedDepthStencil = nil;

  // Check cache first
  if (myPipelineCache.Find(aKey, aCachedPipeline))
  {
    thePipeline = aCachedPipeline;
    // Get depth-stencil state (same for all pipelines for now)
    if (!myDepthStencilCache.Find(0, aCachedDepthStencil))
    {
      myContext->Messenger()->SendInfo() << "Metal_ShaderManager::GetProgram: depth-stencil not found in cache";
      return false;
    }
    theDepthStencil = aCachedDepthStencil;
    return true;
  }

  // Create new pipeline
  myContext->Messenger()->SendInfo() << "Metal_ShaderManager::GetProgram: creating new pipeline for model " << (int)theModel << " bits " << theBits;
  bool aResult = createPipeline(theModel, theBits, thePipeline, theDepthStencil);
  if (aResult)
  {
    myContext->Messenger()->SendInfo() << "Metal_ShaderManager::GetProgram: pipeline created successfully";
  }
  else
  {
    myContext->Messenger()->SendFail() << "Metal_ShaderManager::GetProgram: pipeline creation failed";
  }
  return aResult;
}

// =======================================================================
// function : ChooseFaceShadingModel
// purpose  : Choose shading model for faces
// =======================================================================
Graphic3d_TypeOfShadingModel Metal_ShaderManager::ChooseFaceShadingModel(
  Graphic3d_TypeOfShadingModel theCustomModel,
  bool theHasNodalNormals) const
{
  Graphic3d_TypeOfShadingModel aModel =
    (theCustomModel != Graphic3d_TypeOfShadingModel_DEFAULT) ? theCustomModel : myShadingModel;

  switch (aModel)
  {
    case Graphic3d_TypeOfShadingModel_DEFAULT:
    case Graphic3d_TypeOfShadingModel_Unlit:
    case Graphic3d_TypeOfShadingModel_PhongFacet:
      return aModel;
    case Graphic3d_TypeOfShadingModel_Gouraud:
    case Graphic3d_TypeOfShadingModel_Phong:
      return theHasNodalNormals ? aModel : Graphic3d_TypeOfShadingModel_PhongFacet;
    case Graphic3d_TypeOfShadingModel_Pbr:
      // PBR shading with per-vertex normals
      return theHasNodalNormals ? Graphic3d_TypeOfShadingModel_Pbr
                                : Graphic3d_TypeOfShadingModel_PbrFacet;
    case Graphic3d_TypeOfShadingModel_PbrFacet:
      // PBR facet shading (no per-vertex normals required)
      return Graphic3d_TypeOfShadingModel_PbrFacet;
  }
  return Graphic3d_TypeOfShadingModel_Unlit;
}

// =======================================================================
// function : ChooseLineShadingModel
// purpose  : Choose shading model for lines
// =======================================================================
Graphic3d_TypeOfShadingModel Metal_ShaderManager::ChooseLineShadingModel(
  Graphic3d_TypeOfShadingModel theCustomModel,
  bool theHasNodalNormals) const
{
  Graphic3d_TypeOfShadingModel aModel =
    (theCustomModel != Graphic3d_TypeOfShadingModel_DEFAULT) ? theCustomModel : myShadingModel;

  switch (aModel)
  {
    case Graphic3d_TypeOfShadingModel_DEFAULT:
    case Graphic3d_TypeOfShadingModel_Unlit:
    case Graphic3d_TypeOfShadingModel_PhongFacet:
      return Graphic3d_TypeOfShadingModel_Unlit;
    case Graphic3d_TypeOfShadingModel_Gouraud:
    case Graphic3d_TypeOfShadingModel_Phong:
      return theHasNodalNormals ? aModel : Graphic3d_TypeOfShadingModel_Unlit;
    case Graphic3d_TypeOfShadingModel_Pbr:
    case Graphic3d_TypeOfShadingModel_PbrFacet:
      // PBR line shading - use PBR with normals, or unlit
      return theHasNodalNormals ? Graphic3d_TypeOfShadingModel_Pbr
                                : Graphic3d_TypeOfShadingModel_Unlit;
  }
  return Graphic3d_TypeOfShadingModel_Unlit;
}

// =======================================================================
// function : PrepareFrameUniforms
// purpose  : Prepare frame uniforms
// =======================================================================
void Metal_ShaderManager::PrepareFrameUniforms(Metal_FrameUniforms& theUniforms) const
{
  memcpy(theUniforms.ProjectionMatrix, myProjectionMatrix.GetData(), sizeof(float) * 16);
  memcpy(theUniforms.ViewMatrix, myViewMatrix.GetData(), sizeof(float) * 16);
  memcpy(theUniforms.ProjectionMatrixInverse, myProjectionMatrixInverse.GetData(), sizeof(float) * 16);

  // View matrix inverse - compute or use identity
  NCollection_Mat4<float> aViewInv;
  aViewInv.InitIdentity();
  memcpy(theUniforms.ViewMatrixInverse, aViewInv.GetData(), sizeof(float) * 16);
}

// =======================================================================
// function : PrepareObjectUniforms
// purpose  : Prepare object uniforms
// =======================================================================
void Metal_ShaderManager::PrepareObjectUniforms(Metal_ObjectUniforms& theUniforms) const
{
  memcpy(theUniforms.ModelMatrix, myModelMatrix.GetData(), sizeof(float) * 16);

  // Compute ModelView
  NCollection_Mat4<float> aModelView = myViewMatrix * myModelMatrix;
  memcpy(theUniforms.ModelViewMatrix, aModelView.GetData(), sizeof(float) * 16);

  // Extract upper-left 3x3 as normal matrix (with 4th row for padding)
  theUniforms.NormalMatrix[0] = aModelView.GetValue(0, 0);
  theUniforms.NormalMatrix[1] = aModelView.GetValue(0, 1);
  theUniforms.NormalMatrix[2] = aModelView.GetValue(0, 2);
  theUniforms.NormalMatrix[3] = 0.0f;
  theUniforms.NormalMatrix[4] = aModelView.GetValue(1, 0);
  theUniforms.NormalMatrix[5] = aModelView.GetValue(1, 1);
  theUniforms.NormalMatrix[6] = aModelView.GetValue(1, 2);
  theUniforms.NormalMatrix[7] = 0.0f;
  theUniforms.NormalMatrix[8] = aModelView.GetValue(2, 0);
  theUniforms.NormalMatrix[9] = aModelView.GetValue(2, 1);
  theUniforms.NormalMatrix[10] = aModelView.GetValue(2, 2);
  theUniforms.NormalMatrix[11] = 0.0f;

  memcpy(theUniforms.ObjectColor, myObjectColor, sizeof(float) * 4);
}

// =======================================================================
// function : createShaderLibrary
// purpose  : Create shader library with all shaders
// =======================================================================
bool Metal_ShaderManager::createShaderLibrary()
{
  if (myContext == nullptr || myContext->Device() == nil)
  {
    return false;
  }

  @autoreleasepool
  {
    NSString* aShaderSource = @(generateShaderSource().ToCString());

    NSError* anError = nil;
    MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
    if (@available(macOS 15.0, iOS 18.0, *))
    {
      anOptions.mathMode = MTLMathModeFast;
    }
    else
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      anOptions.fastMathEnabled = YES;
#pragma clang diagnostic pop
    }

    myShaderLibrary = [myContext->Device() newLibraryWithSource:aShaderSource
                                                        options:anOptions
                                                          error:&anError];
    if (myShaderLibrary == nil)
    {
      if (anError != nil)
      {
        myContext->Messenger()->SendFail() << "Metal_ShaderManager: Shader compilation failed: "
                                           << [[anError localizedDescription] UTF8String];
      }
      return false;
    }

    myContext->Messenger()->SendInfo() << "Metal_ShaderManager: Shader library created successfully";
    return true;
  }
}

// =======================================================================
// function : createPipeline
// purpose  : Create pipeline state
// =======================================================================
bool Metal_ShaderManager::createPipeline(Graphic3d_TypeOfShadingModel theModel,
                                          int theBits,
                                          __strong id<MTLRenderPipelineState>& thePipeline,
                                          __strong id<MTLDepthStencilState>& theDepthStencil)
{
  if (myContext == nullptr)
  {
    NSLog(@"Metal_ShaderManager::createPipeline: context is nil");
    return false;
  }
  if (myShaderLibrary == nil)
  {
    NSLog(@"Metal_ShaderManager::createPipeline: shader library is nil");
    myContext->Messenger()->SendFail() << "Metal_ShaderManager::createPipeline: shader library is nil";
    return false;
  }

  @autoreleasepool
  {
    // Determine vertex and fragment function names based on shading model
    NSString* aVertexFunc = nil;
    NSString* aFragmentFunc = nil;

    const bool hasClipping = (theBits & Graphic3d_ShaderFlags_ClipPlanesN) != 0
                          || (theBits & Graphic3d_ShaderFlags_ClipPlanes1) != 0
                          || (theBits & Graphic3d_ShaderFlags_ClipPlanes2) != 0;
    const bool hasHatch = (theBits & Graphic3d_ShaderFlags_HatchPattern) != 0;
    const bool hasStipple = (theBits & Graphic3d_ShaderFlags_StippleLine) != 0;

    // Handle line stipple patterns
    if (hasStipple)
    {
      aVertexFunc = @"vertex_line_stipple_simple";
      aFragmentFunc = hasClipping ? @"fragment_line_stipple_clip" : @"fragment_line_stipple";
    }
    // Handle hatch patterns
    else if (hasHatch)
    {
      aVertexFunc = @"vertex_hatch";
      if (hasClipping)
      {
        aFragmentFunc = @"fragment_hatch_phong_clip";
      }
      else
      {
        aFragmentFunc = @"fragment_hatch_phong";
      }
    }
    else
    {
      switch (theModel)
      {
        case Graphic3d_TypeOfShadingModel_Unlit:
          aVertexFunc = @"vertex_unlit";
          aFragmentFunc = hasClipping ? @"fragment_unlit_clip" : @"fragment_unlit";
          break;
        case Graphic3d_TypeOfShadingModel_Gouraud:
          aVertexFunc = @"vertex_gouraud";
          aFragmentFunc = hasClipping ? @"fragment_gouraud_clip" : @"fragment_gouraud";
          break;
        case Graphic3d_TypeOfShadingModel_Pbr:
        case Graphic3d_TypeOfShadingModel_PbrFacet:
          // PBR shading with Cook-Torrance BRDF
          aVertexFunc = @"vertex_phong";  // reuse Phong vertex shader (provides normals and positions)
          aFragmentFunc = hasClipping ? @"fragment_pbr_clip" : @"fragment_pbr";
          break;
        case Graphic3d_TypeOfShadingModel_Phong:
          // Phong shading with vertex normals
          aVertexFunc = @"vertex_phong";
          aFragmentFunc = hasClipping ? @"fragment_phong_material_clip" : @"fragment_phong_material";
          break;
        case Graphic3d_TypeOfShadingModel_PhongFacet:
        default:
          // Facet shading - no vertex normals, compute from derivatives
          aVertexFunc = @"vertex_phong_facet";
          aFragmentFunc = hasClipping ? @"fragment_phong_facet_material_clip" : @"fragment_phong_facet_material";
          break;
      }
    }

    NSLog(@"Metal_ShaderManager::createPipeline: looking for vertex=%@ fragment=%@", aVertexFunc, aFragmentFunc);
    id<MTLFunction> aVertex = [myShaderLibrary newFunctionWithName:aVertexFunc];
    id<MTLFunction> aFragment = [myShaderLibrary newFunctionWithName:aFragmentFunc];

    if (aVertex == nil || aFragment == nil)
    {
      NSLog(@"Metal_ShaderManager::createPipeline: vertex=%p fragment=%p", aVertex, aFragment);
      myContext->Messenger()->SendFail() << "Metal_ShaderManager: Failed to find shader functions";
      return false;
    }
    NSLog(@"Metal_ShaderManager::createPipeline: functions found, creating pipeline");

    // Create pipeline descriptor
    MTLRenderPipelineDescriptor* aPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    aPipelineDesc.vertexFunction = aVertex;
    aPipelineDesc.fragmentFunction = aFragment;
    aPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    aPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    // Enable alpha blending
    aPipelineDesc.colorAttachments[0].blendingEnabled = YES;
    aPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    aPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    aPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError* anError = nil;
    thePipeline = [myContext->Device() newRenderPipelineStateWithDescriptor:aPipelineDesc
                                                                      error:&anError];
    if (thePipeline == nil)
    {
      if (anError != nil)
      {
        myContext->Messenger()->SendFail() << "Metal_ShaderManager: Pipeline creation failed: "
                                           << [[anError localizedDescription] UTF8String];
      }
      return false;
    }

    // Create or get depth-stencil state
    // Use local __strong variable for ARC compatibility with NCollection_DataMap::Find
    __strong id<MTLDepthStencilState> aCachedDepthStencil = nil;
    if (!myDepthStencilCache.Find(0, aCachedDepthStencil))
    {
      MTLDepthStencilDescriptor* aDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
      aDepthDesc.depthCompareFunction = MTLCompareFunctionLess;
      aDepthDesc.depthWriteEnabled = YES;

      theDepthStencil = [myContext->Device() newDepthStencilStateWithDescriptor:aDepthDesc];
      myDepthStencilCache.Bind(0, theDepthStencil);
    }
    else
    {
      theDepthStencil = aCachedDepthStencil;
    }

    // Cache the pipeline
    Metal_ShaderProgramKey aKey(theModel, theBits);
    myPipelineCache.Bind(aKey, thePipeline);

    return true;
  }
}

// =======================================================================
// function : generateShaderSource
// purpose  : Generate MSL shader source
// =======================================================================
TCollection_AsciiString Metal_ShaderManager::generateShaderSource() const
{
  TCollection_AsciiString aSource;

  aSource +=
    "#include <metal_stdlib>\n"
    "#include <simd/simd.h>\n"
    "using namespace metal;\n"
    "\n"
    "// Maximum number of lights\n"
    "#define MAX_LIGHTS 8\n"
    "#define MAX_CLIP_PLANES 8\n"
    "\n"
    "// Light types\n"
    "#define LIGHT_TYPE_DIRECTIONAL 0\n"
    "#define LIGHT_TYPE_POSITIONAL  1\n"
    "#define LIGHT_TYPE_SPOT        2\n"
    "\n"
    "// Light source structure\n"
    "struct LightSource {\n"
    "  float4 Color;      // RGB + intensity\n"
    "  float4 Position;   // XYZ + isHeadlight\n"
    "  float4 Direction;  // spot direction + range\n"
    "  float4 Parameters; // cos(cutoff), exponent, type, enabled\n"
    "};\n"
    "\n"
    "// Legacy material structure\n"
    "struct Material {\n"
    "  float4 Ambient;\n"
    "  float4 Diffuse;\n"
    "  float4 Specular;\n"
    "  float4 Emissive;\n"
    "  float Shininess;\n"
    "  float Transparency;\n"
    "  float2 padding;\n"
    "};\n"
    "\n"
    "// Common (Phong/Blinn) material - matches Metal_ShaderMaterialCommon\n"
    "struct MaterialCommon {\n"
    "  float4 Diffuse;           // RGB + alpha\n"
    "  float4 Emission;          // RGB + padding\n"
    "  float4 SpecularShininess; // RGB + shininess\n"
    "  float4 Ambient;           // RGB + padding\n"
    "};\n"
    "\n"
    "// PBR material - matches Metal_ShaderMaterialPBR\n"
    "struct MaterialPBR {\n"
    "  float4 BaseColor;    // RGB + alpha\n"
    "  float4 EmissionIOR;  // RGB + IOR\n"
    "  float4 Params;       // occlusion, roughness, metallic, padding\n"
    "};\n"
    "\n"
    "// Comprehensive material uniforms - matches Metal_MaterialUniforms\n"
    "struct MaterialUniforms {\n"
    "  MaterialCommon FrontCommon;\n"
    "  MaterialCommon BackCommon;\n"
    "  MaterialPBR FrontPBR;\n"
    "  MaterialPBR BackPBR;\n"
    "  int IsPBR;\n"
    "  int ToDistinguish;\n"
    "  float AlphaCutoff;\n"
    "  float Padding;\n"
    "};\n"
    "\n"
    "// Frame uniforms (per-frame data)\n"
    "struct FrameUniforms {\n"
    "  float4x4 ProjectionMatrix;\n"
    "  float4x4 ViewMatrix;\n"
    "  float4x4 ProjectionMatrixInverse;\n"
    "  float4x4 ViewMatrixInverse;\n"
    "};\n"
    "\n"
    "// Object uniforms (per-object data)\n"
    "struct ObjectUniforms {\n"
    "  float4x4 ModelMatrix;\n"
    "  float4x4 ModelViewMatrix;\n"
    "  float3x4 NormalMatrix;\n"
    "  float4 ObjectColor;\n"
    "};\n"
    "\n"
    "// Lighting uniforms\n"
    "// Must match Metal_LightUniforms C++ struct exactly (560 bytes total)\n"
    "struct LightUniforms {\n"
    "  LightSource Lights[MAX_LIGHTS];  // 8 * 64 = 512 bytes\n"
    "  float4 AmbientColor;              // 16 bytes (offset 512)\n"
    "  int LightCount;                   // 4 bytes (offset 528)\n"
    "  int padding0;                     // 4 bytes (offset 532)\n"
    "  int padding1;                     // 4 bytes (offset 536)\n"
    "  int padding2;                     // 4 bytes (offset 540)\n"
    "  int padding3;                     // 4 bytes (offset 544)\n"
    "  int padding4;                     // 4 bytes (offset 548)\n"
    "  int padding5;                     // 4 bytes (offset 552)\n"
    "  int padding6;                     // 4 bytes (offset 556) -> total 560\n"
    "};\n"
    "\n"
    "// Clipping uniforms\n"
    "struct ClipUniforms {\n"
    "  float4 Planes[MAX_CLIP_PLANES];\n"
    "  int PlaneCount;\n"
    "  int3 padding;\n"
    "};\n"
    "\n"
    "// Legacy uniforms for simple shaders\n"
    "struct Uniforms {\n"
    "  float4x4 modelViewMatrix;\n"
    "  float4x4 projectionMatrix;\n"
    "  float4 color;\n"
    "};\n"
    "\n"
    "// ======== VERTEX OUTPUT STRUCTURES ========\n"
    "\n"
    "struct VertexOutUnlit {\n"
    "  float4 position [[position]];\n"
    "  float4 color;\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "struct VertexOutGouraud {\n"
    "  float4 position [[position]];\n"
    "  float4 color;\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "struct VertexOutPhong {\n"
    "  float4 position [[position]];\n"
    "  float3 normal;\n"
    "  float3 viewPosition;\n"
    "  float4 color;\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "// ======== HELPER FUNCTIONS ========\n"
    "\n"
    "// Compute Phong lighting for a single light\n"
    "// Light positions/directions are in world space, must be transformed to view space\n"
    "float3 computePhongLight(LightSource light, float3 N, float3 V, float3 fragPos,\n"
    "                         float3 diffuseColor, float3 specularColor, float shininess,\n"
    "                         float4x4 modelViewMatrix) {\n"
    "  if (light.Parameters.w < 0.5) return float3(0.0); // disabled\n"
    "  \n"
    "  int lightType = int(light.Parameters.z);\n"
    "  float3 lightColor = light.Color.rgb * light.Color.w; // color * intensity\n"
    "  float3 L;\n"
    "  float attenuation = 1.0;\n"
    "  \n"
    "  if (lightType == LIGHT_TYPE_DIRECTIONAL) {\n"
    "    // Transform light direction from world space to view space\n"
    "    float3 worldLightDir = -light.Position.xyz;\n"
    "    L = normalize((modelViewMatrix * float4(worldLightDir, 0.0)).xyz);\n"
    "  } else {\n"
    "    // Transform light position from world space to view space\n"
    "    float3 viewLightPos = (modelViewMatrix * float4(light.Position.xyz, 1.0)).xyz;\n"
    "    float3 lightVec = viewLightPos - fragPos;\n"
    "    float dist = length(lightVec);\n"
    "    L = lightVec / dist;\n"
    "    \n"
    "    // Range attenuation\n"
    "    float range = light.Direction.w;\n"
    "    if (range > 0.0) {\n"
    "      attenuation = saturate(1.0 - dist / range);\n"
    "    }\n"
    "    \n"
    "    // Spot light\n"
    "    if (lightType == LIGHT_TYPE_SPOT) {\n"
    "      // Transform spot direction to view space\n"
    "      float3 worldSpotDir = -light.Direction.xyz;\n"
    "      float3 spotDir = normalize((modelViewMatrix * float4(worldSpotDir, 0.0)).xyz);\n"
    "      float cosAngle = dot(L, spotDir);\n"
    "      float cosCutoff = light.Parameters.x;\n"
    "      if (cosAngle < cosCutoff) {\n"
    "        attenuation = 0.0;\n"
    "      } else {\n"
    "        float spotExponent = light.Parameters.y;\n"
    "        attenuation *= pow(cosAngle, spotExponent);\n"
    "      }\n"
    "    }\n"
    "  }\n"
    "  \n"
    "  // Diffuse\n"
    "  float NdotL = max(dot(N, L), 0.0);\n"
    "  float3 diffuse = diffuseColor * lightColor * NdotL;\n"
    "  \n"
    "  // Specular (Blinn-Phong)\n"
    "  float3 H = normalize(L + V);\n"
    "  float NdotH = max(dot(N, H), 0.0);\n"
    "  float3 specular = specularColor * lightColor * pow(NdotH, shininess);\n"
    "  \n"
    "  return (diffuse + specular) * attenuation;\n"
    "}\n"
    "\n"
    "// Check if fragment should be clipped\n"
    "bool isClipped(float3 worldPos, constant ClipUniforms& clip) {\n"
    "  for (int i = 0; i < clip.PlaneCount; i++) {\n"
    "    float4 plane = clip.Planes[i];\n"
    "    float dist = dot(float4(worldPos, 1.0), plane);\n"
    "    if (dist < 0.0) return true;\n"
    "  }\n"
    "  return false;\n"
    "}\n"
    "\n"
    "// ======== UNLIT SHADERS ========\n"
    "\n"
    "vertex VertexOutUnlit vertex_unlit(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutUnlit out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.color = uniforms.color;\n"
    "  return out;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_unlit(VertexOutUnlit in [[stage_in]])\n"
    "{\n"
    "  return in.color;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_unlit_clip(\n"
    "  VertexOutUnlit in [[stage_in]],\n"
    "  constant ClipUniforms& clip [[buffer(1)]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  return in.color;\n"
    "}\n"
    "\n"
    "// ======== GOURAUD SHADERS ========\n"
    "\n"
    "vertex VertexOutGouraud vertex_gouraud(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  const device packed_float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  constant LightUniforms& lights [[buffer(3)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutGouraud out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float3 norm = float3(normals[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  \n"
    "  // Transform normal (simplified - should use inverse transpose)\n"
    "  float3 N = normalize((uniforms.modelViewMatrix * float4(norm, 0.0)).xyz);\n"
    "  float3 V = normalize(-viewPos.xyz);\n"
    "  \n"
    "  // Compute lighting at vertex\n"
    "  float3 result = lights.AmbientColor.rgb * uniforms.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, viewPos.xyz,\n"
    "                                uniforms.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  out.color = float4(result, uniforms.color.a);\n"
    "  return out;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_gouraud(VertexOutGouraud in [[stage_in]])\n"
    "{\n"
    "  return in.color;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_gouraud_clip(\n"
    "  VertexOutGouraud in [[stage_in]],\n"
    "  constant ClipUniforms& clip [[buffer(1)]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  return in.color;\n"
    "}\n"
    "\n"
    "// ======== PHONG SHADERS ========\n"
    "\n"
    "vertex VertexOutPhong vertex_phong(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  const device packed_float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutPhong out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float3 norm = float3(normals[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  \n"
    "  // Transform normal\n"
    "  out.normal = normalize((uniforms.modelViewMatrix * float4(norm, 0.0)).xyz);\n"
    "  out.color = uniforms.color;\n"
    "  return out;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_phong(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms    [[buffer(0)]],\n"
    "  constant LightUniforms& lights [[buffer(1)]])\n"
    "{\n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  // Start with ambient\n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  \n"
    "  // Add contribution from each light\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), in.color.a);\n"
    "}\n"
    "\n"
    "fragment float4 fragment_phong_clip(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms    [[buffer(0)]],\n"
    "  constant LightUniforms& lights [[buffer(1)]],\n"
    "  constant ClipUniforms& clip    [[buffer(2)]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), in.color.a);\n"
    "}\n"
    "\n"
    "// ======== PHONG FACET SHADERS (no vertex normals required) ========\n"
    "\n"
    "// Output structure for facet shaders (no normal interpolation)\n"
    "struct VertexOutFacet {\n"
    "  float4 position [[position]];\n"
    "  float3 viewPosition;\n"
    "  float4 color;\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "// Facet vertex shader - no normals input\n"
    "vertex VertexOutFacet vertex_phong_facet(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutFacet out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  out.color = uniforms.color;\n"
    "  return out;\n"
    "}\n"
    "\n"
    "// Facet fragment shader - computes normals from screen-space derivatives\n"
    "fragment float4 fragment_phong_facet(\n"
    "  VertexOutFacet in [[stage_in]],\n"
    "  constant Uniforms& uniforms    [[buffer(0)]],\n"
    "  constant LightUniforms& lights [[buffer(1)]])\n"
    "{\n"
    "  // Compute face normal from screen-space derivatives\n"
    "  float3 dPdx = dfdx(in.viewPosition);\n"
    "  float3 dPdy = dfdy(in.viewPosition);\n"
    "  float3 N = normalize(cross(dPdx, dPdy));\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  // Ensure normal points toward viewer\n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), in.color.a);\n"
    "}\n"
    "\n"
    "// Facet fragment shader with clipping\n"
    "fragment float4 fragment_phong_facet_clip(\n"
    "  VertexOutFacet in [[stage_in]],\n"
    "  constant Uniforms& uniforms    [[buffer(0)]],\n"
    "  constant LightUniforms& lights [[buffer(1)]],\n"
    "  constant ClipUniforms& clip    [[buffer(2)]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  float3 dPdx = dfdx(in.viewPosition);\n"
    "  float3 dPdy = dfdy(in.viewPosition);\n"
    "  float3 N = normalize(cross(dPdx, dPdy));\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), in.color.a);\n"
    "}\n"
    "\n"
    "// Facet fragment shader with full material support\n"
    "fragment float4 fragment_phong_facet_material(\n"
    "  VertexOutFacet in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  MaterialCommon mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                       ? material.FrontCommon : material.BackCommon;\n"
    "  \n"
    "  float3 dPdx = dfdx(in.viewPosition);\n"
    "  float3 dPdy = dfdy(in.viewPosition);\n"
    "  float3 N = normalize(cross(dPdx, dPdy));\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  float3 diffuseColor = mat.Diffuse.rgb;\n"
    "  float3 specularColor = mat.SpecularShininess.rgb;\n"
    "  float shininess = mat.SpecularShininess.a;\n"
    "  float3 ambientColor = mat.Ambient.rgb;\n"
    "  float3 emissionColor = mat.Emission.rgb;\n"
    "  float alpha = mat.Diffuse.a;\n"
    "  \n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float3 result = ambientColor * lights.AmbientColor.rgb + emissionColor;\n"
    "  \n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                diffuseColor, specularColor, shininess,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), alpha);\n"
    "}\n"
    "\n"
    "// Facet fragment shader with materials and clipping\n"
    "fragment float4 fragment_phong_facet_material_clip(\n"
    "  VertexOutFacet in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  constant ClipUniforms& clip         [[buffer(3)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  MaterialCommon mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                       ? material.FrontCommon : material.BackCommon;\n"
    "  \n"
    "  float3 dPdx = dfdx(in.viewPosition);\n"
    "  float3 dPdy = dfdy(in.viewPosition);\n"
    "  float3 N = normalize(cross(dPdx, dPdy));\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  float3 diffuseColor = mat.Diffuse.rgb;\n"
    "  float3 specularColor = mat.SpecularShininess.rgb;\n"
    "  float shininess = mat.SpecularShininess.a;\n"
    "  float3 ambientColor = mat.Ambient.rgb;\n"
    "  float3 emissionColor = mat.Emission.rgb;\n"
    "  float alpha = mat.Diffuse.a;\n"
    "  \n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float3 result = ambientColor * lights.AmbientColor.rgb + emissionColor;\n"
    "  \n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                diffuseColor, specularColor, shininess,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), alpha);\n"
    "}\n"
    "\n"
    "// ======== MATERIAL-AWARE PHONG SHADERS ========\n"
    "\n"
    "// Phong fragment shader with full material support\n"
    "fragment float4 fragment_phong_material(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  // Select material based on face orientation\n"
    "  MaterialCommon mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                       ? material.FrontCommon : material.BackCommon;\n"
    "  \n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  // Flip normal for back faces\n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  // Extract material properties\n"
    "  float3 diffuseColor = mat.Diffuse.rgb;\n"
    "  float3 specularColor = mat.SpecularShininess.rgb;\n"
    "  float shininess = mat.SpecularShininess.a;\n"
    "  float3 ambientColor = mat.Ambient.rgb;\n"
    "  float3 emissionColor = mat.Emission.rgb;\n"
    "  float alpha = mat.Diffuse.a;\n"
    "  \n"
    "  // Alpha test\n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  // Ambient term\n"
    "  float3 result = ambientColor * lights.AmbientColor.rgb;\n"
    "  \n"
    "  // Add emission\n"
    "  result += emissionColor;\n"
    "  \n"
    "  // Add contribution from each light\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                diffuseColor, specularColor, shininess,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), alpha);\n"
    "}\n"
    "\n"
    "// Phong fragment shader with materials and clipping\n"
    "fragment float4 fragment_phong_material_clip(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  constant ClipUniforms& clip         [[buffer(3)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  // Clipping test first\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  // Select material based on face orientation\n"
    "  MaterialCommon mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                       ? material.FrontCommon : material.BackCommon;\n"
    "  \n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  float3 diffuseColor = mat.Diffuse.rgb;\n"
    "  float3 specularColor = mat.SpecularShininess.rgb;\n"
    "  float shininess = mat.SpecularShininess.a;\n"
    "  float3 ambientColor = mat.Ambient.rgb;\n"
    "  float3 emissionColor = mat.Emission.rgb;\n"
    "  float alpha = mat.Diffuse.a;\n"
    "  \n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float3 result = ambientColor * lights.AmbientColor.rgb + emissionColor;\n"
    "  \n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                diffuseColor, specularColor, shininess,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), alpha);\n"
    "}\n"
    "\n"
    "// ======== PBR HELPER FUNCTIONS ========\n"
    "\n"
    "// Normal Distribution Function (GGX/Trowbridge-Reitz)\n"
    "float distributionGGX(float3 N, float3 H, float roughness) {\n"
    "  float a = roughness * roughness;\n"
    "  float a2 = a * a;\n"
    "  float NdotH = max(dot(N, H), 0.0);\n"
    "  float NdotH2 = NdotH * NdotH;\n"
    "  float nom = a2;\n"
    "  float denom = (NdotH2 * (a2 - 1.0) + 1.0);\n"
    "  denom = M_PI_F * denom * denom;\n"
    "  return nom / max(denom, 0.0001);\n"
    "}\n"
    "\n"
    "// Geometry function (Schlick-GGX)\n"
    "float geometrySchlickGGX(float NdotV, float roughness) {\n"
    "  float r = roughness + 1.0;\n"
    "  float k = (r * r) / 8.0;\n"
    "  return NdotV / (NdotV * (1.0 - k) + k);\n"
    "}\n"
    "\n"
    "float geometrySmith(float3 N, float3 V, float3 L, float roughness) {\n"
    "  float NdotV = max(dot(N, V), 0.0);\n"
    "  float NdotL = max(dot(N, L), 0.0);\n"
    "  return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);\n"
    "}\n"
    "\n"
    "// Fresnel-Schlick approximation\n"
    "float3 fresnelSchlick(float cosTheta, float3 F0) {\n"
    "  return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);\n"
    "}\n"
    "\n"
    "// ======== PBR FRAGMENT SHADER ========\n"
    "\n"
    "fragment float4 fragment_pbr(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  // Select PBR material based on face\n"
    "  MaterialPBR mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                    ? material.FrontPBR : material.BackPBR;\n"
    "  \n"
    "  float3 albedo = mat.BaseColor.rgb;\n"
    "  float alpha = mat.BaseColor.a;\n"
    "  float metallic = mat.Params.b;    // z component\n"
    "  float roughness = mat.Params.g;   // y component\n"
    "  float ao = mat.Params.r;          // x component (occlusion)\n"
    "  float3 emission = mat.EmissionIOR.rgb;\n"
    "  \n"
    "  // Alpha test\n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  // Calculate F0 (reflectance at normal incidence)\n"
    "  float3 F0 = mix(float3(0.04), albedo, metallic);\n"
    "  \n"
    "  float3 Lo = float3(0.0);\n"
    "  \n"
    "  // Accumulate light contributions\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    LightSource light = lights.Lights[i];\n"
    "    if (light.Parameters.w < 0.5) continue; // disabled\n"
    "    \n"
    "    int lightType = int(light.Parameters.z);\n"
    "    float3 lightColor = light.Color.rgb * light.Color.w;\n"
    "    float3 L;\n"
    "    float attenuation = 1.0;\n"
    "    \n"
    "    if (lightType == LIGHT_TYPE_DIRECTIONAL) {\n"
    "      // Transform light direction from world space to view space\n"
    "      float3 worldLightDir = -light.Position.xyz;\n"
    "      L = normalize((uniforms.modelViewMatrix * float4(worldLightDir, 0.0)).xyz);\n"
    "    } else {\n"
    "      // Transform light position from world space to view space\n"
    "      float3 viewLightPos = (uniforms.modelViewMatrix * float4(light.Position.xyz, 1.0)).xyz;\n"
    "      float3 lightVec = viewLightPos - in.viewPosition;\n"
    "      float dist = length(lightVec);\n"
    "      L = lightVec / dist;\n"
    "      float range = light.Direction.w;\n"
    "      if (range > 0.0) {\n"
    "        attenuation = saturate(1.0 - dist / range);\n"
    "        attenuation *= attenuation; // quadratic falloff\n"
    "      }\n"
    "      if (lightType == LIGHT_TYPE_SPOT) {\n"
    "        // Transform spot direction to view space\n"
    "        float3 worldSpotDir = -light.Direction.xyz;\n"
    "        float3 spotDir = normalize((uniforms.modelViewMatrix * float4(worldSpotDir, 0.0)).xyz);\n"
    "        float cosAngle = dot(L, spotDir);\n"
    "        float cosCutoff = light.Parameters.x;\n"
    "        if (cosAngle < cosCutoff) {\n"
    "          attenuation = 0.0;\n"
    "        } else {\n"
    "          float spotExponent = light.Parameters.y;\n"
    "          attenuation *= pow(cosAngle, spotExponent);\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "    \n"
    "    float3 H = normalize(V + L);\n"
    "    float3 radiance = lightColor * attenuation;\n"
    "    \n"
    "    // Cook-Torrance BRDF\n"
    "    float NDF = distributionGGX(N, H, roughness);\n"
    "    float G = geometrySmith(N, V, L, roughness);\n"
    "    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);\n"
    "    \n"
    "    float3 numerator = NDF * G * F;\n"
    "    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;\n"
    "    float3 specular = numerator / denominator;\n"
    "    \n"
    "    // Energy conservation\n"
    "    float3 kS = F;\n"
    "    float3 kD = (float3(1.0) - kS) * (1.0 - metallic);\n"
    "    \n"
    "    float NdotL = max(dot(N, L), 0.0);\n"
    "    \n"
    "    // For metals: add shading term that provides NdotL-based coloring\n"
    "    // This simulates how metals reflect environment tinted by their color\n"
    "    float3 metallicShading = albedo * metallic * 0.5;\n"
    "    \n"
    "    Lo += (kD * albedo / M_PI_F + metallicShading + specular) * radiance * NdotL;\n"
    "  }\n"
    "  \n"
    "  // Ambient lighting with proper metallic handling\n"
    "  // For dielectrics: use albedo. For metals: use F0 (tinted by metal color)\n"
    "  float3 F0_ambient = mix(float3(0.04), albedo, metallic);\n"
    "  float NdotV_ambient = max(dot(N, V), 0.001);\n"
    "  float3 F_ambient = F0_ambient + (float3(1.0) - F0_ambient) * pow(1.0 - NdotV_ambient, 5.0);\n"
    "  float3 kD_ambient = (float3(1.0) - F_ambient) * (1.0 - metallic);\n"
    "  float3 diffuseAmbient = kD_ambient * albedo * lights.AmbientColor.rgb;\n"
    "  float3 metallicAmbient = F0_ambient * lights.AmbientColor.rgb * 0.3 * metallic;\n"
    "  float3 ambient = (diffuseAmbient + metallicAmbient) * ao;\n"
    "  \n"
    "  float3 color = ambient + Lo + emission;\n"
    "  \n"
    "  return float4(color, alpha);\n"
    "}\n"
    "\n"
    "// PBR fragment shader with clipping\n"
    "fragment float4 fragment_pbr_clip(\n"
    "  VertexOutPhong in [[stage_in]],\n"
    "  constant Uniforms& uniforms         [[buffer(0)]],\n"
    "  constant LightUniforms& lights      [[buffer(1)]],\n"
    "  constant MaterialUniforms& material [[buffer(2)]],\n"
    "  constant ClipUniforms& clip         [[buffer(3)]],\n"
    "  bool isFrontFace [[front_facing]])\n"
    "{\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  MaterialPBR mat = (isFrontFace || material.ToDistinguish == 0)\n"
    "                    ? material.FrontPBR : material.BackPBR;\n"
    "  \n"
    "  float3 albedo = mat.BaseColor.rgb;\n"
    "  float alpha = mat.BaseColor.a;\n"
    "  float metallic = mat.Params.b;\n"
    "  float roughness = mat.Params.g;\n"
    "  float ao = mat.Params.r;\n"
    "  float3 emission = mat.EmissionIOR.rgb;\n"
    "  \n"
    "  if (material.AlphaCutoff <= 1.0 && alpha < material.AlphaCutoff) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  if (!isFrontFace) N = -N;\n"
    "  \n"
    "  float3 F0 = mix(float3(0.04), albedo, metallic);\n"
    "  float3 Lo = float3(0.0);\n"
    "  \n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    LightSource light = lights.Lights[i];\n"
    "    if (light.Parameters.w < 0.5) continue;\n"
    "    \n"
    "    int lightType = int(light.Parameters.z);\n"
    "    float3 lightColor = light.Color.rgb * light.Color.w;\n"
    "    float3 L;\n"
    "    float attenuation = 1.0;\n"
    "    \n"
    "    if (lightType == LIGHT_TYPE_DIRECTIONAL) {\n"
    "      // Transform light direction from world space to view space\n"
    "      float3 worldLightDir = -light.Position.xyz;\n"
    "      L = normalize((uniforms.modelViewMatrix * float4(worldLightDir, 0.0)).xyz);\n"
    "    } else {\n"
    "      // Transform light position from world space to view space\n"
    "      float3 viewLightPos = (uniforms.modelViewMatrix * float4(light.Position.xyz, 1.0)).xyz;\n"
    "      float3 lightVec = viewLightPos - in.viewPosition;\n"
    "      float dist = length(lightVec);\n"
    "      L = lightVec / dist;\n"
    "      float range = light.Direction.w;\n"
    "      if (range > 0.0) {\n"
    "        attenuation = saturate(1.0 - dist / range);\n"
    "        attenuation *= attenuation;\n"
    "      }\n"
    "      if (lightType == LIGHT_TYPE_SPOT) {\n"
    "        // Transform spot direction to view space\n"
    "        float3 worldSpotDir = -light.Direction.xyz;\n"
    "        float3 spotDir = normalize((uniforms.modelViewMatrix * float4(worldSpotDir, 0.0)).xyz);\n"
    "        float cosAngle = dot(L, spotDir);\n"
    "        float cosCutoff = light.Parameters.x;\n"
    "        if (cosAngle < cosCutoff) attenuation = 0.0;\n"
    "        else attenuation *= pow(cosAngle, light.Parameters.y);\n"
    "      }\n"
    "    }\n"
    "    \n"
    "    float3 H = normalize(V + L);\n"
    "    float3 radiance = lightColor * attenuation;\n"
    "    \n"
    "    float NDF = distributionGGX(N, H, roughness);\n"
    "    float G = geometrySmith(N, V, L, roughness);\n"
    "    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);\n"
    "    \n"
    "    float3 numerator = NDF * G * F;\n"
    "    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;\n"
    "    float3 specular = numerator / denominator;\n"
    "    \n"
    "    float3 kS = F;\n"
    "    float3 kD = (float3(1.0) - kS) * (1.0 - metallic);\n"
    "    \n"
    "    float NdotL = max(dot(N, L), 0.0);\n"
    "    \n"
    "    // For metals: add shading term that provides NdotL-based coloring\n"
    "    float3 metallicShading = albedo * metallic * 0.5;\n"
    "    \n"
    "    Lo += (kD * albedo / M_PI_F + metallicShading + specular) * radiance * NdotL;\n"
    "  }\n"
    "  \n"
    "  // Ambient lighting with proper metallic handling\n"
    "  float3 F0_ambient = mix(float3(0.04), albedo, metallic);\n"
    "  float NdotV_ambient = max(dot(N, V), 0.001);\n"
    "  float3 F_ambient = F0_ambient + (float3(1.0) - F0_ambient) * pow(1.0 - NdotV_ambient, 5.0);\n"
    "  float3 kD_ambient = (float3(1.0) - F_ambient) * (1.0 - metallic);\n"
    "  float3 diffuseAmbient = kD_ambient * albedo * lights.AmbientColor.rgb;\n"
    "  float3 metallicAmbient = F0_ambient * lights.AmbientColor.rgb * 0.3 * metallic;\n"
    "  float3 ambient = (diffuseAmbient + metallicAmbient) * ao;\n"
    "  \n"
    "  float3 color = ambient + Lo + emission;\n"
    "  \n"
    "  return float4(color, alpha);\n"
    "}\n"
    "\n"
    "// ======== LEGACY SHADERS (for backwards compatibility) ========\n"
    "\n"
    "struct VertexOut {\n"
    "  float4 position [[position]];\n"
    "  float3 normal;\n"
    "  float3 viewPosition;\n"
    "};\n"
    "\n"
    "vertex VertexOut vertex_basic(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms           [[buffer(1)]],\n"
    "  uint vid                              [[vertex_id]])\n"
    "{\n"
    "  VertexOut out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  out.normal = float3(0.0, 0.0, 1.0);\n"
    "  return out;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_solid_color(\n"
    "  VertexOut in                [[stage_in]],\n"
    "  constant Uniforms& uniforms [[buffer(0)]])\n"
    "{\n"
    "  return uniforms.color;\n"
    "}\n"
    "\n"
    "fragment float4 fragment_phong_simple(\n"
    "  VertexOut in                [[stage_in]],\n"
    "  constant Uniforms& uniforms [[buffer(0)]])\n"
    "{\n"
    "  float3 lightDir = normalize(float3(0.0, 0.0, 1.0));\n"
    "  float3 N = normalize(in.normal);\n"
    "  float NdotL = max(dot(N, lightDir), 0.0);\n"
    "  float ambient = 0.3;\n"
    "  float lighting = ambient + (1.0 - ambient) * NdotL;\n"
    "  float4 color = uniforms.color;\n"
    "  color.rgb *= lighting;\n"
    "  return color;\n"
    "}\n"
    "\n"
    "// ======== GEOMETRY EMULATION (WIREFRAME/MESH EDGES) ========\n"
    "\n"
    "// Wireframe parameters uniform structure\n"
    "struct WireframeUniforms {\n"
    "  float4 WireColor;     // wireframe color\n"
    "  float4 FillColor;     // solid fill color\n"
    "  float LineWidth;      // line width in pixels\n"
    "  float Feather;        // edge feather for anti-aliasing\n"
    "  float2 Viewport;      // viewport size\n"
    "};\n"
    "\n"
    "// Input vertex for edge distance compute\n"
    "struct EdgeVertexIn {\n"
    "  float3 position;\n"
    "  float3 normal;\n"
    "};\n"
    "\n"
    "// Processed vertex with edge distance (output from compute, input to render)\n"
    "struct EdgeVertexOut {\n"
    "  float4 position [[position]];\n"
    "  float3 normal;\n"
    "  float3 edgeDistance;  // distance to each edge of triangle\n"
    "  float3 viewPosition;\n"
    "  float4 color;\n"
    "};\n"
    "\n"
    "// Compute shader: Calculate per-vertex edge distances for wireframe\n"
    "// Each thread processes one triangle\n"
    "kernel void compute_edge_distances(\n"
    "  device const EdgeVertexIn* vertices [[buffer(0)]],\n"
    "  device const uint* indices          [[buffer(1)]],\n"
    "  device EdgeVertexOut* output        [[buffer(2)]],\n"
    "  constant Uniforms& uniforms         [[buffer(3)]],\n"
    "  constant float2& viewport           [[buffer(4)]],\n"
    "  uint triangleId                     [[thread_position_in_grid]])\n"
    "{\n"
    "  uint baseIdx = triangleId * 3;\n"
    "  \n"
    "  // Load triangle vertex indices\n"
    "  uint i0 = indices[baseIdx + 0];\n"
    "  uint i1 = indices[baseIdx + 1];\n"
    "  uint i2 = indices[baseIdx + 2];\n"
    "  \n"
    "  // Load positions and normals\n"
    "  float3 p0 = vertices[i0].position;\n"
    "  float3 p1 = vertices[i1].position;\n"
    "  float3 p2 = vertices[i2].position;\n"
    "  float3 n0 = vertices[i0].normal;\n"
    "  float3 n1 = vertices[i1].normal;\n"
    "  float3 n2 = vertices[i2].normal;\n"
    "  \n"
    "  // Transform to clip space\n"
    "  float4x4 mvp = uniforms.projectionMatrix * uniforms.modelViewMatrix;\n"
    "  float4 clip0 = mvp * float4(p0, 1.0);\n"
    "  float4 clip1 = mvp * float4(p1, 1.0);\n"
    "  float4 clip2 = mvp * float4(p2, 1.0);\n"
    "  \n"
    "  // Perspective divide to NDC\n"
    "  float3 ndc0 = clip0.xyz / clip0.w;\n"
    "  float3 ndc1 = clip1.xyz / clip1.w;\n"
    "  float3 ndc2 = clip2.xyz / clip2.w;\n"
    "  \n"
    "  // Convert to screen space\n"
    "  float2 screen0 = (ndc0.xy * 0.5 + 0.5) * viewport;\n"
    "  float2 screen1 = (ndc1.xy * 0.5 + 0.5) * viewport;\n"
    "  float2 screen2 = (ndc2.xy * 0.5 + 0.5) * viewport;\n"
    "  \n"
    "  // Calculate edge vectors (edge opposite to each vertex)\n"
    "  float2 e0 = screen2 - screen1;  // edge opposite to vertex 0\n"
    "  float2 e1 = screen0 - screen2;  // edge opposite to vertex 1\n"
    "  float2 e2 = screen1 - screen0;  // edge opposite to vertex 2\n"
    "  \n"
    "  // Calculate 2x triangle area via cross product\n"
    "  float area2 = abs(e0.x * e1.y - e0.y * e1.x);\n"
    "  \n"
    "  // Calculate heights (distance from vertex to opposite edge)\n"
    "  float h0 = area2 / length(e0);\n"
    "  float h1 = area2 / length(e1);\n"
    "  float h2 = area2 / length(e2);\n"
    "  \n"
    "  // Transform normals to view space\n"
    "  float3x3 normalMatrix = float3x3(\n"
    "    uniforms.modelViewMatrix[0].xyz,\n"
    "    uniforms.modelViewMatrix[1].xyz,\n"
    "    uniforms.modelViewMatrix[2].xyz);\n"
    "  float3 tn0 = normalize(normalMatrix * n0);\n"
    "  float3 tn1 = normalize(normalMatrix * n1);\n"
    "  float3 tn2 = normalize(normalMatrix * n2);\n"
    "  \n"
    "  // View space positions\n"
    "  float3 view0 = (uniforms.modelViewMatrix * float4(p0, 1.0)).xyz;\n"
    "  float3 view1 = (uniforms.modelViewMatrix * float4(p1, 1.0)).xyz;\n"
    "  float3 view2 = (uniforms.modelViewMatrix * float4(p2, 1.0)).xyz;\n"
    "  \n"
    "  // Output vertex 0: has height h0 to edge 0, zero to other edges\n"
    "  output[baseIdx + 0].position = clip0;\n"
    "  output[baseIdx + 0].normal = tn0;\n"
    "  output[baseIdx + 0].edgeDistance = float3(h0, 0.0, 0.0);\n"
    "  output[baseIdx + 0].viewPosition = view0;\n"
    "  output[baseIdx + 0].color = uniforms.color;\n"
    "  \n"
    "  // Output vertex 1\n"
    "  output[baseIdx + 1].position = clip1;\n"
    "  output[baseIdx + 1].normal = tn1;\n"
    "  output[baseIdx + 1].edgeDistance = float3(0.0, h1, 0.0);\n"
    "  output[baseIdx + 1].viewPosition = view1;\n"
    "  output[baseIdx + 1].color = uniforms.color;\n"
    "  \n"
    "  // Output vertex 2\n"
    "  output[baseIdx + 2].position = clip2;\n"
    "  output[baseIdx + 2].normal = tn2;\n"
    "  output[baseIdx + 2].edgeDistance = float3(0.0, 0.0, h2);\n"
    "  output[baseIdx + 2].viewPosition = view2;\n"
    "  output[baseIdx + 2].color = uniforms.color;\n"
    "}\n"
    "\n"
    "// Vertex passthrough for wireframe (processed vertices from compute)\n"
    "vertex EdgeVertexOut vertex_wireframe(\n"
    "  const device EdgeVertexOut* vertices [[buffer(0)]],\n"
    "  uint vid                             [[vertex_id]])\n"
    "{\n"
    "  return vertices[vid];\n"
    "}\n"
    "\n"
    "// Fragment shader: Wireframe overlay on solid shading\n"
    "fragment float4 fragment_wireframe_overlay(\n"
    "  EdgeVertexOut in [[stage_in]],\n"
    "  constant Uniforms& uniforms        [[buffer(0)]],\n"
    "  constant WireframeUniforms& wire   [[buffer(1)]],\n"
    "  constant LightUniforms& lights     [[buffer(2)]])\n"
    "{\n"
    "  // Calculate minimum distance to any edge\n"
    "  float dist = min(in.edgeDistance.x, min(in.edgeDistance.y, in.edgeDistance.z));\n"
    "  \n"
    "  // Anti-aliased edge factor\n"
    "  float edgeFactor = 1.0 - smoothstep(\n"
    "    wire.LineWidth - wire.Feather,\n"
    "    wire.LineWidth + wire.Feather,\n"
    "    dist);\n"
    "  \n"
    "  // Compute Phong lighting for solid fill\n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * wire.FillColor.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                wire.FillColor.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  // Blend wireframe over solid\n"
    "  float3 finalColor = mix(saturate(result), wire.WireColor.rgb, edgeFactor);\n"
    "  return float4(finalColor, in.color.a);\n"
    "}\n"
    "\n"
    "// Fragment shader: Wireframe only (transparent background)\n"
    "fragment float4 fragment_wireframe_only(\n"
    "  EdgeVertexOut in [[stage_in]],\n"
    "  constant WireframeUniforms& wire [[buffer(0)]])\n"
    "{\n"
    "  float dist = min(in.edgeDistance.x, min(in.edgeDistance.y, in.edgeDistance.z));\n"
    "  \n"
    "  float edgeFactor = 1.0 - smoothstep(\n"
    "    wire.LineWidth - wire.Feather,\n"
    "    wire.LineWidth + wire.Feather,\n"
    "    dist);\n"
    "  \n"
    "  if (edgeFactor < 0.01) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  // Depth-based fade for back edges\n"
    "  float3 normal = normalize(in.normal);\n"
    "  float3 viewDir = normalize(-in.viewPosition);\n"
    "  float facing = abs(dot(normal, viewDir));\n"
    "  float depthFade = mix(0.3, 1.0, facing);\n"
    "  \n"
    "  return float4(wire.WireColor.rgb * depthFade, edgeFactor);\n"
    "}\n"
    "\n"
    "// Fragment shader: Hidden-line removal style\n"
    "fragment float4 fragment_wireframe_hidden(\n"
    "  EdgeVertexOut in [[stage_in]],\n"
    "  constant WireframeUniforms& wire [[buffer(0)]])\n"
    "{\n"
    "  float dist = min(in.edgeDistance.x, min(in.edgeDistance.y, in.edgeDistance.z));\n"
    "  \n"
    "  float edgeFactor = 1.0 - smoothstep(\n"
    "    wire.LineWidth - wire.Feather,\n"
    "    wire.LineWidth + wire.Feather,\n"
    "    dist);\n"
    "  \n"
    "  // Check if front-facing\n"
    "  float3 normal = normalize(in.normal);\n"
    "  float3 viewDir = normalize(-in.viewPosition);\n"
    "  float facing = dot(normal, viewDir);\n"
    "  \n"
    "  if (facing < 0.0) {\n"
    "    // Back face - show fill color only\n"
    "    return float4(wire.FillColor.rgb * 0.95, 1.0);\n"
    "  }\n"
    "  \n"
    "  // Front face - show wireframe\n"
    "  float3 finalColor = mix(wire.FillColor.rgb, wire.WireColor.rgb, edgeFactor);\n"
    "  return float4(finalColor, 1.0);\n"
    "}\n"
    "\n"
    "// ======== TESSELLATION SHADERS ========\n"
    "\n"
    "// Tessellation uniforms\n"
    "struct TessUniforms {\n"
    "  float4x4 ModelViewProjection;\n"
    "  float4x4 ModelView;\n"
    "  float2 Viewport;\n"
    "  float TessLevel;        // base tessellation level\n"
    "  float AdaptiveFactor;   // 0 = uniform, 1 = fully adaptive\n"
    "  float3 CameraPos;\n"
    "  float padding;\n"
    "};\n"
    "\n"
    "// Control point for quad tessellation\n"
    "struct TessControlPoint {\n"
    "  float3 position [[attribute(0)]];\n"
    "  float3 normal   [[attribute(1)]];\n"
    "  float2 texCoord [[attribute(2)]];\n"
    "};\n"
    "\n"
    "// Tessellation factors for quad patches\n"
    "struct QuadTessFactors {\n"
    "  half edgeTessellationFactor[4];\n"
    "  half insideTessellationFactor[2];\n"
    "};\n"
    "\n"
    "// Post-tessellation vertex output\n"
    "struct TessVertexOut {\n"
    "  float4 position [[position]];\n"
    "  float3 normal;\n"
    "  float2 texCoord;\n"
    "  float3 viewPosition;\n"
    "};\n"
    "\n"
    "// Compute shader: Calculate adaptive tessellation factors per patch\n"
    "kernel void compute_tess_factors(\n"
    "  device const TessControlPoint* controlPoints [[buffer(0)]],\n"
    "  device QuadTessFactors* tessFactors          [[buffer(1)]],\n"
    "  constant TessUniforms& uniforms              [[buffer(2)]],\n"
    "  uint patchId                                 [[thread_position_in_grid]])\n"
    "{\n"
    "  // Load 4 control points for this quad patch\n"
    "  uint baseIdx = patchId * 4;\n"
    "  float3 p0 = controlPoints[baseIdx + 0].position;\n"
    "  float3 p1 = controlPoints[baseIdx + 1].position;\n"
    "  float3 p2 = controlPoints[baseIdx + 2].position;\n"
    "  float3 p3 = controlPoints[baseIdx + 3].position;\n"
    "  \n"
    "  // Transform to clip space\n"
    "  float4 clip0 = uniforms.ModelViewProjection * float4(p0, 1.0);\n"
    "  float4 clip1 = uniforms.ModelViewProjection * float4(p1, 1.0);\n"
    "  float4 clip2 = uniforms.ModelViewProjection * float4(p2, 1.0);\n"
    "  float4 clip3 = uniforms.ModelViewProjection * float4(p3, 1.0);\n"
    "  \n"
    "  // Perspective divide to NDC\n"
    "  float3 ndc0 = clip0.xyz / clip0.w;\n"
    "  float3 ndc1 = clip1.xyz / clip1.w;\n"
    "  float3 ndc2 = clip2.xyz / clip2.w;\n"
    "  float3 ndc3 = clip3.xyz / clip3.w;\n"
    "  \n"
    "  // Convert to screen space\n"
    "  float2 screen0 = (ndc0.xy * 0.5 + 0.5) * uniforms.Viewport;\n"
    "  float2 screen1 = (ndc1.xy * 0.5 + 0.5) * uniforms.Viewport;\n"
    "  float2 screen2 = (ndc2.xy * 0.5 + 0.5) * uniforms.Viewport;\n"
    "  float2 screen3 = (ndc3.xy * 0.5 + 0.5) * uniforms.Viewport;\n"
    "  \n"
    "  // Calculate screen-space edge lengths (quad edges: 0-1, 1-2, 2-3, 3-0)\n"
    "  float edge01 = length(screen1 - screen0);\n"
    "  float edge12 = length(screen2 - screen1);\n"
    "  float edge23 = length(screen3 - screen2);\n"
    "  float edge30 = length(screen0 - screen3);\n"
    "  \n"
    "  // Adaptive factors based on screen-space edge length\n"
    "  float targetPixelsPerSegment = 10.0;\n"
    "  float baseTess = uniforms.TessLevel;\n"
    "  \n"
    "  float adaptive01 = edge01 / targetPixelsPerSegment;\n"
    "  float adaptive12 = edge12 / targetPixelsPerSegment;\n"
    "  float adaptive23 = edge23 / targetPixelsPerSegment;\n"
    "  float adaptive30 = edge30 / targetPixelsPerSegment;\n"
    "  \n"
    "  // Blend between uniform and adaptive\n"
    "  float factor0 = mix(baseTess, adaptive01, uniforms.AdaptiveFactor);\n"
    "  float factor1 = mix(baseTess, adaptive12, uniforms.AdaptiveFactor);\n"
    "  float factor2 = mix(baseTess, adaptive23, uniforms.AdaptiveFactor);\n"
    "  float factor3 = mix(baseTess, adaptive30, uniforms.AdaptiveFactor);\n"
    "  \n"
    "  // Clamp to valid range [1, 64]\n"
    "  factor0 = clamp(factor0, 1.0, 64.0);\n"
    "  factor1 = clamp(factor1, 1.0, 64.0);\n"
    "  factor2 = clamp(factor2, 1.0, 64.0);\n"
    "  factor3 = clamp(factor3, 1.0, 64.0);\n"
    "  \n"
    "  // Set edge tessellation factors\n"
    "  tessFactors[patchId].edgeTessellationFactor[0] = half(factor0);\n"
    "  tessFactors[patchId].edgeTessellationFactor[1] = half(factor1);\n"
    "  tessFactors[patchId].edgeTessellationFactor[2] = half(factor2);\n"
    "  tessFactors[patchId].edgeTessellationFactor[3] = half(factor3);\n"
    "  \n"
    "  // Inside factors: average of opposing edges\n"
    "  float inside0 = (factor0 + factor2) * 0.5;\n"
    "  float inside1 = (factor1 + factor3) * 0.5;\n"
    "  tessFactors[patchId].insideTessellationFactor[0] = half(inside0);\n"
    "  tessFactors[patchId].insideTessellationFactor[1] = half(inside1);\n"
    "}\n"
    "\n"
    "// Post-tessellation vertex function for quad patches\n"
    "[[patch(quad, 4)]]\n"
    "vertex TessVertexOut vertex_post_tess(\n"
    "  patch_control_point<TessControlPoint> controlPoints [[stage_in]],\n"
    "  float2 patchCoord                                   [[position_in_patch]],\n"
    "  constant TessUniforms& uniforms                     [[buffer(1)]])\n"
    "{\n"
    "  float u = patchCoord.x;\n"
    "  float v = patchCoord.y;\n"
    "  \n"
    "  // Bilinear interpolation of control points\n"
    "  // Patch layout: 3---2\n"
    "  //               |   |\n"
    "  //               0---1\n"
    "  \n"
    "  float3 p0 = controlPoints[0].position;\n"
    "  float3 p1 = controlPoints[1].position;\n"
    "  float3 p2 = controlPoints[2].position;\n"
    "  float3 p3 = controlPoints[3].position;\n"
    "  \n"
    "  float3 n0 = controlPoints[0].normal;\n"
    "  float3 n1 = controlPoints[1].normal;\n"
    "  float3 n2 = controlPoints[2].normal;\n"
    "  float3 n3 = controlPoints[3].normal;\n"
    "  \n"
    "  float2 t0 = controlPoints[0].texCoord;\n"
    "  float2 t1 = controlPoints[1].texCoord;\n"
    "  float2 t2 = controlPoints[2].texCoord;\n"
    "  float2 t3 = controlPoints[3].texCoord;\n"
    "  \n"
    "  // Bilinear interpolation\n"
    "  float3 bottom = mix(p0, p1, u);\n"
    "  float3 top = mix(p3, p2, u);\n"
    "  float3 position = mix(bottom, top, v);\n"
    "  \n"
    "  float3 bottomN = mix(n0, n1, u);\n"
    "  float3 topN = mix(n3, n2, u);\n"
    "  float3 normal = normalize(mix(bottomN, topN, v));\n"
    "  \n"
    "  float2 bottomT = mix(t0, t1, u);\n"
    "  float2 topT = mix(t3, t2, u);\n"
    "  float2 texCoord = mix(bottomT, topT, v);\n"
    "  \n"
    "  TessVertexOut out;\n"
    "  out.position = uniforms.ModelViewProjection * float4(position, 1.0);\n"
    "  out.normal = (uniforms.ModelView * float4(normal, 0.0)).xyz;\n"
    "  out.texCoord = texCoord;\n"
    "  out.viewPosition = (uniforms.ModelView * float4(position, 1.0)).xyz;\n"
    "  \n"
    "  return out;\n"
    "}\n"
    "\n"
    "// Fragment shader for tessellated geometry\n"
    "fragment float4 fragment_tess_phong(\n"
    "  TessVertexOut in [[stage_in]],\n"
    "  constant Uniforms& uniforms    [[buffer(0)]],\n"
    "  constant LightUniforms& lights [[buffer(1)]])\n"
    "{\n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  // Two-sided lighting\n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * uniforms.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                uniforms.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), uniforms.color.a);\n"
    "}\n"
    "\n"
    "// ======== LINE STIPPLE SHADERS ========\n"
    "\n"
    "// Line stipple uniforms structure\n"
    "struct LineUniforms {\n"
    "  float    lineWidth;      // line width in pixels\n"
    "  float    feather;        // edge feather for anti-aliasing\n"
    "  uint     pattern;        // 16-bit stipple pattern\n"
    "  uint     factor;         // stipple factor (stretch multiplier)\n"
    "  float2   viewport;       // viewport size\n"
    "  float2   padding;\n"
    "};\n"
    "\n"
    "// Vertex output for stippled lines\n"
    "struct VertexOutLine {\n"
    "  float4 position [[position]];\n"
    "  float4 color;\n"
    "  float  lineDistance;   // cumulative distance along line in screen space\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "// Check if stipple pattern bit is set at given distance\n"
    "// Pattern is 16-bit, factor stretches it\n"
    "float computeStippleMask(float lineDistance, uint pattern, uint factor) {\n"
    "  // If solid pattern, always visible\n"
    "  if (pattern == 0xFFFFu) {\n"
    "    return 1.0;\n"
    "  }\n"
    "  // If empty pattern, always invisible\n"
    "  if (pattern == 0u) {\n"
    "    return 0.0;\n"
    "  }\n"
    "  \n"
    "  // Scale distance by factor (each bit covers 'factor' pixels)\n"
    "  float scaledDist = lineDistance / float(max(factor, 1u));\n"
    "  \n"
    "  // Get bit position (0-15) from distance\n"
    "  // Pattern repeats every 16 bits\n"
    "  int bitPos = int(floor(scaledDist)) & 0xF;\n"
    "  \n"
    "  // Check if bit is set in pattern (LSB first, like OpenGL)\n"
    "  uint bit = (pattern >> bitPos) & 1u;\n"
    "  \n"
    "  return float(bit);\n"
    "}\n"
    "\n"
    "// Anti-aliased stipple mask with smooth transitions\n"
    "float computeStippleMaskAA(float lineDistance, uint pattern, uint factor, float feather) {\n"
    "  // If solid pattern, always visible\n"
    "  if (pattern == 0xFFFFu) {\n"
    "    return 1.0;\n"
    "  }\n"
    "  // If empty pattern, always invisible\n"
    "  if (pattern == 0u) {\n"
    "    return 0.0;\n"
    "  }\n"
    "  \n"
    "  float scaledDist = lineDistance / float(max(factor, 1u));\n"
    "  float fractPos = fract(scaledDist);\n"
    "  int bitPos = int(floor(scaledDist)) & 0xF;\n"
    "  int nextBitPos = (bitPos + 1) & 0xF;\n"
    "  \n"
    "  // Get current and next bit\n"
    "  float currBit = float((pattern >> bitPos) & 1u);\n"
    "  float nextBit = float((pattern >> nextBitPos) & 1u);\n"
    "  \n"
    "  // Smooth transition near bit boundaries\n"
    "  float edgeDist = min(fractPos, 1.0 - fractPos);\n"
    "  float transitionWidth = feather / float(max(factor, 1u));\n"
    "  \n"
    "  if (currBit != nextBit && fractPos > 1.0 - transitionWidth) {\n"
    "    // Approaching bit boundary with state change\n"
    "    float t = (fractPos - (1.0 - transitionWidth)) / transitionWidth;\n"
    "    return mix(currBit, nextBit, smoothstep(0.0, 1.0, t));\n"
    "  }\n"
    "  \n"
    "  return currBit;\n"
    "}\n"
    "\n"
    "// Vertex shader for stippled lines - basic version\n"
    "// Note: For proper line stipple, we need distance along the line\n"
    "// This requires either geometry shader emulation or compute preprocessing\n"
    "vertex VertexOutLine vertex_line_stipple(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  const device float*  lineDistances    [[buffer(2)]],  // precomputed distances\n"
    "  constant Uniforms& uniforms           [[buffer(1)]],\n"
    "  uint vid                              [[vertex_id]])\n"
    "{\n"
    "  VertexOutLine out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.color = uniforms.color;\n"
    "  out.lineDistance = lineDistances[vid];\n"
    "  return out;\n"
    "}\n"
    "\n"
    "// Simple vertex shader for lines without precomputed distances\n"
    "// Uses vertex index as approximate distance (works for line strips)\n"
    "vertex VertexOutLine vertex_line_stipple_simple(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms           [[buffer(1)]],\n"
    "  constant LineUniforms& line           [[buffer(3)]],\n"
    "  uint vid                              [[vertex_id]])\n"
    "{\n"
    "  VertexOutLine out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  float4 clipPos = uniforms.projectionMatrix * viewPos;\n"
    "  out.position = clipPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.color = uniforms.color;\n"
    "  \n"
    "  // Use a simple per-segment distance based on screen position\n"
    "  // This works reasonably for visualization but isn't perfect for all cases\n"
    "  float2 screenPos = (clipPos.xy / clipPos.w * 0.5 + 0.5) * line.viewport;\n"
    "  out.lineDistance = float(vid) * float(line.factor) * 2.0;\n"
    "  \n"
    "  return out;\n"
    "}\n"
    "\n"
    "// Fragment shader for stippled lines\n"
    "fragment float4 fragment_line_stipple(\n"
    "  VertexOutLine in [[stage_in]],\n"
    "  constant LineUniforms& line [[buffer(0)]])\n"
    "{\n"
    "  // Compute stipple mask\n"
    "  float mask = computeStippleMaskAA(in.lineDistance, line.pattern, line.factor, line.feather);\n"
    "  \n"
    "  // Discard transparent parts of stipple\n"
    "  if (mask < 0.01) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  return float4(in.color.rgb, in.color.a * mask);\n"
    "}\n"
    "\n"
    "// Fragment shader for stippled lines with clipping\n"
    "fragment float4 fragment_line_stipple_clip(\n"
    "  VertexOutLine in [[stage_in]],\n"
    "  constant LineUniforms& line [[buffer(0)]],\n"
    "  constant ClipUniforms& clip [[buffer(1)]])\n"
    "{\n"
    "  // Apply clipping first\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  // Compute stipple mask\n"
    "  float mask = computeStippleMaskAA(in.lineDistance, line.pattern, line.factor, line.feather);\n"
    "  \n"
    "  if (mask < 0.01) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  return float4(in.color.rgb, in.color.a * mask);\n"
    "}\n"
    "\n"
    "// ======== LINE DISTANCE COMPUTE SHADER ========\n"
    "\n"
    "// Compute shader to calculate cumulative line distances for line strips\n"
    "// This is needed for accurate stipple patterns along polylines\n"
    "kernel void compute_line_distances(\n"
    "  device const packed_float3* positions [[buffer(0)]],\n"
    "  device float* lineDistances           [[buffer(1)]],\n"
    "  constant Uniforms& uniforms      [[buffer(2)]],\n"
    "  constant float2& viewport        [[buffer(3)]],\n"
    "  uint vid                         [[thread_position_in_grid]])\n"
    "{\n"
    "  if (vid == 0) {\n"
    "    lineDistances[0] = 0.0;\n"
    "    return;\n"
    "  }\n"
    "  \n"
    "  // Transform current and previous position to screen space\n"
    "  float4x4 mvp = uniforms.projectionMatrix * uniforms.modelViewMatrix;\n"
    "  \n"
    "  float4 currClip = mvp * float4(positions[vid], 1.0);\n"
    "  float4 prevClip = mvp * float4(positions[vid - 1], 1.0);\n"
    "  \n"
    "  float2 currScreen = (currClip.xy / currClip.w * 0.5 + 0.5) * viewport;\n"
    "  float2 prevScreen = (prevClip.xy / prevClip.w * 0.5 + 0.5) * viewport;\n"
    "  \n"
    "  // Distance is cumulative from start\n"
    "  float segmentDist = length(currScreen - prevScreen);\n"
    "  lineDistances[vid] = lineDistances[vid - 1] + segmentDist;\n"
    "}\n"
    "\n"
    "// ======== HATCH PATTERN SHADERS ========\n"
    "\n"
    "// Hatch pattern types matching Aspect_HatchStyle\n"
    "// Note: OCCT enum values are non-contiguous, we remap to 0-12\n"
    "#define HATCH_NONE              0   // Aspect_HS_SOLID\n"
    "#define HATCH_GRID_DIAGONAL     1   // Aspect_HS_GRID_DIAGONAL (cross hatch)\n"
    "#define HATCH_GRID_DIAGONAL_WIDE 2  // Aspect_HS_GRID_DIAGONAL_WIDE\n"
    "#define HATCH_GRID              3   // Aspect_HS_GRID\n"
    "#define HATCH_GRID_WIDE         4   // Aspect_HS_GRID_WIDE\n"
    "#define HATCH_DIAGONAL_45       5   // Aspect_HS_DIAGONAL_45\n"
    "#define HATCH_DIAGONAL_135      6   // Aspect_HS_DIAGONAL_135\n"
    "#define HATCH_HORIZONTAL        7   // Aspect_HS_HORIZONTAL\n"
    "#define HATCH_VERTICAL          8   // Aspect_HS_VERTICAL\n"
    "#define HATCH_DIAGONAL_45_WIDE  9   // Aspect_HS_DIAGONAL_45_WIDE\n"
    "#define HATCH_DIAGONAL_135_WIDE 10  // Aspect_HS_DIAGONAL_135_WIDE\n"
    "#define HATCH_HORIZONTAL_WIDE   11  // Aspect_HS_HORIZONTAL_WIDE\n"
    "#define HATCH_VERTICAL_WIDE     12  // Aspect_HS_VERTICAL_WIDE\n"
    "\n"
    "// Hatch uniforms structure\n"
    "struct HatchUniforms {\n"
    "  int   hatchType;       // pattern type\n"
    "  float spacing;         // spacing between lines\n"
    "  float lineWidth;       // line thickness\n"
    "  float angle;           // custom rotation\n"
    "  float2 viewport;       // viewport size\n"
    "  float2 padding;\n"
    "};\n"
    "\n"
    "// Calculate distance to a line at given angle\n"
    "// Returns positive distance to nearest line\n"
    "float hatchLineDist(float2 coord, float angle, float spacing) {\n"
    "  // Rotate coordinate to align with line angle\n"
    "  float c = cos(angle);\n"
    "  float s = sin(angle);\n"
    "  float rotated = coord.x * c + coord.y * s;\n"
    "  \n"
    "  // Distance to nearest line (lines at multiples of spacing)\n"
    "  return abs(fmod(rotated + spacing * 0.5, spacing) - spacing * 0.5);\n"
    "}\n"
    "\n"
    "// Compute anti-aliased hatch mask for a single line direction\n"
    "float hatchLineMask(float2 fragCoord, float angle, float spacing, float lineWidth) {\n"
    "  float dist = hatchLineDist(fragCoord, angle, spacing);\n"
    "  float feather = 1.0; // anti-aliasing width\n"
    "  return 1.0 - smoothstep(lineWidth * 0.5 - feather, lineWidth * 0.5 + feather, dist);\n"
    "}\n"
    "\n"
    "// Core hatch pattern function\n"
    "// Returns mask value: 1.0 = line (discard), 0.0 = fill (keep)\n"
    "float computeHatchMask(float2 fragCoord, constant HatchUniforms& hatch) {\n"
    "  if (hatch.hatchType == HATCH_NONE) {\n"
    "    return 0.0; // no hatching, keep all pixels\n"
    "  }\n"
    "  \n"
    "  float spacing = hatch.spacing;\n"
    "  float lineWidth = hatch.lineWidth;\n"
    "  float mask = 0.0;\n"
    "  \n"
    "  // Select pattern based on type\n"
    "  switch (hatch.hatchType) {\n"
    "    case HATCH_HORIZONTAL:\n"
    "    case HATCH_HORIZONTAL_WIDE:\n"
    "      mask = hatchLineMask(fragCoord, 0.0, spacing, lineWidth);\n"
    "      break;\n"
    "      \n"
    "    case HATCH_VERTICAL:\n"
    "    case HATCH_VERTICAL_WIDE:\n"
    "      mask = hatchLineMask(fragCoord, M_PI_2_F, spacing, lineWidth);\n"
    "      break;\n"
    "      \n"
    "    case HATCH_DIAGONAL_45:\n"
    "    case HATCH_DIAGONAL_45_WIDE:\n"
    "      mask = hatchLineMask(fragCoord, M_PI_4_F, spacing, lineWidth);\n"
    "      break;\n"
    "      \n"
    "    case HATCH_DIAGONAL_135:\n"
    "    case HATCH_DIAGONAL_135_WIDE:\n"
    "      mask = hatchLineMask(fragCoord, -M_PI_4_F, spacing, lineWidth);\n"
    "      break;\n"
    "      \n"
    "    case HATCH_GRID:\n"
    "    case HATCH_GRID_WIDE: {\n"
    "      // Horizontal + Vertical\n"
    "      float h = hatchLineMask(fragCoord, 0.0, spacing, lineWidth);\n"
    "      float v = hatchLineMask(fragCoord, M_PI_2_F, spacing, lineWidth);\n"
    "      mask = max(h, v);\n"
    "      break;\n"
    "    }\n"
    "      \n"
    "    case HATCH_GRID_DIAGONAL:\n"
    "    case HATCH_GRID_DIAGONAL_WIDE: {\n"
    "      // Diagonal 45 + 135 (cross-hatch)\n"
    "      float d45 = hatchLineMask(fragCoord, M_PI_4_F, spacing, lineWidth);\n"
    "      float d135 = hatchLineMask(fragCoord, -M_PI_4_F, spacing, lineWidth);\n"
    "      mask = max(d45, d135);\n"
    "      break;\n"
    "    }\n"
    "      \n"
    "    default:\n"
    "      mask = 0.0;\n"
    "      break;\n"
    "  }\n"
    "  \n"
    "  return mask;\n"
    "}\n"
    "\n"
    "// Vertex output for hatched geometry\n"
    "struct VertexOutHatch {\n"
    "  float4 position [[position]];\n"
    "  float3 normal;\n"
    "  float3 viewPosition;\n"
    "  float4 color;\n"
    "  float3 worldPosition;\n"
    "};\n"
    "\n"
    "// Vertex shader for hatched surfaces\n"
    "vertex VertexOutHatch vertex_hatch(\n"
    "  const device packed_float3* positions [[buffer(0)]],\n"
    "  const device packed_float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms           [[buffer(1)]],\n"
    "  uint vid                              [[vertex_id]])\n"
    "{\n"
    "  VertexOutHatch out;\n"
    "  float3 pos = float3(positions[vid]);\n"
    "  float3 norm = float3(normals[vid]);\n"
    "  float4 worldPos = float4(pos, 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  out.normal = normalize((uniforms.modelViewMatrix * float4(norm, 0.0)).xyz);\n"
    "  out.color = uniforms.color;\n"
    "  return out;\n"
    "}\n"
    "\n"
    "// Fragment shader: Hatched surface with Phong lighting\n"
    "fragment float4 fragment_hatch_phong(\n"
    "  VertexOutHatch in [[stage_in]],\n"
    "  constant Uniforms& uniforms       [[buffer(0)]],\n"
    "  constant LightUniforms& lights    [[buffer(1)]],\n"
    "  constant HatchUniforms& hatch     [[buffer(2)]])\n"
    "{\n"
    "  // Calculate hatch mask in screen space\n"
    "  float2 fragCoord = in.position.xy;\n"
    "  float mask = computeHatchMask(fragCoord, hatch);\n"
    "  \n"
    "  // Discard hatched pixels (where mask > 0.5)\n"
    "  if (mask > 0.5) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  // Compute Phong lighting for visible pixels\n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  \n"
    "  // Two-sided lighting\n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  // Apply anti-aliasing at edges\n"
    "  float alpha = in.color.a * (1.0 - mask);\n"
    "  return float4(saturate(result), alpha);\n"
    "}\n"
    "\n"
    "// Fragment shader: Hatched surface unlit\n"
    "fragment float4 fragment_hatch_unlit(\n"
    "  VertexOutHatch in [[stage_in]],\n"
    "  constant HatchUniforms& hatch [[buffer(0)]])\n"
    "{\n"
    "  float2 fragCoord = in.position.xy;\n"
    "  float mask = computeHatchMask(fragCoord, hatch);\n"
    "  \n"
    "  if (mask > 0.5) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  float alpha = in.color.a * (1.0 - mask);\n"
    "  return float4(in.color.rgb, alpha);\n"
    "}\n"
    "\n"
    "// Fragment shader: Hatched surface with clipping\n"
    "fragment float4 fragment_hatch_phong_clip(\n"
    "  VertexOutHatch in [[stage_in]],\n"
    "  constant Uniforms& uniforms       [[buffer(0)]],\n"
    "  constant LightUniforms& lights    [[buffer(1)]],\n"
    "  constant HatchUniforms& hatch     [[buffer(2)]],\n"
    "  constant ClipUniforms& clip       [[buffer(3)]])\n"
    "{\n"
    "  // Apply clipping first\n"
    "  if (isClipped(in.worldPosition, clip)) discard_fragment();\n"
    "  \n"
    "  // Calculate hatch mask\n"
    "  float2 fragCoord = in.position.xy;\n"
    "  float mask = computeHatchMask(fragCoord, hatch);\n"
    "  \n"
    "  if (mask > 0.5) {\n"
    "    discard_fragment();\n"
    "  }\n"
    "  \n"
    "  // Compute Phong lighting\n"
    "  float3 N = normalize(in.normal);\n"
    "  float3 V = normalize(-in.viewPosition);\n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  \n"
    "  float3 result = lights.AmbientColor.rgb * in.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, in.viewPosition,\n"
    "                                in.color.rgb, float3(1.0), 32.0,\n"
    "                                uniforms.modelViewMatrix);\n"
    "  }\n"
    "  \n"
    "  float alpha = in.color.a * (1.0 - mask);\n"
    "  return float4(saturate(result), alpha);\n"
    "}\n";

  return aSource;
}
