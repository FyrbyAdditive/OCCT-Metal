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

#ifndef Metal_AspectState_HeaderFile
#define Metal_AspectState_HeaderFile

#include <Aspect_InteriorStyle.hxx>
#include <Aspect_PolygonOffsetMode.hxx>
#include <Graphic3d_AlphaMode.hxx>
#include <Graphic3d_TypeOfBackfacingModel.hxx>
#include <Graphic3d_TypeOfShadingModel.hxx>
#include <Graphic3d_Aspects.hxx>
#include <Graphic3d_HatchStyle.hxx>
#include <NCollection_Vec4.hxx>
#include <Metal_LineAttribs.hxx>

//! Material properties for Metal shaders.
struct Metal_MaterialState
{
  NCollection_Vec4<float> Ambient;    //!< ambient color
  NCollection_Vec4<float> Diffuse;    //!< diffuse color
  NCollection_Vec4<float> Specular;   //!< specular color
  NCollection_Vec4<float> Emissive;   //!< emissive color
  float                   Shininess;  //!< specular exponent (0-128)
  float                   Transparency; //!< alpha value (0=opaque, 1=transparent)
  float                   Padding[2];

  //! Default constructor.
  Metal_MaterialState()
  : Ambient(0.1f, 0.1f, 0.1f, 1.0f),
    Diffuse(0.8f, 0.8f, 0.8f, 1.0f),
    Specular(1.0f, 1.0f, 1.0f, 1.0f),
    Emissive(0.0f, 0.0f, 0.0f, 1.0f),
    Shininess(32.0f),
    Transparency(0.0f)
  {
    Padding[0] = Padding[1] = 0.0f;
  }

  //! Initialize from Graphic3d_MaterialAspect.
  void SetMaterial(const Graphic3d_MaterialAspect& theMat)
  {
    const Quantity_Color& anAmb = theMat.AmbientColor();
    const Quantity_Color& aDiff = theMat.DiffuseColor();
    const Quantity_Color& aSpec = theMat.SpecularColor();
    const Quantity_Color& anEmis = theMat.EmissiveColor();

    Ambient = NCollection_Vec4<float>((float)anAmb.Red(), (float)anAmb.Green(),
                                       (float)anAmb.Blue(), 1.0f);
    Diffuse = NCollection_Vec4<float>((float)aDiff.Red(), (float)aDiff.Green(),
                                       (float)aDiff.Blue(), 1.0f);
    Specular = NCollection_Vec4<float>((float)aSpec.Red(), (float)aSpec.Green(),
                                        (float)aSpec.Blue(), 1.0f);
    Emissive = NCollection_Vec4<float>((float)anEmis.Red(), (float)anEmis.Green(),
                                        (float)anEmis.Blue(), 1.0f);
    Shininess = theMat.Shininess() * 128.0f;
    Transparency = theMat.Transparency();
  }
};

//! Polygon offset parameters.
struct Metal_PolygonOffset
{
  Aspect_PolygonOffsetMode Mode;
  float                    Factor;
  float                    Units;

  Metal_PolygonOffset()
  : Mode(Aspect_POM_Fill),
    Factor(1.0f),
    Units(0.0f)
  {}

  Metal_PolygonOffset(const Graphic3d_PolygonOffset& theOffset)
  : Mode(theOffset.Mode),
    Factor(theOffset.Factor),
    Units(theOffset.Units)
  {}

  bool operator==(const Metal_PolygonOffset& theOther) const
  {
    return Mode == theOther.Mode
        && Factor == theOther.Factor
        && Units == theOther.Units;
  }

  bool operator!=(const Metal_PolygonOffset& theOther) const { return !(*this == theOther); }
};

//! Complete rendering aspect state for Metal.
//! Combines material, polygon offset, face culling, and other rendering parameters.
class Metal_AspectState
{
public:

  //! Default constructor.
  Metal_AspectState()
  : myInteriorStyle(Aspect_IS_SOLID),
    myShadingModel(Graphic3d_TypeOfShadingModel_Phong),
    myAlphaMode(Graphic3d_AlphaMode_BlendAuto),
    myAlphaCutoff(0.5f),
    myFaceCulling(Graphic3d_TypeOfBackfacingModel_BackCulled),
    myDistinguish(false),
    myToMapTexture(false)
  {
    myInteriorColor = NCollection_Vec4<float>(0.8f, 0.8f, 0.8f, 1.0f);
    myEdgeColor = NCollection_Vec4<float>(0.0f, 0.0f, 0.0f, 1.0f);
  }

