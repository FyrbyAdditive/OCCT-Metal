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

#ifndef Metal_Context_HeaderFile
#define Metal_Context_HeaderFile

#include <Aspect_GraphicsLibrary.hxx>
#include <Graphic3d_Camera.hxx>
#include <Graphic3d_DiagnosticInfo.hxx>
#include <Metal_Caps.hxx>
#include <Metal_Resource.hxx>
#include <Message.hxx>
#include <NCollection_DataMap.hxx>
#include <NCollection_IndexedDataMap.hxx>
#include <NCollection_List.hxx>
#include <NCollection_Mat4.hxx>
#include <NCollection_Shared.hxx>
#include <Standard_Transient.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
#import <dispatch/dispatch.h>
@protocol MTLDevice;
@protocol MTLCommandQueue;
@protocol MTLCommandBuffer;
@protocol MTLRenderCommandEncoder;
@protocol MTLLibrary;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
@protocol MTLFunction;
#endif

class Metal_Window;

//! Maximum number of frames that can be in flight simultaneously for triple-buffering.
static const int Metal_MaxFramesInFlight = 3;

//! This class manages the Metal context including device, command queue,
//! and shared resources. It is the central hub for all Metal operations.
class Metal_Context : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Context, Standard_Transient)
  friend class Metal_Window;

public:

  typedef NCollection_Shared<NCollection_DataMap<TCollection_AsciiString, occ::handle<Metal_Resource>>> Metal_ResourcesMap;
  typedef NCollection_Shared<NCollection_List<occ::handle<Metal_Resource>>> Metal_ResourcesList;

public:

  //! Empty constructor. Call Init() to perform initialization.
  //! @param theCaps optional capabilities configuration
  Standard_EXPORT Metal_Context(const occ::handle<Metal_Caps>& theCaps = nullptr);

  //! Destructor.
  Standard_EXPORT ~Metal_Context() override;

  //! Release all resources, including shared ones.
  Standard_EXPORT void forcedRelease();

  //! Share Metal context resources with another context.
  //! @param theShareCtx handle to context to share resources with
  Standard_EXPORT void Share(const occ::handle<Metal_Context>& theShareCtx);

  //! Initialize the Metal context.
  //! @param thePreferLowPower prefer integrated GPU over discrete
  //! @return false if Metal is not available
  Standard_EXPORT bool Init(bool thePreferLowPower = false);

  //! @return true if this context is valid (has been initialized)
  bool IsValid() const { return myIsInitialized; }

  //! Return active graphics library (always Metal).
  Aspect_GraphicsLibrary GraphicsLibrary() const { return Aspect_GraphicsLibrary_Metal; }

  //! Access capabilities.
  const occ::handle<Metal_Caps>& Caps() const { return myCaps; }

  //! Change capabilities (should be done before Init).
  occ::handle<Metal_Caps>& ChangeCaps() { return myCaps; }

  //! Return the messenger instance for logging.
  const occ::handle<Message_Messenger>& Messenger() const { return myMsgContext; }

  //! Set the messenger instance for logging.
  void SetMessenger(const occ::handle<Message_Messenger>& theMsger) { myMsgContext = theMsger; }

public: //! @name Device and command queue access

