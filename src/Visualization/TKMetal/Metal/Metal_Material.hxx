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

#ifndef Metal_Material_HeaderFile
#define Metal_Material_HeaderFile

#include <Graphic3d_Aspects.hxx>
#include <Graphic3d_MaterialAspect.hxx>
#include <NCollection_Vec3.hxx>
#include <NCollection_Vec4.hxx>
#include <Quantity_Color.hxx>
#include <cstring>

class Metal_Context;

//! Common (Phong/Blinn) material definition for Metal shaders.
//! Packed for efficient GPU buffer transfer.
struct Metal_MaterialCommon
{
  NCollection_Vec4<float> Diffuse;           //!< diffuse RGB + alpha
  NCollection_Vec4<float> Emission;          //!< emission RGB + padding
  NCollection_Vec4<float> SpecularShininess; //!< specular RGB + shininess
  NCollection_Vec4<float> Ambient;           //!< ambient RGB + padding

  //! Return shininess value.
  float Shine() const { return SpecularShininess.a(); }

  //! Return mutable shininess.
  float& ChangeShine() { return SpecularShininess.a(); }

  //! Default constructor.
  Metal_MaterialCommon()
  : Diffuse(1.0f),
    Emission(0.0f, 0.0f, 0.0f, 1.0f),
    SpecularShininess(1.0f, 1.0f, 1.0f, 32.0f),
    Ambient(0.1f, 0.1f, 0.1f, 1.0f)
  {
  }

  //! Set material color (affects ambient and diffuse).
  void SetColor(const NCollection_Vec3<float>& theColor)
  {
    Ambient.SetValues(theColor * 0.25f, Ambient.a());
    Diffuse.SetValues(theColor, Diffuse.a());
  }
};

//! PBR material definition for Metal shaders.
//! Follows metallic-roughness workflow.
struct Metal_MaterialPBR
{
  NCollection_Vec4<float> BaseColor;    //!< base color RGB + alpha
  NCollection_Vec4<float> EmissionIOR;  //!< emission RGB + index of refraction
  NCollection_Vec4<float> Params;       //!< (occlusion, roughness, metallic, padding)

  //! Return metallic value.
  float Metallic() const { return Params.b(); }

  //! Return mutable metallic.
  float& ChangeMetallic() { return Params.b(); }

  //! Return roughness value.
  float Roughness() const { return Params.g(); }

  //! Return mutable roughness.
  float& ChangeRoughness() { return Params.g(); }

  //! Return occlusion value.
  float Occlusion() const { return Params.r(); }

  //! Return mutable occlusion.
  float& ChangeOcclusion() { return Params.r(); }

  //! Return index of refraction.
  float IOR() const { return EmissionIOR.a(); }

  //! Return mutable IOR.
  float& ChangeIOR() { return EmissionIOR.a(); }

  //! Default constructor.
  Metal_MaterialPBR()
  : BaseColor(1.0f),
    EmissionIOR(0.0f, 0.0f, 0.0f, 1.5f),
    Params(1.0f, 0.5f, 0.0f, 1.0f)
  {
  }

  //! Set material color.
  void SetColor(const NCollection_Vec3<float>& theColor)
  {
    BaseColor.SetValues(theColor, BaseColor.a());
  }
};

//! Complete material definition for Metal shaders.
//! Contains both Common (Phong) and PBR material data
//! for front and back faces.
struct Metal_Material
{
  Metal_MaterialCommon Common[2]; //!< [0]=front, [1]=back
  Metal_MaterialPBR    Pbr[2];    //!< [0]=front, [1]=back

  //! Set material color for all faces.
  void SetColor(const NCollection_Vec3<float>& theColor)
  {
    Common[0].SetColor(theColor);
    Common[1].SetColor(theColor);
    Pbr[0].SetColor(theColor);
    Pbr[1].SetColor(theColor);
  }

  //! Initialize material from Graphic3d aspects.
  //! @param theCtx Metal context
  //! @param theFront front face material aspect
  //! @param theFrontColor front face color
  //! @param theBack back face material aspect
  //! @param theBackColor back face color
  Standard_EXPORT void Init(Metal_Context* theCtx,
                            const Graphic3d_MaterialAspect& theFront,
                            const Quantity_Color& theFrontColor,
                            const Graphic3d_MaterialAspect& theBack,
                            const Quantity_Color& theBackColor);

  //! Initialize single face material.
  //! @param theCtx Metal context
  //! @param theMat material aspect
  //! @param theColor material color
  //! @param theIndex face index (0=front, 1=back)
  Standard_EXPORT void Init(Metal_Context* theCtx,
                            const Graphic3d_MaterialAspect& theMat,
                            const Quantity_Color& theColor,
                            int theIndex);

  //! Initialize material from Graphic3d_Aspects handle.
  //! Convenience method that extracts front/back materials and colors.
  //! @param theAspect the aspects to extract material from
  Standard_EXPORT void Init(const occ::handle<Graphic3d_Aspects>& theAspect);

  //! Check equality with another material.
  bool IsEqual(const Metal_Material& theOther) const
  {
    return std::memcmp(this, &theOther, sizeof(Metal_Material)) == 0;
  }

  bool operator==(const Metal_Material& theOther) const { return IsEqual(theOther); }
  bool operator!=(const Metal_Material& theOther) const { return !IsEqual(theOther); }

  //! Return packed common material data for shader.
  const NCollection_Vec4<float>* PackedCommon() const
  {
    return reinterpret_cast<const NCollection_Vec4<float>*>(Common);
  }

  //! Number of vec4 elements in packed common data.
  static int NbOfVec4Common() { return 4 * 2; }

  //! Return packed PBR material data for shader.
  const NCollection_Vec4<float>* PackedPbr() const
  {
    return reinterpret_cast<const NCollection_Vec4<float>*>(Pbr);
  }

  //! Number of vec4 elements in packed PBR data.
  static int NbOfVec4Pbr() { return 3 * 2; }

  //! Return total size in bytes for buffer allocation.
  static size_t BufferSize() { return sizeof(Metal_Material); }
};

//! Material flag for distinguishing face sides.
enum Metal_MaterialFlag
{
  Metal_MaterialFlag_Front = 0, //!< front face material
  Metal_MaterialFlag_Back = 1   //!< back face material
};

#endif // Metal_Material_HeaderFile
