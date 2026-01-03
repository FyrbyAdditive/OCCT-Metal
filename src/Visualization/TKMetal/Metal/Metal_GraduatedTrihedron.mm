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

#include <Metal_GraduatedTrihedron.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>
#include <Metal_View.hxx>
#include <Metal_ShaderManager.hxx>

#include <cmath>
#include <algorithm>

namespace
{
  //! Compute nice tick spacing for a given range
  static float computeTickSpacing(float theRange)
  {
    if (theRange <= 0.0f)
    {
      return 1.0f;
    }

    // Find order of magnitude
    float aMagnitude = std::pow(10.0f, std::floor(std::log10(theRange)));
    float aNormalized = theRange / aMagnitude;

    // Choose nice spacing: 1, 2, 5, 10
    float aSpacing = aMagnitude;
    if (aNormalized > 5.0f)
    {
      aSpacing = aMagnitude;
    }
    else if (aNormalized > 2.0f)
    {
      aSpacing = aMagnitude * 0.5f;
    }
    else if (aNormalized > 1.0f)
    {
      aSpacing = aMagnitude * 0.2f;
    }
    else
    {
      aSpacing = aMagnitude * 0.1f;
    }

    return aSpacing;
  }
}

// =======================================================================
// function : Render
// purpose  : Render graduated trihedron
// =======================================================================
void Metal_GraduatedTrihedron::Render(Metal_Workspace* theWorkspace,
                                       const NCollection_Vec3<float>& theMin,
                                       const NCollection_Vec3<float>& theMax)
{
  if (!myIsEnabled || theWorkspace == nullptr)
  {
    return;
  }

  id<MTLRenderCommandEncoder> anEncoder = theWorkspace->ActiveEncoder();
  if (anEncoder == nil)
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nullptr)
  {
    return;
  }

  // Get device from context
  id<MTLDevice> aDevice = aCtx->Device();
  if (aDevice == nil)
  {
    return;
  }

  // Compute bounding box dimensions
  NCollection_Vec3<float> aSize = theMax - theMin;
  NCollection_Vec3<float> aOrigin = theMin;

  // Collect vertices for lines
  std::vector<float> aPositions;
  std::vector<float> aColors;

  // Helper to add a line segment
  auto addLine = [&](const NCollection_Vec3<float>& p1, const NCollection_Vec3<float>& p2,
                     const NCollection_Vec3<float>& color)
  {
    aPositions.push_back(p1.x()); aPositions.push_back(p1.y()); aPositions.push_back(p1.z());
    aPositions.push_back(p2.x()); aPositions.push_back(p2.y()); aPositions.push_back(p2.z());
    aColors.push_back(color.x()); aColors.push_back(color.y()); aColors.push_back(color.z()); aColors.push_back(1.0f);
    aColors.push_back(color.x()); aColors.push_back(color.y()); aColors.push_back(color.z()); aColors.push_back(1.0f);
  };

  // Draw main axes if enabled
  if (myDrawAxes)
  {
    // X axis (red)
    addLine(aOrigin,
            NCollection_Vec3<float>(theMax.x(), aOrigin.y(), aOrigin.z()),
            myXColor);

    // Y axis (green)
    addLine(aOrigin,
            NCollection_Vec3<float>(aOrigin.x(), theMax.y(), aOrigin.z()),
            myYColor);

    // Z axis (blue)
    addLine(aOrigin,
            NCollection_Vec3<float>(aOrigin.x(), aOrigin.y(), theMax.z()),
            myZColor);
  }

  // Draw tick marks if enabled
  if (myDrawTicks)
  {
    float aTickLen = myTickmarkLength;

    // X axis ticks
    float aSpacingX = computeTickSpacing(aSize.x());
    for (float x = aOrigin.x() + aSpacingX; x < theMax.x(); x += aSpacingX)
    {
      NCollection_Vec3<float> aTickStart(x, aOrigin.y(), aOrigin.z());
      NCollection_Vec3<float> aTickEndY(x, aOrigin.y() - aTickLen, aOrigin.z());
      NCollection_Vec3<float> aTickEndZ(x, aOrigin.y(), aOrigin.z() - aTickLen);
      addLine(aTickStart, aTickEndY, myXColor);
      addLine(aTickStart, aTickEndZ, myXColor);
    }

    // Y axis ticks
    float aSpacingY = computeTickSpacing(aSize.y());
    for (float y = aOrigin.y() + aSpacingY; y < theMax.y(); y += aSpacingY)
    {
      NCollection_Vec3<float> aTickStart(aOrigin.x(), y, aOrigin.z());
      NCollection_Vec3<float> aTickEndX(aOrigin.x() - aTickLen, y, aOrigin.z());
      NCollection_Vec3<float> aTickEndZ(aOrigin.x(), y, aOrigin.z() - aTickLen);
      addLine(aTickStart, aTickEndX, myYColor);
      addLine(aTickStart, aTickEndZ, myYColor);
    }

    // Z axis ticks
    float aSpacingZ = computeTickSpacing(aSize.z());
    for (float z = aOrigin.z() + aSpacingZ; z < theMax.z(); z += aSpacingZ)
    {
      NCollection_Vec3<float> aTickStart(aOrigin.x(), aOrigin.y(), z);
      NCollection_Vec3<float> aTickEndX(aOrigin.x() - aTickLen, aOrigin.y(), z);
      NCollection_Vec3<float> aTickEndY(aOrigin.x(), aOrigin.y() - aTickLen, z);
      addLine(aTickStart, aTickEndX, myZColor);
      addLine(aTickStart, aTickEndY, myZColor);
    }
  }

  // Draw grid if enabled
  if (myDrawGrid)
  {
    float aSpacingX = computeTickSpacing(aSize.x());
    float aSpacingY = computeTickSpacing(aSize.y());
    float aSpacingZ = computeTickSpacing(aSize.z());

    // XY plane grid (at Z = zmin)
    for (float x = aOrigin.x(); x <= theMax.x() + aSpacingX * 0.01f; x += aSpacingX)
    {
      addLine(NCollection_Vec3<float>(x, aOrigin.y(), aOrigin.z()),
              NCollection_Vec3<float>(x, theMax.y(), aOrigin.z()),
              myGridColor);
    }
    for (float y = aOrigin.y(); y <= theMax.y() + aSpacingY * 0.01f; y += aSpacingY)
    {
      addLine(NCollection_Vec3<float>(aOrigin.x(), y, aOrigin.z()),
              NCollection_Vec3<float>(theMax.x(), y, aOrigin.z()),
              myGridColor);
    }

    // XZ plane grid (at Y = ymin)
    for (float x = aOrigin.x(); x <= theMax.x() + aSpacingX * 0.01f; x += aSpacingX)
    {
      addLine(NCollection_Vec3<float>(x, aOrigin.y(), aOrigin.z()),
              NCollection_Vec3<float>(x, aOrigin.y(), theMax.z()),
              myGridColor);
    }
    for (float z = aOrigin.z(); z <= theMax.z() + aSpacingZ * 0.01f; z += aSpacingZ)
    {
      addLine(NCollection_Vec3<float>(aOrigin.x(), aOrigin.y(), z),
              NCollection_Vec3<float>(theMax.x(), aOrigin.y(), z),
              myGridColor);
    }

    // YZ plane grid (at X = xmin)
    for (float y = aOrigin.y(); y <= theMax.y() + aSpacingY * 0.01f; y += aSpacingY)
    {
      addLine(NCollection_Vec3<float>(aOrigin.x(), y, aOrigin.z()),
              NCollection_Vec3<float>(aOrigin.x(), y, theMax.z()),
              myGridColor);
    }
    for (float z = aOrigin.z(); z <= theMax.z() + aSpacingZ * 0.01f; z += aSpacingZ)
    {
      addLine(NCollection_Vec3<float>(aOrigin.x(), aOrigin.y(), z),
              NCollection_Vec3<float>(aOrigin.x(), theMax.y(), z),
              myGridColor);
    }
  }

  // Only draw if we have vertices
  if (aPositions.empty())
  {
    return;
  }

  // Create buffers
  NSUInteger aPositionSize = aPositions.size() * sizeof(float);
  NSUInteger aColorSize = aColors.size() * sizeof(float);

  id<MTLBuffer> aPosBuffer = [aDevice newBufferWithBytes:aPositions.data()
                                                   length:aPositionSize
                                                  options:MTLResourceStorageModeShared];
  id<MTLBuffer> aColorBuffer = [aDevice newBufferWithBytes:aColors.data()
                                                     length:aColorSize
                                                    options:MTLResourceStorageModeShared];

  // Apply matrices as uniforms
  // The workspace already has model-view and projection matrices set
  theWorkspace->ApplyUniforms();

  // Set vertex buffers
  [anEncoder setVertexBuffer:aPosBuffer offset:0 atIndex:0];
  [anEncoder setVertexBuffer:aColorBuffer offset:0 atIndex:1];

  // Draw lines (2 vertices per line)
  NSUInteger aVertexCount = aPositions.size() / 3;
  [anEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:aVertexCount];
}

// =======================================================================
// function : Release
// purpose  : Release resources
// =======================================================================
void Metal_GraduatedTrihedron::Release(Metal_Context* /*theCtx*/)
{
  // Release any cached buffers
  // For now, we create buffers on each render - could be optimized
}