#ifdef __OBJC__
  //! Return the Metal device.
  id<MTLDevice> Device() const { return myDevice; }

  //! Return the Metal command queue.
  id<MTLCommandQueue> CommandQueue() const { return myCommandQueue; }

  //! Return the default shader library.
  id<MTLLibrary> DefaultLibrary() const { return myDefaultLibrary; }

  //! Create a new command buffer.
  Standard_EXPORT id<MTLCommandBuffer> CreateCommandBuffer();

  //! Return current command buffer (creates one if needed).
  Standard_EXPORT id<MTLCommandBuffer> CurrentCommandBuffer();

  //! Commit the current command buffer and wait for completion.
  Standard_EXPORT void CommitAndWait();

  //! Commit the current command buffer (non-blocking).
  Standard_EXPORT void Commit();

  //! Return default render pipeline state.
  id<MTLRenderPipelineState> DefaultPipeline() const { return myDefaultPipeline; }

  //! Return default depth-stencil state.
  id<MTLDepthStencilState> DefaultDepthStencilState() const { return myDefaultDepthStencilState; }

  //! Return depth-stencil state with depth write disabled (for transparent objects).
  id<MTLDepthStencilState> TransparentDepthStencilState() const { return myTransparentDepthStencilState; }

  //! Return line/edge render pipeline state.
  id<MTLRenderPipelineState> LinePipeline() const { return myLinePipeline; }

  //! Return wireframe render pipeline state (triangles as lines).
  id<MTLRenderPipelineState> WireframePipeline() const { return myWireframePipeline; }

  //! Return blending (transparency) render pipeline state.
  id<MTLRenderPipelineState> BlendingPipeline() const { return myBlendingPipeline; }

  //! Return gradient background render pipeline state.
  id<MTLRenderPipelineState> GradientPipeline() const { return myGradientPipeline; }

  //! Return textured background render pipeline state.
  id<MTLRenderPipelineState> TexturedBackgroundPipeline() const { return myTexturedBackgroundPipeline; }

  //! Initialize default shaders and pipeline.
  Standard_EXPORT bool InitDefaultShaders();
#endif

public: //! @name Device capabilities

  //! Return device name.
  const TCollection_AsciiString& DeviceName() const { return myDeviceName; }

  //! Return maximum texture dimension.
  int MaxTextureSize() const { return myMaxTexDim; }

  //! Return maximum buffer length in bytes.
  size_t MaxBufferLength() const { return myMaxBufferLength; }

  //! Return maximum number of color render targets.
  int MaxColorAttachments() const { return myMaxColorAttachments; }

  //! Return maximum MSAA sample count.
  int MaxMsaaSamples() const { return myMaxMsaaSamples; }

  //! Return true if device supports argument buffers tier 2.
  bool HasArgumentBuffersTier2() const { return myHasArgumentBuffersTier2; }

  //! Return true if device supports ray tracing.
  bool HasRayTracing() const { return myHasRayTracing; }

  //! Check if specific pixel format is supported.
  Standard_EXPORT bool IsFormatSupported(int thePixelFormat) const;

public: //! @name Shared resources

  //! Access shared resource by its name.
  //! @param theKey unique identifier
  //! @return handle to shared resource or NULL
  Standard_EXPORT const occ::handle<Metal_Resource>& GetResource(const TCollection_AsciiString& theKey) const;

  //! Access shared resource by its name with type casting.
  //! @param theKey unique identifier
  //! @param theValue handle to fill
  //! @return true if resource was found
  template <typename TheHandleType>
  bool GetResource(const TCollection_AsciiString& theKey, TheHandleType& theValue) const
  {
    const occ::handle<Metal_Resource>& aResource = GetResource(theKey);
    if (aResource.IsNull())
    {
      return false;
    }
    theValue = TheHandleType::DownCast(aResource);
    return !theValue.IsNull();
  }

  //! Register shared resource.
  //! @param theKey unique identifier
  //! @param theResource resource to register
  //! @return true on success
  Standard_EXPORT bool ShareResource(const TCollection_AsciiString& theKey,
                                     const occ::handle<Metal_Resource>& theResource);

  //! Release shared resource if not used elsewhere.
  //! @param theKey unique identifier
  //! @param theToDelay postpone release until next frame
  Standard_EXPORT void ReleaseResource(const TCollection_AsciiString& theKey,
                                       bool theToDelay = false);

  //! Append resource to queue for delayed clean up.
  template <class T>
  void DelayedRelease(occ::handle<T>& theResource)
  {
    myUnusedResources->Prepend(theResource);
    theResource.Nullify();
  }

  //! Clean up the delayed release queue.
  Standard_EXPORT void ReleaseDelayed();

  //! Return map of shared resources.
  const Metal_ResourcesMap& SharedResources() const { return *mySharedResources; }

