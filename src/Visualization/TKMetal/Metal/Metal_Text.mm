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

#include <Metal_Text.hxx>
#include <Metal_Context.hxx>
#include <Metal_Font.hxx>
#include <Metal_Workspace.hxx>
#include <Metal_ShaderManager.hxx>
#include <Metal_View.hxx>

#include <Font_FontMgr.hxx>
#include <Font_FTFont.hxx>
#include <Font_TextFormatter.hxx>
#include <Graphic3d_TransformUtils.hxx>
#include <TCollection_HAsciiString.hxx>

#include <cmath>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Text, Standard_Transient)

namespace
{
  static const NCollection_Mat4<double> THE_IDENTITY_MATRIX;
  static const TCollection_AsciiString THE_DEFAULT_FONT(Font_NOF_ASCII_MONO);

  //! Apply floor to vector components.
  inline NCollection_Vec2<float>& floorVec(NCollection_Vec2<float>& theVec)
  {
    theVec.x() = std::floor(theVec.x());
    theVec.y() = std::floor(theVec.y());
    return theVec;
  }
}

// =======================================================================
// function : Metal_Text
// purpose  : Constructor
// =======================================================================
Metal_Text::Metal_Text(const occ::handle<Graphic3d_Text>& theTextParams)
: myText(theTextParams),
  myIs2D(false),
  myScaleHeight(1.0f),
  myBndVertsBuffer(nil),
  myTextOffset(0.0f, 0.0f, 0.0f)
{
  //
}

// =======================================================================
// function : ~Metal_Text
// purpose  : Destructor
// =======================================================================
Metal_Text::~Metal_Text()
{
  Release(nullptr);
}

