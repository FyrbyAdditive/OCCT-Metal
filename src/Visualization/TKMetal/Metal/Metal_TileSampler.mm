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

#include <Metal_TileSampler.hxx>
#include <Metal_Context.hxx>
#include <Metal_Texture.hxx>
#include <Graphic3d_RenderingParams.hxx>

#include <algorithm>
#include <cmath>

// =======================================================================
// function : Metal_TileSampler
// purpose  : Constructor
// =======================================================================
Metal_TileSampler::Metal_TileSampler()
: myLastSample(0),
  myScaleFactor(1.0e6f),
  myTileSize(32),
  myViewSize(0, 0)
{
  //
}

// =======================================================================
// function : ~Metal_TileSampler
// purpose  : Destructor
// =======================================================================
Metal_TileSampler::~Metal_TileSampler()
{
  //
}

// =======================================================================
// function : SetSize
// purpose  : Set viewport size and compute tile layout
// =======================================================================
void Metal_TileSampler::SetSize(const Graphic3d_RenderingParams& theParams,
                                const NCollection_Vec2<int>& theSize)
{
  // Determine optimal tile size based on rendering parameters
  myTileSize = 32; // Default tile size

  if (theParams.AdaptiveScreenSampling)
  {
    // Use smaller tiles for adaptive sampling (more granular control)
    myTileSize = std::max(8, std::min(32, theParams.RayTracingTileSize));
  }

  myViewSize = theSize;

  // Compute number of tiles
  const int aNbTilesX = (myViewSize.x() + myTileSize - 1) / myTileSize;
  const int aNbTilesY = (myViewSize.y() + myTileSize - 1) / myTileSize;

  // Initialize tiles with 1 sample each
  myTiles.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  for (size_t aRow = 0; aRow < myTiles.SizeY; ++aRow)
  {
    for (size_t aCol = 0; aCol < myTiles.SizeX; ++aCol)
    {
      myTiles.ChangeValue(aRow, aCol) = 1;
    }
  }

  // Initialize tile samples (total pixels per tile)
  myTileSamples.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  for (int aRow = 0; aRow < aNbTilesY; ++aRow)
  {
    for (int aCol = 0; aCol < aNbTilesX; ++aCol)
    {
      myTileSamples.ChangeValue(aRow, aCol) = tileArea(aCol, aRow);
    }
  }

  // Initialize variance map
  myVarianceMap.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  myVarianceRaw.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  for (size_t aRow = 0; aRow < myVarianceMap.SizeY; ++aRow)
  {
    for (size_t aCol = 0; aCol < myVarianceMap.SizeX; ++aCol)
    {
      myVarianceMap.ChangeValue(aRow, aCol) = 1.0f;
      myVarianceRaw.ChangeValue(aRow, aCol) = 1;
    }
  }

  // Initialize offset maps
  myOffsets.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  myOffsetsShrunk.Init(Standard_Size(aNbTilesX), Standard_Size(aNbTilesY));
  for (int aRow = 0; aRow < aNbTilesY; ++aRow)
  {
    for (int aCol = 0; aCol < aNbTilesX; ++aCol)
    {
      myOffsets.ChangeValue(aRow, aCol) = NCollection_Vec2<int>(aCol, aRow);
      myOffsetsShrunk.ChangeValue(aRow, aCol) = NCollection_Vec2<int>(aCol, aRow);
    }
  }

  // Initialize marginal distribution
  myMarginalMap.resize(aNbTilesY + 1, 0.0f);

  Reset();
}

// =======================================================================
// function : GrabVarianceMap
// purpose  : Fetch variance from GPU and build sampling distribution
// =======================================================================
void Metal_TileSampler::GrabVarianceMap(Metal_Context* theCtx,
                                        const occ::handle<Metal_Texture>& theTexture)
{
  if (theCtx == nullptr || theTexture.IsNull() || !theTexture->IsValid())
  {
    return;
  }

  const int aNbTilesX = NbTilesX();
  const int aNbTilesY = NbTilesY();

  if (aNbTilesX == 0 || aNbTilesY == 0)
  {
    return;
  }

  // Read variance texture from GPU
  // For now, use a simplified approach - actual implementation would
  // use a blit encoder to copy texture data to a shared buffer

  id<MTLTexture> aTexture = theTexture->TextureId();
  if (aTexture == nil)
  {
    return;
  }

  // Allocate buffer for readback
  NSUInteger aWidth = [aTexture width];
  NSUInteger aHeight = [aTexture height];

  if (aWidth != (NSUInteger)aNbTilesX || aHeight != (NSUInteger)aNbTilesY)
  {
    // Texture size doesn't match tile grid
    return;
  }

  std::vector<float> aVarianceData(aNbTilesX * aNbTilesY);

  MTLRegion aRegion = MTLRegionMake2D(0, 0, aWidth, aHeight);
  [aTexture getBytes:aVarianceData.data()
         bytesPerRow:aWidth * sizeof(float)
          fromRegion:aRegion
         mipmapLevel:0];

  // Update variance map and compute marginal distribution
  float aTotalVariance = 0.0f;

  for (int aRow = 0; aRow < aNbTilesY; ++aRow)
  {
    float aRowVariance = 0.0f;
    for (int aCol = 0; aCol < aNbTilesX; ++aCol)
    {
      float aVariance = aVarianceData[aRow * aNbTilesX + aCol];
      myVarianceMap.ChangeValue(aRow, aCol) = aVariance;
      myVarianceRaw.ChangeValue(aRow, aCol) = int(aVariance * myScaleFactor);
      aRowVariance += aVariance;
    }
    myMarginalMap[aRow] = aRowVariance;
    aTotalVariance += aRowVariance;
  }

  // Normalize marginal distribution
  if (aTotalVariance > 0.0f)
  {
    float aAccum = 0.0f;
    for (int aRow = 0; aRow < aNbTilesY; ++aRow)
    {
      aAccum += myMarginalMap[aRow] / aTotalVariance;
      myMarginalMap[aRow] = aAccum;
    }
  }
  myMarginalMap[aNbTilesY] = 1.0f;
}