  //! Initialize from Graphic3d_Aspects.
  void SetAspects(const occ::handle<Graphic3d_Aspects>& theAspects)
  {
    if (theAspects.IsNull())
    {
      return;
    }

    myInteriorStyle = theAspects->InteriorStyle();
    myShadingModel = theAspects->ShadingModel();
    myAlphaMode = theAspects->AlphaMode();
    myAlphaCutoff = theAspects->AlphaCutoff();
    myFaceCulling = theAspects->FaceCulling();
    myDistinguish = theAspects->Distinguish();
    myToMapTexture = theAspects->ToMapTexture();

    const Quantity_ColorRGBA& anIntColor = theAspects->InteriorColorRGBA();
    const Quantity_Color& anIntRGB = anIntColor.GetRGB();
    myInteriorColor = NCollection_Vec4<float>((float)anIntRGB.Red(), (float)anIntRGB.Green(),
                                               (float)anIntRGB.Blue(), anIntColor.Alpha());

    const Quantity_ColorRGBA& anEdgeColor = theAspects->EdgeColorRGBA();
    const Quantity_Color& anEdgeRGB = anEdgeColor.GetRGB();
    myEdgeColor = NCollection_Vec4<float>((float)anEdgeRGB.Red(), (float)anEdgeRGB.Green(),
                                           (float)anEdgeRGB.Blue(), anEdgeColor.Alpha());

    myFrontMaterial.SetMaterial(theAspects->FrontMaterial());
    myBackMaterial.SetMaterial(theAspects->BackMaterial());

    myPolygonOffset = Metal_PolygonOffset(theAspects->PolygonOffset());

    // Extract hatch style if interior style is hatched
    if (myInteriorStyle == Aspect_IS_HATCH)
    {
      const occ::handle<Graphic3d_HatchStyle>& aHatchStyle = theAspects->HatchStyle();
      if (!aHatchStyle.IsNull())
      {
        myHatchAttribs = Metal_HatchAttribs::FromAspectHatchStyle(
          static_cast<Aspect_HatchStyle>(aHatchStyle->HatchType()));
      }
      else
      {
        // Default to cross-hatch if no style specified
        myHatchAttribs = Metal_HatchAttribs::FromAspectHatchStyle(Aspect_HS_GRID_DIAGONAL);
      }
    }
    else
    {
      // Reset hatch attribs for non-hatched styles
      myHatchAttribs = Metal_HatchAttribs();
    }

    // Extract line attributes
    myLineAttribs.SetType(theAspects->LineType());
    myLineAttribs.Width = static_cast<float>(theAspects->LineWidth());
    myLineAttribs.Factor = static_cast<uint16_t>(theAspects->LineStippleFactor());
  }

  //! @name Accessors

  Aspect_InteriorStyle InteriorStyle() const { return myInteriorStyle; }
  void SetInteriorStyle(Aspect_InteriorStyle theStyle) { myInteriorStyle = theStyle; }

  Graphic3d_TypeOfShadingModel ShadingModel() const { return myShadingModel; }
  void SetShadingModel(Graphic3d_TypeOfShadingModel theModel) { myShadingModel = theModel; }

  Graphic3d_AlphaMode AlphaMode() const { return myAlphaMode; }
  float AlphaCutoff() const { return myAlphaCutoff; }
  void SetAlphaMode(Graphic3d_AlphaMode theMode, float theCutoff = 0.5f)
  {
    myAlphaMode = theMode;
    myAlphaCutoff = theCutoff;
  }

  Graphic3d_TypeOfBackfacingModel FaceCulling() const { return myFaceCulling; }
  void SetFaceCulling(Graphic3d_TypeOfBackfacingModel theCulling) { myFaceCulling = theCulling; }

  bool Distinguish() const { return myDistinguish; }
  void SetDistinguish(bool theValue) { myDistinguish = theValue; }

  bool ToMapTexture() const { return myToMapTexture; }
  void SetToMapTexture(bool theValue) { myToMapTexture = theValue; }

  const NCollection_Vec4<float>& InteriorColor() const { return myInteriorColor; }
  void SetInteriorColor(const NCollection_Vec4<float>& theColor) { myInteriorColor = theColor; }

  const NCollection_Vec4<float>& EdgeColor() const { return myEdgeColor; }
  void SetEdgeColor(const NCollection_Vec4<float>& theColor) { myEdgeColor = theColor; }

  const Metal_MaterialState& FrontMaterial() const { return myFrontMaterial; }
  Metal_MaterialState& ChangeFrontMaterial() { return myFrontMaterial; }

  const Metal_MaterialState& BackMaterial() const { return myBackMaterial; }
  Metal_MaterialState& ChangeBackMaterial() { return myBackMaterial; }

  const Metal_PolygonOffset& PolygonOffset() const { return myPolygonOffset; }
  void SetPolygonOffset(const Metal_PolygonOffset& theOffset) { myPolygonOffset = theOffset; }

  //! Return hatch attributes.
  const Metal_HatchAttribs& HatchAttribs() const { return myHatchAttribs; }

  //! Return modifiable hatch attributes.
  Metal_HatchAttribs& ChangeHatchAttribs() { return myHatchAttribs; }

  //! Set hatch attributes.
  void SetHatchAttribs(const Metal_HatchAttribs& theAttribs) { myHatchAttribs = theAttribs; }

  //! Return true if interior style is hatched.
  bool IsHatched() const { return myInteriorStyle == Aspect_IS_HATCH && myHatchAttribs.IsHatched(); }

  //! Return line attributes.
  const Metal_LineAttribs& LineAttribs() const { return myLineAttribs; }

  //! Return modifiable line attributes.
  Metal_LineAttribs& ChangeLineAttribs() { return myLineAttribs; }

  //! Set line attributes.
  void SetLineAttribs(const Metal_LineAttribs& theAttribs) { myLineAttribs = theAttribs; }

  //! Return true if line is stippled (not solid).
  bool IsStippled() const { return !myLineAttribs.IsSolid() && myLineAttribs.IsVisible(); }

private:

  Aspect_InteriorStyle             myInteriorStyle;
  Graphic3d_TypeOfShadingModel     myShadingModel;
  Graphic3d_AlphaMode              myAlphaMode;
  float                            myAlphaCutoff;
  Graphic3d_TypeOfBackfacingModel  myFaceCulling;
  bool                             myDistinguish;
  bool                             myToMapTexture;

  NCollection_Vec4<float>          myInteriorColor;
  NCollection_Vec4<float>          myEdgeColor;

  Metal_MaterialState              myFrontMaterial;
  Metal_MaterialState              myBackMaterial;

  Metal_PolygonOffset              myPolygonOffset;

  Metal_HatchAttribs               myHatchAttribs;

  Metal_LineAttribs                myLineAttribs;
};

#endif // Metal_AspectState_HeaderFile
