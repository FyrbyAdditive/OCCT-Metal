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

#ifndef Metal_TextureSet_HeaderFile
#define Metal_TextureSet_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <NCollection_Array1.hxx>
#include <Graphic3d_TextureUnit.hxx>
#include <Graphic3d_TextureSet.hxx>
#include <Graphic3d_TextureSetBits.hxx>

class Metal_Texture;
class Metal_Sampler;

//! Class holding array of textures to be mapped as a set.
//! Manages Metal textures with their associated samplers and texture units.
//! Textures should be defined in ascending order of texture units within the set.
class Metal_TextureSet : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_TextureSet, Standard_Transient)

public:

  //! Texture slot - combination of Texture, Sampler and binding Unit.
  struct TextureSlot
  {
    occ::handle<Metal_Texture> Texture;  //!< Metal texture
    occ::handle<Metal_Sampler> Sampler;  //!< Metal sampler state
    Graphic3d_TextureUnit      Unit;     //!< Texture unit for binding

    //! Implicit conversion to texture handle.
    operator const occ::handle<Metal_Texture>&() const { return Texture; }

    //! Implicit conversion to texture handle.
    operator occ::handle<Metal_Texture>&() { return Texture; }

    //! Default constructor.
    TextureSlot()
    : Unit(Graphic3d_TextureUnit_0)
    {
    }
  };

  //! Class for iterating texture set.
  class Iterator : public NCollection_Array1<TextureSlot>::Iterator
  {
  public:

    //! Empty constructor.
    Iterator() = default;

    //! Constructor.
    Iterator(const occ::handle<Metal_TextureSet>& theSet)
    {
      if (!theSet.IsNull())
      {
        NCollection_Array1<TextureSlot>::Iterator::Init(theSet->myTextures);
      }
    }

    //! Access texture.
    const occ::handle<Metal_Texture>& Value() const
    {
      return NCollection_Array1<TextureSlot>::Iterator::Value().Texture;
    }

    //! Access texture (mutable).
    occ::handle<Metal_Texture>& ChangeValue()
    {
      return NCollection_Array1<TextureSlot>::Iterator::ChangeValue().Texture;
    }

    //! Access sampler.
    const occ::handle<Metal_Sampler>& Sampler() const
    {
      return NCollection_Array1<TextureSlot>::Iterator::Value().Sampler;
    }

    //! Access sampler (mutable).
    occ::handle<Metal_Sampler>& ChangeSampler()
    {
      return NCollection_Array1<TextureSlot>::Iterator::ChangeValue().Sampler;
    }

    //! Access texture unit.
    Graphic3d_TextureUnit Unit() const
    {
      return NCollection_Array1<TextureSlot>::Iterator::Value().Unit;
    }

    //! Access texture unit (mutable).
    Graphic3d_TextureUnit& ChangeUnit()
    {
      return NCollection_Array1<TextureSlot>::Iterator::ChangeValue().Unit;
    }
  };

