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

#ifndef Metal_PostProcess_HeaderFile
#define Metal_PostProcess_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <Graphic3d_ToneMappingMethod.hxx>
#include <NCollection_Vec2.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;
class Metal_FrameBuffer;

//! Post-processing effect types.
enum Metal_PostProcessEffect
{
  Metal_PostProcessEffect_None = 0,           //!< No effect
  Metal_PostProcessEffect_FXAA = 1,           //!< Fast approximate anti-aliasing
  Metal_PostProcessEffect_ToneMapping = 2,    //!< HDR tone mapping
  Metal_PostProcessEffect_Vignette = 4,       //!< Vignette effect
  Metal_PostProcessEffect_GammaCorrection = 8 //!< Gamma correction
};

//! Post-processing parameters.
struct Metal_PostProcessParams
{
  //! Tone mapping method.
  Graphic3d_ToneMappingMethod ToneMappingMethod;

  //! Exposure value for tone mapping (default: 1.0).
  float Exposure;

  //! White point for filmic tone mapping (default: 1.0).
  float WhitePoint;

  //! Gamma correction value (default: 2.2).
  float Gamma;

  //! FXAA quality preset (0=low, 1=medium, 2=high, default: 1).
  int FXAAQuality;

  //! Vignette intensity (0-1, default: 0.3).
  float VignetteIntensity;

  //! Vignette radius (0-1, default: 0.7).
  float VignetteRadius;

  //! Default constructor.
  Metal_PostProcessParams()
  : ToneMappingMethod(Graphic3d_ToneMappingMethod_Disabled),
    Exposure(1.0f),
    WhitePoint(1.0f),
    Gamma(2.2f),
    FXAAQuality(1),
    VignetteIntensity(0.3f),
    VignetteRadius(0.7f) {}
};

//! Metal post-processing effect manager.
//! Provides FXAA anti-aliasing, tone mapping, gamma correction,
//! and other image-space effects.
class Metal_PostProcess : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_PostProcess, Standard_Transient)

public:

  //! Create empty post-processor.
  Standard_EXPORT Metal_PostProcess();

  //! Destructor.
  Standard_EXPORT ~Metal_PostProcess();

  //! Initialize post-processing resources.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return true if post-processor is valid.
  bool IsValid() const { return myIsValid; }

  //! Set enabled effects (bitmask of Metal_PostProcessEffect).
  void SetEffects(int theEffects) { myEffects = theEffects; }

  //! Return enabled effects.
  int Effects() const { return myEffects; }

  //! Set post-processing parameters.
  void SetParams(const Metal_PostProcessParams& theParams) { myParams = theParams; }

  //! Return post-processing parameters.
  const Metal_PostProcessParams& Params() const { return myParams; }

  //! Return modifiable parameters.
  Metal_PostProcessParams& ChangeParams() { return myParams; }

  //! Apply post-processing effects to an image.
  //! @param theCtx Metal context
  //! @param theCommandBuffer command buffer
  //! @param theSource source texture (scene rendered image)
  //! @param theTarget target texture (output with effects applied)
#ifdef __OBJC__
  Standard_EXPORT void Apply(Metal_Context* theCtx,
                             id<MTLCommandBuffer> theCommandBuffer,
                             id<MTLTexture> theSource,
                             id<MTLTexture> theTarget);
#endif

  //! Apply FXAA anti-aliasing.
  //! @param theCtx Metal context
  //! @param theCommandBuffer command buffer
  //! @param theSource source texture
  //! @param theTarget target texture
#ifdef __OBJC__
  Standard_EXPORT void ApplyFXAA(Metal_Context* theCtx,
                                 id<MTLCommandBuffer> theCommandBuffer,
                                 id<MTLTexture> theSource,
                                 id<MTLTexture> theTarget);
#endif

  //! Apply tone mapping and color grading.
  //! @param theCtx Metal context
  //! @param theCommandBuffer command buffer
  //! @param theSource source texture (HDR)
  //! @param theTarget target texture (LDR)
#ifdef __OBJC__
  Standard_EXPORT void ApplyToneMapping(Metal_Context* theCtx,
                                        id<MTLCommandBuffer> theCommandBuffer,
                                        id<MTLTexture> theSource,
                                        id<MTLTexture> theTarget);
#endif

private:

#ifdef __OBJC__
  id<MTLLibrary>             myLibrary;
  id<MTLSamplerState>        mySampler;
  id<MTLRenderPipelineState> myFXAAPipeline;
  id<MTLRenderPipelineState> myToneMappingPipeline;
  id<MTLRenderPipelineState> myCombinedPipeline;
#else
  void* myLibrary;
  void* mySampler;
  void* myFXAAPipeline;
  void* myToneMappingPipeline;
  void* myCombinedPipeline;
#endif

  Metal_PostProcessParams myParams;
  int  myEffects;
  bool myIsValid;
};

DEFINE_STANDARD_HANDLE(Metal_PostProcess, Standard_Transient)

#endif // Metal_PostProcess_HeaderFile
