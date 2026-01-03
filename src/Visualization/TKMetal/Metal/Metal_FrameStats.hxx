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

#ifndef Metal_FrameStats_HeaderFile
#define Metal_FrameStats_HeaderFile

#include <Graphic3d_FrameStats.hxx>
#include <OSD_Timer.hxx>

class Metal_View;

//! Frame statistics for Metal backend.
//! Tracks GPU/CPU timing, draw calls, primitives, and memory usage.
class Metal_FrameStats : public Graphic3d_FrameStats
{
  DEFINE_STANDARD_RTTIEXT(Metal_FrameStats, Graphic3d_FrameStats)

public:

  //! Default constructor.
  Standard_EXPORT Metal_FrameStats();

  //! Destructor.
  Standard_EXPORT ~Metal_FrameStats() override;

  //! Copy counters from another source (used for synchronized views).
  void CopyFrom(const occ::handle<Graphic3d_FrameStats>& theOther)
  {
    if (!theOther.IsNull())
    {
      // Copy counters logic would go here
    }
  }

public: //! @name GPU timing

  //! Return estimated GPU memory used by textures in bytes.
  size_t TextureMemory() const { return myTextureMemory; }

  //! Return estimated GPU memory used by vertex buffers in bytes.
  size_t BufferMemory() const { return myBufferMemory; }

  //! Return total estimated GPU memory in bytes.
  size_t TotalGpuMemory() const { return myTextureMemory + myBufferMemory; }

  //! Update GPU memory statistics.
  void SetGpuMemory(size_t theTextureMemory, size_t theBufferMemory)
  {
    myTextureMemory = theTextureMemory;
    myBufferMemory = theBufferMemory;
  }

public: //! @name Draw call statistics

  //! Return number of draw calls in last frame.
  int DrawCalls() const { return myDrawCalls; }

  //! Return number of triangles rendered in last frame.
  int64_t TrianglesCount() const { return myTrianglesCount; }

  //! Return number of lines rendered in last frame.
  int64_t LinesCount() const { return myLinesCount; }

  //! Return number of points rendered in last frame.
  int64_t PointsCount() const { return myPointsCount; }

  //! Reset draw statistics for new frame.
  void ResetDrawStats()
  {
    myDrawCalls = 0;
    myTrianglesCount = 0;
    myLinesCount = 0;
    myPointsCount = 0;
  }

  //! Add draw call with primitive counts.
  void AddDrawCall(int theTriangles, int theLines, int thePoints)
  {
    myDrawCalls++;
    myTrianglesCount += theTriangles;
    myLinesCount += theLines;
    myPointsCount += thePoints;
  }

public: //! @name Timing

  //! Start CPU timer.
  void StartCpuTimer() { myCpuTimer.Start(); }

  //! Stop CPU timer.
  void StopCpuTimer() { myCpuTimer.Stop(); }

  //! Return CPU time in seconds.
  double CpuTime() const { return myCpuTimer.ElapsedTime(); }

  //! Reset CPU timer.
  void ResetCpuTimer() { myCpuTimer.Reset(); }

  //! Return GPU time in seconds (if GPU timing is available).
  double GpuTime() const { return myGpuTime; }

  //! Set GPU time.
  void SetGpuTime(double theTime) { myGpuTime = theTime; }

protected:

  // GPU memory
  size_t myTextureMemory;  //!< texture memory in bytes
  size_t myBufferMemory;   //!< buffer memory in bytes

  // Draw statistics
  int     myDrawCalls;      //!< number of draw calls
  int64_t myTrianglesCount; //!< number of triangles
  int64_t myLinesCount;     //!< number of lines
  int64_t myPointsCount;    //!< number of points

  // Timing
  OSD_Timer myCpuTimer;  //!< CPU timer
  double    myGpuTime;   //!< GPU time in seconds
};

DEFINE_STANDARD_HANDLE(Metal_FrameStats, Graphic3d_FrameStats)

#endif // Metal_FrameStats_HeaderFile