public:

  //! Empty constructor.
  Standard_EXPORT Metal_TextureSet();

  //! Constructor with pre-allocated size.
  //! @param theNbTextures number of texture slots to allocate
  Standard_EXPORT Metal_TextureSet(int theNbTextures);

  //! Constructor for a single texture.
  //! @param theTexture texture to store
  //! @param theUnit texture unit for binding
  Standard_EXPORT Metal_TextureSet(const occ::handle<Metal_Texture>& theTexture,
                                   Graphic3d_TextureUnit theUnit = Graphic3d_TextureUnit_0);

  //! Return texture units declared within the program.
  //! @sa Graphic3d_TextureSetBits
  int TextureSetBits() const { return myTextureSetBits; }

  //! Return texture units declared within the program (mutable).
  //! @sa Graphic3d_TextureSetBits
  int& ChangeTextureSetBits() { return myTextureSetBits; }

  //! Return TRUE if texture array is empty.
  bool IsEmpty() const { return myTextures.IsEmpty(); }

  //! Return number of textures.
  int Size() const { return myTextures.Size(); }

  //! Return the lower index in texture set.
  int Lower() const { return myTextures.Lower(); }

  //! Return the upper index in texture set.
  int Upper() const { return myTextures.Upper(); }

  //! Return the first texture.
  const occ::handle<Metal_Texture>& First() const { return myTextures.First().Texture; }

  //! Return the first texture (mutable).
  occ::handle<Metal_Texture>& ChangeFirst() { return myTextures.ChangeFirst().Texture; }

  //! Return the first texture unit.
  Graphic3d_TextureUnit FirstUnit() const { return myTextures.First().Unit; }

  //! Return the first sampler.
  const occ::handle<Metal_Sampler>& FirstSampler() const { return myTextures.First().Sampler; }

  //! Return the first sampler (mutable).
  occ::handle<Metal_Sampler>& ChangeFirstSampler() { return myTextures.ChangeFirst().Sampler; }

  //! Return the last texture.
  const occ::handle<Metal_Texture>& Last() const { return myTextures.Last().Texture; }

  //! Return the last texture (mutable).
  occ::handle<Metal_Texture>& ChangeLast() { return myTextures.ChangeLast().Texture; }

  //! Return the last texture unit.
  Graphic3d_TextureUnit LastUnit() const { return myTextures.Last().Unit; }

  //! Return the last texture unit (mutable).
  Graphic3d_TextureUnit& ChangeLastUnit() { return myTextures.ChangeLast().Unit; }

  //! Return the last sampler.
  const occ::handle<Metal_Sampler>& LastSampler() const { return myTextures.Last().Sampler; }

  //! Return the last sampler (mutable).
  occ::handle<Metal_Sampler>& ChangeLastSampler() { return myTextures.ChangeLast().Sampler; }

  //! Return the texture at specified position within [0, Size()) range.
  const occ::handle<Metal_Texture>& Value(int theIndex) const
  {
    return myTextures.Value(theIndex).Texture;
  }

  //! Return the texture at specified position within [0, Size()) range (mutable).
  occ::handle<Metal_Texture>& ChangeValue(int theIndex)
  {
    return myTextures.ChangeValue(theIndex).Texture;
  }

  //! Return the sampler at specified position within [0, Size()) range.
  const occ::handle<Metal_Sampler>& GetSampler(int theIndex) const
  {
    return myTextures.Value(theIndex).Sampler;
  }

  //! Return the sampler at specified position within [0, Size()) range (mutable).
  occ::handle<Metal_Sampler>& ChangeSampler(int theIndex)
  {
    return myTextures.ChangeValue(theIndex).Sampler;
  }

  //! Return the texture unit at specified position within [0, Size()) range.
  Graphic3d_TextureUnit GetUnit(int theIndex) const
  {
    return myTextures.Value(theIndex).Unit;
  }

  //! Return the texture unit at specified position (mutable).
  Graphic3d_TextureUnit& ChangeUnit(int theIndex)
  {
    return myTextures.ChangeValue(theIndex).Unit;
  }

  //! Return the full texture slot at specified position.
  const TextureSlot& GetSlot(int theIndex) const
  {
    return myTextures.Value(theIndex);
  }

  //! Return the full texture slot at specified position (mutable).
  TextureSlot& ChangeSlot(int theIndex)
  {
    return myTextures.ChangeValue(theIndex);
  }

  //! Return TRUE if texture color modulation has been enabled for the first texture
  //! or if texture is not set at all.
  Standard_EXPORT bool IsModulate() const;

  //! Return TRUE if other than point sprite textures are defined within point set.
  Standard_EXPORT bool HasNonPointSprite() const;

  //! Return TRUE if last texture is a point sprite.
  Standard_EXPORT bool HasPointSprite() const;

  //! Nullify all handles.
  void InitZero()
  {
    myTextures.Init(TextureSlot());
    myTextureSetBits = Graphic3d_TextureSetBits_NONE;
  }

protected:

  NCollection_Array1<TextureSlot> myTextures;      //!< array of texture slots
  int                             myTextureSetBits; //!< texture unit bits
};

DEFINE_STANDARD_HANDLE(Metal_TextureSet, Standard_Transient)

#endif // Metal_TextureSet_HeaderFile
