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

#include <Metal_GraphicDriver.hxx>
#include <Metal_View.hxx>
#include <Metal_Window.hxx>
#include <Metal_Structure.hxx>
#include <Font_FontMgr.hxx>
#include <Font_FTFont.hxx>
#include <Graphic3d_StructureManager.hxx>
#include <Graphic3d_TypeOfLimit.hxx>
#include <NCollection_String.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_GraphicDriver, Graphic3d_GraphicDriver)

// =======================================================================
// function : Metal_GraphicDriver
// purpose  : Constructor
// =======================================================================
Metal_GraphicDriver::Metal_GraphicDriver(const occ::handle<Aspect_DisplayConnection>& theDisp,
                                         bool theToInitialize)
: Graphic3d_GraphicDriver(theDisp),
  myCaps(new Metal_Caps())
{
  if (theToInitialize)
  {
    InitContext();
  }
}

// =======================================================================
// function : ~Metal_GraphicDriver
// purpose  : Destructor
// =======================================================================
Metal_GraphicDriver::~Metal_GraphicDriver()
{
  ReleaseContext();
}

// =======================================================================
// function : ReleaseContext
// purpose  : Release Metal context
// =======================================================================
void Metal_GraphicDriver::ReleaseContext()
{
  // Release all views first
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    const occ::handle<Metal_View>& aView = aViewIter.Value();
    if (!aView.IsNull())
    {
      aView->ReleaseGlResources(mySharedContext.get());
    }
  }
  myMapOfView.Clear();

  // Release structures (Phase 1 does not implement structures)
  // for (NCollection_DataMap<int, Metal_Structure*>::Iterator aStructIter(myMapOfStructure);
  //      aStructIter.More(); aStructIter.Next())
  // {
  //   Metal_Structure* aStruct = aStructIter.Value();
  //   if (aStruct != nullptr)
  //   {
  //     aStruct->Release(mySharedContext.get());
  //   }
  // }
  // myMapOfStructure.Clear();

  // Release context
  if (!mySharedContext.IsNull())
  {
    mySharedContext->forcedRelease();
    mySharedContext.Nullify();
  }
}

// =======================================================================
// function : InitContext
// purpose  : Initialize Metal context
// =======================================================================
bool Metal_GraphicDriver::InitContext()
{
  ReleaseContext();

  mySharedContext = new Metal_Context(myCaps);
  if (!mySharedContext->Init(myCaps->preferLowPowerGPU))
  {
    return false;
  }

  // Initialize default shaders for basic rendering
  if (!mySharedContext->InitDefaultShaders())
  {
    // Not fatal - shaders will be created on demand
  }

  return true;
}

// =======================================================================
// function : InquireLimit
// purpose  : Request limit of graphic resource
// =======================================================================
int Metal_GraphicDriver::InquireLimit(const Graphic3d_TypeOfLimit theType) const
{
  if (mySharedContext.IsNull() || !mySharedContext->IsValid())
  {
    return 0;
  }

  switch (theType)
  {
    case Graphic3d_TypeOfLimit_MaxNbLights:
      return 8; // Standard limit for OCCT
    case Graphic3d_TypeOfLimit_MaxNbClipPlanes:
      return 8; // Metal can handle many, but OCCT uses 8
    case Graphic3d_TypeOfLimit_MaxNbViews:
      return 256;
    case Graphic3d_TypeOfLimit_MaxTextureSize:
      return mySharedContext->MaxTextureSize();
    case Graphic3d_TypeOfLimit_MaxCombinedTextureUnits:
      return 31; // Metal supports 31 textures per shader stage
    case Graphic3d_TypeOfLimit_MaxMsaa:
      return mySharedContext->MaxMsaaSamples();
    case Graphic3d_TypeOfLimit_MaxViewDumpSizeX:
    case Graphic3d_TypeOfLimit_MaxViewDumpSizeY:
      return mySharedContext->MaxTextureSize();
    case Graphic3d_TypeOfLimit_HasRayTracing:
      return mySharedContext->HasRayTracing() ? 1 : 0;
    case Graphic3d_TypeOfLimit_HasRayTracingTextures:
      return mySharedContext->HasRayTracing() ? 1 : 0;
    case Graphic3d_TypeOfLimit_HasRayTracingAdaptiveSampling:
      return 0; // Not implemented yet
    case Graphic3d_TypeOfLimit_HasRayTracingAdaptiveSamplingAtomic:
      return 0; // Not implemented yet
    case Graphic3d_TypeOfLimit_HasSRGB:
      return 1; // Metal always supports sRGB
    case Graphic3d_TypeOfLimit_HasPBR:
      return 1; // Metal supports PBR
    case Graphic3d_TypeOfLimit_HasBlendedOit:
      return 1;
    case Graphic3d_TypeOfLimit_HasBlendedOitMsaa:
      return 1;
    case Graphic3d_TypeOfLimit_HasFlatShading:
      return 1;
    case Graphic3d_TypeOfLimit_HasMeshEdges:
      return 1;
    case Graphic3d_TypeOfLimit_IsWorkaroundFBO:
      return 0;
    case Graphic3d_TypeOfLimit_NB:
      return 0;
  }
  return 0;
}

