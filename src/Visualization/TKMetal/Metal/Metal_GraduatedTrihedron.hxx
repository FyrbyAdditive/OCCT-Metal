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

#ifndef Metal_GraduatedTrihedron_HeaderFile
#define Metal_GraduatedTrihedron_HeaderFile

#include <Graphic3d_GraduatedTrihedron.hxx>
#include <NCollection_Vec3.hxx>

class Metal_Context;
class Metal_Workspace;
class Metal_Text;

//! Graduated trihedron (axis with tick marks and labels) for Metal.
//! Renders X/Y/Z axes with configurable graduation, labels, and colors.
class Metal_GraduatedTrihedron
{
public:

  //! Default constructor.
  Metal_GraduatedTrihedron()
  : myIsEnabled(false),
    myDrawGrid(true),
    myDrawAxes(true),
    myDrawLabels(true),
    myDrawTicks(true),
    myTickmarkLength(5.0f),
    myNeedsRebuild(true),
    myCachedPositionBuffer(nullptr),
    myCachedColorBuffer(nullptr),
    myCachedVertexCount(0)
  {
    // Default axis colors
    myXColor = NCollection_Vec3<float>(1.0f, 0.0f, 0.0f);
    myYColor = NCollection_Vec3<float>(0.0f, 1.0f, 0.0f);
    myZColor = NCollection_Vec3<float>(0.0f, 0.0f, 1.0f);

    // Default grid color
    myGridColor = NCollection_Vec3<float>(0.5f, 0.5f, 0.5f);

    // Initialize cached bounds to invalid
    myCachedMin = NCollection_Vec3<float>(0.0f, 0.0f, 0.0f);
    myCachedMax = NCollection_Vec3<float>(0.0f, 0.0f, 0.0f);
  }

  //! Destructor.
  ~Metal_GraduatedTrihedron() {}

  //! Return true if graduated trihedron is enabled.
  bool IsEnabled() const { return myIsEnabled; }

  //! Enable/disable graduated trihedron.
  void SetEnabled(bool theValue) { myIsEnabled = theValue; }

  //! Return true if grid is drawn.
  bool ToDrawGrid() const { return myDrawGrid; }

  //! Set grid drawing.
  void SetDrawGrid(bool theValue)
  {
    if (myDrawGrid != theValue)
    {
      myDrawGrid = theValue;
      myNeedsRebuild = true;
    }
  }

  //! Return true if axes are drawn.
  bool ToDrawAxes() const { return myDrawAxes; }

  //! Set axes drawing.
  void SetDrawAxes(bool theValue)
  {
    if (myDrawAxes != theValue)
    {
      myDrawAxes = theValue;
      myNeedsRebuild = true;
    }
  }

  //! Return true if labels are drawn.
  bool ToDrawLabels() const { return myDrawLabels; }

  //! Set label drawing.
  void SetDrawLabels(bool theValue)
  {
    if (myDrawLabels != theValue)
    {
      myDrawLabels = theValue;
      myNeedsRebuild = true;
    }
  }

  //! Return true if tick marks are drawn.
  bool ToDrawTicks() const { return myDrawTicks; }

  //! Set tick mark drawing.
  void SetDrawTicks(bool theValue)
  {
    if (myDrawTicks != theValue)
    {
      myDrawTicks = theValue;
      myNeedsRebuild = true;
    }
  }

  //! Set X axis color.
  void SetXColor(float theR, float theG, float theB)
  {
    myXColor = NCollection_Vec3<float>(theR, theG, theB);
    myNeedsRebuild = true;
  }

  //! Set Y axis color.
  void SetYColor(float theR, float theG, float theB)
  {
    myYColor = NCollection_Vec3<float>(theR, theG, theB);
    myNeedsRebuild = true;
  }

  //! Set Z axis color.
  void SetZColor(float theR, float theG, float theB)
  {
    myZColor = NCollection_Vec3<float>(theR, theG, theB);
    myNeedsRebuild = true;
  }

  //! Set grid color.
  void SetGridColor(float theR, float theG, float theB)
  {
    myGridColor = NCollection_Vec3<float>(theR, theG, theB);
    myNeedsRebuild = true;
  }

  //! Return tick mark length.
  float TickmarkLength() const { return myTickmarkLength; }

  //! Set tick mark length.
  void SetTickmarkLength(float theLength)
  {
    if (myTickmarkLength != theLength)
    {
      myTickmarkLength = theLength;
      myNeedsRebuild = true;
    }
  }

  //! Configure from Graphic3d_GraduatedTrihedron.
  void SetData(const Graphic3d_GraduatedTrihedron& theData)
  {
    // Copy settings from OCCT graduated trihedron
    myDrawGrid = theData.ToDrawGrid();
    myDrawAxes = theData.ToDrawAxes();
  }

  //! Render graduated trihedron.
  void Render(Metal_Workspace* theWorkspace,
              const NCollection_Vec3<float>& theMin,
              const NCollection_Vec3<float>& theMax);

  //! Release resources.
  void Release(Metal_Context* theCtx);

private:

#ifdef __OBJC__
  //! Build cached geometry buffers.
  void buildBuffers(id<MTLDevice> theDevice,
                    const NCollection_Vec3<float>& theMin,
                    const NCollection_Vec3<float>& theMax);
#endif

private:

  bool myIsEnabled;     //!< enabled flag
  bool myDrawGrid;      //!< draw grid
  bool myDrawAxes;      //!< draw axes
  bool myDrawLabels;    //!< draw labels
  bool myDrawTicks;     //!< draw tick marks

  NCollection_Vec3<float> myXColor;     //!< X axis color
  NCollection_Vec3<float> myYColor;     //!< Y axis color
  NCollection_Vec3<float> myZColor;     //!< Z axis color
  NCollection_Vec3<float> myGridColor;  //!< grid color

  float myTickmarkLength; //!< tick mark length

  // Buffer caching
  bool myNeedsRebuild;                    //!< flag indicating buffers need rebuild
  NCollection_Vec3<float> myCachedMin;    //!< cached bounding box min
  NCollection_Vec3<float> myCachedMax;    //!< cached bounding box max
#ifdef __OBJC__
  id<MTLBuffer> myCachedPositionBuffer;   //!< cached position buffer
  id<MTLBuffer> myCachedColorBuffer;      //!< cached color buffer
  NSUInteger myCachedVertexCount;         //!< number of vertices in cached buffers
#else
  void* myCachedPositionBuffer;           //!< cached position buffer (opaque)
  void* myCachedColorBuffer;              //!< cached color buffer (opaque)
  unsigned long myCachedVertexCount;      //!< number of vertices in cached buffers
#endif
};

#endif // Metal_GraduatedTrihedron_HeaderFile
