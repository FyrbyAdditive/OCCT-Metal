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

#ifndef Metal_StereoComposer_HeaderFile
#define Metal_StereoComposer_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <Graphic3d_StereoMode.hxx>
#include <NCollection_Mat4.hxx>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

class Metal_Context;
class Metal_FrameBuffer;

//! Uniform buffer for stereo composition shader.
struct Metal_StereoUniforms
{
  NCollection_Mat4<float> AnaglyphLeft;   //!< Left eye anaglyph color filter
  NCollection_Mat4<float> AnaglyphRight;  //!< Right eye anaglyph color filter
  float TexOffset[2];                     //!< Texture offset for smooth interlacing
  int   ReverseStereo;                    //!< Flag to swap left/right eyes
  int   Padding;                          //!< Padding for alignment
};

//! Metal stereo image composer.
//! Combines left and right eye images using various stereo modes
//! (anaglyph, interlaced, side-by-side, over-under, etc.)
class Metal_StereoComposer : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_StereoComposer, Standard_Transient)

public:

  //! Create empty stereo composer.
  Standard_EXPORT Metal_StereoComposer();

  //! Destructor.
  Standard_EXPORT ~Metal_StereoComposer();

  //! Initialize stereo composition resources.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return true if composer is valid.
  bool IsValid() const { return myIsValid; }

  //! Compose stereo image from left and right eye buffers.
  //! @param theCtx Metal context
  //! @param theLeftEye left eye frame buffer
  //! @param theRightEye right eye frame buffer
  //! @param theTarget target frame buffer (or nil for drawable)
  //! @param theMode stereo composition mode
  //! @param theReverseStereo flag to swap left/right eyes
  //! @param theAnaglyphLeft left anaglyph color matrix
  //! @param theAnaglyphRight right anaglyph color matrix
  //! @param theSmoothInterlacing apply smooth interlacing filter
#ifdef __OBJC__
  Standard_EXPORT void Compose(Metal_Context* theCtx,
                               id<MTLCommandBuffer> theCommandBuffer,
                               id<MTLTexture> theLeftEye,
                               id<MTLTexture> theRightEye,
                               id<MTLTexture> theTarget,
                               Graphic3d_StereoMode theMode,
                               bool theReverseStereo,
                               const NCollection_Mat4<float>& theAnaglyphLeft,
                               const NCollection_Mat4<float>& theAnaglyphRight,
                               bool theSmoothInterlacing);
#endif

  //! Compose stereo image using frame buffer wrappers.
  Standard_EXPORT void Compose(Metal_Context* theCtx,
                               const occ::handle<Metal_FrameBuffer>& theLeftEye,
                               const occ::handle<Metal_FrameBuffer>& theRightEye,
                               const occ::handle<Metal_FrameBuffer>& theTarget,
                               Graphic3d_StereoMode theMode,
                               bool theReverseStereo,
                               const NCollection_Mat4<float>& theAnaglyphLeft,
                               const NCollection_Mat4<float>& theAnaglyphRight,
                               bool theSmoothInterlacing);

private:

  //! Get or create pipeline for specific stereo mode.
#ifdef __OBJC__
  id<MTLRenderPipelineState> getPipeline(Metal_Context* theCtx,
                                         Graphic3d_StereoMode theMode,
                                         MTLPixelFormat theTargetFormat);
#endif

private:

#ifdef __OBJC__
  id<MTLLibrary>             myLibrary;              //!< Shader library
  id<MTLSamplerState>        mySampler;              //!< Texture sampler
  id<MTLRenderPipelineState> myPipelineAnaglyph;     //!< Anaglyph mode pipeline
  id<MTLRenderPipelineState> myPipelineRowInterlaced;   //!< Row interlaced pipeline
  id<MTLRenderPipelineState> myPipelineColInterlaced;   //!< Column interlaced pipeline
  id<MTLRenderPipelineState> myPipelineChessboard;   //!< Chessboard pipeline
  id<MTLRenderPipelineState> myPipelineSideBySide;   //!< Side-by-side pipeline
  id<MTLRenderPipelineState> myPipelineOverUnder;    //!< Over-under pipeline
#else
  void* myLibrary;
  void* mySampler;
  void* myPipelineAnaglyph;
  void* myPipelineRowInterlaced;
  void* myPipelineColInterlaced;
  void* myPipelineChessboard;
  void* myPipelineSideBySide;
  void* myPipelineOverUnder;
#endif

  bool myIsValid;
};

DEFINE_STANDARD_HANDLE(Metal_StereoComposer, Standard_Transient)

#endif // Metal_StereoComposer_HeaderFile
