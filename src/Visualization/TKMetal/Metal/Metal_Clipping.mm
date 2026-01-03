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

#include <Metal_Clipping.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Clipping, Standard_Transient)

// =======================================================================
// function : Metal_Clipping
// purpose  : Constructor
// =======================================================================
Metal_Clipping::Metal_Clipping()
: myNbClipPlanesOn(0),
  myNbCappingOn(0),
  myHasChains(false)
{
  // Initialize world-view matrix to identity
  memset(myWorldViewMatrix, 0, sizeof(myWorldViewMatrix));
  myWorldViewMatrix[0] = 1.0f;
  myWorldViewMatrix[5] = 1.0f;
  myWorldViewMatrix[10] = 1.0f;
  myWorldViewMatrix[15] = 1.0f;
}

// =======================================================================
// function : ~Metal_Clipping
// purpose  : Destructor
// =======================================================================
Metal_Clipping::~Metal_Clipping()
{
  Reset();
}

// =======================================================================
// function : Reset
// purpose  : Reset clipping state
// =======================================================================
void Metal_Clipping::Reset()
{
  myPlanes.Clear();
  myPlaneData.Clear();
  myNbClipPlanesOn = 0;
  myNbCappingOn = 0;
  myHasChains = false;
}

// =======================================================================
// function : Add
// purpose  : Add clipping planes
// =======================================================================
void Metal_Clipping::Add(Metal_Context* /*theCtx*/,
                         const Graphic3d_SequenceOfHClipPlane& thePlanes)
{
  for (Graphic3d_SequenceOfHClipPlane::Iterator aPlaneIter(thePlanes);
       aPlaneIter.More(); aPlaneIter.Next())
  {
    const occ::handle<Graphic3d_ClipPlane>& aPlane = aPlaneIter.Value();
    if (aPlane.IsNull())
    {
      continue;
    }

    // Check if plane is already added
    bool isFound = false;
    for (int i = 0; i < myPlanes.Length(); ++i)
    {
      if (myPlanes.Value(i) == aPlane)
      {
        isFound = true;
        break;
      }
    }
    if (isFound)
    {
      continue;
    }

    // Check for maximum planes
    if (myPlanes.Length() >= Metal_Clipping_MaxPlanes)
    {
      break;
    }

    myPlanes.Append(aPlane);

    // Add plane data
    Metal_ClippingPlaneData aData;
    memset(&aData, 0, sizeof(aData));

    const NCollection_Vec4<double>& anEq = aPlane->GetEquation();
    aData.Equation[0] = static_cast<float>(anEq.x());
    aData.Equation[1] = static_cast<float>(anEq.y());
    aData.Equation[2] = static_cast<float>(anEq.z());
    aData.Equation[3] = static_cast<float>(anEq.w());
    aData.ChainIndex = -1;
    aData.IsEnabled = aPlane->IsOn() ? 1 : 0;

    myPlaneData.Append(aData);

    if (aPlane->IsOn())
    {
      if (aPlane->IsCapping())
      {
        ++myNbCappingOn;
      }
      else
      {
        ++myNbClipPlanesOn;
      }
    }

    // Check for chains
    if (!aPlane->ChainNextPlane().IsNull())
    {
      myHasChains = true;
    }
  }
}

// =======================================================================
// function : Remove
// purpose  : Remove clipping planes
// =======================================================================
void Metal_Clipping::Remove(Metal_Context* /*theCtx*/,
                            const Graphic3d_SequenceOfHClipPlane& thePlanes)
{
  for (Graphic3d_SequenceOfHClipPlane::Iterator aPlaneIter(thePlanes);
       aPlaneIter.More(); aPlaneIter.Next())
  {
    const occ::handle<Graphic3d_ClipPlane>& aPlane = aPlaneIter.Value();
    if (aPlane.IsNull())
    {
      continue;
    }

    for (int i = 0; i < myPlanes.Length(); ++i)
    {
      if (myPlanes.Value(i) == aPlane)
      {
        if (aPlane->IsOn())
        {
          if (aPlane->IsCapping())
          {
            --myNbCappingOn;
          }
          else
          {
            --myNbClipPlanesOn;
          }
        }

        // Mark plane as removed by setting to null and disabled
        myPlanes.ChangeValue(i).Nullify();
        myPlaneData.ChangeValue(i).IsEnabled = 0;
        break;
      }
    }
  }

  // Recalculate chain status
  myHasChains = false;
  for (int i = 0; i < myPlanes.Length(); ++i)
  {
    if (!myPlanes.Value(i).IsNull() && !myPlanes.Value(i)->ChainNextPlane().IsNull())
    {
      myHasChains = true;
      break;
    }
  }
}

