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

#ifndef Metal_ShaderProgram_HeaderFile
#define Metal_ShaderProgram_HeaderFile

#include <Metal_Resource.hxx>
#include <Metal_ShaderObject.hxx>
#include <Graphic3d_ShaderProgram.hxx>
#include <Graphic3d_TextureSetBits.hxx>
#include <Graphic3d_RenderTransparentMethod.hxx>
#include <NCollection_Sequence.hxx>
#include <NCollection_DataMap.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLRenderPipelineState;
@protocol MTLComputePipelineState;
@protocol MTLDepthStencilState;
#endif

class Metal_Context;

//! Uniform state variable types (matching OpenGL for compatibility).
enum Metal_UniformStateType
{
  Metal_LightSourcesState,
  Metal_ClipPlanesState,
  Metal_ModelWorldState,
  Metal_WorldViewState,
  Metal_ProjectionState,
  Metal_MaterialState,
  Metal_SurfDetailState,
  Metal_OitState,
  Metal_UniformStateType_NB
};

//! Wrapper for Metal shader program (render or compute pipeline).
//! Manages vertex and fragment shaders, pipeline state creation, and uniform binding.
class Metal_ShaderProgram : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_ShaderProgram, Metal_Resource)

public:

  //! Create uninitialized shader program.
  //! @param theProxy optional high-level shader program definition
  //! @param theId program identifier for caching
  Standard_EXPORT Metal_ShaderProgram(const occ::handle<Graphic3d_ShaderProgram>& theProxy = nullptr,
                                      const TCollection_AsciiString& theId = "");

  //! Destructor.
  Standard_EXPORT ~Metal_ShaderProgram() override;

  //! Return program identifier.
  const TCollection_AsciiString& Id() const { return myId; }

  //! Return TRUE if program is valid (pipeline created).
  bool IsValid() const { return myRenderPipeline != nullptr || myComputePipeline != nullptr; }

  //! Return estimated GPU memory usage.
  size_t EstimatedDataSize() const override { return 0; }

  //! Return proxy shader program (from application layer).
  const occ::handle<Graphic3d_ShaderProgram>& Proxy() const { return myProxy; }

public: //! @name Shader attachment

  //! Attach vertex shader.
  //! @param theShader compiled vertex shader
  //! @return true on success
  Standard_EXPORT bool AttachVertexShader(const occ::handle<Metal_ShaderObject>& theShader);

  //! Attach fragment shader.
  //! @param theShader compiled fragment shader
  //! @return true on success
  Standard_EXPORT bool AttachFragmentShader(const occ::handle<Metal_ShaderObject>& theShader);

  //! Attach compute shader.
  //! @param theShader compiled compute shader
  //! @return true on success
  Standard_EXPORT bool AttachComputeShader(const occ::handle<Metal_ShaderObject>& theShader);

  //! Return vertex shader.
  const occ::handle<Metal_ShaderObject>& VertexShader() const { return myVertexShader; }

  //! Return fragment shader.
  const occ::handle<Metal_ShaderObject>& FragmentShader() const { return myFragmentShader; }

  //! Return compute shader.
  const occ::handle<Metal_ShaderObject>& ComputeShader() const { return myComputeShader; }

public: //! @name Pipeline creation

  //! Create render pipeline state.
  //! @param theCtx Metal context
  //! @param theColorFormat pixel format for color attachment
  //! @param theDepthFormat pixel format for depth attachment (0 if none)
  //! @param theSampleCount MSAA sample count (1 for no MSAA)
  //! @return true on success
  Standard_EXPORT bool CreateRenderPipeline(Metal_Context* theCtx,
                                            int theColorFormat,
                                            int theDepthFormat,
                                            int theSampleCount = 1);

  //! Create compute pipeline state.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool CreateComputePipeline(Metal_Context* theCtx);

  //! Return link/creation log (errors/warnings).
  const TCollection_AsciiString& LinkLog() const { return myLinkLog; }

