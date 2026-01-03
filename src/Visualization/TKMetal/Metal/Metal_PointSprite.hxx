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

#ifndef Metal_PointSprite_HeaderFile
#define Metal_PointSprite_HeaderFile

#include <Metal_Resource.hxx>
#include <Metal_Texture.hxx>
#include <Aspect_TypeOfMarker.hxx>
#include <Graphic3d_MarkerImage.hxx>
#include <TCollection_AsciiString.hxx>
#include <NCollection_DataMap.hxx>

class Metal_Context;

//! Point sprite (marker) texture for Metal.
//! Generates and caches marker textures for different marker types.
class Metal_PointSprite : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_PointSprite, Metal_Resource)

public:

  //! Default sprite size in pixels.
  static const int DefaultSpriteSize = 32;

  //! Get standard marker sprite size for given scale.
  static int GetMarkerSize(float theScale)
  {
    return (int)(DefaultSpriteSize * theScale);
  }

public:

  //! Constructor for built-in marker type.
  Standard_EXPORT Metal_PointSprite(Aspect_TypeOfMarker theType,
                                     float theScale = 1.0f);

  //! Constructor for custom marker image.
  Standard_EXPORT Metal_PointSprite(const occ::handle<Graphic3d_MarkerImage>& theImage);

  //! Destructor.
  Standard_EXPORT ~Metal_PointSprite() override;

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const override;

  //! Return marker type.
  Aspect_TypeOfMarker MarkerType() const { return myMarkerType; }

  //! Return marker scale.
  float MarkerScale() const { return myMarkerScale; }

  //! Return true if sprite is valid.
  bool IsValid() const { return !myTexture.IsNull() && myTexture->IsValid(); }

  //! Return sprite texture.
  const occ::handle<Metal_Texture>& Texture() const { return myTexture; }

  //! Return sprite size in pixels.
  int SpriteSize() const { return mySpriteSize; }

  //! Initialize Metal resources (create texture).
  Standard_EXPORT bool Init(Metal_Context* theCtx);

  //! Generate a key for caching this sprite.
  TCollection_AsciiString GetKey() const;

protected:

  //! Generate sprite image for built-in marker type.
  Standard_EXPORT bool generateBuiltinMarker(Metal_Context* theCtx);

  //! Generate sprite image from custom marker image.
  Standard_EXPORT bool generateCustomMarker(Metal_Context* theCtx);

  //! Draw a point marker.
  void drawPoint(uint8_t* theData, int theSize, int theStride);

  //! Draw a plus marker (+).
  void drawPlus(uint8_t* theData, int theSize, int theStride);

  //! Draw a star marker (*).
  void drawStar(uint8_t* theData, int theSize, int theStride);

  //! Draw an X marker.
  void drawX(uint8_t* theData, int theSize, int theStride);

  //! Draw a circle marker (O).
  void drawCircle(uint8_t* theData, int theSize, int theStride, bool theFilled);

  //! Draw a ring marker.
  void drawRing(uint8_t* theData, int theSize, int theStride, float theThickness);

  //! Draw a ball marker (shaded sphere).
  void drawBall(uint8_t* theData, int theSize, int theStride);

protected:

  Aspect_TypeOfMarker                 myMarkerType;   //!< marker type
  float                               myMarkerScale;  //!< marker scale
  int                                 mySpriteSize;   //!< sprite size in pixels
  occ::handle<Graphic3d_MarkerImage>  myMarkerImage;  //!< custom marker image
  occ::handle<Metal_Texture>          myTexture;      //!< sprite texture
};

DEFINE_STANDARD_HANDLE(Metal_PointSprite, Metal_Resource)

//! Cache of point sprites for Metal rendering.
class Metal_PointSpriteCache
{
public:

  //! Constructor.
  Metal_PointSpriteCache() {}

  //! Release all sprites.
  void Release(Metal_Context* theCtx)
  {
    for (NCollection_DataMap<TCollection_AsciiString, occ::handle<Metal_PointSprite>>::Iterator
         anIter(mySprites); anIter.More(); anIter.Next())
    {
      anIter.Value()->Release(theCtx);
    }
    mySprites.Clear();
  }

  //! Get or create sprite for built-in marker type.
  occ::handle<Metal_PointSprite> GetSprite(Metal_Context* theCtx,
                                            Aspect_TypeOfMarker theType,
                                            float theScale = 1.0f)
  {
    // Generate key
    TCollection_AsciiString aKey = TCollection_AsciiString("M") + (int)theType
                                 + "_S" + (int)(theScale * 100);

    occ::handle<Metal_PointSprite> aSprite;
    if (mySprites.Find(aKey, aSprite))
    {
      return aSprite;
    }

    // Create new sprite
    aSprite = new Metal_PointSprite(theType, theScale);
    if (aSprite->Init(theCtx))
    {
      mySprites.Bind(aKey, aSprite);
      return aSprite;
    }

    return occ::handle<Metal_PointSprite>();
  }

  //! Get or create sprite for custom marker image.
  occ::handle<Metal_PointSprite> GetSprite(Metal_Context* theCtx,
                                            const occ::handle<Graphic3d_MarkerImage>& theImage)
  {
    if (theImage.IsNull())
    {
      return occ::handle<Metal_PointSprite>();
    }

    TCollection_AsciiString aKey = theImage->GetImageId();
    occ::handle<Metal_PointSprite> aSprite;
    if (mySprites.Find(aKey, aSprite))
    {
      return aSprite;
    }

    aSprite = new Metal_PointSprite(theImage);
    if (aSprite->Init(theCtx))
    {
      mySprites.Bind(aKey, aSprite);
      return aSprite;
    }

    return occ::handle<Metal_PointSprite>();
  }

private:

  NCollection_DataMap<TCollection_AsciiString, occ::handle<Metal_PointSprite>> mySprites;
};

#endif // Metal_PointSprite_HeaderFile
