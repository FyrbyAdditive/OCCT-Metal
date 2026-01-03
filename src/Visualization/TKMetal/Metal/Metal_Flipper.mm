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

#include <Metal_Flipper.hxx>
#include <cmath>

// =======================================================================
// function : ComputeMatrix
// purpose  : Compute billboard model matrix
// =======================================================================
NCollection_Mat4<float> Metal_Flipper::ComputeMatrix(
  const NCollection_Mat4<float>& theViewMatrix,
  const NCollection_Vec3<float>& theViewPos) const
{
  NCollection_Mat4<float> aResult;
  aResult.InitIdentity();

  if (myMode == Mode_None)
  {
    // No billboard - just translation and scale
    aResult.SetColumn(3, NCollection_Vec4<float>(myPosition.x(), myPosition.y(), myPosition.z(), 1.0f));
    if (myScale != 1.0f)
    {
      aResult.SetValue(0, 0, myScale);
      aResult.SetValue(1, 1, myScale);
      aResult.SetValue(2, 2, myScale);
    }
    return aResult;
  }

  // Calculate look direction from object to camera
  NCollection_Vec3<float> aLook = theViewPos - myPosition;
  float aDistance = aLook.Modulus();

  if (aDistance < 1e-6f)
  {
    // Camera is at object position
    aResult.SetColumn(3, NCollection_Vec4<float>(myPosition.x(), myPosition.y(), myPosition.z(), 1.0f));
    return aResult;
  }

  aLook /= aDistance;

  NCollection_Vec3<float> aRight, aUp;

  if (myMode == Mode_Spherical)
  {
    // Full billboard - extract camera right and up from view matrix
    // The view matrix has camera axes in rows (transposed)
    aRight = NCollection_Vec3<float>(theViewMatrix.GetValue(0, 0),
                                      theViewMatrix.GetValue(1, 0),
                                      theViewMatrix.GetValue(2, 0));
    aUp = NCollection_Vec3<float>(theViewMatrix.GetValue(0, 1),
                                   theViewMatrix.GetValue(1, 1),
                                   theViewMatrix.GetValue(2, 1));
  }
  else if (myMode == Mode_Cylindrical)
  {
    // Cylindrical - rotate around Y axis only
    NCollection_Vec3<float> aWorldUp(0.0f, 1.0f, 0.0f);
    aRight = NCollection_Vec3<float>::Cross(aWorldUp, aLook);
    float aRightLen = aRight.Modulus();
    if (aRightLen > 1e-6f)
    {
      aRight /= aRightLen;
    }
    else
    {
      aRight = NCollection_Vec3<float>(1.0f, 0.0f, 0.0f);
    }
    aUp = aWorldUp;
    aLook = NCollection_Vec3<float>::Cross(aRight, aUp);
  }
  else // Mode_Screen
  {
    // Screen-aligned - use view matrix axes directly
    aRight = NCollection_Vec3<float>(theViewMatrix.GetValue(0, 0),
                                      theViewMatrix.GetValue(1, 0),
                                      theViewMatrix.GetValue(2, 0));
    aUp = NCollection_Vec3<float>(theViewMatrix.GetValue(0, 1),
                                   theViewMatrix.GetValue(1, 1),
                                   theViewMatrix.GetValue(2, 1));
    aLook = NCollection_Vec3<float>(theViewMatrix.GetValue(0, 2),
                                     theViewMatrix.GetValue(1, 2),
                                     theViewMatrix.GetValue(2, 2));
  }

  // Apply scale
  float aScale = myScale;
  if (myFixedScale && aDistance > 1.0f)
  {
    // Scale inversely with distance to maintain fixed screen size
    aScale *= aDistance;
  }

  aRight *= aScale;
  aUp *= aScale;
  NCollection_Vec3<float> aForward = NCollection_Vec3<float>::Cross(aRight, aUp);
  aForward.Normalize();
  aForward *= aScale;

  // Build rotation matrix
  aResult.SetValue(0, 0, aRight.x());
  aResult.SetValue(1, 0, aRight.y());
  aResult.SetValue(2, 0, aRight.z());

  aResult.SetValue(0, 1, aUp.x());
  aResult.SetValue(1, 1, aUp.y());
  aResult.SetValue(2, 1, aUp.z());

  aResult.SetValue(0, 2, aForward.x());
  aResult.SetValue(1, 2, aForward.y());
  aResult.SetValue(2, 2, aForward.z());

  // Set position
  aResult.SetValue(0, 3, myPosition.x());
  aResult.SetValue(1, 3, myPosition.y());
  aResult.SetValue(2, 3, myPosition.z());

  return aResult;
}