public: //! @name Program configuration

  //! Return TRUE if program defines tessellation stage.
  bool HasTessellationStage() const { return myHasTessShader; }

  //! Return maximum number of light sources.
  int NbLightsMax() const { return myNbLightsMax; }

  //! Set maximum number of light sources.
  void SetNbLightsMax(int theCount) { myNbLightsMax = theCount; }

  //! Return number of shadow maps.
  int NbShadowMaps() const { return myNbShadowMaps; }

  //! Set number of shadow maps.
  void SetNbShadowMaps(int theCount) { myNbShadowMaps = theCount; }

  //! Return maximum number of clipping planes.
  int NbClipPlanesMax() const { return myNbClipPlanesMax; }

  //! Set maximum number of clipping planes.
  void SetNbClipPlanesMax(int theCount) { myNbClipPlanesMax = theCount; }

  //! Return number of fragment outputs.
  int NbFragmentOutputs() const { return myNbFragOutputs; }

  //! Set number of fragment outputs.
  void SetNbFragmentOutputs(int theCount) { myNbFragOutputs = theCount; }

  //! Return TRUE if fragment shader performs alpha test.
  bool HasAlphaTest() const { return myHasAlphaTest; }

  //! Set alpha test flag.
  void SetHasAlphaTest(bool theValue) { myHasAlphaTest = theValue; }

  //! Return OIT output mode.
  Graphic3d_RenderTransparentMethod OitOutput() const { return myOitOutput; }

  //! Set OIT output mode.
  void SetOitOutput(Graphic3d_RenderTransparentMethod theMethod) { myOitOutput = theMethod; }

  //! Return texture units declared in program.
  int TextureSetBits() const { return myTextureSetBits; }

  //! Set texture units bits.
  void SetTextureSetBits(int theBits) { myTextureSetBits = theBits; }

public: //! @name State tracking

  //! Return index of last modification for given state type.
  size_t ActiveState(Metal_UniformStateType theType) const
  {
    return theType < Metal_UniformStateType_NB ? myCurrentState[theType] : 0;
  }

  //! Update state index for given type.
  void UpdateState(Metal_UniformStateType theType, size_t theIndex)
  {
    if (theType < Metal_UniformStateType_NB)
    {
      myCurrentState[theType] = theIndex;
    }
  }

public: //! @name Resource management

  //! Release all Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return render pipeline state.
  id<MTLRenderPipelineState> RenderPipeline() const { return myRenderPipeline; }

  //! Return compute pipeline state.
  id<MTLComputePipelineState> ComputePipeline() const { return myComputePipeline; }

  //! Return depth-stencil state.
  id<MTLDepthStencilState> DepthStencilState() const { return myDepthStencilState; }

  //! Set depth-stencil state.
  void SetDepthStencilState(id<MTLDepthStencilState> theState) { myDepthStencilState = theState; }
#endif

protected:

  TCollection_AsciiString myId;        //!< program identifier
  occ::handle<Graphic3d_ShaderProgram> myProxy; //!< high-level program definition

  // Attached shaders
  occ::handle<Metal_ShaderObject> myVertexShader;
  occ::handle<Metal_ShaderObject> myFragmentShader;
  occ::handle<Metal_ShaderObject> myComputeShader;

#ifdef __OBJC__
  id<MTLRenderPipelineState>  myRenderPipeline;   //!< render pipeline state
  id<MTLComputePipelineState> myComputePipeline;  //!< compute pipeline state
  id<MTLDepthStencilState>    myDepthStencilState; //!< depth-stencil state
#else
  void* myRenderPipeline;
  void* myComputePipeline;
  void* myDepthStencilState;
#endif

  TCollection_AsciiString myLinkLog;  //!< pipeline creation log

  // Program configuration
  int  myNbLightsMax;     //!< max light sources
  int  myNbShadowMaps;    //!< shadow map count
  int  myNbClipPlanesMax; //!< max clip planes
  int  myNbFragOutputs;   //!< fragment output count
  int  myTextureSetBits;  //!< texture units
  Graphic3d_RenderTransparentMethod myOitOutput; //!< OIT mode
  bool myHasAlphaTest;    //!< alpha test enabled
  bool myHasTessShader;   //!< has tessellation

  // State tracking
  size_t myCurrentState[Metal_UniformStateType_NB];
};

DEFINE_STANDARD_HANDLE(Metal_ShaderProgram, Metal_Resource)

#endif // Metal_ShaderProgram_HeaderFile