// =======================================================================
// function : CreateStructure
// purpose  : Create new structure
// =======================================================================
occ::handle<Graphic3d_CStructure> Metal_GraphicDriver::CreateStructure(
  const occ::handle<Graphic3d_StructureManager>& theManager)
{
  occ::handle<Metal_Structure> aStructure = new Metal_Structure(theManager);
  return aStructure;
}

// =======================================================================
// function : RemoveStructure
// purpose  : Remove structure
// =======================================================================
void Metal_GraphicDriver::RemoveStructure(occ::handle<Graphic3d_CStructure>& theCStructure)
{
  if (theCStructure.IsNull())
  {
    return;
  }

  // Metal_Structure* aStruct = static_cast<Metal_Structure*>(theCStructure.get());
  // myMapOfStructure.UnBind(aStruct->Identification());
  theCStructure.Nullify();
}

// =======================================================================
// function : CreateView
// purpose  : Create new view
// =======================================================================
occ::handle<Graphic3d_CView> Metal_GraphicDriver::CreateView(
  const occ::handle<Graphic3d_StructureManager>& theMgr)
{
  occ::handle<Metal_View> aView = new Metal_View(theMgr, this, myCaps, mySharedContext);
  myMapOfView.Add(aView);
  return aView;
}

// =======================================================================
// function : RemoveView
// purpose  : Remove view
// =======================================================================
void Metal_GraphicDriver::RemoveView(const occ::handle<Graphic3d_CView>& theView)
{
  occ::handle<Metal_View> aView = occ::handle<Metal_View>::DownCast(theView);
  if (aView.IsNull())
  {
    return;
  }

  aView->ReleaseGlResources(mySharedContext.get());
  myMapOfView.Remove(aView);
}

// =======================================================================
// function : CreateRenderWindow
// purpose  : Create Metal window from native window
// =======================================================================
occ::handle<Metal_Window> Metal_GraphicDriver::CreateRenderWindow(
  const occ::handle<Aspect_Window>& theNativeWindow,
  const occ::handle<Aspect_Window>& theSizeWindow)
{
  occ::handle<Metal_Window> aWindow = new Metal_Window(mySharedContext, theNativeWindow, theSizeWindow);
  return aWindow;
}

