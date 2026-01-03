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

#ifndef Metal_TileSampler_HeaderFile
#define Metal_TileSampler_HeaderFile

#include <Metal_HaltonSampler.hxx>
#include <Metal_Texture.hxx>
#include <NCollection_Vec2.hxx>
#include <Image_PixMapTypedData.hxx>
#include <Standard_Handle.hxx>

#include <vector>

class Graphic3d_RenderingParams;
class Metal_Context;

//! Tool object for sampling screen tiles according to estimated pixel variance.
//! Used in progressive path tracing to prioritize noisy regions.
//!
//! The rendering window is split into tiles (pixel blocks) to improve GPU coherency.
//! Tiles with higher variance (noise) are sampled more frequently, leading to
//! faster visual convergence while maintaining interactivity.
//!
//! Key features:
//! - Adaptive tile selection based on variance estimation
//! - Halton sequence for quasi-random tile sampling
//! - Configurable tile size and sample distribution
//! - GPU texture upload for shader access
class Metal_TileSampler
{
public:

  //! Create tile sampler with default settings.
  Standard_EXPORT Metal_TileSampler();

  //! Destructor.
  Standard_EXPORT ~Metal_TileSampler();

  //! Return size of individual tile in pixels.
  NCollection_Vec2<int> TileSize() const { return NCollection_Vec2<int>(myTileSize, myTileSize); }

  //! Return scale factor for quantization of visual error.
  float VarianceScaleFactor() const { return myScaleFactor; }

  //! Return number of tiles in X dimension.
  int NbTilesX() const { return (int)myTiles.SizeX; }

  //! Return number of tiles in Y dimension.
  int NbTilesY() const { return (int)myTiles.SizeY; }

  //! Return total number of tiles.
  int NbTiles() const { return int(myTiles.SizeX * myTiles.SizeY); }

  //! Return ray-tracing viewport size.
  const NCollection_Vec2<int>& ViewSize() const { return myViewSize; }

  //! Return number of offset tiles (adaptive or non-adaptive).
  NCollection_Vec2<int> NbOffsetTiles(bool theAdaptive) const
  {
    return theAdaptive
             ? NCollection_Vec2<int>((int)myOffsetsShrunk.SizeX, (int)myOffsetsShrunk.SizeY)
             : NCollection_Vec2<int>((int)myOffsets.SizeX, (int)myOffsets.SizeY);
  }

  //! Return maximum number of offset tiles.
  NCollection_Vec2<int> NbOffsetTilesMax() const
  {
    return NbOffsetTiles(true).IsEqual(NCollection_Vec2<int>(0, 0))
             ? NbOffsetTiles(false)
             : NbOffsetTiles(true);
  }

  //! Return viewport for rendering using offsets texture.
  NCollection_Vec2<int> OffsetTilesViewport(bool theAdaptive) const
  {
    return NbOffsetTiles(theAdaptive) * myTileSize;
  }

  //! Return maximum viewport for rendering using offsets texture.
  NCollection_Vec2<int> OffsetTilesViewportMax() const
  {
    return NbOffsetTilesMax() * myTileSize;
  }

  //! Return maximum number of samples per tile.
  int MaxTileSamples() const
  {
    int aNbSamples = 0;
    for (size_t aRowIter = 0; aRowIter < myTiles.SizeY; ++aRowIter)
    {
      for (size_t aColIter = 0; aColIter < myTiles.SizeX; ++aColIter)
      {
        aNbSamples = std::max(aNbSamples, static_cast<int>(myTiles.Value(aRowIter, aColIter)));
      }
    }
    return aNbSamples;
  }

  //! Set viewport size and recompute tile layout.
  //! @param theParams rendering parameters
  //! @param theSize viewport size in pixels
  Standard_EXPORT void SetSize(const Graphic3d_RenderingParams& theParams,
                               const NCollection_Vec2<int>& theSize);

  //! Fetch variance map from GPU and build tile sampling distribution.
  //! @param theCtx Metal context
  //! @param theTexture variance texture from GPU
  Standard_EXPORT void GrabVarianceMap(Metal_Context* theCtx,
                                       const occ::handle<Metal_Texture>& theTexture);

  //! Reset tile sampler to initial state.
  void Reset() { myLastSample = 0; }

  //! Upload tile samples to GPU texture.
  //! @param theCtx Metal context
  //! @param theSamplesTexture target texture
  //! @param theAdaptive use adaptive sampling
  //! @return true on success
  Standard_EXPORT bool UploadSamples(Metal_Context* theCtx,
                                     const occ::handle<Metal_Texture>& theSamplesTexture,
                                     bool theAdaptive);

  //! Upload tile offsets to GPU texture.
  //! @param theCtx Metal context
  //! @param theOffsetsTexture target texture
  //! @param theAdaptive use adaptive sampling
  //! @return true on success
  Standard_EXPORT bool UploadOffsets(Metal_Context* theCtx,
                                     const occ::handle<Metal_Texture>& theOffsetsTexture,
                                     bool theAdaptive);

  //! Return current sample index.
  unsigned int CurrentSample() const { return myLastSample; }

  //! Set current sample index.
  void SetCurrentSample(unsigned int theSample) { myLastSample = theSample; }

protected:

  //! Return pixel area of tile at given position.
  int tileArea(int theX, int theY) const
  {
    const int aSizeX = std::min(myTileSize, myViewSize.x() - theX * myTileSize);
    const int aSizeY = std::min(myTileSize, myViewSize.y() - theY * myTileSize);
    return aSizeX * aSizeY;
  }

  //! Sample next tile based on variance distribution.
  Standard_EXPORT NCollection_Vec2<int> nextTileToSample();

  //! Upload data to GPU textures.
  Standard_EXPORT bool upload(Metal_Context* theCtx,
                              const occ::handle<Metal_Texture>& theSamplesTexture,
                              const occ::handle<Metal_Texture>& theOffsetsTexture,
                              bool theAdaptive);

protected:

  Image_PixMapTypedData<unsigned int> myTiles;         //!< Samples per tile
  Image_PixMapTypedData<unsigned int> myTileSamples;   //!< Total samples for tile pixels
  Image_PixMapTypedData<float>        myVarianceMap;   //!< Per-tile variance estimate
  Image_PixMapTypedData<int>          myVarianceRaw;   //!< Raw variance data

  Image_PixMapTypedData<NCollection_Vec2<int>> myOffsets;       //!< Tile redirect map
  Image_PixMapTypedData<NCollection_Vec2<int>> myOffsetsShrunk; //!< Shrunk tile redirect map

  std::vector<float>   myMarginalMap;   //!< Marginal distribution for sampling
  Metal_HaltonSampler  mySampler;       //!< Halton sequence generator
  unsigned int         myLastSample;    //!< Current sample index
  float                myScaleFactor;   //!< Variance quantization scale
  int                  myTileSize;      //!< Tile size in pixels
  NCollection_Vec2<int> myViewSize;     //!< Viewport size
};

#endif // Metal_TileSampler_HeaderFile
