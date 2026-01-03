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
#include <Metal_View.hxx>
#include <Aspect_TypeOfTriedronPosition.hxx>
#include <Graphic3d_Text.hxx>

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

  // Initialize transform persistence for upper-left corner
  myCountersTrsfPers = new Graphic3d_TransformPers(
    Graphic3d_TMF_2d,
    Aspect_TOTP_LEFT_UPPER,
    NCollection_Vec2<int>(20, 20));

  // Create text element (will be updated dynamically with real stats)
  occ::handle<Graphic3d_Text> aTextParams = new Graphic3d_Text(14.0f);
  aTextParams->SetText("FPS: --"); // Initial text, updated by buildText()
  aTextParams->SetHorizontalAlignment(Graphic3d_HTA_LEFT);
  aTextParams->SetVerticalAlignment(Graphic3d_VTA_TOP);
  myCountersText = new Metal_Text(aTextParams);
  myCountersText->Set2D(true);
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
void Metal_FrameStatsPrs::Release(Metal_Context* theCtx)
{
  if (!myCountersText.IsNull())
  {
    myCountersText->Release(theCtx);
  }
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

  // Get frame stats from context
  Metal_Context* aCtx = theWorkspace->Context();
  occ::handle<Metal_FrameStats> aStats = aCtx != nullptr ? aCtx->FrameStats() : nullptr;

  // Update transform persistence from view rendering params
  Metal_View* aView = theWorkspace->View();
  if (aView != nullptr)
  {
    myCountersTrsfPers = aView->RenderingParams().StatsPosition;
    if (myTextAspect.IsNull())
    {
      myTextAspect = aView->RenderingParams().StatsTextAspect;
    }
  }

  buildText(aStats);

  // Update the counters text element
  if (!myCountersText.IsNull())
  {
    occ::handle<Graphic3d_Text> aText = myCountersText->Text();
    if (!aText.IsNull())
    {
      aText->SetText(myStatsText.ToCString());

      // Adjust alignment based on corner
      if (!myCountersTrsfPers.IsNull())
      {
        const int aCorner = myCountersTrsfPers->Corner2d();
        if ((aCorner & Aspect_TOTP_LEFT) != 0)
        {
          aText->SetHorizontalAlignment(Graphic3d_HTA_LEFT);
        }
        else if ((aCorner & Aspect_TOTP_RIGHT) != 0)
        {
          aText->SetHorizontalAlignment(Graphic3d_HTA_RIGHT);
        }
        if ((aCorner & Aspect_TOTP_TOP) != 0)
        {
          aText->SetVerticalAlignment(Graphic3d_VTA_TOP);
        }
        else if ((aCorner & Aspect_TOTP_BOTTOM) != 0)
        {
          aText->SetVerticalAlignment(Graphic3d_VTA_BOTTOM);
        }
      }
    }
  }

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
// purpose  : Build FPS chart geometry from FPS history
// =======================================================================
void Metal_FrameStatsPrs::buildChart(const occ::handle<Metal_FrameStats>& theStats)
{
  if (theStats.IsNull())
  {
    return;
  }

  // Chart rendering uses the FPS history data stored in myFpsHistory[]
  // The chart is built as a series of vertical bars, one per frame
  //
  // Color coding:
  // - Green: FPS >= 60 (good performance)
  // - Yellow: 30 <= FPS < 60 (medium performance)
  // - Red: FPS < 30 (poor performance)
  //
  // Note: Full chart rendering would require additional vertex buffer
  // management and a separate render pass. The current implementation
  // relies on the text statistics which provide the key metrics.
  // Chart geometry would be built here and rendered in Render() method.
}

// =======================================================================
// function : Render
// purpose  : Render statistics overlay
// =======================================================================
void Metal_FrameStatsPrs::Render(const occ::handle<Metal_Workspace>& theWorkspace) const
{
  if (theWorkspace.IsNull() || myCountersText.IsNull())
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nullptr)
  {
    return;
  }

  // Disable depth writing for overlay
  const bool wasDepthWrite = aCtx->DepthMask();
  if (wasDepthWrite)
  {
    aCtx->SetDepthMask(false);
  }

  // Apply transform persistence for 2D positioning
  // Note: Metal_Text with 2D mode handles screen-space positioning

  // Render the counters text
  myCountersText->Render(theWorkspace.get());

  // Restore depth write state
  if (wasDepthWrite)
  {
    aCtx->SetDepthMask(wasDepthWrite);
  }
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
