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

#ifndef Metal_OIT_HeaderFile
#define Metal_OIT_HeaderFile

#include <Metal_Resource.hxx>
#include <Standard_Handle.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
#endif

class Metal_Context;
class Metal_Texture;

//! OIT rendering method enumeration.
enum Metal_OITMethod
{
  Metal_OITMethod_None,           //!< No OIT, standard alpha blending
  Metal_OITMethod_WeightedBlended, //!< Weighted blended OIT (fast, single pass)
  Metal_OITMethod_DepthPeeling     //!< Dual depth peeling (accurate, multi-pass)
};

//! Order-Independent Transparency (OIT) resource manager for Metal.
//! Supports both weighted blended OIT and dual depth peeling algorithms.
//!
//! Weighted Blended OIT:
//! - Single pass, approximate
//! - Uses 2 color attachments (accumulation + weight)
//! - Good performance, acceptable quality for most cases
//!
//! Depth Peeling:
//! - Multi-pass, exact ordering
//! - Uses ping-pong framebuffers with depth testing
//! - Higher quality but slower (N passes for N layers)
class Metal_OIT : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_OIT, Metal_Resource)

public:

  //! Constructor.
  Standard_EXPORT Metal_OIT();

  //! Destructor.
  Standard_EXPORT ~Metal_OIT() override;

  //! @return true if OIT resources are initialized
  bool IsValid() const { return myIsInitialized; }

  //! Return current OIT method.
  Metal_OITMethod Method() const { return myMethod; }

  //! Return width of OIT buffers.
  int Width() const { return myWidth; }

  //! Return height of OIT buffers.
  int Height() const { return myHeight; }

  //! Return depth factor for weighted blended OIT (0-1).
  float DepthFactor() const { return myDepthFactor; }

  //! Set depth factor for weighted blended OIT.
  //! Higher values give more weight to depth in coverage calculation.
  void SetDepthFactor(float theFactor) { myDepthFactor = theFactor < 0.0f ? 0.0f : (theFactor > 1.0f ? 1.0f : theFactor); }

  //! Return number of depth peeling layers.
  int NbDepthPeelingLayers() const { return myNbPeelingLayers; }

  //! Set number of depth peeling layers.
  void SetNbDepthPeelingLayers(int theNbLayers) { myNbPeelingLayers = theNbLayers > 0 ? theNbLayers : 4; }

  //! Initialize OIT resources with specified method and dimensions.
  //! @param theCtx Metal context
  //! @param theMethod OIT method to use
  //! @param theWidth buffer width
  //! @param theHeight buffer height
  //! @param theSampleCount MSAA sample count (1 for no MSAA)
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            Metal_OITMethod theMethod,
                            int theWidth,
                            int theHeight,
                            int theSampleCount = 1);

  //! Resize OIT buffers if dimensions changed.
  //! @param theCtx Metal context
  //! @param theWidth new width
  //! @param theHeight new height
  //! @return true on success
  Standard_EXPORT bool Resize(Metal_Context* theCtx,
                              int theWidth,
                              int theHeight);

  //! Begin OIT rendering pass.
  //! For weighted blended: sets up accumulation pass
  //! For depth peeling: begins first peel pass
  //! @param theCtx Metal context
  //! @param theEncoder current render command encoder (will be ended)
  Standard_EXPORT void BeginAccumulation(Metal_Context* theCtx);

  //! End OIT accumulation and composite result.
  //! @param theCtx Metal context
  //! @param theTargetTexture destination texture for final result
  Standard_EXPORT void EndAccumulationAndComposite(Metal_Context* theCtx,
                                                    id<MTLTexture> theTargetTexture);

  //! For depth peeling: advance to next peel pass.
  //! @param theCtx Metal context
  //! @return true if more passes needed, false if done
  Standard_EXPORT bool NextPeelingPass(Metal_Context* theCtx);

  //! Return current peeling pass index (0-based).
  int CurrentPeelingPass() const { return myCurrentPeelingPass; }

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const override;

