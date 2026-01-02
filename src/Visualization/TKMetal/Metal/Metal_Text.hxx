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
#include <NCollection_Vec3.hxx>

class Metal_Context;
class Metal_Workspace;

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

  //! Render the text.
  Standard_EXPORT void Render(Metal_Workspace* theWorkspace) const;

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const;

protected:

  occ::handle<Graphic3d_Text> myText;  //!< text parameters
  bool myIs2D;                         //!< 2D text flag

};

#endif // Metal_Text_HeaderFile