public: //! @name Frame management for triple-buffering

  //! Return current frame index (0 to MaxFramesInFlight-1).
  int CurrentFrameIndex() const { return myCurrentFrameIndex; }

  //! Advance to next frame. Should be called at end of frame.
  Standard_EXPORT void AdvanceFrame();

  //! Wait for frame to become available (blocks until GPU finishes).
  Standard_EXPORT void WaitForFrame();

public: //! @name Render state management

  //! Return current depth compare function.
  int DepthFunc() const { return myDepthFunc; }

  //! Set depth compare function.
  Standard_EXPORT void SetDepthFunc(int theFunc);

  //! Return current depth write mask.
  bool DepthMask() const { return myDepthMask; }

  //! Set depth write mask.
  Standard_EXPORT void SetDepthMask(bool theValue);

  //! Return true if blending is enabled.
  bool BlendEnabled() const { return myBlendEnabled; }

  //! Enable or disable blending.
  Standard_EXPORT void SetBlendEnabled(bool theValue);

  //! Set blend function (source and destination factors).
  Standard_EXPORT void SetBlendFunc(int theSrcFactor, int theDstFactor);

  //! Set blend function with separate alpha factors.
  Standard_EXPORT void SetBlendFuncSeparate(int theSrcRGB, int theDstRGB, int theSrcAlpha, int theDstAlpha);

  //! Return true if color mask is enabled.
  bool ColorMask() const { return myColorMask; }

  //! Enable or disable color writing.
  Standard_EXPORT void SetColorMask(bool theValue);

  //! Clear depth buffer.
  Standard_EXPORT void ClearDepth();

  //! Clear color buffer with specified color.
  Standard_EXPORT void ClearColor(float theR, float theG, float theB, float theA);

  //! Bind shader program (nullptr to unbind).
  Standard_EXPORT void BindProgram(void* theProgram);

  //! Return the camera.
  const occ::handle<Graphic3d_Camera>& Camera() const { return myCamera; }

  //! Set the camera.
  void SetCamera(const occ::handle<Graphic3d_Camera>& theCamera) { myCamera = theCamera; }

  //! Return shader manager.
  class Metal_ShaderManager* ShaderManager() const { return myShaderManager; }

  //! Set shader manager.
  void SetShaderManager(class Metal_ShaderManager* theManager) { myShaderManager = theManager; }

  //! Return frame statistics.
  const occ::handle<class Metal_FrameStats>& FrameStats() const { return myFrameStats; }

  //! Set frame statistics object.
  void SetFrameStats(const occ::handle<class Metal_FrameStats>& theStats) { myFrameStats = theStats; }

public: //! @name State classes for tracking matrix state

  //! Matrix state template for model/view/projection matrices.
  template<typename T>
  class MatrixState
  {
  public:
    MatrixState() : myRevision(0) { myCurrent.InitIdentity(); }
    const T& Current() const { return myCurrent; }
    void SetCurrent(const T& theMat) { myCurrent = theMat; ++myRevision; }
    size_t Revision() const { return myRevision; }
  private:
    T myCurrent;
    size_t myRevision;
  };

  MatrixState<NCollection_Mat4<float>> WorldViewState;   //!< world-view matrix state
  MatrixState<NCollection_Mat4<float>> ProjectionState;  //!< projection matrix state
  MatrixState<NCollection_Mat4<float>> ModelWorldState;  //!< model-world matrix state

  //! Return current viewport (x, y, width, height).
  const int* Viewport() const { return myViewport; }

  //! Set current viewport.
  void SetViewport(int theX, int theY, int theWidth, int theHeight)
  {
    myViewport[0] = theX;
    myViewport[1] = theY;
    myViewport[2] = theWidth;
    myViewport[3] = theHeight;
  }

