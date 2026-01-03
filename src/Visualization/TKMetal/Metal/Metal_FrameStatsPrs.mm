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

#include <Metal_FrameStatsPrs.hxx>
#include <Metal_FrameStats.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>

#include <cstdio>
#include <cstring>

IMPLEMENT_STANDARD_RTTIEXT(Metal_FrameStatsPrs, Standard_Transient)

// =======================================================================
// function : Metal_FrameStatsPrs
// purpose  : Constructor
// =======================================================================
Metal_FrameStatsPrs::Metal_FrameStatsPrs()
: myPosition(0.01f, 0.98f),
  myChartWidth(200),
  myChartHeight(100),
  myShowChart(true),
  myNeedsUpdate(true),
  myFpsHistoryIndex(0),
  myTextBuffer(nil),
  myChartBuffer(nil)
{
  memset(myFpsHistory, 0, sizeof(myFpsHistory));
}

// =======================================================================
// function : ~Metal_FrameStatsPrs
// purpose  : Destructor
// =======================================================================
Metal_FrameStatsPrs::~Metal_FrameStatsPrs()
{
  Release(nullptr);
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_FrameStatsPrs::Release(Metal_Context* /*theCtx*/)
{
  myTextBuffer = nil;
  myChartBuffer = nil;
}

// =======================================================================
// function : Update
// purpose  : Update statistics from workspace
// =======================================================================
void Metal_FrameStatsPrs::Update(const occ::handle<Metal_Workspace>& theWorkspace)
{
  if (theWorkspace.IsNull())
  {
    return;
  }

  // Get frame stats from workspace
  // For now, create placeholder text
  occ::handle<Metal_FrameStats> aStats; // = theWorkspace->FrameStats();

  buildText(aStats);

  if (myShowChart)
  {
    buildChart(aStats);
  }

  myNeedsUpdate = false;
}

// =======================================================================
// function : buildText
// purpose  : Build statistics text
// =======================================================================
void Metal_FrameStatsPrs::buildText(const occ::handle<Metal_FrameStats>& theStats)
{
  myStatsText.Clear();

  if (theStats.IsNull())
  {
    myStatsText = "FPS: --\nDraw calls: --\nTriangles: --\nMemory: --";
    return;
  }

  // Format statistics
  char aBuffer[512];
  snprintf(aBuffer, sizeof(aBuffer),
           "FPS: %.1f\n"
           "CPU: %.2f ms\n"
           "GPU: %.2f ms\n"
           "Draw calls: %d\n"
           "Triangles: %s\n"
           "Lines: %s\n"
           "Points: %s\n"
           "Textures: %s\n"
           "Buffers: %s",
           theStats->FrameRate(),
           theStats->CpuTime() * 1000.0,
           theStats->GpuTime() * 1000.0,
           theStats->DrawCalls(),
           FormatCount(theStats->TrianglesCount()).ToCString(),
           FormatCount(theStats->LinesCount()).ToCString(),
           FormatCount(theStats->PointsCount()).ToCString(),
           FormatMemory(theStats->TextureMemory()).ToCString(),
           FormatMemory(theStats->BufferMemory()).ToCString());

  myStatsText = aBuffer;

  // Update FPS history for chart
  myFpsHistory[myFpsHistoryIndex] = static_cast<float>(theStats->FrameRate());
  myFpsHistoryIndex = (myFpsHistoryIndex + 1) % FPS_HISTORY_SIZE;
}

// =======================================================================
// function : buildChart
// purpose  : Build FPS chart geometry
// =======================================================================
void Metal_FrameStatsPrs::buildChart(const occ::handle<Metal_FrameStats>& /*theStats*/)
{
  // Chart rendering would go here
  // For now, just a placeholder
}

// =======================================================================
// function : Render
// purpose  : Render statistics overlay
// =======================================================================
void Metal_FrameStatsPrs::Render(const occ::handle<Metal_Workspace>& /*theWorkspace*/) const
{
  // Text rendering using Metal_Text would go here
  // This is a stub - actual implementation would use workspace's
  // text rendering facilities
}

// =======================================================================
// function : FormatFps
// purpose  : Format FPS value
// =======================================================================
TCollection_AsciiString Metal_FrameStatsPrs::FormatFps(double theFps)
{
  char aBuffer[32];
  if (theFps >= 100.0)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.0f", theFps);
  }
  else if (theFps >= 10.0)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.1f", theFps);
  }
  else
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.2f", theFps);
  }
  return TCollection_AsciiString(aBuffer);
}

// =======================================================================
// function : FormatMemory
// purpose  : Format memory size as human-readable string
// =======================================================================
TCollection_AsciiString Metal_FrameStatsPrs::FormatMemory(size_t theBytes)
{
  char aBuffer[32];

  if (theBytes >= 1024 * 1024 * 1024)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.2f GB",
             static_cast<double>(theBytes) / (1024.0 * 1024.0 * 1024.0));
  }
  else if (theBytes >= 1024 * 1024)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.1f MB",
             static_cast<double>(theBytes) / (1024.0 * 1024.0));
  }
  else if (theBytes >= 1024)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.0f KB",
             static_cast<double>(theBytes) / 1024.0);
  }
  else
  {
    snprintf(aBuffer, sizeof(aBuffer), "%zu B", theBytes);
  }

  return TCollection_AsciiString(aBuffer);
}

// =======================================================================
// function : FormatCount
// purpose  : Format large count with suffixes
// =======================================================================
TCollection_AsciiString Metal_FrameStatsPrs::FormatCount(int64_t theCount)
{
  char aBuffer[32];

  if (theCount >= 1000000000)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.2f G", static_cast<double>(theCount) / 1000000000.0);
  }
  else if (theCount >= 1000000)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.2f M", static_cast<double>(theCount) / 1000000.0);
  }
  else if (theCount >= 1000)
  {
    snprintf(aBuffer, sizeof(aBuffer), "%.1f K", static_cast<double>(theCount) / 1000.0);
  }
  else
  {
    snprintf(aBuffer, sizeof(aBuffer), "%lld", theCount);
  }

  return TCollection_AsciiString(aBuffer);
}
