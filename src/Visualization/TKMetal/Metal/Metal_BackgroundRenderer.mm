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

#include <Metal_BackgroundRenderer.hxx>
#include <Metal_Context.hxx>
#include <Metal_Texture.hxx>
#include <Metal_Workspace.hxx>

// =======================================================================
// function : Render
// purpose  : Render background
// =======================================================================
void Metal_BackgroundRenderer::Render(Metal_Workspace* theWorkspace,
                                       int theWidth,
                                       int theHeight)
{
  if (theWorkspace == nullptr || myFillMethod == FillMethod_None)
  {
    return;
  }

  // Background rendering implementation would go here
  // For now, the clear color handles basic solid backgrounds
  // Full implementation would render a fullscreen quad with:
  // - Solid color shader
  // - Gradient shader (horizontal, vertical, diagonal, corner)
  // - Texture shader (with scale/offset)
  // - Cubemap/skybox shader

  myIsDirty = false;
}

// =======================================================================
// function : Release
// purpose  : Release resources
// =======================================================================
void Metal_BackgroundRenderer::Release(Metal_Context* theCtx)
{
  if (!myTexture.IsNull())
  {
    myTexture->Release(theCtx);
    myTexture.Nullify();
  }
  if (!myCubemap.IsNull())
  {
    myCubemap->Release(theCtx);
    myCubemap.Nullify();
  }
}