#ifdef __OBJC__
  //! Return accumulation texture (weighted OIT) or current depth texture (peeling).
  id<MTLTexture> AccumTexture() const { return myAccumTexture; }

  //! Return weight texture (weighted OIT only).
  id<MTLTexture> WeightTexture() const { return myWeightTexture; }

  //! Return compositing pipeline state.
  id<MTLRenderPipelineState> CompositePipeline() const { return myCompositePipeline; }

  //! Return depth peeling front color texture.
  id<MTLTexture> PeelingFrontColor() const { return myPeelingFrontColor[myPeelingReadIndex]; }

  //! Return depth peeling back color texture.
  id<MTLTexture> PeelingBackColor() const { return myPeelingBackColor[myPeelingReadIndex]; }

  //! Return depth peeling depth texture (min/max).
  id<MTLTexture> PeelingDepthTexture() const { return myPeelingDepth[myPeelingReadIndex]; }

  //! Return blended back color texture (depth peeling).
  id<MTLTexture> BlendBackTexture() const { return myBlendBackTexture; }
#endif

protected:

  //! Initialize weighted blended OIT resources.
  Standard_EXPORT bool initWeightedBlended(Metal_Context* theCtx);

  //! Initialize depth peeling OIT resources.
  Standard_EXPORT bool initDepthPeeling(Metal_Context* theCtx);

  //! Create compositing pipeline for weighted blended OIT.
  Standard_EXPORT bool createWeightedCompositePipeline(Metal_Context* theCtx);

  //! Create compositing pipeline for depth peeling.
  Standard_EXPORT bool createPeelingCompositePipeline(Metal_Context* theCtx);

  //! Perform weighted blended composition.
  Standard_EXPORT void compositeWeightedBlended(Metal_Context* theCtx,
                                                 id<MTLTexture> theTargetTexture);

  //! Perform depth peeling composition.
  Standard_EXPORT void compositeDepthPeeling(Metal_Context* theCtx,
                                              id<MTLTexture> theTargetTexture);

protected:

#ifdef __OBJC__
  // Weighted blended OIT textures
  id<MTLTexture>             myAccumTexture;        //!< Accumulated color (RGBA16Float)
  id<MTLTexture>             myWeightTexture;       //!< Weight/revealage (R16Float)
  id<MTLRenderPipelineState> myCompositePipeline;   //!< Compositing pipeline

  // Depth peeling textures (ping-pong)
  id<MTLTexture>             myPeelingDepth[2];     //!< Min/max depth (RG32Float)
  id<MTLTexture>             myPeelingFrontColor[2]; //!< Front color (RGBA16Float)
  id<MTLTexture>             myPeelingBackColor[2]; //!< Back color (RGBA16Float)
  id<MTLTexture>             myBlendBackTexture;    //!< Accumulated back color
  id<MTLRenderPipelineState> myPeelingBlendPipeline; //!< Peeling blend pipeline
  id<MTLRenderPipelineState> myPeelingFlushPipeline; //!< Peeling flush pipeline
#else
  void*                      myAccumTexture;
  void*                      myWeightTexture;
  void*                      myCompositePipeline;
  void*                      myPeelingDepth[2];
  void*                      myPeelingFrontColor[2];
  void*                      myPeelingBackColor[2];
  void*                      myBlendBackTexture;
  void*                      myPeelingBlendPipeline;
  void*                      myPeelingFlushPipeline;
#endif

  Metal_OITMethod myMethod;             //!< Current OIT method
  int             myWidth;              //!< Buffer width
  int             myHeight;             //!< Buffer height
  int             mySampleCount;        //!< MSAA sample count
  float           myDepthFactor;        //!< Depth factor for weighted OIT
  int             myNbPeelingLayers;    //!< Number of depth peeling layers
  int             myCurrentPeelingPass; //!< Current peeling pass (0-based)
  int             myPeelingReadIndex;   //!< Ping-pong read index
  bool            myIsInitialized;      //!< Initialization flag
  size_t          myEstimatedSize;      //!< Estimated GPU memory
};

#endif // Metal_OIT_HeaderFile