// =======================================================================
// function : SetPosition
// purpose  : Set position
// =======================================================================
void Metal_Text::SetPosition(const NCollection_Vec3<float>& thePoint)
{
  myText->SetPosition(gp_Pnt(thePoint.x(), thePoint.y(), thePoint.z()));
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Text::Release(Metal_Context* theCtx)
{
  (void)theCtx;

  // Release Metal buffers
  for (int i = 0; i < myVertsBuffers.Length(); ++i)
  {
    myVertsBuffers.ChangeValue(i) = nil;
    myTCrdsBuffers.ChangeValue(i) = nil;
  }
  myVertsBuffers.Clear();
  myTCrdsBuffers.Clear();
  myTextureIndices.Clear();
  myBndVertsBuffer = nil;

  // Release font reference
  if (!myFont.IsNull())
  {
    myFont.Nullify();
  }
}

// =======================================================================
// function : EstimatedDataSize
// purpose  : Return estimated GPU memory usage
// =======================================================================
size_t Metal_Text::EstimatedDataSize() const
{
  size_t aSize = 0;
  for (int i = 0; i < myVertsBuffers.Length(); ++i)
  {
    id<MTLBuffer> aVertsBuffer = myVertsBuffers.Value(i);
    id<MTLBuffer> aTCrdsBuffer = myTCrdsBuffers.Value(i);
    if (aVertsBuffer != nil)
    {
      aSize += [aVertsBuffer length];
    }
    if (aTCrdsBuffer != nil)
    {
      aSize += [aTCrdsBuffer length];
    }
  }
  if (myBndVertsBuffer != nil)
  {
    aSize += [myBndVertsBuffer length];
  }
  return aSize;
}

// =======================================================================
// function : FontKey
// purpose  : Generate font resource key
// =======================================================================
TCollection_AsciiString Metal_Text::FontKey(const Graphic3d_Aspects& theAspect,
                                             int theHeight,
                                             unsigned int theResolution,
                                             Font_Hinting theFontHinting)
{
  const Font_FontAspect anAspect = theAspect.TextFontAspect() != Font_FA_Undefined
                                     ? theAspect.TextFontAspect()
                                     : Font_FA_Regular;
  const TCollection_AsciiString& aFont = !theAspect.TextFont().IsNull()
                                           ? theAspect.TextFont()->String()
                                           : THE_DEFAULT_FONT;

  char aSuff[64];
  Sprintf(aSuff, ":%d:%d:%d:%d", int(anAspect), int(theResolution), theHeight, int(theFontHinting));
  return aFont + aSuff;
}

// =======================================================================
// function : FindFont
// purpose  : Find or create font for rendering
// =======================================================================
occ::handle<Metal_Font> Metal_Text::FindFont(Metal_Context* theCtx,
                                              const Graphic3d_Aspects& theAspect,
                                              int theHeight,
                                              unsigned int theResolution,
                                              Font_Hinting theFontHinting)
{
  if (theHeight < 2 || theCtx == nullptr)
  {
    return occ::handle<Metal_Font>();
  }

  TCollection_AsciiString aKey = FontKey(theAspect, theHeight, theResolution, theFontHinting);

  // Check if font is already cached
  occ::handle<Metal_Font> aFont;
  if (theCtx->GetResource(aKey, aFont))
  {
    return aFont;
  }

  // Create new font
  occ::handle<Font_FontMgr> aFontMgr = Font_FontMgr::GetInstance();
  const TCollection_AsciiString& aFontName = !theAspect.TextFont().IsNull()
                                               ? theAspect.TextFont()->String()
                                               : THE_DEFAULT_FONT;
  Font_FontAspect anAspect = theAspect.TextFontAspect() != Font_FA_Undefined
                               ? theAspect.TextFontAspect()
                               : Font_FA_Regular;
  Font_FTFontParams aParams;
  aParams.PointSize = theHeight;
  aParams.Resolution = theResolution;
  aParams.FontHinting = theFontHinting;

  occ::handle<Font_FTFont> aFontFt = Font_FTFont::FindAndCreate(aFontName, anAspect, aParams, Font_StrictLevel_Any);
  if (aFontFt.IsNull())
  {
    NSLog(@"Metal_Text: Font '%s' not found in system!", aFontName.ToCString());
    return occ::handle<Metal_Font>();
  }

  aFont = new Metal_Font(aFontFt, aKey);
  if (!aFont->Init(theCtx))
  {
    NSLog(@"Metal_Text: Font '%s' initialization failed!", aFontName.ToCString());
    aFont->Release(theCtx);
    return occ::handle<Metal_Font>();
  }

  theCtx->ShareResource(aKey, aFont);
  return aFont;
}

// =======================================================================
// function : StringSize
// purpose  : Compute text string dimensions
// =======================================================================
void Metal_Text::StringSize(Metal_Context* theCtx,
                             const NCollection_String& theText,
                             const Graphic3d_Aspects& theAspect,
                             float theHeight,
                             unsigned int theResolution,
                             Font_Hinting theFontHinting,
                             float& theWidth,
                             float& theAscent,
                             float& theDescent)
{
  theWidth = 0.0f;
  theAscent = 0.0f;
  theDescent = 0.0f;

  occ::handle<Metal_Font> aFont = FindFont(theCtx, theAspect, (int)theHeight, theResolution, theFontHinting);
  if (aFont.IsNull() || !aFont->IsValid())
  {
    return;
  }

  theAscent = aFont->Ascender();
  theDescent = aFont->Descender();

  float aWidth = 0.0f;
  for (NCollection_UtfIterator<char> anIter = theText.Iterator(); *anIter != 0;)
  {
    const char32_t aCharThis = *anIter;
    const char32_t aCharNext = *++anIter;

    if (aCharThis == '\x0D' || aCharThis == '\a' || aCharThis == '\f' ||
        aCharThis == '\b' || aCharThis == '\v')
    {
      continue; // skip control codes
    }
    else if (aCharThis == '\x0A') // new line
    {
      theWidth = std::max(theWidth, aWidth);
      aWidth = 0.0f;
      continue;
    }
    else if (aCharThis == ' ')
    {
      aWidth += aFont->FTFont()->AdvanceX(aCharThis, aCharNext);
      continue;
    }
    else if (aCharThis == '\t')
    {
      aWidth += aFont->FTFont()->AdvanceX(' ', aCharNext) * 8.0f;
      continue;
    }

    aWidth += aFont->FTFont()->AdvanceX(aCharThis, aCharNext);
  }
  theWidth = std::max(theWidth, aWidth);
}

// =======================================================================
// function : Render
// purpose  : Render the text (workspace version)
// =======================================================================
void Metal_Text::Render(Metal_Workspace* theWorkspace) const
{
  if (theWorkspace == nullptr || myText.IsNull())
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nullptr)
  {
    return;
  }

  // Get aspects and colors from workspace
  const occ::handle<Graphic3d_Aspects>& anAspect = theWorkspace->Aspect();
  if (anAspect.IsNull())
  {
    return;
  }

  NCollection_Vec4<float> aColorText;
  NCollection_Vec4<float> aColorSubs;

  if (theWorkspace->IsHighlighting())
  {
    const Quantity_ColorRGBA& aHighlight = theWorkspace->HighlightColor();
    aColorText = NCollection_Vec4<float>(
      (float)aHighlight.GetRGB().Red(),
      (float)aHighlight.GetRGB().Green(),
      (float)aHighlight.GetRGB().Blue(),
      aHighlight.Alpha()
    );
    aColorSubs = aColorText;
  }
  else
  {
    const Quantity_ColorRGBA& aTextColor = anAspect->ColorRGBA();
    aColorText = NCollection_Vec4<float>(
      (float)aTextColor.GetRGB().Red(),
      (float)aTextColor.GetRGB().Green(),
      (float)aTextColor.GetRGB().Blue(),
      aTextColor.Alpha()
    );
    const Quantity_ColorRGBA& aSubsColor = anAspect->ColorSubTitleRGBA();
    aColorSubs = NCollection_Vec4<float>(
      (float)aSubsColor.GetRGB().Red(),
      (float)aSubsColor.GetRGB().Green(),
      (float)aSubsColor.GetRGB().Blue(),
      aSubsColor.Alpha()
    );
  }

  // Get rendering resolution
  unsigned int aResolution = 96; // default
  Font_Hinting aHinting = Font_Hinting_Off;
  if (theWorkspace->View() != nullptr)
  {
    aResolution = theWorkspace->View()->RenderingParams().Resolution;
    aHinting = theWorkspace->View()->RenderingParams().FontHinting;
  }

  render(theWorkspace, *anAspect, aColorText, aColorSubs, aResolution, aHinting);
}