// =======================================================================
// function : GetPlaneEquations
// purpose  : Get plane equations for shader
// =======================================================================
void Metal_Clipping::GetPlaneEquations(float* thePlanes, int& theCount) const
{
  theCount = 0;

  for (int i = 0; i < myPlaneData.Length() && theCount < Metal_Clipping_MaxPlanes; ++i)
  {
    const Metal_ClippingPlaneData& aData = myPlaneData.Value(i);
    if (aData.IsEnabled)
    {
      thePlanes[theCount * 4 + 0] = aData.Equation[0];
      thePlanes[theCount * 4 + 1] = aData.Equation[1];
      thePlanes[theCount * 4 + 2] = aData.Equation[2];
      thePlanes[theCount * 4 + 3] = aData.Equation[3];
      ++theCount;
    }
  }
}

// =======================================================================
// function : recalculatePlanes
// purpose  : Recalculate plane equations transformed to view space
// =======================================================================
void Metal_Clipping::recalculatePlanes()
{
  // Transform plane equations from world space to view space
  // A plane P in world space transforms to P' = (M^-T) * P
  // where M is the world-view matrix
  //
  // For a 4x4 matrix stored column-major:
  // [m0  m4  m8  m12]
  // [m1  m5  m9  m13]
  // [m2  m6  m10 m14]
  // [m3  m7  m11 m15]
  //
  // The inverse-transpose for the upper-left 3x3 (orthonormal rotation)
  // is just the transpose. For plane equation (A, B, C, D):
  // - The normal (A, B, C) is transformed by the 3x3 inverse-transpose
  // - The D component needs adjustment for translation

  const float* m = myWorldViewMatrix;

  for (int i = 0; i < myPlanes.Length(); ++i)
  {
    const occ::handle<Graphic3d_ClipPlane>& aPlane = myPlanes.Value(i);
    if (aPlane.IsNull())
    {
      continue;
    }

    Metal_ClippingPlaneData& aData = myPlaneData.ChangeValue(i);
    const NCollection_Vec4<double>& anEq = aPlane->GetEquation();

    // Get plane equation in world space
    float a = static_cast<float>(anEq.x());
    float b = static_cast<float>(anEq.y());
    float c = static_cast<float>(anEq.z());
    float d = static_cast<float>(anEq.w());

    // Transform plane to view space using M^(-T)
    // For orthonormal matrices (rotation only), M^(-T) = M
    // For general case with translation, we need:
    // n' = R^T * n (where R is 3x3 rotation part)
    // d' = d - dot(t, n) (where t is translation)
    //
    // Since we're using column-major storage and M is world-view:
    // Rotation is in m[0-2], m[4-6], m[8-10] (columns)
    // Translation is in m[12-14]

    // Transform normal by transpose of upper-left 3x3
    float ax = m[0] * a + m[1] * b + m[2] * c;
    float ay = m[4] * a + m[5] * b + m[6] * c;
    float az = m[8] * a + m[9] * b + m[10] * c;

    // Transform D: d' = d - dot(translation, original_normal)
    float tx = m[12];
    float ty = m[13];
    float tz = m[14];
    float ad = d - (tx * a + ty * b + tz * c);

    aData.Equation[0] = ax;
    aData.Equation[1] = ay;
    aData.Equation[2] = az;
    aData.Equation[3] = ad;
    aData.IsEnabled = aPlane->IsOn() ? 1 : 0;
  }
}

// =======================================================================
// function : UpdateViewSpacePlanes
// purpose  : Public method to update plane equations
// =======================================================================
void Metal_Clipping::UpdateViewSpacePlanes()
{
  if (myPlanes.Length() > 0)
  {
    recalculatePlanes();
  }
}
