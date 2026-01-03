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

#include <Metal_TextureSet.hxx>
#include <Metal_Texture.hxx>
#include <Metal_Sampler.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_TextureSet, Standard_Transient)

// =======================================================================
// function : Metal_TextureSet
// purpose  : Default constructor
// =======================================================================
Metal_TextureSet::Metal_TextureSet()
: myTextureSetBits(Graphic3d_TextureSetBits_NONE)
{
  //
}

// =======================================================================
// function : Metal_TextureSet
// purpose  : Constructor with pre-allocated size
// =======================================================================
Metal_TextureSet::Metal_TextureSet(int theNbTextures)
: myTextures(0, theNbTextures - 1),
  myTextureSetBits(Graphic3d_TextureSetBits_NONE)
{
  //
}

// =======================================================================
// function : Metal_TextureSet
// purpose  : Constructor for a single texture
// =======================================================================
Metal_TextureSet::Metal_TextureSet(const occ::handle<Metal_Texture>& theTexture,
                                   Graphic3d_TextureUnit theUnit)
: myTextures(0, 0),
  myTextureSetBits(Graphic3d_TextureSetBits_NONE)
{
  if (!theTexture.IsNull())
  {
    myTextures.ChangeFirst().Texture = theTexture;
    myTextures.ChangeFirst().Unit = theUnit;
    myTextureSetBits |= Graphic3d_TextureSetBits_BaseColor;
  }
}

// =======================================================================
// function : IsModulate
// purpose  : Return TRUE if texture color modulation is enabled
// =======================================================================
bool Metal_TextureSet::IsModulate() const
{
  // For Metal, we always modulate unless specifically configured otherwise
  // The texture parameters would indicate modulation mode
  return myTextures.IsEmpty() || myTextures.First().Texture.IsNull();
}

// =======================================================================
// function : HasNonPointSprite
// purpose  : Check for non-point-sprite textures
// =======================================================================
bool Metal_TextureSet::HasNonPointSprite() const
{
  if (myTextures.IsEmpty())
  {
    return false;
  }
  // Check if first texture exists and is not a point sprite.
  // Point sprite textures are stored last in the texture set.
  // Non-empty set with valid first texture = has non-point-sprite.
  return !myTextures.First().Texture.IsNull();
}

// =======================================================================
// function : HasPointSprite
// purpose  : Check if texture set includes a point sprite
// =======================================================================
bool Metal_TextureSet::HasPointSprite() const
{
  // Point sprite textures are stored as the last texture in the set.
  // Currently Metal_PointSprite provides marker textures but they are
  // rendered separately via point primitive rendering, not through
  // the texture set mechanism. This method returns false as texture sets
  // don't store point sprite references directly.
  // See Metal_PointSprite and Metal_PointSpriteCache for point rendering.
  return false;
}