// =======================================================================
// function : Render
// purpose  : Render with explicit aspect (no workspace - limited functionality)
// =======================================================================
void Metal_Text::Render(Metal_Context* theCtx,
                        const Graphic3d_Aspects& theAspect,
                        unsigned int theResolution,
                        Font_Hinting theFontHinting) const
{
  // This variant cannot render because it has no access to the render encoder.
  // Use the Metal_Workspace version instead.
  (void)theCtx;
  (void)theAspect;
  (void)theResolution;
  (void)theFontHinting;
}

// =======================================================================
// function : render
// purpose  : Render implementation
// =======================================================================
void Metal_Text::render(Metal_Workspace* theWorkspace,
                         const Graphic3d_Aspects& theAspect,
                         const NCollection_Vec4<float>& theColorText,
                         const NCollection_Vec4<float>& theColorSubs,
                         unsigned int theResolution,
                         Font_Hinting theFontHinting) const
{
  if (theWorkspace == nullptr)
  {
    return;
  }

  Metal_Context* theCtx = theWorkspace->Context();
  if (theCtx == nullptr)
  {
    return;
  }

  if (myText->Text().IsEmpty() && myText->TextFormatter().IsNull())
  {
    return;
  }

  // Check if we need to rebuild font
  TCollection_AsciiString aFontKey = FontKey(theAspect, (int)myText->Height(), theResolution, theFontHinting);
  if (!myFont.IsNull() && !myFont->ResourceKey().IsEqual(aFontKey))
  {
    const_cast<Metal_Text*>(this)->Release(theCtx);
  }

  // Find or create font
  if (myFont.IsNull())
  {
    myFont = FindFont(theCtx, theAspect, (int)myText->Height(), theResolution, theFontHinting);
  }
  if (myFont.IsNull() || !myFont->WasInitialized())
  {
    return;
  }

  // Initialize matrices from context
  // For 3D text, we need proper model-view-projection matrices to compute scale
  if (!myIs2D)
  {
    // Get current model-view matrix (world-view * model-world)
    // Convert from float to double for precision
    const NCollection_Mat4<float> aModelViewF =
      theCtx->WorldViewState.Current() * theCtx->ModelWorldState.Current();
    for (int i = 0; i < 4; ++i)
    {
      for (int j = 0; j < 4; ++j)
      {
        myModelMatrix.SetValue(i, j, static_cast<double>(aModelViewF.GetValue(i, j)));
      }
    }

    // Get projection matrix
    const NCollection_Mat4<float>& aProjF = theCtx->ProjectionState.Current();
    for (int i = 0; i < 4; ++i)
    {
      for (int j = 0; j < 4; ++j)
      {
        myProjMatrix.SetValue(i, j, static_cast<double>(aProjF.GetValue(i, j)));
      }
    }
  }

  // Build glyph geometry if needed
  if (myVertsBuffers.IsEmpty())
  {
    occ::handle<Font_TextFormatter> aFormatter = myText->TextFormatter();
    if (aFormatter.IsNull())
    {
      aFormatter = new Font_TextFormatter();
    }
    aFormatter->SetupAlignment(myText->HorizontalAlignment(), myText->VerticalAlignment());
    aFormatter->Reset();
    aFormatter->Append(myText->Text(), *myFont->FTFont());
    aFormatter->Format();

    // Build glyph quads
    id<MTLDevice> aDevice = theCtx->Device();
    if (aDevice == nil)
    {
      return;
    }

    // Create vertex data for each glyph
    NCollection_Vector<NCollection_Vector<NCollection_Vec2<float>>> aVertsPerTex;
    NCollection_Vector<NCollection_Vector<NCollection_Vec2<float>>> aTCrdsPerTex;
    NCollection_Vector<int> aTexIndices;

    Metal_Font::Tile aTile;
    NCollection_Vec2<float> aVec(0.0f, 0.0f);

    for (Font_TextFormatter::Iterator aFormatterIt(*aFormatter, Font_TextFormatter::IterationFilter_ExcludeInvisible);
         aFormatterIt.More();
         aFormatterIt.Next())
    {
      if (!myFont->RenderGlyph(theCtx, aFormatterIt.Symbol(), aTile))
      {
        continue;
      }

      const NCollection_Vec2<float>& aBottomLeft = aFormatter->BottomLeft(aFormatterIt.SymbolPosition());
      aTile.px.Right += aBottomLeft.x();
      aTile.px.Left += aBottomLeft.x();
      aTile.px.Bottom += aBottomLeft.y();
      aTile.px.Top += aBottomLeft.y();

      const Font_Rect& aRectUV = aTile.uv;
      const int aTexture = aTile.texture;

      // Find or create vertex list for this texture
      int aListId = -1;
      for (int i = 0; i < aTexIndices.Length(); ++i)
      {
        if (aTexIndices.Value(i) == aTexture)
        {
          aListId = i;
          break;
        }
      }
      if (aListId < 0)
      {
        aListId = aTexIndices.Length();
        aTexIndices.Append(aTexture);
        aVertsPerTex.Append(NCollection_Vector<NCollection_Vec2<float>>());
        aTCrdsPerTex.Append(NCollection_Vector<NCollection_Vec2<float>>());
      }

      NCollection_Vector<NCollection_Vec2<float>>& aVerts = aVertsPerTex.ChangeValue(aListId);
      NCollection_Vector<NCollection_Vec2<float>>& aTCrds = aTCrdsPerTex.ChangeValue(aListId);

      // Two triangles per glyph (6 vertices)
      aVerts.Append(floorVec(aTile.px.TopRight(aVec)));
      aVerts.Append(floorVec(aTile.px.TopLeft(aVec)));
      aVerts.Append(floorVec(aTile.px.BottomLeft(aVec)));
      aTCrds.Append(aRectUV.TopRight(aVec));
      aTCrds.Append(aRectUV.TopLeft(aVec));
      aTCrds.Append(aRectUV.BottomLeft(aVec));

      aVerts.Append(floorVec(aTile.px.BottomRight(aVec)));
      aVerts.Append(floorVec(aTile.px.TopRight(aVec)));
      aVerts.Append(floorVec(aTile.px.BottomLeft(aVec)));
      aTCrds.Append(aRectUV.BottomRight(aVec));
      aTCrds.Append(aRectUV.TopRight(aVec));
      aTCrds.Append(aRectUV.BottomLeft(aVec));
    }

    // Create Metal buffers
    myTextureIndices = aTexIndices;
    for (int i = 0; i < aVertsPerTex.Length(); ++i)
    {
      const NCollection_Vector<NCollection_Vec2<float>>& aVerts = aVertsPerTex.Value(i);
      const NCollection_Vector<NCollection_Vec2<float>>& aTCrds = aTCrdsPerTex.Value(i);

      if (aVerts.IsEmpty())
      {
        continue;
      }

      // Copy to contiguous arrays
      size_t aVertCount = aVerts.Length();
      std::vector<float> aVertsData(aVertCount * 2);
      std::vector<float> aTCrdsData(aVertCount * 2);
      for (int v = 0; v < (int)aVertCount; ++v)
      {
        aVertsData[v * 2 + 0] = aVerts.Value(v).x();
        aVertsData[v * 2 + 1] = aVerts.Value(v).y();
        aTCrdsData[v * 2 + 0] = aTCrds.Value(v).x();
        aTCrdsData[v * 2 + 1] = aTCrds.Value(v).y();
      }

      id<MTLBuffer> aVertsBuffer = [aDevice newBufferWithBytes:aVertsData.data()
                                                        length:aVertsData.size() * sizeof(float)
                                                       options:MTLResourceStorageModeShared];
      id<MTLBuffer> aTCrdsBuffer = [aDevice newBufferWithBytes:aTCrdsData.data()
                                                        length:aTCrdsData.size() * sizeof(float)
                                                       options:MTLResourceStorageModeShared];
      myVertsBuffers.Append(aVertsBuffer);
      myTCrdsBuffers.Append(aTCrdsBuffer);
    }

    // Get bounding box for background
    aFormatter->BndBox(myBndBox);
  }

  if (myVertsBuffers.IsEmpty())
  {
    return;
  }

  // Setup rendering
  myScaleHeight = 1.0f;

  // For 3D text, compute scale for constant height on screen
  if (!myIs2D && !theAspect.IsTextZoomable())
  {
    // Get text height in pixels
    const double aPointSize = static_cast<double>(myFont->FTFont()->PointSize());

    // Get text position
    const gp_Pnt& aPoint = myText->Position();

    // Get viewport from context
    const int* aCtxViewport = theCtx->Viewport();
    int aViewport[4];
    if (aCtxViewport[2] > 0 && aCtxViewport[3] > 0)
    {
      aViewport[0] = aCtxViewport[0];
      aViewport[1] = aCtxViewport[1];
      aViewport[2] = aCtxViewport[2];
      aViewport[3] = aCtxViewport[3];
    }
    else
    {
      // Fallback if viewport not set
      aViewport[0] = 0;
      aViewport[1] = 0;
      aViewport[2] = 800;
      aViewport[3] = 600;
    }

    // Project 3D position to window coordinates
    Graphic3d_TransformUtils::Project<double>(
      aPoint.X(), aPoint.Y(), aPoint.Z(),
      myModelMatrix, myProjMatrix, aViewport,
      myWinXYZ.x(), myWinXYZ.y(), myWinXYZ.z());

    // Compute scale factor for constant screen height
    // UnProject two points at same window X,Z but different Y to get world distance
    static const NCollection_Mat4<double> THE_IDENTITY_MATRIX;
    NCollection_Vec3<double> aPnt1, aPnt2;

    Graphic3d_TransformUtils::UnProject<double>(
      myWinXYZ.x(), myWinXYZ.y(), myWinXYZ.z(),
      THE_IDENTITY_MATRIX, myProjMatrix, aViewport,
      aPnt1.x(), aPnt1.y(), aPnt1.z());

    Graphic3d_TransformUtils::UnProject<double>(
      myWinXYZ.x(), myWinXYZ.y() + aPointSize, myWinXYZ.z(),
      THE_IDENTITY_MATRIX, myProjMatrix, aViewport,
      aPnt2.x(), aPnt2.y(), aPnt2.z());

    // Scale factor = world distance per pixel
    double aDeltaY = aPnt2.y() - aPnt1.y();
    if (std::abs(aDeltaY) > 1e-10 && std::abs(aPointSize) > 1e-10)
    {
      myScaleHeight = static_cast<float>(aDeltaY / aPointSize);
    }
  }

  // Render based on display type
  switch (theAspect.TextDisplayType())
  {
    case Aspect_TODT_SUBTITLE:
    {
      drawRect(theWorkspace, theAspect, theColorSubs);
      break;
    }
    case Aspect_TODT_DEKALE:
    {
      // Draw shadow copies in 4 directions (3D style effect)
      drawTextWithOffset(theWorkspace, theAspect, theColorSubs, NCollection_Vec3<float>(+1.0f, +1.0f, 0.0f));
      drawTextWithOffset(theWorkspace, theAspect, theColorSubs, NCollection_Vec3<float>(-1.0f, -1.0f, 0.0f));
      drawTextWithOffset(theWorkspace, theAspect, theColorSubs, NCollection_Vec3<float>(-1.0f, +1.0f, 0.0f));
      drawTextWithOffset(theWorkspace, theAspect, theColorSubs, NCollection_Vec3<float>(+1.0f, -1.0f, 0.0f));
      break;
    }
    case Aspect_TODT_SHADOW:
    {
      // Draw shadow copy at bottom-right
      drawTextWithOffset(theWorkspace, theAspect, theColorSubs, NCollection_Vec3<float>(+1.0f, -1.0f, 0.0f));
      break;
    }
    case Aspect_TODT_BLEND:
    case Aspect_TODT_DIMENSION:
    case Aspect_TODT_NORMAL:
    default:
      break;
  }

  // Draw main text (reset offset to zero)
  myTextOffset = NCollection_Vec3<float>(0.0f, 0.0f, 0.0f);
  setupMatrix(theWorkspace, theAspect, myTextOffset);
  drawText(theWorkspace, theAspect, theColorText);
}

