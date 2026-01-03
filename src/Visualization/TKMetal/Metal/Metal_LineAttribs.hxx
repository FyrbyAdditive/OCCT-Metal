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
struct Metal_HatchAttribs
{
  //! Hatch type.
  enum HatchType
  {
    HatchType_None = 0,       //!< solid fill (no hatching)
    HatchType_Horizontal,     //!< horizontal lines
    HatchType_Vertical,       //!< vertical lines
    HatchType_Diagonal45,     //!< diagonal lines at 45 degrees
    HatchType_Diagonal135,    //!< diagonal lines at 135 degrees
    HatchType_Grid,           //!< horizontal + vertical grid
    HatchType_GridDiagonal,   //!< diagonal grid (cross-hatch)
    HatchType_Custom          //!< custom pattern texture
  };

  //! Default constructor with solid fill.
  Metal_HatchAttribs()
  : Type(HatchType_None),
    Spacing(8.0f),
    LineWidth(1.0f),
    Angle(0.0f)
  {}

  //! Constructor with hatch type.
  Metal_HatchAttribs(HatchType theType, float theSpacing = 8.0f, float theLineWidth = 1.0f)
  : Type(theType),
    Spacing(theSpacing),
    LineWidth(theLineWidth),
    Angle(0.0f)
  {}

  //! Return true if hatching is enabled.
  bool IsHatched() const { return Type != HatchType_None; }

  //! Compare two hatch attributes.
  bool operator==(const Metal_HatchAttribs& theOther) const
  {
    return Type == theOther.Type
        && Spacing == theOther.Spacing
        && LineWidth == theOther.LineWidth
        && Angle == theOther.Angle;
  }

  bool operator!=(const Metal_HatchAttribs& theOther) const { return !(*this == theOther); }

  HatchType Type;      //!< hatch pattern type
  float     Spacing;   //!< spacing between hatch lines
  float     LineWidth; //!< width of hatch lines
  float     Angle;     //!< custom rotation angle (for custom patterns)
};

#endif // Metal_LineAttribs_HeaderFile
