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

#ifndef Metal_FrameStatsPrs_HeaderFile
#define Metal_FrameStatsPrs_HeaderFile

#include <Standard_Transient.hxx>
#include <Standard_Handle.hxx>
#include <Graphic3d_AspectText3d.hxx>
#include <TCollection_AsciiString.hxx>
#include <NCollection_Vec2.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
@protocol MTLRenderPipelineState;
#endif

class Metal_Context;
class Metal_FrameStats;
class Metal_Workspace;

//! On-screen presentation of frame statistics.
//! Renders FPS, draw calls, triangle counts, and memory usage
//! as a text overlay in the viewport corner.
class Metal_FrameStatsPrs : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_FrameStatsPrs, Standard_Transient)

public:

  //! Default constructor.
  Standard_EXPORT Metal_FrameStatsPrs();

  //! Destructor.
  Standard_EXPORT ~Metal_FrameStatsPrs();

  //! Render the statistics overlay.
  //! @param theWorkspace rendering workspace
  Standard_EXPORT void Render(const occ::handle<Metal_Workspace>& theWorkspace) const;

  //! Release Metal resources.
  //! @param theCtx Metal context
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Update statistics text from frame stats.
  //! @param theWorkspace workspace with current stats
  Standard_EXPORT void Update(const occ::handle<Metal_Workspace>& theWorkspace);

  //! Return TRUE if presentation needs update.
  bool NeedsUpdate() const { return myNeedsUpdate; }

  //! Set update flag.
  void SetNeedsUpdate(bool theFlag) { myNeedsUpdate = theFlag; }

  //! Set text aspect for rendering.
  void SetTextAspect(const occ::handle<Graphic3d_AspectText3d>& theAspect)
  {
    myTextAspect = theAspect;
  }

  //! Return text aspect.
  const occ::handle<Graphic3d_AspectText3d>& TextAspect() const { return myTextAspect; }

  //! Set position in viewport (normalized 0-1).
  void SetPosition(float theX, float theY)
  {
    myPosition = NCollection_Vec2<float>(theX, theY);
  }

  //! Return position.
  const NCollection_Vec2<float>& Position() const { return myPosition; }

  //! Enable/disable chart display.
  void SetShowChart(bool theShow) { myShowChart = theShow; }

  //! Return TRUE if chart is shown.
  bool ShowChart() const { return myShowChart; }

  //! Set chart size in pixels.
  void SetChartSize(int theWidth, int theHeight)
  {
    myChartWidth = theWidth;
    myChartHeight = theHeight;
  }

public: //! @name Statistics formatting

  //! Format FPS value as string.
  Standard_EXPORT static TCollection_AsciiString FormatFps(double theFps);

  //! Format memory size as human-readable string.
  Standard_EXPORT static TCollection_AsciiString FormatMemory(size_t theBytes);

  //! Format large count with suffixes (K, M).
  Standard_EXPORT static TCollection_AsciiString FormatCount(int64_t theCount);

protected:

  //! Build statistics text.
  Standard_EXPORT void buildText(const occ::handle<Metal_FrameStats>& theStats);

  //! Build chart geometry.
  Standard_EXPORT void buildChart(const occ::handle<Metal_FrameStats>& theStats);

protected:

  occ::handle<Graphic3d_AspectText3d> myTextAspect; //!< text rendering aspect
  TCollection_AsciiString myStatsText;              //!< formatted stats text
  NCollection_Vec2<float> myPosition;               //!< position in viewport (0-1)
  int     myChartWidth;   //!< chart width in pixels
  int     myChartHeight;  //!< chart height in pixels
  bool    myShowChart;    //!< show performance chart
  bool    myNeedsUpdate;  //!< flag indicating update needed

  // FPS history for chart
  static const int FPS_HISTORY_SIZE = 60;
  float   myFpsHistory[FPS_HISTORY_SIZE]; //!< FPS values for chart
  int     myFpsHistoryIndex;              //!< current index in history

#ifdef __OBJC__
  id<MTLBuffer> myTextBuffer;   //!< buffer for text vertices
  id<MTLBuffer> myChartBuffer;  //!< buffer for chart vertices
#else
  void* myTextBuffer;
  void* myChartBuffer;
#endif
};

DEFINE_STANDARD_HANDLE(Metal_FrameStatsPrs, Standard_Transient)

#endif // Metal_FrameStatsPrs_HeaderFile