// =======================================================================
// function : drawText
// purpose  : Draw text quads using render encoder
// =======================================================================
void Metal_Text::drawText(Metal_Workspace* theWorkspace,
                           const Graphic3d_Aspects& theAspect,
                           const NCollection_Vec4<float>& theColor) const
{
  (void)theAspect;

  if (theWorkspace == nullptr || myVertsBuffers.IsEmpty())
  {
    return;
  }

  id<MTLRenderCommandEncoder> anEncoder = theWorkspace->ActiveEncoder();
  if (anEncoder == nil)
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nil)
  {
    return;
  }

  // Text rendering uniform structure
  struct TextUniforms
  {
    float ModelViewProjection[16];
    float Color[4];
    float Offset[2];
    float Scale;
    float Padding;
  };

  // Prepare uniforms
  TextUniforms aUniforms;

  // For 2D text, create orthographic projection
  if (myIs2D)
  {
    const int* aViewport = aCtx->Viewport();
    float aWidth = static_cast<float>(aViewport[2] > 0 ? aViewport[2] : 800);
    float aHeight = static_cast<float>(aViewport[3] > 0 ? aViewport[3] : 600);

    // Orthographic projection matrix (NDC: -1 to 1)
    // Maps (0,0)-(width,height) to (-1,-1)-(1,1) with Y flipped for Metal
    NCollection_Mat4<float> aOrthoMat;
    aOrthoMat.SetValue(0, 0, 2.0f / aWidth);
    aOrthoMat.SetValue(1, 1, -2.0f / aHeight); // Flip Y for Metal
    aOrthoMat.SetValue(2, 2, 1.0f);
    aOrthoMat.SetValue(3, 3, 1.0f);
    aOrthoMat.SetValue(0, 3, -1.0f);
    aOrthoMat.SetValue(1, 3, 1.0f);

    // Apply text position offset
    const gp_Pnt& aPos = myText->Position();
    NCollection_Mat4<float> aTranslateMat;
    aTranslateMat.InitIdentity();
    aTranslateMat.SetValue(0, 3, static_cast<float>(aPos.X()) + myTextOffset.x());
    aTranslateMat.SetValue(1, 3, static_cast<float>(aPos.Y()) + myTextOffset.y());

    NCollection_Mat4<float> aMVP = aOrthoMat * aTranslateMat;
    for (int i = 0; i < 16; ++i)
    {
      aUniforms.ModelViewProjection[i] = aMVP.GetData()[i];
    }
  }
  else
  {
    // 3D text - use computed matrices with scale and offset
    NCollection_Mat4<float> aModelMat;
    aModelMat.InitIdentity();

    // Apply position
    const gp_Pnt& aPos = myText->Position();
    aModelMat.SetValue(0, 3, static_cast<float>(aPos.X()));
    aModelMat.SetValue(1, 3, static_cast<float>(aPos.Y()));
    aModelMat.SetValue(2, 3, static_cast<float>(aPos.Z()));

    // Apply scale for constant screen height
    if (myScaleHeight != 1.0f)
    {
      aModelMat.SetValue(0, 0, myScaleHeight);
      aModelMat.SetValue(1, 1, myScaleHeight);
      aModelMat.SetValue(2, 2, myScaleHeight);
    }

    // Combine with view and projection
    NCollection_Mat4<float> aViewProj = aCtx->ProjectionState.Current() * aCtx->WorldViewState.Current();
    NCollection_Mat4<float> aMVP = aViewProj * aModelMat;

    for (int i = 0; i < 16; ++i)
    {
      aUniforms.ModelViewProjection[i] = aMVP.GetData()[i];
    }
  }

  aUniforms.Color[0] = theColor.x();
  aUniforms.Color[1] = theColor.y();
  aUniforms.Color[2] = theColor.z();
  aUniforms.Color[3] = theColor.w();
  aUniforms.Offset[0] = myTextOffset.x();
  aUniforms.Offset[1] = myTextOffset.y();
  aUniforms.Scale = myScaleHeight;
  aUniforms.Padding = 0.0f;

  // Draw each texture batch
  for (int i = 0; i < myVertsBuffers.Length(); ++i)
  {
    id<MTLBuffer> aVertsBuffer = myVertsBuffers.Value(i);
    id<MTLBuffer> aTCrdsBuffer = myTCrdsBuffers.Value(i);
    int aTexIndex = myTextureIndices.Value(i);

    if (aVertsBuffer == nil || aTCrdsBuffer == nil)
    {
      continue;
    }

    // Bind vertex buffers
    [anEncoder setVertexBuffer:aVertsBuffer offset:0 atIndex:0];
    [anEncoder setVertexBuffer:aTCrdsBuffer offset:0 atIndex:1];

    // Bind uniforms
    [anEncoder setVertexBytes:&aUniforms length:sizeof(aUniforms) atIndex:2];
    [anEncoder setFragmentBytes:&aUniforms length:sizeof(aUniforms) atIndex:0];

    // Bind font texture
    if (!myFont.IsNull() && aTexIndex >= 0 && aTexIndex < myFont->NbTextures())
    {
      const occ::handle<Metal_Texture>& aTexture = myFont->Texture(aTexIndex);
      if (!aTexture.IsNull() && aTexture->IsValid())
      {
        [anEncoder setFragmentTexture:aTexture->Texture() atIndex:0];
      }
    }

    // Draw triangles
    NSUInteger aVertCount = [aVertsBuffer length] / (2 * sizeof(float));
    [anEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                  vertexStart:0
                  vertexCount:aVertCount];
  }
}

