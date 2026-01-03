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
  (void)theView;
  (void)theIsImmediateOnly;
  // Metal-specific statistics collection would go here
  // For now, statistics are updated manually via AddDrawCall(), SetGpuMemory(), etc.
}
