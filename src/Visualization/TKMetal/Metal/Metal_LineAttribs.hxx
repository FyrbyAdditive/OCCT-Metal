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

#ifndef Metal_LineAttribs_HeaderFile
#define Metal_LineAttribs_HeaderFile

#include <Aspect_TypeOfLine.hxx>
#include <Aspect_HatchStyle.hxx>
#include <Graphic3d_Aspects.hxx>

//! Line rendering attributes for Metal.
//! Manages line type, width, stipple pattern, and feather settings.
struct Metal_LineAttribs
{
  //! Default line pattern values for each line type.
  static uint16_t PatternForType(Aspect_TypeOfLine theType)
  {
    return Graphic3d_Aspects::DefaultLinePatternForType(theType);
  }

  //! Line type from pattern.
  static Aspect_TypeOfLine TypeForPattern(uint16_t thePattern)
  {
    return Graphic3d_Aspects::DefaultLineTypeForPattern(thePattern);
  }

  //! Default constructor with solid line.
  Metal_LineAttribs()
  : Type(Aspect_TOL_SOLID),
    Pattern(0xFFFF),
    Factor(1),
    Width(1.0f),
    Feather(1.0f)
  {}

  //! Constructor with line type.
  Metal_LineAttribs(Aspect_TypeOfLine theType, float theWidth = 1.0f)
  : Type(theType),
    Pattern(PatternForType(theType)),
    Factor(1),
    Width(theWidth),
    Feather(1.0f)
  {}

  //! Constructor with full parameters.
  Metal_LineAttribs(uint16_t thePattern, uint16_t theFactor, float theWidth, float theFeather = 1.0f)
  : Type(TypeForPattern(thePattern)),
    Pattern(thePattern),
    Factor(theFactor),
    Width(theWidth),
    Feather(theFeather)
  {}

  //! Set line type and update pattern.
  void SetType(Aspect_TypeOfLine theType)
  {
    Type = theType;
    Pattern = PatternForType(theType);
  }

  //! Set custom pattern.
  void SetPattern(uint16_t thePattern)
  {
    Pattern = thePattern;
    Type = TypeForPattern(thePattern);
  }

  //! Return true if line is visible (not empty).
  bool IsVisible() const { return Type != Aspect_TOL_EMPTY && Pattern != 0; }

  //! Return true if line is solid (no stipple).
  bool IsSolid() const { return Pattern == 0xFFFF; }

  //! Compare two line attributes.
  bool operator==(const Metal_LineAttribs& theOther) const
  {
    return Type == theOther.Type
        && Pattern == theOther.Pattern
        && Factor == theOther.Factor
        && Width == theOther.Width
        && Feather == theOther.Feather;
  }

  bool operator!=(const Metal_LineAttribs& theOther) const { return !(*this == theOther); }

  Aspect_TypeOfLine Type;    //!< line type
  uint16_t          Pattern; //!< stipple pattern (16-bit)
  uint16_t          Factor;  //!< stipple factor (1-256)
  float             Width;   //!< line width in pixels
  float             Feather; //!< line edge feather amount
};

//! Hatch rendering attributes for Metal.
//! Manages interior fill style with hatch patterns.
//! The hatch type values match the Aspect_HatchStyle enum values directly.
struct Metal_HatchAttribs
{
  //! Default spacing values for narrow and wide patterns.
  static constexpr float NarrowSpacing = 8.0f;
  static constexpr float WideSpacing = 16.0f;

  //! Convert Aspect_HatchStyle to Metal hatch type and spacing.
  //! The Aspect_HatchStyle enum values are used directly as shader hatch types.
  static Metal_HatchAttribs FromAspectHatchStyle(Aspect_HatchStyle theStyle)
  {
    Metal_HatchAttribs anAttribs;
    anAttribs.Type = static_cast<int>(theStyle);

    // Set spacing based on pattern (wide patterns have larger spacing)
    switch (theStyle)
    {
      case Aspect_HS_SOLID:
        anAttribs.Spacing = NarrowSpacing;
        break;
      case Aspect_HS_GRID_DIAGONAL_WIDE:
      case Aspect_HS_GRID_WIDE:
      case Aspect_HS_DIAGONAL_45_WIDE:
      case Aspect_HS_DIAGONAL_135_WIDE:
      case Aspect_HS_HORIZONTAL_WIDE:
      case Aspect_HS_VERTICAL_WIDE:
        anAttribs.Spacing = WideSpacing;
        break;
      default:
        anAttribs.Spacing = NarrowSpacing;
        break;
    }
    return anAttribs;
  }

  //! Default constructor with solid fill.
  Metal_HatchAttribs()
  : Type(0),          // Aspect_HS_SOLID = 0
    Spacing(NarrowSpacing),
    LineWidth(1.0f),
    Angle(0.0f)
  {}

  //! Constructor with hatch style.
  Metal_HatchAttribs(Aspect_HatchStyle theStyle, float theLineWidth = 1.0f)
  : Type(static_cast<int>(theStyle)),
    Spacing(NarrowSpacing),
    LineWidth(theLineWidth),
    Angle(0.0f)
  {
    *this = FromAspectHatchStyle(theStyle);
    LineWidth = theLineWidth;
  }

  //! Return true if hatching is enabled.
  bool IsHatched() const { return Type != static_cast<int>(Aspect_HS_SOLID); }

  //! Compare two hatch attributes.
  bool operator==(const Metal_HatchAttribs& theOther) const
  {
    return Type == theOther.Type
        && Spacing == theOther.Spacing
        && LineWidth == theOther.LineWidth
        && Angle == theOther.Angle;
  }

  bool operator!=(const Metal_HatchAttribs& theOther) const { return !(*this == theOther); }

  int       Type;      //!< hatch pattern type (Aspect_HatchStyle value)
  float     Spacing;   //!< spacing between hatch lines in pixels
  float     LineWidth; //!< width of hatch lines in pixels
  float     Angle;     //!< custom rotation angle in radians
};

#endif // Metal_LineAttribs_HeaderFile