// =======================================================================
// function : drawRect
// purpose  : Draw background rectangle using render encoder
// =======================================================================
void Metal_Text::drawRect(Metal_Workspace* theWorkspace,
                           const Graphic3d_Aspects& theAspect,
                           const NCollection_Vec4<float>& theColor) const
{
  (void)theAspect;

  if (theWorkspace == nullptr)
  {
    return;
  }

  id<MTLRenderCommandEncoder> anEncoder = theWorkspace->ActiveEncoder();
  if (anEncoder == nil)
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nil)
  {
    return;
  }

  // Create background quad vertices if needed
  if (myBndVertsBuffer == nil)
  {
    // Expand bounding box slightly for padding
    float aPadding = 2.0f;
    float aQuad[8] = {
      myBndBox.Left - aPadding,  myBndBox.Bottom - aPadding,
      myBndBox.Right + aPadding, myBndBox.Bottom - aPadding,
      myBndBox.Left - aPadding,  myBndBox.Top + aPadding,
      myBndBox.Right + aPadding, myBndBox.Top + aPadding
    };

    id<MTLDevice> aDevice = aCtx->Device();
    if (aDevice != nil)
    {
      myBndVertsBuffer = [aDevice newBufferWithBytes:aQuad
                                              length:sizeof(aQuad)
                                             options:MTLResourceStorageModeShared];
    }
  }

  if (myBndVertsBuffer == nil)
  {
    return;
  }

  // Uniform structure for solid color rendering
  struct RectUniforms
  {
    float ModelViewProjection[16];
    float Color[4];
  };

  RectUniforms aUniforms;

  // Setup matrix (same as text)
  if (myIs2D)
  {
    const int* aViewport = aCtx->Viewport();
    float aWidth = static_cast<float>(aViewport[2] > 0 ? aViewport[2] : 800);
    float aHeight = static_cast<float>(aViewport[3] > 0 ? aViewport[3] : 600);

    NCollection_Mat4<float> aOrthoMat;
    aOrthoMat.SetValue(0, 0, 2.0f / aWidth);
    aOrthoMat.SetValue(1, 1, -2.0f / aHeight);
    aOrthoMat.SetValue(2, 2, 1.0f);
    aOrthoMat.SetValue(3, 3, 1.0f);
    aOrthoMat.SetValue(0, 3, -1.0f);
    aOrthoMat.SetValue(1, 3, 1.0f);

    const gp_Pnt& aPos = myText->Position();
    NCollection_Mat4<float> aTranslateMat;
    aTranslateMat.InitIdentity();
    aTranslateMat.SetValue(0, 3, static_cast<float>(aPos.X()));
    aTranslateMat.SetValue(1, 3, static_cast<float>(aPos.Y()));

    NCollection_Mat4<float> aMVP = aOrthoMat * aTranslateMat;
    for (int i = 0; i < 16; ++i)
    {
      aUniforms.ModelViewProjection[i] = aMVP.GetData()[i];
    }
  }
  else
  {
    NCollection_Mat4<float> aModelMat;
    aModelMat.InitIdentity();

    const gp_Pnt& aPos = myText->Position();
    aModelMat.SetValue(0, 3, static_cast<float>(aPos.X()));
    aModelMat.SetValue(1, 3, static_cast<float>(aPos.Y()));
    aModelMat.SetValue(2, 3, static_cast<float>(aPos.Z()));

    if (myScaleHeight != 1.0f)
    {
      aModelMat.SetValue(0, 0, myScaleHeight);
      aModelMat.SetValue(1, 1, myScaleHeight);
      aModelMat.SetValue(2, 2, myScaleHeight);
    }

    NCollection_Mat4<float> aViewProj = aCtx->ProjectionState.Current() * aCtx->WorldViewState.Current();
    NCollection_Mat4<float> aMVP = aViewProj * aModelMat;

    for (int i = 0; i < 16; ++i)
    {
      aUniforms.ModelViewProjection[i] = aMVP.GetData()[i];
    }
  }

  aUniforms.Color[0] = theColor.x();
  aUniforms.Color[1] = theColor.y();
  aUniforms.Color[2] = theColor.z();
  aUniforms.Color[3] = theColor.w();

  // Bind vertex buffer
  [anEncoder setVertexBuffer:myBndVertsBuffer offset:0 atIndex:0];

  // Bind uniforms
  [anEncoder setVertexBytes:&aUniforms length:sizeof(aUniforms) atIndex:2];
  [anEncoder setFragmentBytes:&aUniforms length:sizeof(aUniforms) atIndex:0];

  // Draw as triangle strip (4 vertices = 2 triangles)
  [anEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4];
}