// =======================================================================
// function : TextSize
// purpose  : Compute text dimensions
// =======================================================================
void Metal_GraphicDriver::TextSize(const occ::handle<Graphic3d_CView>& theView,
                                   const char* theText,
                                   float theHeight,
                                   float& theWidth,
                                   float& theAscent,
                                   float& theDescent) const
{
  theWidth = 0.0f;
  theAscent = 0.0f;
  theDescent = 0.0f;

  if (theText == nullptr || theText[0] == '\0')
  {
    return;
  }

  // Get font parameters from view's rendering params
  unsigned int aResolution = 72;
  Font_Hinting aFontHinting = Font_Hinting_Off;
  if (!theView.IsNull())
  {
    aResolution = theView->RenderingParams().Resolution;
    aFontHinting = theView->RenderingParams().FontHinting;
  }

  // Use height with minimum
  const float aHeight = (theHeight < 2.0f) ? DefaultTextHeight() : theHeight;

  // Find a system font
  occ::handle<Font_FontMgr> aFontMgr = Font_FontMgr::GetInstance();
  Font_FontAspect aFontAspect = Font_FontAspect_Regular;
  occ::handle<Font_SystemFont> aSystemFont = aFontMgr->FindFont(TCollection_AsciiString(""), aFontAspect);
  if (aSystemFont.IsNull())
  {
    // Fallback to approximation if no system font found
    theWidth = aHeight * 0.6f * strlen(theText);
    theAscent = aHeight * 0.8f;
    theDescent = aHeight * 0.2f;
    return;
  }

  // Create FTFont for measurement
  Font_FTFontParams aFontParams;
  aFontParams.PointSize = (unsigned int)aHeight;
  aFontParams.Resolution = aResolution;
  aFontParams.FontHinting = aFontHinting;

  occ::handle<Font_FTFont> aFont = new Font_FTFont();
  bool aToSynthesizeItalic = false;
  int aFaceId = 0;
  TCollection_AsciiString aFontPath = aSystemFont->FontPathAny(aFontAspect, aToSynthesizeItalic, aFaceId);
  if (!aFont->Init(aFontPath, aFontParams))
  {
    // Fallback to approximation
    theWidth = aHeight * 0.6f * strlen(theText);
    theAscent = aHeight * 0.8f;
    theDescent = aHeight * 0.2f;
    return;
  }

  // Get ascent and descent from font metrics
  theAscent = aFont->Ascender();
  theDescent = -aFont->Descender(); // Descender is typically negative

  // Compute width by summing character advances
  NCollection_String aTextStr(theText);
  float aWidth = 0.0f;
  for (NCollection_UtfIterator<char> anIter = aTextStr.Iterator(); *anIter != 0;)
  {
    const char32_t aCharThis = *anIter;
    const char32_t aCharNext = *++anIter;

    // Skip control characters
    if (aCharThis == '\x0D' || aCharThis == '\a' || aCharThis == '\f' ||
        aCharThis == '\b' || aCharThis == '\v')
    {
      continue;
    }
    else if (aCharThis == '\x0A') // newline
    {
      theWidth = std::max(theWidth, aWidth);
      aWidth = 0.0f;
      continue;
    }
    else if (aCharThis == '\t')
    {
      aWidth += aFont->AdvanceX(' ', aCharNext) * 8.0f;
      continue;
    }

    aWidth += aFont->AdvanceX(aCharThis, aCharNext);
  }
  theWidth = std::max(theWidth, aWidth);
}

// =======================================================================
// function : DefaultTextHeight
// purpose  : Return default text height
// =======================================================================
float Metal_GraphicDriver::DefaultTextHeight() const
{
  return 16.0f;
}

// =======================================================================
// function : ViewExists
// purpose  : Check if view exists for window
// =======================================================================
bool Metal_GraphicDriver::ViewExists(const occ::handle<Aspect_Window>& theWindow,
                                     occ::handle<Graphic3d_CView>& theView)
{
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    const occ::handle<Metal_View>& aView = aViewIter.Value();
    if (!aView->Window().IsNull()
     && aView->Window() == theWindow)
    {
      theView = aView;
      return true;
    }
  }
  theView.Nullify();
  return false;
}

