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

#ifndef Metal_Workspace_HeaderFile
#define Metal_Workspace_HeaderFile

#include <Standard_Transient.hxx>
#include <Graphic3d_Aspects.hxx>
#include <Graphic3d_LightSet.hxx>
#include <Graphic3d_TypeOfShadingModel.hxx>
#include <Graphic3d_SequenceOfHClipPlane.hxx>
#include <NCollection_Mat4.hxx>
#include <Quantity_ColorRGBA.hxx>

#ifdef __OBJC__
@protocol MTLRenderCommandEncoder;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
#endif

class Metal_Context;
class Metal_View;
class Metal_ShaderManager;
class Metal_Clipping;

//! Workspace for Metal rendering state management.
//! Holds current render encoder and manages shader state.
class Metal_Workspace : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Workspace, Standard_Transient)

public:

  //! Create workspace.
  Standard_EXPORT Metal_Workspace(Metal_Context* theCtx, Metal_View* theView);

  //! Destructor.
  Standard_EXPORT ~Metal_Workspace();

  //! Return Metal context.
  Metal_Context* Context() const { return myContext; }

  //! Return associated view.
  Metal_View* View() const { return myView; }

  //! Set current render command encoder.
  Standard_EXPORT void SetEncoder(
#ifdef __OBJC__
    id<MTLRenderCommandEncoder> theEncoder
#else
    void* theEncoder
#endif
  );

#ifdef __OBJC__
  //! Return current render command encoder.
  id<MTLRenderCommandEncoder> ActiveEncoder() const { return myEncoder; }
#endif

  //! Set current aspect.
  Standard_EXPORT void SetAspect(const occ::handle<Graphic3d_Aspects>& theAspect);

  //! Return current aspect.
  const occ::handle<Graphic3d_Aspects>& Aspect() const { return myAspect; }

  //! Set model-view matrix.
  void SetModelMatrix(const NCollection_Mat4<float>& theMat) { myModelMatrix = theMat; }

  //! Return model-view matrix.
  const NCollection_Mat4<float>& ModelMatrix() const { return myModelMatrix; }

  //! Set projection matrix.
  void SetProjectionMatrix(const NCollection_Mat4<float>& theMat) { myProjectionMatrix = theMat; }

  //! Return projection matrix.
  const NCollection_Mat4<float>& ProjectionMatrix() const { return myProjectionMatrix; }

  //! Apply current pipeline state to encoder.
  Standard_EXPORT void ApplyPipelineState();

  //! Apply current uniform data (matrices, colors) to encoder.
  Standard_EXPORT void ApplyUniforms();

  //! Return highlight color (for highlighted objects).
  const Quantity_ColorRGBA& HighlightColor() const { return myHighlightColor; }

  //! Set highlight color.
  void SetHighlightColor(const Quantity_ColorRGBA& theColor) { myHighlightColor = theColor; }

  //! Return true if currently rendering highlighted object.
  bool IsHighlighting() const { return myIsHighlighting; }

  //! Set highlighting mode.
  void SetHighlighting(bool theValue) { myIsHighlighting = theValue; }

  //! Return shader manager.
  Metal_ShaderManager* ShaderManager() const { return myShaderManager; }

  //! Set shader manager.
  void SetShaderManager(Metal_ShaderManager* theManager) { myShaderManager = theManager; }

  //! Return clipping manager.
  Metal_Clipping* Clipping() const { return myClipping; }

  //! Set clipping manager.
  void SetClipping(Metal_Clipping* theClipping) { myClipping = theClipping; }

  //! Update light sources for rendering.
  Standard_EXPORT void SetLightSources(const occ::handle<Graphic3d_LightSet>& theLights);

  //! Update clipping planes for rendering.
  Standard_EXPORT void SetClippingPlanes(const Graphic3d_SequenceOfHClipPlane& thePlanes);

  //! Return current shading model.
  Graphic3d_TypeOfShadingModel ShadingModel() const { return myShadingModel; }

  //! Set shading model.
  void SetShadingModel(Graphic3d_TypeOfShadingModel theModel) { myShadingModel = theModel; }

  //! Apply lighting uniforms to encoder.
  Standard_EXPORT void ApplyLightingUniforms();

  //! Apply clipping uniforms to encoder.
  Standard_EXPORT void ApplyClippingUniforms();

  //! Set edge rendering mode.
  void SetEdgeRendering(bool theValue) { myIsEdgeRendering = theValue; }

  //! Return true if currently rendering edges.
  bool IsEdgeRendering() const { return myIsEdgeRendering; }

  //! Set edge color for rendering.
  void SetEdgeColor(const Quantity_ColorRGBA& theColor) { myEdgeColor = theColor; }

  //! Return edge color.
  const Quantity_ColorRGBA& EdgeColor() const { return myEdgeColor; }

  //! Apply edge uniforms (uses edge color instead of face color).
  Standard_EXPORT void ApplyEdgeUniforms();

  //! Set wireframe rendering mode (triangles rendered as lines).
  void SetWireframeMode(bool theValue) { myIsWireframeMode = theValue; }

  //! Return true if wireframe mode is active.
  bool IsWireframeMode() const { return myIsWireframeMode; }

  //! Apply pipeline state for edge/line rendering.
  Standard_EXPORT void ApplyEdgePipelineState();

  //! Set transparent/blending rendering mode.
  void SetTransparentMode(bool theValue) { myIsTransparentMode = theValue; }

  //! Return true if transparent mode is active.
  bool IsTransparentMode() const { return myIsTransparentMode; }

  //! Apply pipeline state for transparent objects (alpha blending enabled, depth write disabled).
  Standard_EXPORT void ApplyBlendingPipelineState();

  //! Return depth-stencil state with depth write disabled (for transparent objects).
  Standard_EXPORT void ApplyTransparentDepthState();

protected:

  Metal_Context* myContext;      //!< Metal context
  Metal_View*    myView;         //!< associated view

#ifdef __OBJC__
  id<MTLRenderCommandEncoder>  myEncoder;            //!< current render encoder
  id<MTLRenderPipelineState>   myCurrentPipeline;    //!< current pipeline state
  id<MTLDepthStencilState>     myDepthStencilState;  //!< depth-stencil state
#else
  void* myEncoder;
  void* myCurrentPipeline;
  void* myDepthStencilState;
#endif

  occ::handle<Graphic3d_Aspects> myAspect;           //!< current aspect
  NCollection_Mat4<float>        myModelMatrix;      //!< model-view matrix
  NCollection_Mat4<float>        myProjectionMatrix; //!< projection matrix
  Quantity_ColorRGBA             myHighlightColor;   //!< highlight color
  bool                           myIsHighlighting;   //!< highlighting mode flag

  Quantity_ColorRGBA             myEdgeColor;        //!< edge color for edge rendering
  bool                           myIsEdgeRendering;  //!< edge rendering mode flag
  bool                           myIsWireframeMode;  //!< wireframe mode flag
  bool                           myIsTransparentMode; //!< transparent/blending mode flag

  Metal_ShaderManager*           myShaderManager;    //!< shader manager
  Metal_Clipping*                myClipping;         //!< clipping manager
  Graphic3d_TypeOfShadingModel   myShadingModel;     //!< current shading model
  occ::handle<Graphic3d_LightSet> myLightSources;    //!< current light sources
};

#endif // Metal_Workspace_HeaderFile