// =======================================================================
// function : drawTextWithOffset
// purpose  : Draw text glyphs with pixel offset for shadow effects
// =======================================================================
void Metal_Text::drawTextWithOffset(Metal_Workspace* theWorkspace,
                                     const Graphic3d_Aspects& theAspect,
                                     const NCollection_Vec4<float>& theColor,
                                     const NCollection_Vec3<float>& theOffset) const
{
  // Store the offset for use during rendering
  myTextOffset = theOffset;

  // Setup matrix with the offset and draw
  setupMatrix(theWorkspace, theAspect, theOffset);
  drawText(theWorkspace, theAspect, theColor);
}

// =======================================================================
// function : setupMatrix
// purpose  : Setup model-view matrix for text positioning
// =======================================================================
void Metal_Text::setupMatrix(Metal_Workspace* theWorkspace,
                              const Graphic3d_Aspects& theAspect,
                              const NCollection_Vec3<float>& theOffset) const
{
  (void)theAspect;

  if (theWorkspace == nullptr)
  {
    return;
  }

  Metal_Context* aCtx = theWorkspace->Context();
  if (aCtx == nullptr)
  {
    return;
  }

  // Store offset for use in drawText
  myTextOffset = theOffset;

  // For 3D text with custom orientation, compute full matrix
  if (!myIs2D && myText->HasPlane())
  {
    const gp_Ax2& anOrientation = myText->Orientation();
    const gp_Dir& aVectorDir = anOrientation.XDirection();
    const gp_Dir& aVectorUp = anOrientation.Direction();
    const gp_Dir& aVectorRight = anOrientation.YDirection();

    // Build orientation matrix
    NCollection_Mat4<double> aOrientMat;
    aOrientMat.SetColumn(0, NCollection_Vec3<double>(aVectorDir.X(), aVectorDir.Y(), aVectorDir.Z()));
    aOrientMat.SetColumn(1, NCollection_Vec3<double>(aVectorRight.X(), aVectorRight.Y(), aVectorRight.Z()));
    aOrientMat.SetColumn(2, NCollection_Vec3<double>(aVectorUp.X(), aVectorUp.Y(), aVectorUp.Z()));

    myOrientationMatrix = aOrientMat;
  }
}
