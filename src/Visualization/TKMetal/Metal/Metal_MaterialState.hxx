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

#ifndef Metal_MaterialState_HeaderFile
#define Metal_MaterialState_HeaderFile

#include <Metal_Material.hxx>
#include <Standard_Transient.hxx>

//! State interface base class for tracking state changes.
class Metal_StateInterface
{
public:
  //! Default constructor.
  Metal_StateInterface() : myIndex(0) {}

  //! Return state index (incremented on each change).
  size_t Index() const { return myIndex; }

  //! Increment state index to indicate change.
  void Update() { ++myIndex; }

protected:
  size_t myIndex; //!< state change counter
};

//! Material state for tracking material changes in rendering.
//! Used to minimize uniform buffer updates by detecting when
//! material actually changes between draw calls.
class Metal_MaterialState : public Metal_StateInterface
{
public:

  //! Default constructor.
  Metal_MaterialState()
  : myAlphaCutoff(0.5f),
    myToDistinguish(false),
    myToMapTexture(false)
  {
  }

  //! Set material state.
  //! @param theMat material definition
  //! @param theAlphaCutoff alpha test threshold (>1.0 disables)
  //! @param theToDistinguish distinguish front/back faces
  //! @param theToMapTexture enable texture mapping
  void Set(const Metal_Material& theMat,
           float theAlphaCutoff,
           bool theToDistinguish,
           bool theToMapTexture)
  {
    myMaterial = theMat;
    myAlphaCutoff = theAlphaCutoff;
    myToDistinguish = theToDistinguish;
    myToMapTexture = theToMapTexture;
    Update();
  }

  //! Return current material.
  const Metal_Material& Material() const { return myMaterial; }

  //! Return mutable material.
  Metal_Material& ChangeMaterial() { return myMaterial; }

  //! Return alpha cutoff threshold.
  float AlphaCutoff() const { return myAlphaCutoff; }

  //! Set alpha cutoff threshold.
  void SetAlphaCutoff(float theValue)
  {
    if (myAlphaCutoff != theValue)
    {
      myAlphaCutoff = theValue;
      Update();
    }
  }

  //! Return TRUE if alpha test should be performed.
  bool HasAlphaCutoff() const { return myAlphaCutoff <= 1.0f; }

  //! Return distinguish front/back flag.
  bool ToDistinguish() const { return myToDistinguish; }

  //! Set distinguish front/back flag.
  void SetToDistinguish(bool theValue)
  {
    if (myToDistinguish != theValue)
    {
      myToDistinguish = theValue;
      Update();
    }
  }

  //! Return texture mapping flag.
  bool ToMapTexture() const { return myToMapTexture; }

  //! Set texture mapping flag.
  void SetToMapTexture(bool theValue)
  {
    if (myToMapTexture != theValue)
    {
      myToMapTexture = theValue;
      Update();
    }
  }

  //! Compare with another state for equality.
  bool IsEqual(const Metal_MaterialState& theOther) const
  {
    return myMaterial == theOther.myMaterial
        && myAlphaCutoff == theOther.myAlphaCutoff
        && myToDistinguish == theOther.myToDistinguish
        && myToMapTexture == theOther.myToMapTexture;
  }

  bool operator==(const Metal_MaterialState& theOther) const { return IsEqual(theOther); }
  bool operator!=(const Metal_MaterialState& theOther) const { return !IsEqual(theOther); }

private:

  Metal_Material myMaterial;      //!< material definition
  float          myAlphaCutoff;   //!< alpha test threshold
  bool           myToDistinguish; //!< distinguish front/back
  bool           myToMapTexture;  //!< enable texture mapping
};

#endif // Metal_MaterialState_HeaderFile
