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

#import <Metal/Metal.h>

#include <Metal_Text.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Text, Standard_Transient)

// =======================================================================
// function : Metal_Text
// purpose  : Constructor
// =======================================================================
Metal_Text::Metal_Text(const occ::handle<Graphic3d_Text>& theTextParams)
: myText(theTextParams),
  myIs2D(false)
{
  //
}

// =======================================================================
// function : ~Metal_Text
// purpose  : Destructor
// =======================================================================
Metal_Text::~Metal_Text()
{
  //
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Text::Release(Metal_Context* /*theCtx*/)
{
  // No GPU resources to release in basic implementation
  // Font texture atlas would be released here
}

// =======================================================================
// function : Render
// purpose  : Render the text
// =======================================================================
void Metal_Text::Render(Metal_Workspace* theWorkspace) const
{
  if (theWorkspace == nullptr || myText.IsNull())
  {
    return;
  }

  // Basic text rendering implementation
  // For full implementation, this would:
  // 1. Get/create font texture atlas for the font
  // 2. Layout glyphs using Font_TextFormatter
  // 3. Generate textured quads for each glyph
  // 4. Render quads with texture atlas sampling

  // For now, we store the text but actual rendering requires
  // font texture atlas support which is a significant undertaking.
  // The structure is in place for future implementation.

  // Get text properties (for future use when implementing full text rendering)
  // const NCollection_String& aString = myText->Text();
  // const gp_Pnt& aPosition = myText->Position();
  // const double aHeight = myText->Height();

  // TODO: Implement full glyph-based text rendering
  // This requires:
  // - Font_FTFont integration for glyph data
  // - Font texture atlas generation and caching
  // - Quad generation for each glyph
  // - Proper text positioning and alignment
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
size_t Metal_Text::EstimatedDataSize() const
{
  // No GPU resources in basic implementation
  return 0;
}
