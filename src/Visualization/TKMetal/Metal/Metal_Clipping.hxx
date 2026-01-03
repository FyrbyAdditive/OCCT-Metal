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

#ifndef Metal_Clipping_HeaderFile
#define Metal_Clipping_HeaderFile

#include <Graphic3d_ClipPlane.hxx>
#include <Graphic3d_SequenceOfHClipPlane.hxx>
#include <NCollection_Vector.hxx>
#include <Standard_Transient.hxx>

class Metal_Context;

//! Maximum number of clipping planes.
static const int Metal_Clipping_MaxPlanes = 8;

//! Clipping plane data for shader uniform.
struct Metal_ClippingPlaneData
{
  float Equation[4]; //!< plane equation (A, B, C, D)
  int   ChainIndex;  //!< index of next plane in chain (-1 if none)
  int   IsEnabled;   //!< enabled flag
  int   Padding[2];  //!< alignment padding
};

//! Manager for clipping planes in Metal rendering.
class Metal_Clipping : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Clipping, Standard_Transient)

public:

  //! Create clipping manager.
  Standard_EXPORT Metal_Clipping();

  //! Destructor.
  Standard_EXPORT ~Metal_Clipping();

  //! Return true if clipping is enabled.
  bool IsClippingOn() const { return myNbClipPlanesOn > 0; }

  //! Return true if capping is enabled.
  bool IsCappingOn() const { return myNbCappingOn > 0; }

  //! Return number of clipping or capping planes currently on.
  int NbClippingOrCappingOn() const { return myNbClipPlanesOn + myNbCappingOn; }

  //! Return true if there are clipping chains (linked planes).
  bool HasClippingChains() const { return myHasChains; }

  //! Reset clipping state.
  Standard_EXPORT void Reset();

  //! Add clipping planes from sequence.
  //! @param[in] theCtx    Metal context
  //! @param[in] thePlanes sequence of clipping planes
  Standard_EXPORT void Add(Metal_Context* theCtx,
                           const Graphic3d_SequenceOfHClipPlane& thePlanes);

  //! Remove clipping planes from sequence.
  //! @param[in] theCtx    Metal context
  //! @param[in] thePlanes sequence of clipping planes to remove
  Standard_EXPORT void Remove(Metal_Context* theCtx,
                              const Graphic3d_SequenceOfHClipPlane& thePlanes);

  //! Return clipping plane equations for shader uniform.
  //! @param[out] thePlanes output array of plane equations (size MAX_CLIP_PLANES * 4)
  //! @param[out] theCount  number of active planes
  Standard_EXPORT void GetPlaneEquations(float* thePlanes, int& theCount) const;

  //! Return plane data for shader uniform buffer.
  const NCollection_Vector<Metal_ClippingPlaneData>& PlaneData() const { return myPlaneData; }

  //! Return number of active clipping planes.
  int NbActivePlanes() const { return myNbClipPlanesOn; }

  //! Set world-view matrix for transforming clipping planes.
  //! Automatically recalculates plane equations in view space.
  void SetWorldViewMatrix(const float* theMat)
  {
    bool aChanged = false;
    for (int i = 0; i < 16; ++i)
    {
      if (myWorldViewMatrix[i] != theMat[i])
      {
        myWorldViewMatrix[i] = theMat[i];
        aChanged = true;
      }
    }
    if (aChanged && myPlanes.Length() > 0)
    {
      recalculatePlanes();
    }
  }

  //! Update all plane equations to view space using current matrix.
  //! Call this when planes change or before rendering.
  Standard_EXPORT void UpdateViewSpacePlanes();

  //! Return the current world-view matrix.
  const float* WorldViewMatrix() const { return myWorldViewMatrix; }

protected:

  //! Recalculate plane equations based on current world-view matrix.
  void recalculatePlanes();

protected:

  NCollection_Vector<occ::handle<Graphic3d_ClipPlane>> myPlanes;    //!< active clipping planes
  NCollection_Vector<Metal_ClippingPlaneData>          myPlaneData; //!< plane data for shader
  float myWorldViewMatrix[16]; //!< current world-view matrix
  int   myNbClipPlanesOn;      //!< number of clipping planes on
  int   myNbCappingOn;         //!< number of capping planes on
  bool  myHasChains;           //!< flag for clipping chains
};

#endif // Metal_Clipping_HeaderFile
