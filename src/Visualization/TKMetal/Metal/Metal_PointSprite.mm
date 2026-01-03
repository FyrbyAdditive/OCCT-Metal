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

#include <Metal_PointSprite.hxx>
#include <Metal_Context.hxx>
#include <Image_PixMap.hxx>

#include <cmath>

IMPLEMENT_STANDARD_RTTIEXT(Metal_PointSprite, Metal_Resource)

// =======================================================================
// function : Metal_PointSprite
// purpose  : Constructor for built-in marker type
// =======================================================================
Metal_PointSprite::Metal_PointSprite(Aspect_TypeOfMarker theType,
                                       float theScale)
: myMarkerType(theType),
  myMarkerScale(theScale),
  mySpriteSize(GetMarkerSize(theScale))
{
  //
}

// =======================================================================
// function : Metal_PointSprite
// purpose  : Constructor for custom marker image
// =======================================================================
Metal_PointSprite::Metal_PointSprite(const occ::handle<Graphic3d_MarkerImage>& theImage)
: myMarkerType(Aspect_TOM_USERDEFINED),
  myMarkerScale(1.0f),
  mySpriteSize(DefaultSpriteSize),
  myMarkerImage(theImage)
{
  //
}

// =======================================================================
// function : ~Metal_PointSprite
// purpose  : Destructor
// =======================================================================
Metal_PointSprite::~Metal_PointSprite()
{
  //
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_PointSprite::Release(Metal_Context* theCtx)
{
  if (!myTexture.IsNull())
  {
    myTexture->Release(theCtx);
    myTexture.Nullify();
  }
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
size_t Metal_PointSprite::EstimatedDataSize() const
{
  return myTexture.IsNull() ? 0 : myTexture->EstimatedDataSize();
}

// =======================================================================
// function : GetKey
// purpose  : Generate a key for caching this sprite
// =======================================================================
TCollection_AsciiString Metal_PointSprite::GetKey() const
{
  if (myMarkerType == Aspect_TOM_USERDEFINED && !myMarkerImage.IsNull())
  {
    return myMarkerImage->GetImageId();
  }
  return TCollection_AsciiString("M") + (int)myMarkerType
       + "_S" + (int)(myMarkerScale * 100);
}

// =======================================================================
// function : Init
// purpose  : Initialize Metal resources
// =======================================================================
bool Metal_PointSprite::Init(Metal_Context* theCtx)
{
  Release(theCtx);

  if (myMarkerType == Aspect_TOM_EMPTY)
  {
    return false;
  }

  if (myMarkerType == Aspect_TOM_USERDEFINED)
  {
    return generateCustomMarker(theCtx);
  }

  return generateBuiltinMarker(theCtx);
}

// =======================================================================
// function : generateBuiltinMarker
// purpose  : Generate sprite image for built-in marker type
// =======================================================================
bool Metal_PointSprite::generateBuiltinMarker(Metal_Context* theCtx)
{
  // Create RGBA image
  Image_PixMap anImage;
  if (!anImage.InitZero(Image_Format_RGBA, mySpriteSize, mySpriteSize))
  {
    return false;
  }

  uint8_t* aData = anImage.ChangeData();
  int aStride = (int)anImage.SizeRowBytes();

  switch (myMarkerType)
  {
    case Aspect_TOM_POINT:
      drawPoint(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_PLUS:
      drawPlus(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_STAR:
      drawStar(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_X:
      drawX(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_O:
      drawCircle(aData, mySpriteSize, aStride, false);
      break;
    case Aspect_TOM_O_POINT:
      drawCircle(aData, mySpriteSize, aStride, false);
      drawPoint(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_O_PLUS:
      drawCircle(aData, mySpriteSize, aStride, false);
      drawPlus(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_O_STAR:
      drawCircle(aData, mySpriteSize, aStride, false);
      drawStar(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_O_X:
      drawCircle(aData, mySpriteSize, aStride, false);
      drawX(aData, mySpriteSize, aStride);
      break;
    case Aspect_TOM_RING1:
      drawRing(aData, mySpriteSize, aStride, 0.25f);
      break;
    case Aspect_TOM_RING2:
      drawRing(aData, mySpriteSize, aStride, 0.15f);
      break;
    case Aspect_TOM_RING3:
      drawRing(aData, mySpriteSize, aStride, 0.08f);
      break;
    case Aspect_TOM_BALL:
      drawBall(aData, mySpriteSize, aStride);
      break;
    default:
      drawPoint(aData, mySpriteSize, aStride);
      break;
  }

  // Create texture
  myTexture = new Metal_Texture();
  return myTexture->Create2D(theCtx, anImage, false);
}

// =======================================================================
// function : generateCustomMarker
// purpose  : Generate sprite image from custom marker image
// =======================================================================
bool Metal_PointSprite::generateCustomMarker(Metal_Context* theCtx)
{
  if (myMarkerImage.IsNull())
  {
    return false;
  }

  const occ::handle<Image_PixMap>& anImage = myMarkerImage->GetImage();
  if (anImage.IsNull())
  {
    return false;
  }

  mySpriteSize = (int)anImage->SizeX();

  myTexture = new Metal_Texture();
  return myTexture->Create2D(theCtx, *anImage, false);
}

// =======================================================================
// function : drawPoint
// purpose  : Draw a point marker
// =======================================================================
void Metal_PointSprite::drawPoint(uint8_t* theData, int theSize, int theStride)
{
  int aCenter = theSize / 2;
  int aRadius = theSize / 8;
  if (aRadius < 1) aRadius = 1;

  for (int y = -aRadius; y <= aRadius; y++)
  {
    for (int x = -aRadius; x <= aRadius; x++)
    {
      if (x * x + y * y <= aRadius * aRadius)
      {
        int px = aCenter + x;
        int py = aCenter + y;
        if (px >= 0 && px < theSize && py >= 0 && py < theSize)
        {
          uint8_t* p = theData + py * theStride + px * 4;
          p[0] = p[1] = p[2] = p[3] = 255;
        }
      }
    }
  }
}

// =======================================================================
// function : drawPlus
// purpose  : Draw a plus marker (+)
// =======================================================================
void Metal_PointSprite::drawPlus(uint8_t* theData, int theSize, int theStride)
{
  int aCenter = theSize / 2;
  int aHalf = theSize / 3;
  int aThick = theSize / 10;
  if (aThick < 1) aThick = 1;

  // Horizontal bar
  for (int y = aCenter - aThick; y <= aCenter + aThick; y++)
  {
    for (int x = aCenter - aHalf; x <= aCenter + aHalf; x++)
    {
      if (x >= 0 && x < theSize && y >= 0 && y < theSize)
      {
        uint8_t* p = theData + y * theStride + x * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }
    }
  }

  // Vertical bar
  for (int y = aCenter - aHalf; y <= aCenter + aHalf; y++)
  {
    for (int x = aCenter - aThick; x <= aCenter + aThick; x++)
    {
      if (x >= 0 && x < theSize && y >= 0 && y < theSize)
      {
        uint8_t* p = theData + y * theStride + x * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }
    }
  }
}

// =======================================================================
// function : drawStar
// purpose  : Draw a star marker (*)
// =======================================================================
void Metal_PointSprite::drawStar(uint8_t* theData, int theSize, int theStride)
{
  // Draw + and X overlapped
  drawPlus(theData, theSize, theStride);
  drawX(theData, theSize, theStride);
}

// =======================================================================
// function : drawX
// purpose  : Draw an X marker
// =======================================================================
void Metal_PointSprite::drawX(uint8_t* theData, int theSize, int theStride)
{
  int aCenter = theSize / 2;
  int aHalf = theSize / 3;
  int aThick = theSize / 12;
  if (aThick < 1) aThick = 1;

  for (int i = -aHalf; i <= aHalf; i++)
  {
    for (int t = -aThick; t <= aThick; t++)
    {
      // Diagonal 1
      int x1 = aCenter + i + t;
      int y1 = aCenter + i;
      if (x1 >= 0 && x1 < theSize && y1 >= 0 && y1 < theSize)
      {
        uint8_t* p = theData + y1 * theStride + x1 * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }

      // Diagonal 2
      int x2 = aCenter + i + t;
      int y2 = aCenter - i;
      if (x2 >= 0 && x2 < theSize && y2 >= 0 && y2 < theSize)
      {
        uint8_t* p = theData + y2 * theStride + x2 * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }
    }
  }
}

// =======================================================================
// function : drawCircle
// purpose  : Draw a circle marker (O)
// =======================================================================
void Metal_PointSprite::drawCircle(uint8_t* theData, int theSize, int theStride, bool theFilled)
{
  int aCenter = theSize / 2;
  float aRadius = theSize * 0.4f;
  float aThick = theSize * 0.08f;
  if (aThick < 1.0f) aThick = 1.0f;

  for (int y = 0; y < theSize; y++)
  {
    for (int x = 0; x < theSize; x++)
    {
      float dx = x - aCenter;
      float dy = y - aCenter;
      float dist = sqrtf(dx * dx + dy * dy);

      bool draw = false;
      if (theFilled)
      {
        draw = (dist <= aRadius);
      }
      else
      {
        draw = (dist >= aRadius - aThick && dist <= aRadius + aThick);
      }

      if (draw)
      {
        uint8_t* p = theData + y * theStride + x * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }
    }
  }
}

// =======================================================================
// function : drawRing
// purpose  : Draw a ring marker
// =======================================================================
void Metal_PointSprite::drawRing(uint8_t* theData, int theSize, int theStride, float theThickness)
{
  int aCenter = theSize / 2;
  float aRadius = theSize * 0.4f;
  float aThick = theSize * theThickness;
  if (aThick < 1.0f) aThick = 1.0f;

  for (int y = 0; y < theSize; y++)
  {
    for (int x = 0; x < theSize; x++)
    {
      float dx = x - aCenter;
      float dy = y - aCenter;
      float dist = sqrtf(dx * dx + dy * dy);

      if (dist >= aRadius - aThick && dist <= aRadius + aThick)
      {
        uint8_t* p = theData + y * theStride + x * 4;
        p[0] = p[1] = p[2] = p[3] = 255;
      }
    }
  }
}

// =======================================================================
// function : drawBall
// purpose  : Draw a ball marker (shaded sphere)
// =======================================================================
void Metal_PointSprite::drawBall(uint8_t* theData, int theSize, int theStride)
{
  int aCenter = theSize / 2;
  float aRadius = theSize * 0.45f;

  for (int y = 0; y < theSize; y++)
  {
    for (int x = 0; x < theSize; x++)
    {
      float dx = x - aCenter;
      float dy = y - aCenter;
      float dist2 = dx * dx + dy * dy;
      float r2 = aRadius * aRadius;

      if (dist2 <= r2)
      {
        // Calculate z for sphere
        float z = sqrtf(r2 - dist2);

        // Normalize
        float nx = dx / aRadius;
        float ny = dy / aRadius;
        float nz = z / aRadius;

        // Simple lighting (light from top-left-front)
        float lx = -0.5f, ly = -0.5f, lz = 0.707f;
        float dot = nx * lx + ny * ly + nz * lz;
        if (dot < 0) dot = 0;

        // Add ambient
        float intensity = 0.3f + 0.7f * dot;
        if (intensity > 1.0f) intensity = 1.0f;

        uint8_t val = (uint8_t)(255 * intensity);

        uint8_t* p = theData + y * theStride + x * 4;
        p[0] = p[1] = p[2] = val;
        p[3] = 255;
      }
    }
  }
}
