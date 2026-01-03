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

#include <Metal_FrameStats.hxx>
#include <Metal_View.hxx>
#include <Graphic3d_CStructure.hxx>
#include <Graphic3d_Layer.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_FrameStats, Graphic3d_FrameStats)

// =======================================================================
// function : Metal_FrameStats
// purpose  : Constructor
// =======================================================================
Metal_FrameStats::Metal_FrameStats()
: myTextureMemory(0),
  myBufferMemory(0),
  myDrawCalls(0),
  myTrianglesCount(0),
  myLinesCount(0),
  myPointsCount(0),
  myGpuTime(0.0)
{
  //
}

// =======================================================================
// function : ~Metal_FrameStats
// purpose  : Destructor
// =======================================================================
Metal_FrameStats::~Metal_FrameStats()
{
  //
}

// =======================================================================
// function : updateStatistics
// purpose  : Collect statistics from the view
// =======================================================================
void Metal_FrameStats::updateStatistics(const occ::handle<Graphic3d_CView>& theView,
                                         bool theIsImmediateOnly)
{
  if (theView.IsNull())
  {
    return;
  }

  // Get active data frame for modification
  Graphic3d_FrameStatsDataTmp& aData = ActiveDataFrame();

  // Count layers
  const NCollection_List<occ::handle<Graphic3d_Layer>>& aLayers = theView->Layers();
  size_t aNbLayers = 0;
  size_t aNbStructs = 0;
  size_t aNbLayersRendered = 0;
  size_t aNbStructsRendered = 0;
  size_t aNbGroupsRendered = 0;
  size_t aNbElemsRendered = 0;
  size_t aNbTriangles = 0;
  size_t aNbLines = 0;
  size_t aNbPoints = 0;
  size_t aNbFillElems = 0;
  size_t aNbLineElems = 0;
  size_t aNbPointElems = 0;
  size_t aNbTextElems = 0;

  // Immediate layer counters
  size_t aNbLayersImmediate = 0;
  size_t aNbStructsImmediate = 0;
  size_t aNbGroupsImmediate = 0;
  size_t aNbElemsImmediate = 0;
  size_t aNbTrianglesImmediate = 0;
  size_t aNbLinesImmediate = 0;
  size_t aNbPointsImmediate = 0;
  size_t aNbFillElemsImmediate = 0;
  size_t aNbLineElemsImmediate = 0;
  size_t aNbPointElemsImmediate = 0;
  size_t aNbTextElemsImmediate = 0;

  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(aLayers);
       aLayerIter.More(); aLayerIter.Next())
  {
    const occ::handle<Graphic3d_Layer>& aLayer = aLayerIter.Value();
    if (aLayer.IsNull())
    {
      continue;
    }

    ++aNbLayers;

    // Count structures in layer
    int aNbLayerStructs = aLayer->NbStructures();
    int aNbLayerStructsNotCulled = aLayer->NbStructuresNotCulled();
    aNbStructs += aNbLayerStructs;

    // Check if layer has visible structures
    if (aNbLayerStructs > 0)
    {
      ++aNbLayersRendered;
    }

    aNbStructsRendered += aNbLayerStructsNotCulled;

    if (aLayer->IsImmediate())
    {
      ++aNbLayersImmediate;
      aNbStructsImmediate += aNbLayerStructsNotCulled;
    }
  }

  // Update scene counters (overall)
  aData[Graphic3d_FrameStatsCounter_NbLayers] = aNbLayers;
  aData[Graphic3d_FrameStatsCounter_NbStructs] = aNbStructs;

  // Update GPU memory counters
  aData[Graphic3d_FrameStatsCounter_EstimatedBytesGeom] = myBufferMemory;
  aData[Graphic3d_FrameStatsCounter_EstimatedBytesTextures] = myTextureMemory;
  aData[Graphic3d_FrameStatsCounter_EstimatedBytesFbos] = 0;

  // Update rendered counters
  aData[Graphic3d_FrameStatsCounter_NbLayersNotCulled] = aNbLayersRendered;
  aData[Graphic3d_FrameStatsCounter_NbStructsNotCulled] = aNbStructsRendered;
  aData[Graphic3d_FrameStatsCounter_NbGroupsNotCulled] = aNbGroupsRendered;
  aData[Graphic3d_FrameStatsCounter_NbElemsNotCulled] = aNbElemsRendered;
  aData[Graphic3d_FrameStatsCounter_NbElemsFillNotCulled] = aNbFillElems;
  aData[Graphic3d_FrameStatsCounter_NbElemsLineNotCulled] = aNbLineElems;
  aData[Graphic3d_FrameStatsCounter_NbElemsPointNotCulled] = aNbPointElems;
  aData[Graphic3d_FrameStatsCounter_NbElemsTextNotCulled] = aNbTextElems;

  // Use our tracked primitive counts if available
  if (myTrianglesCount > 0 || myLinesCount > 0 || myPointsCount > 0)
  {
    aData[Graphic3d_FrameStatsCounter_NbTrianglesNotCulled] = (size_t)myTrianglesCount;
    aData[Graphic3d_FrameStatsCounter_NbLinesNotCulled] = (size_t)myLinesCount;
    aData[Graphic3d_FrameStatsCounter_NbPointsNotCulled] = (size_t)myPointsCount;
  }
  else
  {
    aData[Graphic3d_FrameStatsCounter_NbTrianglesNotCulled] = aNbTriangles;
    aData[Graphic3d_FrameStatsCounter_NbLinesNotCulled] = aNbLines;
    aData[Graphic3d_FrameStatsCounter_NbPointsNotCulled] = aNbPoints;
  }

  // Update immediate layer counters
  aData[Graphic3d_FrameStatsCounter_NbLayersImmediate] = aNbLayersImmediate;
  aData[Graphic3d_FrameStatsCounter_NbStructsImmediate] = aNbStructsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbGroupsImmediate] = aNbGroupsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbElemsImmediate] = aNbElemsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbElemsFillImmediate] = aNbFillElemsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbElemsLineImmediate] = aNbLineElemsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbElemsPointImmediate] = aNbPointElemsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbElemsTextImmediate] = aNbTextElemsImmediate;
  aData[Graphic3d_FrameStatsCounter_NbTrianglesImmediate] = aNbTrianglesImmediate;
  aData[Graphic3d_FrameStatsCounter_NbLinesImmediate] = aNbLinesImmediate;
  aData[Graphic3d_FrameStatsCounter_NbPointsImmediate] = aNbPointsImmediate;

  (void)theIsImmediateOnly;
}
