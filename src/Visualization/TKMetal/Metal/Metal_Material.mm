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

#include <Metal_Material.hxx>
#include <Metal_Context.hxx>

// =======================================================================
// function : Init
// purpose  : Initialize material from front and back aspects
// =======================================================================
void Metal_Material::Init(Metal_Context* theCtx,
                          const Graphic3d_MaterialAspect& theFront,
                          const Quantity_Color& theFrontColor,
                          const Graphic3d_MaterialAspect& theBack,
                          const Quantity_Color& theBackColor)
{
  Init(theCtx, theFront, theFrontColor, 0);
  Init(theCtx, theBack, theBackColor, 1);
}

// =======================================================================
// function : Init
// purpose  : Initialize single face material
// =======================================================================
void Metal_Material::Init(Metal_Context* /*theCtx*/,
                          const Graphic3d_MaterialAspect& theMat,
                          const Quantity_Color& theColor,
                          int theIndex)
{
  // Clamp index
  const int anIdx = (theIndex == 0) ? 0 : 1;

  // Get colors from material
  const Quantity_Color& aAmbient = theMat.AmbientColor();
  const Quantity_Color& aDiffuse = theMat.DiffuseColor();
  const Quantity_Color& aSpecular = theMat.SpecularColor();
  const Quantity_Color& aEmission = theMat.EmissiveColor();

  // Common (Phong) material
  Metal_MaterialCommon& aCommon = Common[anIdx];

  aCommon.Ambient = NCollection_Vec4<float>(
    static_cast<float>(aAmbient.Red()),
    static_cast<float>(aAmbient.Green()),
    static_cast<float>(aAmbient.Blue()),
    1.0f);

  aCommon.Diffuse = NCollection_Vec4<float>(
    static_cast<float>(aDiffuse.Red()),
    static_cast<float>(aDiffuse.Green()),
    static_cast<float>(aDiffuse.Blue()),
    1.0f - static_cast<float>(theMat.Transparency()));

  aCommon.SpecularShininess = NCollection_Vec4<float>(
    static_cast<float>(aSpecular.Red()),
    static_cast<float>(aSpecular.Green()),
    static_cast<float>(aSpecular.Blue()),
    static_cast<float>(theMat.Shininess()) * 128.0f);

  aCommon.Emission = NCollection_Vec4<float>(
    static_cast<float>(aEmission.Red()),
    static_cast<float>(aEmission.Green()),
    static_cast<float>(aEmission.Blue()),
    1.0f);

  // Apply color override
  if (theMat.MaterialType() != Graphic3d_MATERIAL_ASPECT)
  {
    const NCollection_Vec3<float> aColor(
      static_cast<float>(theColor.Red()),
      static_cast<float>(theColor.Green()),
      static_cast<float>(theColor.Blue()));
    aCommon.SetColor(aColor);
  }

  // PBR material
  Metal_MaterialPBR& aPbr = Pbr[anIdx];

  // Base color (use diffuse or override color)
  if (theMat.MaterialType() == Graphic3d_MATERIAL_ASPECT)
  {
    aPbr.BaseColor = NCollection_Vec4<float>(
      static_cast<float>(aDiffuse.Red()),
      static_cast<float>(aDiffuse.Green()),
      static_cast<float>(aDiffuse.Blue()),
      1.0f - static_cast<float>(theMat.Transparency()));
  }
  else
  {
    aPbr.BaseColor = NCollection_Vec4<float>(
      static_cast<float>(theColor.Red()),
      static_cast<float>(theColor.Green()),
      static_cast<float>(theColor.Blue()),
      1.0f - static_cast<float>(theMat.Transparency()));
  }

  // Emission and IOR
  aPbr.EmissionIOR = NCollection_Vec4<float>(
    static_cast<float>(aEmission.Red()),
    static_cast<float>(aEmission.Green()),
    static_cast<float>(aEmission.Blue()),
    static_cast<float>(theMat.RefractionIndex()));

  // PBR parameters
  float aMetallic = 0.0f;
  float aRoughness = 0.5f;

  // Estimate metallic/roughness from traditional material
  // These are approximations based on material properties
  if (theMat.MaterialType() == Graphic3d_MATERIAL_PHYSIC)
  {
    // Physical materials - estimate from specular
    float aSpecIntensity = (aSpecular.Red() + aSpecular.Green() + aSpecular.Blue()) / 3.0f;
    aMetallic = aSpecIntensity > 0.5f ? 1.0f : 0.0f;
    aRoughness = 1.0f - theMat.Shininess();
  }
  else
  {
    // Aspect materials - use defaults
    aRoughness = 1.0f - theMat.Shininess() * 0.5f;
  }

  // Try to get PBR values if available
  if (theMat.PBRMaterial().IsDefined)
  {
    const Graphic3d_PBRMaterial& aPbrSrc = theMat.PBRMaterial();
    aMetallic = aPbrSrc.Metallic();
    aRoughness = aPbrSrc.NormalizedRoughness();

    // Override base color from PBR
    const Quantity_ColorRGBA& aPbrColor = aPbrSrc.Color();
    aPbr.BaseColor = NCollection_Vec4<float>(
      static_cast<float>(aPbrColor.GetRGB().Red()),
      static_cast<float>(aPbrColor.GetRGB().Green()),
      static_cast<float>(aPbrColor.GetRGB().Blue()),
      aPbrColor.Alpha());

    // Emission from PBR
    const Graphic3d_Vec3& aPbrEmission = aPbrSrc.Emission();
    aPbr.EmissionIOR.SetValues(
      NCollection_Vec3<float>(aPbrEmission.r(), aPbrEmission.g(), aPbrEmission.b()),
      aPbr.EmissionIOR.a());

    // IOR from PBR
    aPbr.ChangeIOR() = aPbrSrc.IOR();
  }

  aPbr.Params = NCollection_Vec4<float>(1.0f, aRoughness, aMetallic, 1.0f);
}