// =======================================================================
// function : InsertLayerBefore
// purpose  : Insert layer before another
// =======================================================================
void Metal_GraphicDriver::InsertLayerBefore(const Graphic3d_ZLayerId theNewLayerId,
                                            const Graphic3d_ZLayerSettings& theSettings,
                                            const Graphic3d_ZLayerId theLayerAfter)
{
  Graphic3d_GraphicDriver::InsertLayerBefore(theNewLayerId, theSettings, theLayerAfter);
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    aViewIter.Value()->InsertLayerBefore(theNewLayerId, theSettings, theLayerAfter);
  }
}

// =======================================================================
// function : InsertLayerAfter
// purpose  : Insert layer after another
// =======================================================================
void Metal_GraphicDriver::InsertLayerAfter(const Graphic3d_ZLayerId theNewLayerId,
                                           const Graphic3d_ZLayerSettings& theSettings,
                                           const Graphic3d_ZLayerId theLayerBefore)
{
  Graphic3d_GraphicDriver::InsertLayerAfter(theNewLayerId, theSettings, theLayerBefore);
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    aViewIter.Value()->InsertLayerAfter(theNewLayerId, theSettings, theLayerBefore);
  }
}

// =======================================================================
// function : RemoveZLayer
// purpose  : Remove Z layer
// =======================================================================
void Metal_GraphicDriver::RemoveZLayer(const Graphic3d_ZLayerId theLayerId)
{
  Graphic3d_GraphicDriver::RemoveZLayer(theLayerId);
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    aViewIter.Value()->RemoveZLayer(theLayerId);
  }
}

// =======================================================================
// function : SetZLayerSettings
// purpose  : Set Z layer settings
// =======================================================================
void Metal_GraphicDriver::SetZLayerSettings(const Graphic3d_ZLayerId theLayerId,
                                            const Graphic3d_ZLayerSettings& theSettings)
{
  Graphic3d_GraphicDriver::SetZLayerSettings(theLayerId, theSettings);
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    aViewIter.Value()->SetZLayerSettings(theLayerId, theSettings);
  }
}

// =======================================================================
// function : SetBuffersNoSwap
// purpose  : Set swap buffer behavior
// =======================================================================
void Metal_GraphicDriver::SetBuffersNoSwap(bool theIsNoSwap)
{
  myCaps->buffersNoSwap = theIsNoSwap;
}

// =======================================================================
// function : EnableVBO
// purpose  : VBO control (no-op on Metal)
// =======================================================================
void Metal_GraphicDriver::EnableVBO(bool theToTurnOn)
{
  // Metal always uses buffers, this is a no-op
  (void)theToTurnOn;
}

// =======================================================================
// function : IsVerticalSync
// purpose  : Check VSync status
// =======================================================================
bool Metal_GraphicDriver::IsVerticalSync() const
{
  return myCaps->swapInterval != 0;
}

// =======================================================================
// function : SetVerticalSync
// purpose  : Set VSync
// =======================================================================
void Metal_GraphicDriver::SetVerticalSync(bool theToEnable)
{
  myCaps->swapInterval = theToEnable ? 1 : 0;
}

// =======================================================================
// function : MemoryInfo
// purpose  : Get GPU memory info
// =======================================================================
bool Metal_GraphicDriver::MemoryInfo(size_t& theFreeBytes,
                                     TCollection_AsciiString& theInfo) const
{
  theFreeBytes = 0;
  if (!mySharedContext.IsNull() && mySharedContext->IsValid())
  {
    theInfo = mySharedContext->MemoryInfo();
    return true;
  }
  return false;
}

// =======================================================================
// function : GetSharedContext
// purpose  : Get shared Metal context
// =======================================================================
const occ::handle<Metal_Context>& Metal_GraphicDriver::GetSharedContext() const
{
  return mySharedContext;
}

// =======================================================================
// function : setDeviceLost
// purpose  : Set device lost flag
// =======================================================================
void Metal_GraphicDriver::setDeviceLost()
{
  for (NCollection_Map<occ::handle<Metal_View>>::Iterator aViewIter(myMapOfView);
       aViewIter.More(); aViewIter.Next())
  {
    aViewIter.Value()->SetImmediateModeDrawToFront(false);
  }
}
