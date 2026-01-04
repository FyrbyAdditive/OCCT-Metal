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
                                      id<MTLRenderPipelineState>& thePipeline,
                                      id<MTLDepthStencilState>& theDepthStencil)
{
  Metal_ShaderProgramKey aKey(theModel, theBits);

  // Check cache first
  if (myPipelineCache.Find(aKey, thePipeline))
  {
    // Get depth-stencil state (same for all pipelines for now)
    if (!myDepthStencilCache.Find(0, theDepthStencil))
    {
      return false;
    }
    return true;
  }

  // Create new pipeline
  return createPipeline(theModel, theBits, thePipeline, theDepthStencil);
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
    case Graphic3d_TypeOfShadingModel_PbrFacet:
      // PBR shading requires:
      // - Metallic/roughness material uniforms
      // - IBL (Image-Based Lighting) environment maps
      // - Fresnel/GGX BRDF calculations in shader
      // Currently falls back to Phong until PBR shaders are implemented.
      return theHasNodalNormals ? Graphic3d_TypeOfShadingModel_Phong
                                : Graphic3d_TypeOfShadingModel_PhongFacet;
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
      // PBR line shading not implemented - fall back to Phong/Unlit
      return theHasNodalNormals ? Graphic3d_TypeOfShadingModel_Phong
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
                                          id<MTLRenderPipelineState>& thePipeline,
                                          id<MTLDepthStencilState>& theDepthStencil)
{
  if (myContext == nullptr || myShaderLibrary == nil)
  {
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

    // Handle hatch patterns
    if (hasHatch)
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
        case Graphic3d_TypeOfShadingModel_Phong:
        case Graphic3d_TypeOfShadingModel_PhongFacet:
        default:
          aVertexFunc = @"vertex_phong";
          aFragmentFunc = hasClipping ? @"fragment_phong_clip" : @"fragment_phong";
          break;
      }
    }

    id<MTLFunction> aVertex = [myShaderLibrary newFunctionWithName:aVertexFunc];
    id<MTLFunction> aFragment = [myShaderLibrary newFunctionWithName:aFragmentFunc];

    if (aVertex == nil || aFragment == nil)
    {
      myContext->Messenger()->SendFail() << "Metal_ShaderManager: Failed to find shader functions";
      return false;
    }

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
    if (!myDepthStencilCache.Find(0, theDepthStencil))
    {
      MTLDepthStencilDescriptor* aDepthDesc = [[MTLDepthStencilDescriptor alloc] init];
      aDepthDesc.depthCompareFunction = MTLCompareFunctionLess;
      aDepthDesc.depthWriteEnabled = YES;

      theDepthStencil = [myContext->Device() newDepthStencilStateWithDescriptor:aDepthDesc];
      myDepthStencilCache.Bind(0, theDepthStencil);
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
    "// Material structure\n"
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
    "struct LightUniforms {\n"
    "  LightSource Lights[MAX_LIGHTS];\n"
    "  float4 AmbientColor;\n"
    "  int LightCount;\n"
    "  int3 padding;\n"
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
    "float3 computePhongLight(LightSource light, float3 N, float3 V, float3 fragPos,\n"
    "                         float3 diffuseColor, float3 specularColor, float shininess) {\n"
    "  if (light.Parameters.w < 0.5) return float3(0.0); // disabled\n"
    "  \n"
    "  int lightType = int(light.Parameters.z);\n"
    "  float3 lightColor = light.Color.rgb * light.Color.w; // color * intensity\n"
    "  float3 L;\n"
    "  float attenuation = 1.0;\n"
    "  \n"
    "  if (lightType == LIGHT_TYPE_DIRECTIONAL) {\n"
    "    L = normalize(-light.Position.xyz);\n"
    "  } else {\n"
    "    float3 lightVec = light.Position.xyz - fragPos;\n"
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
    "      float3 spotDir = normalize(-light.Direction.xyz);\n"
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
    "  const device float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutUnlit out;\n"
    "  float4 worldPos = float4(positions[vid], 1.0);\n"
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
    "  const device float3* positions [[buffer(0)]],\n"
    "  const device float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  constant LightUniforms& lights [[buffer(3)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutGouraud out;\n"
    "  float4 worldPos = float4(positions[vid], 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  \n"
    "  // Transform normal (simplified - should use inverse transpose)\n"
    "  float3 N = normalize((uniforms.modelViewMatrix * float4(normals[vid], 0.0)).xyz);\n"
    "  float3 V = normalize(-viewPos.xyz);\n"
    "  \n"
    "  // Compute lighting at vertex\n"
    "  float3 result = lights.AmbientColor.rgb * uniforms.color.rgb;\n"
    "  for (int i = 0; i < lights.LightCount; i++) {\n"
    "    result += computePhongLight(lights.Lights[i], N, V, viewPos.xyz,\n"
    "                                uniforms.color.rgb, float3(1.0), 32.0);\n"
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
    "  const device float3* positions [[buffer(0)]],\n"
    "  const device float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutPhong out;\n"
    "  float4 worldPos = float4(positions[vid], 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  \n"
    "  // Transform normal\n"
    "  out.normal = normalize((uniforms.modelViewMatrix * float4(normals[vid], 0.0)).xyz);\n"
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
    "                                in.color.rgb, float3(1.0), 32.0);\n"
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
    "                                in.color.rgb, float3(1.0), 32.0);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), in.color.a);\n"
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
    "  const device float3* positions [[buffer(0)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOut out;\n"
    "  float4 worldPos = float4(positions[vid], 1.0);\n"
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
    "  constant WireframeUniforms& wire [[buffer(0)]],\n"
    "  constant LightUniforms& lights   [[buffer(1)]])\n"
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
    "                                wire.FillColor.rgb, float3(1.0), 32.0);\n"
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
    "                                uniforms.color.rgb, float3(1.0), 32.0);\n"
    "  }\n"
    "  \n"
    "  return float4(saturate(result), uniforms.color.a);\n"
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
    "  const device float3* positions [[buffer(0)]],\n"
    "  const device float3* normals   [[buffer(2)]],\n"
    "  constant Uniforms& uniforms    [[buffer(1)]],\n"
    "  uint vid                       [[vertex_id]])\n"
    "{\n"
    "  VertexOutHatch out;\n"
    "  float4 worldPos = float4(positions[vid], 1.0);\n"
    "  float4 viewPos = uniforms.modelViewMatrix * worldPos;\n"
    "  out.position = uniforms.projectionMatrix * viewPos;\n"
    "  out.worldPosition = worldPos.xyz;\n"
    "  out.viewPosition = viewPos.xyz;\n"
    "  out.normal = normalize((uniforms.modelViewMatrix * float4(normals[vid], 0.0)).xyz);\n"
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
    "                                in.color.rgb, float3(1.0), 32.0);\n"
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
    "                                in.color.rgb, float3(1.0), 32.0);\n"
    "  }\n"
    "  \n"
    "  float alpha = in.color.a * (1.0 - mask);\n"
    "  return float4(saturate(result), alpha);\n"
    "}\n";

  return aSource;
}
