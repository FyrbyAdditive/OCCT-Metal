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

#ifndef Metal_Flipper_HeaderFile
#define Metal_Flipper_HeaderFile

#include <NCollection_Mat4.hxx>
#include <NCollection_Vec3.hxx>

class Metal_Context;
class Metal_Workspace;

//! Flipper/Billboard transform for Metal.
//! Provides transforms for objects that should always face the camera
//! or maintain specific orientations regardless of view.
class Metal_Flipper
{
public:

  //! Billboard/flipper mode.
  enum Mode
  {
    Mode_None,         //!< no billboard effect
    Mode_Spherical,    //!< full billboard (always face camera)
    Mode_Cylindrical,  //!< rotate around Y axis only
    Mode_Screen        //!< screen-aligned (no rotation, fixed size)
  };

public:

  //! Default constructor.
  Metal_Flipper()
  : myMode(Mode_None),
    myScale(1.0f),
    myFixedScale(false)
  {
    myPosition = NCollection_Vec3<float>(0.0f, 0.0f, 0.0f);
    myModelMatrix.InitIdentity();
  }

  //! Return flipper mode.
  Mode GetMode() const { return myMode; }

  //! Set flipper mode.
  void SetMode(Mode theMode) { myMode = theMode; }

  //! Return true if spherical billboard.
  bool IsSpherical() const { return myMode == Mode_Spherical; }

  //! Return true if cylindrical billboard.
  bool IsCylindrical() const { return myMode == Mode_Cylindrical; }

  //! Return true if screen-aligned.
  bool IsScreen() const { return myMode == Mode_Screen; }

  //! Set position in world space.
  void SetPosition(float theX, float theY, float theZ)
  {
    myPosition = NCollection_Vec3<float>(theX, theY, theZ);
  }

  //! Set position.
  void SetPosition(const NCollection_Vec3<float>& thePos)
  {
    myPosition = thePos;
  }

  //! Return position.
  const NCollection_Vec3<float>& Position() const { return myPosition; }

  //! Return scale factor.
  float Scale() const { return myScale; }

  //! Set scale factor.
  void SetScale(float theScale) { myScale = theScale; }

  //! Return true if scale is fixed (doesn't change with distance).
  bool HasFixedScale() const { return myFixedScale; }

  //! Set fixed scale mode.
  void SetFixedScale(bool theValue) { myFixedScale = theValue; }

  //! Compute billboard model matrix.
  //! @param theViewMatrix current view matrix
  //! @param theViewPos camera position
  //! @return model matrix for billboard rendering
  NCollection_Mat4<float> ComputeMatrix(const NCollection_Mat4<float>& theViewMatrix,
                                         const NCollection_Vec3<float>& theViewPos) const;

  //! Return cached model matrix.
  const NCollection_Mat4<float>& ModelMatrix() const { return myModelMatrix; }

  //! Update and cache model matrix.
  void UpdateMatrix(const NCollection_Mat4<float>& theViewMatrix,
                    const NCollection_Vec3<float>& theViewPos)
  {
    myModelMatrix = ComputeMatrix(theViewMatrix, theViewPos);
  }

private:

  Mode                    myMode;        //!< billboard mode
  NCollection_Vec3<float> myPosition;    //!< world position
  float                   myScale;       //!< scale factor
  bool                    myFixedScale;  //!< fixed scale flag
  NCollection_Mat4<float> myModelMatrix; //!< cached model matrix
};

#endif // Metal_Flipper_HeaderFile
