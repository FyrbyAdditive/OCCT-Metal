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

#ifndef Metal_HaltonSampler_HeaderFile
#define Metal_HaltonSampler_HeaderFile

#include <vector>
#include <cstring>

//! Compute points of the Halton sequence with digit-permutations for different bases.
//! This is a low-discrepancy sequence generator used for quasi-Monte Carlo sampling
//! in ray tracing. The sequence provides better coverage than pseudo-random sampling.
class Metal_HaltonSampler
{
public:

  //! Return the number of supported dimensions.
  static unsigned get_num_dimensions() { return 3u; }

public:

  //! Initialize the sampler with Faure-permutations.
  Metal_HaltonSampler()
  {
    std::memset(myPerm3, 0, sizeof(myPerm3));
    std::memset(myPerm5, 0, sizeof(myPerm5));
    initFaure();
  }

  //! Return the Halton sample for the given dimension and index.
  //! @param theDimension dimension (0, 1, or 2)
  //! @param theIndex sample index
  //! @return sample value in [0, 1)
  float sample(unsigned theDimension, unsigned theIndex) const
  {
    switch (theDimension)
    {
      case 0: return halton2(theIndex);
      case 1: return halton3(theIndex);
      case 2: return halton5(theIndex);
    }
    return 0.0f;
  }

  //! Return 2D sample (x, y) for the given index.
  //! @param theIndex sample index
  //! @param theX output x coordinate [0, 1)
  //! @param theY output y coordinate [0, 1)
  void sample2D(unsigned theIndex, float& theX, float& theY) const
  {
    theX = halton2(theIndex);
    theY = halton3(theIndex);
  }

  //! Return 3D sample (x, y, z) for the given index.
  //! @param theIndex sample index
  //! @param theX output x coordinate [0, 1)
  //! @param theY output y coordinate [0, 1)
  //! @param theZ output z coordinate [0, 1)
  void sample3D(unsigned theIndex, float& theX, float& theY, float& theZ) const
  {
    theX = halton2(theIndex);
    theY = halton3(theIndex);
    theZ = halton5(theIndex);
  }

private:

  //! Initialize permutation tables using Faure permutations.
  void initFaure()
  {
    const unsigned THE_MAX_BASE = 5u;
    std::vector<std::vector<unsigned short>> aPerms(THE_MAX_BASE + 1);

    // Keep identity permutations for base 1, 2, 3
    for (unsigned k = 1; k <= 3; ++k)
    {
      aPerms[k].resize(k);
      for (unsigned i = 0; i < k; ++i)
      {
        aPerms[k][i] = static_cast<unsigned short>(i);
      }
    }

    // Compute Faure permutations for base 4 and 5
    for (unsigned aBase = 4; aBase <= THE_MAX_BASE; ++aBase)
    {
      aPerms[aBase].resize(aBase);
      const unsigned b = aBase / 2;
      if (aBase & 1) // odd
      {
        for (unsigned i = 0; i < aBase - 1; ++i)
        {
          aPerms[aBase][i + (i >= b)] = aPerms[aBase - 1][i] + (aPerms[aBase - 1][i] >= b);
        }
        aPerms[aBase][b] = static_cast<unsigned short>(b);
      }
      else // even
      {
        for (unsigned i = 0; i < b; ++i)
        {
          aPerms[aBase][i]     = 2 * aPerms[b][i];
          aPerms[aBase][b + i] = 2 * aPerms[b][i] + 1;
        }
      }
    }

    // Build lookup tables
    for (unsigned short i = 0; i < 243; ++i)
    {
      myPerm3[i] = invert(3, 5, i, aPerms[3]);
    }
    for (unsigned short i = 0; i < 125; ++i)
    {
      myPerm5[i] = invert(5, 3, i, aPerms[5]);
    }
  }

  //! Helper function for building permutation tables.
  static unsigned short invert(unsigned short theBase,
                               unsigned short theDigits,
                               unsigned short theIndex,
                               const std::vector<unsigned short>& thePerm)
  {
    unsigned short aResult = 0;
    for (unsigned short i = 0; i < theDigits; ++i)
    {
      aResult = aResult * theBase + thePerm[theIndex % theBase];
      theIndex /= theBase;
    }
    return aResult;
  }

  //! Radical inverse in base 2 using direct bit reversal.
  //! This is faster than the general case due to bit manipulation.
  float halton2(unsigned theIndex) const
  {
    theIndex = (theIndex << 16) | (theIndex >> 16);
    theIndex = ((theIndex & 0x00ff00ff) << 8) | ((theIndex & 0xff00ff00) >> 8);
    theIndex = ((theIndex & 0x0f0f0f0f) << 4) | ((theIndex & 0xf0f0f0f0) >> 4);
    theIndex = ((theIndex & 0x33333333) << 2) | ((theIndex & 0xcccccccc) >> 2);
    theIndex = ((theIndex & 0x55555555) << 1) | ((theIndex & 0xaaaaaaaa) >> 1);

    // Write reversed bits directly into floating-point mantissa
    union { unsigned u; float f; } aResult;
    aResult.u = 0x3f800000u | (theIndex >> 9);
    return aResult.f - 1.0f;
  }

  //! Radical inverse in base 3 using permutation table.
  float halton3(unsigned theIndex) const
  {
    return (myPerm3[theIndex % 243u] * 14348907u +
            myPerm3[(theIndex / 243u) % 243u] * 59049u +
            myPerm3[(theIndex / 59049u) % 243u] * 243u +
            myPerm3[(theIndex / 14348907u) % 243u])
           * float(0.999999999999999 / 3486784401u);
  }

  //! Radical inverse in base 5 using permutation table.
  float halton5(unsigned theIndex) const
  {
    return (myPerm5[theIndex % 125u] * 1953125u +
            myPerm5[(theIndex / 125u) % 125u] * 15625u +
            myPerm5[(theIndex / 15625u) % 125u] * 125u +
            myPerm5[(theIndex / 1953125u) % 125u])
           * float(0.999999999999999 / 244140625u);
  }

private:

  unsigned short myPerm3[243]; //!< Permutation table for base 3
  unsigned short myPerm5[125]; //!< Permutation table for base 5
};

#endif // Metal_HaltonSampler_HeaderFile
