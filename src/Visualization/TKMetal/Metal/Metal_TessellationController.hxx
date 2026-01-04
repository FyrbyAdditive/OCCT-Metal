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

#ifndef Metal_TessellationController_HeaderFile
#define Metal_TessellationController_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <NCollection_Mat4.hxx>

#ifdef __OBJC__
@protocol MTLDevice;
@protocol MTLBuffer;
@protocol MTLCommandBuffer;
@protocol MTLRenderCommandEncoder;
@protocol MTLComputePipelineState;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
@protocol MTLLibrary;
#endif

class Metal_Context;

//! Tessellation parameters.
struct Metal_TessParams
{
  float ModelViewProjection[16];  //!< MVP matrix
  float ModelView[16];            //!< ModelView matrix
  float Viewport[2];              //!< Viewport size
  float TessLevel;                //!< Base tessellation level (1-64)
  float AdaptiveFactor;           //!< Adaptive factor (0 = uniform, 1 = fully adaptive)
  float CameraPos[3];             //!< Camera position for LOD
  float Padding;

  //! Default constructor.
  Metal_TessParams()
  : TessLevel(8.0f),
    AdaptiveFactor(0.0f),
    Padding(0.0f)
  {
    memset(ModelViewProjection, 0, sizeof(ModelViewProjection));
    memset(ModelView, 0, sizeof(ModelView));
    Viewport[0] = 800.0f;
    Viewport[1] = 600.0f;
    CameraPos[0] = 0.0f;
    CameraPos[1] = 0.0f;
    CameraPos[2] = 5.0f;
  }
};

//! Tessellation controller for Metal.
//! Manages tessellation pipeline state and compute-based tessellation factor calculation.
//! Metal tessellation uses: compute shader (tessellation factors) + post-tessellation vertex function.
class Metal_TessellationController : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_TessellationController, Standard_Transient)

public:

  //! Create tessellation controller.
  //! @param[in] theCtx Metal context
  Standard_EXPORT Metal_TessellationController(Metal_Context* theCtx);

  //! Destructor.
  Standard_EXPORT ~Metal_TessellationController();

  //! Release all GPU resources.
  Standard_EXPORT void Release();

  //! Check if controller is valid and ready to use.
  bool IsValid() const { return myIsValid; }

  //! Compute tessellation factors for patches.
  //! @param[in] theCmdBuf       command buffer
  //! @param[in] theControlPoints control point buffer (4 points per quad patch)
  //! @param[in] thePatchCount   number of patches
  //! @param[in] theParams       tessellation parameters
  //! @return true on success
  Standard_EXPORT bool ComputeTessFactors(
#ifdef __OBJC__
    id<MTLCommandBuffer> theCmdBuf,
    id<MTLBuffer> theControlPoints,
#else
    void* theCmdBuf,
    void* theControlPoints,
#endif
    int thePatchCount,
    const Metal_TessParams& theParams);

  //! Begin tessellation render pass.
  //! Sets up pipeline and tessellation factor buffer.
  //! @param[in] theEncoder     render command encoder
  //! @param[in] theControlPoints control point buffer
  //! @param[in] theParams      tessellation parameters
  Standard_EXPORT void BeginTessellationPass(
#ifdef __OBJC__
    id<MTLRenderCommandEncoder> theEncoder,
    id<MTLBuffer> theControlPoints,
#else
    void* theEncoder,
    void* theControlPoints,
#endif
    const Metal_TessParams& theParams);

  //! Draw tessellated patches.
  //! @param[in] theEncoder    render command encoder
  //! @param[in] thePatchCount number of quad patches to draw
  Standard_EXPORT void DrawPatches(
#ifdef __OBJC__
    id<MTLRenderCommandEncoder> theEncoder,
#else
    void* theEncoder,
#endif
    int thePatchCount);

  //! Get tessellation factor buffer.
#ifdef __OBJC__
  id<MTLBuffer> TessFactorBuffer() const { return myTessFactorBuffer; }
#else
  void* TessFactorBuffer() const { return myTessFactorBuffer; }
#endif

  //! Get tessellation render pipeline.
#ifdef __OBJC__
  id<MTLRenderPipelineState> TessRenderPipeline() const { return myTessRenderPipeline; }
#else
  void* TessRenderPipeline() const { return myTessRenderPipeline; }
#endif

  //! Get depth stencil state.
#ifdef __OBJC__
  id<MTLDepthStencilState> DepthStencilState() const { return myDepthStencilState; }
#else
  void* DepthStencilState() const { return myDepthStencilState; }
#endif

  //! Set base tessellation level (1-64).
  void SetTessLevel(float theLevel) { myTessLevel = fmax(1.0f, fmin(64.0f, theLevel)); }

  //! Get tessellation level.
  float TessLevel() const { return myTessLevel; }

  //! Set adaptive factor (0 = uniform tessellation, 1 = fully adaptive).
  void SetAdaptiveFactor(float theFactor) { myAdaptiveFactor = fmax(0.0f, fmin(1.0f, theFactor)); }

  //! Get adaptive factor.
  float AdaptiveFactor() const { return myAdaptiveFactor; }

  //! Set maximum tessellation factor (clamped to 64).
  void SetMaxTessFactor(int theFactor) { myMaxTessFactor = fmax(1, fmin(64, theFactor)); }

  //! Get maximum tessellation factor.
  int MaxTessFactor() const { return myMaxTessFactor; }

protected:

  //! Initialize pipelines.
  bool initPipelines();

  //! Ensure tessellation factor buffer is large enough.
  bool ensureTessFactorBuffer(int thePatchCount);

protected:

  Metal_Context* myContext;    //!< Metal context
  float myTessLevel;           //!< Base tessellation level
  float myAdaptiveFactor;      //!< Adaptive factor
  int myMaxTessFactor;         //!< Maximum tessellation factor
  int myTessFactorCapacity;    //!< Current buffer capacity in patches
  bool myIsValid;              //!< Initialization status

#ifdef __OBJC__
  id<MTLComputePipelineState> myTessFactorPipeline;   //!< Tessellation factor compute pipeline
  id<MTLRenderPipelineState> myTessRenderPipeline;    //!< Tessellation render pipeline
  id<MTLDepthStencilState> myDepthStencilState;       //!< Depth stencil state
  id<MTLBuffer> myTessFactorBuffer;                   //!< Tessellation factors buffer
  id<MTLBuffer> myTessUniformBuffer;                  //!< Tessellation uniforms buffer
#else
  void* myTessFactorPipeline;
  void* myTessRenderPipeline;
  void* myDepthStencilState;
  void* myTessFactorBuffer;
  void* myTessUniformBuffer;
#endif
};

DEFINE_STANDARD_HANDLE(Metal_TessellationController, Standard_Transient)

#endif // Metal_TessellationController_HeaderFile