public: //! @name Diagnostics

  //! Fill in the dictionary with Metal device info.
  Standard_EXPORT void DiagnosticInformation(
    NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict,
    Graphic3d_DiagnosticInfo theFlags) const;

  //! Return memory info string.
  Standard_EXPORT TCollection_AsciiString MemoryInfo() const;

private:

  //! Query device capabilities.
  void queryDeviceCaps();

private:

#ifdef __OBJC__
  id<MTLDevice>              myDevice;                   //!< Metal device
  id<MTLCommandQueue>        myCommandQueue;             //!< Command queue
  id<MTLLibrary>             myDefaultLibrary;           //!< Default shader library
  id<MTLCommandBuffer>       myCurrentCmdBuffer;         //!< Current command buffer
  id<MTLRenderPipelineState> myDefaultPipeline;          //!< Default render pipeline
  id<MTLRenderPipelineState> myLinePipeline;             //!< Line/edge render pipeline
  id<MTLRenderPipelineState> myWireframePipeline;        //!< Wireframe render pipeline
  id<MTLRenderPipelineState> myBlendingPipeline;         //!< Blending (transparency) pipeline
  id<MTLRenderPipelineState> myGradientPipeline;         //!< Gradient background pipeline
  id<MTLRenderPipelineState> myTexturedBackgroundPipeline;   //!< Textured background pipeline
  id<MTLDepthStencilState>   myDefaultDepthStencilState;     //!< Default depth-stencil state
  id<MTLDepthStencilState>   myTransparentDepthStencilState; //!< Depth-stencil for transparent objects
  dispatch_semaphore_t       myFrameSemaphore;           //!< Semaphore for triple-buffering
#else
  void*                myDevice;
  void*                myCommandQueue;
  void*                myDefaultLibrary;
  void*                myCurrentCmdBuffer;
  void*                myDefaultPipeline;
  void*                myLinePipeline;
  void*                myWireframePipeline;
  void*                myBlendingPipeline;
  void*                myGradientPipeline;
  void*                myTexturedBackgroundPipeline;
  void*                myDefaultDepthStencilState;
  void*                myTransparentDepthStencilState;
  void*                myFrameSemaphore;
#endif

  occ::handle<Metal_Caps>      myCaps;            //!< Capabilities configuration
  occ::handle<Message_Messenger> myMsgContext;   //!< Messenger for logging
  occ::handle<Metal_ResourcesMap> mySharedResources; //!< Shared resources map
  occ::handle<Metal_ResourcesList> myUnusedResources; //!< Delayed release queue

  TCollection_AsciiString myDeviceName;           //!< Device name
  int                     myMaxTexDim;            //!< Max texture dimension
  size_t                  myMaxBufferLength;      //!< Max buffer size
  int                     myMaxColorAttachments;  //!< Max color attachments
  int                     myMaxMsaaSamples;       //!< Max MSAA samples
  bool                    myHasArgumentBuffersTier2; //!< Argument buffers tier 2 support
  bool                    myHasRayTracing;        //!< Ray tracing support
  bool                    myIsInitialized;        //!< Initialization flag
  int                     myCurrentFrameIndex;    //!< Current frame for triple-buffering

  // Render state
  int                     myDepthFunc;            //!< Current depth compare function
  bool                    myDepthMask;            //!< Current depth write mask
  bool                    myBlendEnabled;         //!< Blending enabled flag
  int                     myBlendSrcRGB;          //!< Blend source RGB factor
  int                     myBlendDstRGB;          //!< Blend destination RGB factor
  int                     myBlendSrcAlpha;        //!< Blend source alpha factor
  int                     myBlendDstAlpha;        //!< Blend destination alpha factor
  bool                    myColorMask;            //!< Color write mask
  int                     myViewport[4];          //!< Current viewport (x, y, width, height)

  occ::handle<Graphic3d_Camera> myCamera;         //!< Current camera
  class Metal_ShaderManager* myShaderManager;     //!< Shader manager
  occ::handle<class Metal_FrameStats> myFrameStats; //!< Frame statistics
};

#endif // Metal_Context_HeaderFile
