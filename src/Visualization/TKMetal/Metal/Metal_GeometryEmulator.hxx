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

#ifndef Metal_GeometryEmulator_HeaderFile
#define Metal_GeometryEmulator_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <NCollection_Vec4.hxx>

#ifdef __OBJC__
@protocol MTLDevice;
@protocol MTLBuffer;
@protocol MTLCommandBuffer;
@protocol MTLComputePipelineState;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
@protocol MTLLibrary;
#endif

class Metal_Context;

//! Wireframe rendering mode.
enum Metal_WireframeMode
{
  Metal_WireframeMode_Overlay,   //!< Wireframe over solid shading
  Metal_WireframeMode_Only,      //!< Wireframe only (transparent fill)
  Metal_WireframeMode_Hidden     //!< Hidden-line removal style
};

//! Wireframe parameters.
struct Metal_WireframeParams
{
  float WireColor[4];   //!< Wireframe line color (RGBA)
  float FillColor[4];   //!< Solid fill color (RGBA)
  float LineWidth;      //!< Line width in pixels
  float Feather;        //!< Edge feathering for anti-aliasing
  float Viewport[2];    //!< Viewport size (width, height)

  //! Default constructor with reasonable defaults.
  Metal_WireframeParams()
  {
    WireColor[0] = 1.0f; WireColor[1] = 1.0f;
    WireColor[2] = 1.0f; WireColor[3] = 1.0f;
    FillColor[0] = 0.5f; FillColor[1] = 0.5f;
    FillColor[2] = 0.8f; FillColor[3] = 1.0f;
    LineWidth = 1.5f;
    Feather = 1.0f;
    Viewport[0] = 800.0f;
    Viewport[1] = 600.0f;
  }
};

//! Geometry shader emulator for Metal.
//! Provides wireframe/mesh edges rendering using compute-based edge distance calculation.
//! This emulates OpenGL geometry shader functionality for Graphic3d_ShaderFlags_MeshEdges.
class Metal_GeometryEmulator : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_GeometryEmulator, Standard_Transient)

public:

  //! Create geometry emulator.
  //! @param[in] theCtx Metal context
  Standard_EXPORT Metal_GeometryEmulator(Metal_Context* theCtx);

  //! Destructor.
  Standard_EXPORT ~Metal_GeometryEmulator();

  //! Release all GPU resources.
  Standard_EXPORT void Release();

  //! Check if emulator is valid and ready to use.
  Standard_EXPORT bool IsValid() const { return myIsValid; }

  //! Process triangle mesh to compute edge distances.
  //! This runs a compute shader that outputs processed vertices ready for wireframe rendering.
  //! @param[in] theCmdBuf      command buffer
  //! @param[in] theVertices    vertex buffer (position + normal, 24 bytes per vertex)
  //! @param[in] theIndices     index buffer (triangles, 3 indices per triangle)
  //! @param[in] theTriangleCount number of triangles
  //! @param[in] theUniforms    transform uniforms buffer
  //! @param[in] theViewportWidth  viewport width
  //! @param[in] theViewportHeight viewport height
  //! @return true on success
  Standard_EXPORT bool Process(
#ifdef __OBJC__
    id<MTLCommandBuffer> theCmdBuf,
    id<MTLBuffer> theVertices,
    id<MTLBuffer> theIndices,
#else
    void* theCmdBuf,
    void* theVertices,
    void* theIndices,
#endif
    int theTriangleCount,
#ifdef __OBJC__
    id<MTLBuffer> theUniforms,
#else
    void* theUniforms,
#endif
    float theViewportWidth,
    float theViewportHeight);

  //! Get processed vertex buffer (output from compute shader).
  //! This buffer contains positions with edge distances, ready for wireframe rendering.
#ifdef __OBJC__
  id<MTLBuffer> ProcessedVertexBuffer() const { return myProcessedVertexBuffer; }
#else
  void* ProcessedVertexBuffer() const { return myProcessedVertexBuffer; }
#endif

  //! Get number of processed vertices (3 * triangle count).
  int ProcessedVertexCount() const { return myProcessedVertexCount; }

  //! Get wireframe render pipeline for specified mode.
#ifdef __OBJC__
  id<MTLRenderPipelineState> WireframePipeline(Metal_WireframeMode theMode) const;
#else
  void* WireframePipeline(Metal_WireframeMode theMode) const;
#endif

  //! Get depth stencil state for wireframe rendering.
#ifdef __OBJC__
  id<MTLDepthStencilState> DepthStencilState() const { return myDepthStencilState; }
#else
  void* DepthStencilState() const { return myDepthStencilState; }
#endif

  //! Set wireframe parameters.
  void SetWireframeParams(const Metal_WireframeParams& theParams) { myWireParams = theParams; }

  //! Get wireframe parameters.
  const Metal_WireframeParams& WireframeParams() const { return myWireParams; }

  //! Set wireframe color.
  void SetWireColor(float theR, float theG, float theB, float theA = 1.0f)
  {
    myWireParams.WireColor[0] = theR;
    myWireParams.WireColor[1] = theG;
    myWireParams.WireColor[2] = theB;
    myWireParams.WireColor[3] = theA;
  }

  //! Set fill color.
  void SetFillColor(float theR, float theG, float theB, float theA = 1.0f)
  {
    myWireParams.FillColor[0] = theR;
    myWireParams.FillColor[1] = theG;
    myWireParams.FillColor[2] = theB;
    myWireParams.FillColor[3] = theA;
  }

  //! Set line width in pixels.
  void SetLineWidth(float theWidth) { myWireParams.LineWidth = theWidth; }

  //! Set edge feathering amount for anti-aliasing.
  void SetFeather(float theFeather) { myWireParams.Feather = theFeather; }

protected:

  //! Initialize compute and render pipelines.
  bool initPipelines();

  //! Ensure processed vertex buffer is large enough.
  bool ensureProcessedBuffer(int theVertexCount);

protected:

  Metal_Context* myContext;           //!< Metal context
  Metal_WireframeParams myWireParams; //!< Wireframe rendering parameters
  int myProcessedVertexCount;         //!< Number of processed vertices
  int myProcessedBufferCapacity;      //!< Current buffer capacity in vertices
  bool myIsValid;                     //!< Initialization status

#ifdef __OBJC__
  id<MTLComputePipelineState> myComputePipeline;    //!< Edge distance compute pipeline
  id<MTLRenderPipelineState> myOverlayPipeline;     //!< Wireframe overlay render pipeline
  id<MTLRenderPipelineState> myOnlyPipeline;        //!< Wireframe-only render pipeline
  id<MTLRenderPipelineState> myHiddenPipeline;      //!< Hidden-line render pipeline
  id<MTLDepthStencilState> myDepthStencilState;     //!< Depth stencil state
  id<MTLBuffer> myProcessedVertexBuffer;            //!< Output buffer from compute shader
  id<MTLBuffer> myViewportBuffer;                   //!< Viewport size uniform buffer
#else
  void* myComputePipeline;
  void* myOverlayPipeline;
  void* myOnlyPipeline;
  void* myHiddenPipeline;
  void* myDepthStencilState;
  void* myProcessedVertexBuffer;
  void* myViewportBuffer;
#endif
};

DEFINE_STANDARD_HANDLE(Metal_GeometryEmulator, Standard_Transient)

#endif // Metal_GeometryEmulator_HeaderFile
