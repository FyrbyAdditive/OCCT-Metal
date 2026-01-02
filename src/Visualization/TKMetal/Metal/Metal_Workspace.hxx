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
#include <NCollection_Mat4.hxx>
#include <Quantity_ColorRGBA.hxx>

#ifdef __OBJC__
@protocol MTLRenderCommandEncoder;
@protocol MTLRenderPipelineState;
@protocol MTLDepthStencilState;
#endif

class Metal_Context;
class Metal_View;

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
};

#endif // Metal_Workspace_HeaderFile