// =======================================================================
// function : nextTileToSample
// purpose  : Select next tile based on variance
// =======================================================================
NCollection_Vec2<int> Metal_TileSampler::nextTileToSample()
{
  const int aNbTilesX = NbTilesX();
  const int aNbTilesY = NbTilesY();

  if (aNbTilesX == 0 || aNbTilesY == 0)
  {
    return NCollection_Vec2<int>(0, 0);
  }

  // Use Halton sequence for quasi-random sampling
  float aX, aY;
  mySampler.sample2D(myLastSample++, aX, aY);

  // Map to tile grid using marginal distribution
  int aRow = 0;
  for (int i = 0; i < aNbTilesY; ++i)
  {
    if (aY <= myMarginalMap[i])
    {
      aRow = i;
      break;
    }
  }

  // Find column based on row variance distribution
  float aRowTotal = 0.0f;
  for (int aCol = 0; aCol < aNbTilesX; ++aCol)
  {
    aRowTotal += myVarianceMap.Value(aRow, aCol);
  }

  int aCol = 0;
  if (aRowTotal > 0.0f)
  {
    float aAccum = 0.0f;
    for (int i = 0; i < aNbTilesX; ++i)
    {
      aAccum += myVarianceMap.Value(aRow, i) / aRowTotal;
      if (aX <= aAccum)
      {
        aCol = i;
        break;
      }
    }
  }
  else
  {
    aCol = int(aX * aNbTilesX) % aNbTilesX;
  }

  return NCollection_Vec2<int>(aCol, aRow);
}

// =======================================================================
// function : UploadSamples
// purpose  : Upload tile samples to GPU
// =======================================================================
bool Metal_TileSampler::UploadSamples(Metal_Context* theCtx,
                                      const occ::handle<Metal_Texture>& theSamplesTexture,
                                      bool theAdaptive)
{
  return upload(theCtx, theSamplesTexture, occ::handle<Metal_Texture>(), theAdaptive);
}

// =======================================================================
// function : UploadOffsets
// purpose  : Upload tile offsets to GPU
// =======================================================================
bool Metal_TileSampler::UploadOffsets(Metal_Context* theCtx,
                                      const occ::handle<Metal_Texture>& theOffsetsTexture,
                                      bool theAdaptive)
{
  return upload(theCtx, occ::handle<Metal_Texture>(), theOffsetsTexture, theAdaptive);
}

// =======================================================================
// function : upload
// purpose  : Upload data to GPU textures
// =======================================================================
bool Metal_TileSampler::upload(Metal_Context* theCtx,
                               const occ::handle<Metal_Texture>& theSamplesTexture,
                               const occ::handle<Metal_Texture>& theOffsetsTexture,
                               bool theAdaptive)
{
  if (theCtx == nullptr)
  {
    return false;
  }

  const int aNbTilesX = NbTilesX();
  const int aNbTilesY = NbTilesY();

  if (aNbTilesX == 0 || aNbTilesY == 0)
  {
    return false;
  }

  // Upload samples texture
  if (!theSamplesTexture.IsNull() && theSamplesTexture->IsValid())
  {
    id<MTLTexture> aTexture = theSamplesTexture->TextureId();
    if (aTexture != nil)
    {
      // Build samples data
      std::vector<unsigned int> aSamplesData(aNbTilesX * aNbTilesY);
      for (int aRow = 0; aRow < aNbTilesY; ++aRow)
      {
        for (int aCol = 0; aCol < aNbTilesX; ++aCol)
        {
          aSamplesData[aRow * aNbTilesX + aCol] = myTiles.Value(aRow, aCol);
        }
      }

      MTLRegion aRegion = MTLRegionMake2D(0, 0, aNbTilesX, aNbTilesY);
      [aTexture replaceRegion:aRegion
                  mipmapLevel:0
                    withBytes:aSamplesData.data()
                  bytesPerRow:aNbTilesX * sizeof(unsigned int)];
    }
  }

  // Upload offsets texture
  if (!theOffsetsTexture.IsNull() && theOffsetsTexture->IsValid())
  {
    id<MTLTexture> aTexture = theOffsetsTexture->TextureId();
    if (aTexture != nil)
    {
      const Image_PixMapTypedData<NCollection_Vec2<int>>& anOffsets =
        theAdaptive ? myOffsetsShrunk : myOffsets;

      // Build offsets data (RG32Sint format - 2 ints per pixel)
      std::vector<int> anOffsetsData(aNbTilesX * aNbTilesY * 2);
      for (int aRow = 0; aRow < aNbTilesY; ++aRow)
      {
        for (int aCol = 0; aCol < aNbTilesX; ++aCol)
        {
          const NCollection_Vec2<int>& anOffset = anOffsets.Value(aRow, aCol);
          int anIdx = (aRow * aNbTilesX + aCol) * 2;
          anOffsetsData[anIdx + 0] = anOffset.x();
          anOffsetsData[anIdx + 1] = anOffset.y();
        }
      }

      MTLRegion aRegion = MTLRegionMake2D(0, 0, aNbTilesX, aNbTilesY);
      [aTexture replaceRegion:aRegion
                  mipmapLevel:0
                    withBytes:anOffsetsData.data()
                  bytesPerRow:aNbTilesX * 2 * sizeof(int)];
    }
  }

  return true;
}
