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

#ifndef Metal_Text_HeaderFile
#define Metal_Text_HeaderFile

#include <Standard_Transient.hxx>
#include <Graphic3d_Text.hxx>
#include <Graphic3d_Aspects.hxx>
#include <Font_Rect.hxx>
#include <Font_Hinting.hxx>
#include <NCollection_Mat4.hxx>
#include <NCollection_Vec3.hxx>
#include <NCollection_Vec4.hxx>
#include <NCollection_Vector.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
#endif

class Metal_Context;
class Metal_Workspace;
class Metal_Font;
class Metal_VertexBuffer;

//! Text rendering element for Metal.
//! Stores text parameters and renders text using font texture atlas.
class Metal_Text : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Text, Standard_Transient)

public:

  //! Create text element from text parameters.
  Standard_EXPORT Metal_Text(const occ::handle<Graphic3d_Text>& theTextParams);

  //! Destructor.
  Standard_EXPORT ~Metal_Text();

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return text parameters.
  const occ::handle<Graphic3d_Text>& Text() const { return myText; }

  //! Set text parameters.
  void SetText(const occ::handle<Graphic3d_Text>& theText) { myText = theText; }

  //! Return true if text is 2D (screen-space).
  bool Is2D() const { return myIs2D; }

  //! Set 2D mode.
  void Set2D(bool theValue) { myIs2D = theValue; }

  //! Set position.
  void SetPosition(const NCollection_Vec3<float>& thePoint);

  //! Render the text.
  Standard_EXPORT void Render(Metal_Workspace* theWorkspace) const;

  //! Render with explicit aspect and colors.
  Standard_EXPORT void Render(Metal_Context* theCtx,
                              const Graphic3d_Aspects& theAspect,
                              unsigned int theResolution,
                              Font_Hinting theFontHinting) const;

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const;

  //! Compute text string dimensions.
  Standard_EXPORT static void StringSize(Metal_Context* theCtx,
                                          const NCollection_String& theText,
                                          const Graphic3d_Aspects& theAspect,
                                          float theHeight,
                                          unsigned int theResolution,
                                          Font_Hinting theFontHinting,
                                          float& theWidth,
                                          float& theAscent,
                                          float& theDescent);

protected:

  //! Render implementation with given colors.
  Standard_EXPORT void render(Metal_Workspace* theWorkspace,
                               const Graphic3d_Aspects& theAspect,
                               const NCollection_Vec4<float>& theColorText,
                               const NCollection_Vec4<float>& theColorSubs,
                               unsigned int theResolution,
                               Font_Hinting theFontHinting) const;

  //! Draw text quads using render encoder from workspace.
  Standard_EXPORT void drawText(Metal_Workspace* theWorkspace,
                                 const Graphic3d_Aspects& theAspect,
                                 const NCollection_Vec4<float>& theColor) const;

  //! Draw background rectangle using render encoder from workspace.
  Standard_EXPORT void drawRect(Metal_Workspace* theWorkspace,
                                 const Graphic3d_Aspects& theAspect,
                                 const NCollection_Vec4<float>& theColor) const;

  //! Draw text glyphs with pixel offset for shadow effects.
  //! @param theWorkspace workspace with render encoder
  //! @param theAspect aspects
  //! @param theColor text color
  //! @param theOffset pixel offset (x, y, 0)
  Standard_EXPORT void drawTextWithOffset(Metal_Workspace* theWorkspace,
                                           const Graphic3d_Aspects& theAspect,
                                           const NCollection_Vec4<float>& theColor,
                                           const NCollection_Vec3<float>& theOffset) const;

  //! Setup model-view matrix for text positioning.
  //! @param theWorkspace workspace for matrix state
  //! @param theAspect aspects
  //! @param theOffset pixel offset for shadow effects
  Standard_EXPORT void setupMatrix(Metal_Workspace* theWorkspace,
                                    const Graphic3d_Aspects& theAspect,
                                    const NCollection_Vec3<float>& theOffset) const;

  //! Find or create font for rendering.
  Standard_EXPORT static occ::handle<Metal_Font> FindFont(Metal_Context* theCtx,
                                                           const Graphic3d_Aspects& theAspect,
                                                           int theHeight,
                                                           unsigned int theResolution,
                                                           Font_Hinting theFontHinting);

  //! Generate font resource key.
  Standard_EXPORT static TCollection_AsciiString FontKey(const Graphic3d_Aspects& theAspect,
                                                          int theHeight,
                                                          unsigned int theResolution,
                                                          Font_Hinting theFontHinting);

protected:

  occ::handle<Graphic3d_Text> myText;  //!< text parameters
  bool myIs2D;                         //!< 2D text flag
  mutable float myScaleHeight;         //!< scale factor for constant height

  //! GPU resources - mutable for lazy initialization during const Render()
  mutable occ::handle<Metal_Font> myFont; //!< font with texture atlas

  //! Per-texture vertex data
#ifdef __OBJC__
  mutable NCollection_Vector<id<MTLBuffer>> myVertsBuffers; //!< vertex position buffers
  mutable NCollection_Vector<id<MTLBuffer>> myTCrdsBuffers; //!< texture coordinate buffers
  mutable id<MTLBuffer> myBndVertsBuffer;                   //!< background quad buffer
#else
  mutable NCollection_Vector<void*> myVertsBuffers;
  mutable NCollection_Vector<void*> myTCrdsBuffers;
  mutable void* myBndVertsBuffer;
#endif
  mutable NCollection_Vector<int> myTextureIndices; //!< texture indices for each buffer
  mutable Font_Rect myBndBox;                        //!< bounding box for background

  //! Transform matrices (mutable for Render const)
  mutable NCollection_Mat4<double> myProjMatrix;        //!< projection matrix
  mutable NCollection_Mat4<double> myOrientationMatrix; //!< orientation matrix
  mutable NCollection_Mat4<double> myModelMatrix;       //!< model-view matrix
  mutable NCollection_Vec3<double> myWinXYZ;            //!< window coordinates
  mutable NCollection_Vec3<float> myTextOffset;         //!< current pixel offset for shadow rendering

};

#endif // Metal_Text_HeaderFile
