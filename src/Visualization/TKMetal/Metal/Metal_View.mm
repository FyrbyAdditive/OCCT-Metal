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

// Import Apple frameworks first to avoid Handle name conflicts with Carbon
#import <TargetConditionals.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Now include OCCT headers
#include <Metal_View.hxx>
#include <Metal_GraphicDriver.hxx>
#include <Metal_Structure.hxx>
#include <Metal_Workspace.hxx>
#include <Metal_FrameBuffer.hxx>
#include <BVH_LinearBuilder.hxx>
#include <Graphic3d_Structure.hxx>
#include <Image_PixMap.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_View, Graphic3d_CView)

// =======================================================================
// function : Metal_View
// purpose  : Constructor
// =======================================================================
Metal_View::Metal_View(const occ::handle<Graphic3d_StructureManager>& theMgr,
                       const Metal_GraphicDriver* theDriver,
                       const occ::handle<Metal_Caps>& theCaps,
                       const occ::handle<Metal_Context>& theContext)
: Graphic3d_CView(theMgr),
  myDriver(theDriver),
  myCaps(theCaps),
  myContext(theContext),
  myBgGradientFrom(Quantity_NOC_BLACK),
  myBgGradientTo(Quantity_NOC_BLACK),
  myBgGradientMethod(Aspect_GradientFillMethod_None),
  myBgImageStyle(Aspect_FM_CENTERED),
  myZLayerMax(0),
  myBackBufferRestored(false),
  myToDrawImmediate(false),
  myFrameCounter(0),
  myDepthTexture(nil),
  myDepthWidth(0),
  myDepthHeight(0)
{
  myLights = new Graphic3d_LightSet();
  myClipPlanes = new Graphic3d_SequenceOfHClipPlane();
}

// =======================================================================
// function : ~Metal_View
// purpose  : Destructor
// =======================================================================
Metal_View::~Metal_View()
{
  ReleaseGlResources(myContext.get());
  Remove();
}

// =======================================================================
// function : ReleaseGlResources
// purpose  : Release Metal resources
// =======================================================================
void Metal_View::ReleaseGlResources(Metal_Context* theCtx)
{
  (void)theCtx;

  // Release framebuffers
  if (!myFBO.IsNull())
  {
    myFBO->Release(theCtx);
    myFBO.Nullify();
  }
  if (!myMainFBO.IsNull())
  {
    myMainFBO->Release(theCtx);
    myMainFBO.Nullify();
  }

  // Release depth texture
  myDepthTexture = nil;
  myDepthWidth = 0;
  myDepthHeight = 0;

  // Release window
  myWindow.Nullify();
}

// =======================================================================
// function : Remove
// purpose  : Deletes and erases the view
// =======================================================================
void Metal_View::Remove()
{
  if (IsRemoved())
  {
    return;
  }

  myLayers.Clear();
  Graphic3d_CView::Remove();
}

// =======================================================================
// function : SetImmediateModeDrawToFront
// purpose  : Set immediate mode draw to front
// =======================================================================
bool Metal_View::SetImmediateModeDrawToFront(const bool theDrawToFrontBuffer)
{
  bool aPrev = myToDrawImmediate;
  myToDrawImmediate = theDrawToFrontBuffer;
  return aPrev;
}

// =======================================================================
// function : SetWindow
// purpose  : Creates and maps rendering window to the view
// =======================================================================
void Metal_View::SetWindow(const occ::handle<Graphic3d_CView>& theParentVIew,
                           const occ::handle<Aspect_Window>& theWindow,
                           const Aspect_RenderingContext theContext)
{
  (void)theParentVIew;
  (void)theContext;

  myPlatformWindow = theWindow;

  if (myContext.IsNull())
  {
    return;
  }

  // Create Metal window
  myWindow = new Metal_Window(myContext, theWindow, theWindow);
  if (!myWindow->Init())
  {
    myWindow.Nullify();
    return;
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : Window
// purpose  : Returns window associated with the view
// =======================================================================
occ::handle<Aspect_Window> Metal_View::Window() const
{
  return myPlatformWindow;
}

// =======================================================================
// function : Resized
// purpose  : Handle changing size of the rendering window
// =======================================================================
void Metal_View::Resized()
{
  if (!myWindow.IsNull())
  {
    myWindow->Resize();
    myBackBufferRestored = false;
  }
}

// =======================================================================
// function : Redraw
// purpose  : Redraw content of the view
// =======================================================================
void Metal_View::Redraw()
{
  if (myWindow.IsNull() || myContext.IsNull() || !myContext->IsValid())
  {
    return;
  }

  ++myFrameCounter;

  // Wait for previous frame to complete (triple-buffering)
  myContext->WaitForFrame();

  // Get next drawable from the Metal layer
  id<CAMetalDrawable> aDrawable = myWindow->NextDrawable();
  if (aDrawable == nil)
  {
    return;
  }

  // Get or create command buffer for this frame
  id<MTLCommandBuffer> aCommandBuffer = myContext->CurrentCommandBuffer();
  if (aCommandBuffer == nil)
  {
    return;
  }

  // Ensure we have a depth buffer
  int aWidth = (int)aDrawable.texture.width;
  int aHeight = (int)aDrawable.texture.height;
  initDepthBuffer(aWidth, aHeight);

  // Create render pass descriptor
  MTLRenderPassDescriptor* aRenderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];

  // Configure color attachment (clear to background color)
  aRenderPassDesc.colorAttachments[0].texture = aDrawable.texture;
  aRenderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
  aRenderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

  // Get background color (convert from Quantity_ColorRGBA to Metal clear color)
  const Quantity_Color& aBgRgb = myBgColor.GetRGB();
  aRenderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(aBgRgb.Red(), aBgRgb.Green(), aBgRgb.Blue(), 1.0);

  // Configure depth attachment
  if (myDepthTexture != nil)
  {
    aRenderPassDesc.depthAttachment.texture = myDepthTexture;
    aRenderPassDesc.depthAttachment.loadAction = MTLLoadActionClear;
    aRenderPassDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
    aRenderPassDesc.depthAttachment.clearDepth = 1.0;
  }

  // Create render command encoder
  id<MTLRenderCommandEncoder> aRenderEncoder = [aCommandBuffer renderCommandEncoderWithDescriptor:aRenderPassDesc];
  if (aRenderEncoder == nil)
  {
    return;
  }

  // Set viewport
  MTLViewport aViewport;
  aViewport.originX = 0.0;
  aViewport.originY = 0.0;
  aViewport.width = aWidth;
  aViewport.height = aHeight;
  aViewport.znear = 0.0;
  aViewport.zfar = 1.0;
  [aRenderEncoder setViewport:aViewport];

  // Check if we have displayed structures to render
  bool aHasStructures = (NumberOfDisplayedStructures() > 0);

  if (aHasStructures && myContext->DefaultPipeline() != nil)
  {
    // Create workspace for rendering
    occ::handle<Metal_Workspace> aWorkspace = new Metal_Workspace(myContext.get(), this);
    aWorkspace->SetEncoder(aRenderEncoder);

    // Set up camera matrices
    if (!myCamera.IsNull())
    {
      // Get matrices from camera
      const NCollection_Mat4<float>& aModelView = myCamera->OrientationMatrixF();
      const NCollection_Mat4<float>& aProjection = myCamera->ProjectionMatrixF();

      aWorkspace->SetModelMatrix(aModelView);
      aWorkspace->SetProjectionMatrix(aProjection);
    }

    // Apply pipeline state
    aWorkspace->ApplyPipelineState();

    // Set light sources
    if (!myLights.IsNull())
    {
      aWorkspace->SetLightSources(myLights);
    }

    // Render all displayed structures
    renderStructures(aWorkspace.get());
  }
  else if (myContext->DefaultPipeline() != nil)
  {
    // No structures to render, draw test triangle for visual feedback
    drawTestTriangle((__bridge void*)aRenderEncoder, aWidth, aHeight);
  }

  // End encoding
  [aRenderEncoder endEncoding];

  // Present the drawable
  [aCommandBuffer presentDrawable:aDrawable];

  // Commit command buffer and signal frame completion
  myContext->Commit();

  myBackBufferRestored = true;
}

// =======================================================================
// function : RedrawImmediate
// purpose  : Redraw immediate content of the view
// =======================================================================
void Metal_View::RedrawImmediate()
{
  // For Phase 1, just do a full redraw
  // Later phases will implement incremental immediate mode rendering
  if (!myBackBufferRestored)
  {
    Redraw();
    return;
  }

  // For now, immediate mode also triggers full redraw
  Redraw();
}

// =======================================================================
// function : Invalidate
// purpose  : Marks BVH tree as dirty
// =======================================================================
void Metal_View::Invalidate()
{
  myBackBufferRestored = false;
}

// =======================================================================
// function : BufferDump
// purpose  : Dump active rendering buffer into specified memory buffer
// =======================================================================
bool Metal_View::BufferDump(Image_PixMap& theImage,
                            const Graphic3d_BufferType& theBufferType)
{
  if (myContext.IsNull() || !myContext->IsValid())
  {
    return false;
  }

  // Get the texture to read from
  id<MTLTexture> aTexture = nil;
  int aWidth = 0;
  int aHeight = 0;

  if (theBufferType == Graphic3d_BT_Depth)
  {
    // Read from depth buffer
    aTexture = myDepthTexture;
    aWidth = myDepthWidth;
    aHeight = myDepthHeight;

    if (aTexture == nil || aWidth == 0 || aHeight == 0)
    {
      return false;
    }

    // Initialize image for depth buffer (32-bit float)
    if (!theImage.InitZero(Image_Format_GrayF, aWidth, aHeight))
    {
      return false;
    }

    // Read depth data
    MTLRegion aRegion = MTLRegionMake2D(0, 0, aWidth, aHeight);
    size_t aBytesPerRow = aWidth * sizeof(float);

    [aTexture getBytes:theImage.ChangeData()
           bytesPerRow:aBytesPerRow
            fromRegion:aRegion
           mipmapLevel:0];

    return true;
  }

  // For color buffer, get from FBO or main scene
  occ::handle<Metal_FrameBuffer> aFBO;
  if (!myFBO.IsNull() && myFBO->IsValid())
  {
    aFBO = myFBO;
  }
  else if (!myMainFBO.IsNull() && myMainFBO->IsValid())
  {
    aFBO = myMainFBO;
  }

  if (aFBO.IsNull())
  {
    // For window rendering without FBO, we cannot read back
    return false;
  }

  aWidth = aFBO->GetSizeX();
  aHeight = aFBO->GetSizeY();
  aTexture = aFBO->MetalColorTexture();

  if (aTexture == nil || aWidth == 0 || aHeight == 0)
  {
    return false;
  }

  // Determine image format based on texture format
  Image_Format anImageFormat = Image_Format_RGBA;
  MTLPixelFormat aPixelFormat = aTexture.pixelFormat;

  if (aPixelFormat == MTLPixelFormatBGRA8Unorm)
  {
    anImageFormat = Image_Format_BGRA;
  }
  else if (aPixelFormat == MTLPixelFormatRGBA8Unorm)
  {
    anImageFormat = Image_Format_RGBA;
  }
  else if (aPixelFormat == MTLPixelFormatRGBA16Float)
  {
    anImageFormat = Image_Format_RGBAF_half;
  }
  else if (aPixelFormat == MTLPixelFormatRGBA32Float)
  {
    anImageFormat = Image_Format_RGBAF;
  }

  // Initialize image
  if (!theImage.InitZero(anImageFormat, aWidth, aHeight))
  {
    return false;
  }

  // Read pixel data using the FBO's readback method (handles private storage textures)
  if (!aFBO->ReadColorPixels(myContext.get(), theImage.ChangeData()))
  {
    return false;
  }

  // Metal textures are top-to-bottom, but Image_PixMap expects bottom-to-top
  // Flip the image vertically
  size_t aBytesPerRow = theImage.SizeRowBytes();
  Standard_Byte* aRowBuffer = new Standard_Byte[aBytesPerRow];
  Standard_Byte* aData = theImage.ChangeData();

  for (int y = 0; y < aHeight / 2; ++y)
  {
    Standard_Byte* aTopRow = aData + y * aBytesPerRow;
    Standard_Byte* aBottomRow = aData + (aHeight - 1 - y) * aBytesPerRow;

    memcpy(aRowBuffer, aTopRow, aBytesPerRow);
    memcpy(aTopRow, aBottomRow, aBytesPerRow);
    memcpy(aBottomRow, aRowBuffer, aBytesPerRow);
  }

  delete[] aRowBuffer;

  return true;
}

// =======================================================================
// function : ShadowMapDump
// purpose  : Dumps shadowmap framebuffer into an image
// =======================================================================
bool Metal_View::ShadowMapDump(Image_PixMap& theImage,
                               const TCollection_AsciiString& theLightName)
{
  (void)theImage;
  (void)theLightName;
  // Not implemented in Phase 1
  return false;
}

// =======================================================================
// function : InvalidateBVHData
// purpose  : Marks BVH tree and primitives as outdated
// =======================================================================
void Metal_View::InvalidateBVHData(const Graphic3d_ZLayerId theLayerId)
{
  (void)theLayerId;
  myBackBufferRestored = false;
}

// =======================================================================
// function : InsertLayerBefore
// purpose  : Add a layer to the view
// =======================================================================
void Metal_View::InsertLayerBefore(const Graphic3d_ZLayerId theNewLayerId,
                                   const Graphic3d_ZLayerSettings& theSettings,
                                   const Graphic3d_ZLayerId theLayerAfter)
{
  // Check if layer already exists
  if (myLayerMap.IsBound(theNewLayerId))
  {
    return;
  }

  // Create BVH builder for frustum culling
  occ::handle<BVH_Builder3d> aBVHBuilder = new BVH_LinearBuilder<double, 3>(BVH_Constants_LeafNodeSizeSingle, BVH_Constants_MaxTreeDepth);

  // Create the new layer
  occ::handle<Graphic3d_Layer> aNewLayer = new Graphic3d_Layer(theNewLayerId, aBVHBuilder);
  aNewLayer->SetLayerSettings(theSettings);

  // Add to map
  myLayerMap.Bind(theNewLayerId, aNewLayer);

  // Update max layer ID
  if (theNewLayerId > myZLayerMax)
  {
    myZLayerMax = theNewLayerId;
  }

  // Find position to insert (before theLayerAfter)
  if (theLayerAfter == Graphic3d_ZLayerId_UNKNOWN || myLayers.IsEmpty())
  {
    // Insert at the beginning
    myLayers.Prepend(aNewLayer);
  }
  else
  {
    // Find the layer to insert before
    bool aFound = false;
    for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
         anIter.More(); anIter.Next())
    {
      if (anIter.Value()->LayerId() == theLayerAfter)
      {
        myLayers.InsertBefore(aNewLayer, anIter);
        aFound = true;
        break;
      }
    }
    if (!aFound)
    {
      // Layer not found, append to end
      myLayers.Append(aNewLayer);
    }
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : InsertLayerAfter
// purpose  : Add a layer to the view
// =======================================================================
void Metal_View::InsertLayerAfter(const Graphic3d_ZLayerId theNewLayerId,
                                  const Graphic3d_ZLayerSettings& theSettings,
                                  const Graphic3d_ZLayerId theLayerBefore)
{
  // Check if layer already exists
  if (myLayerMap.IsBound(theNewLayerId))
  {
    return;
  }

  // Create BVH builder for frustum culling
  occ::handle<BVH_Builder3d> aBVHBuilder = new BVH_LinearBuilder<double, 3>(BVH_Constants_LeafNodeSizeSingle, BVH_Constants_MaxTreeDepth);

  // Create the new layer
  occ::handle<Graphic3d_Layer> aNewLayer = new Graphic3d_Layer(theNewLayerId, aBVHBuilder);
  aNewLayer->SetLayerSettings(theSettings);

  // Add to map
  myLayerMap.Bind(theNewLayerId, aNewLayer);

  // Update max layer ID
  if (theNewLayerId > myZLayerMax)
  {
    myZLayerMax = theNewLayerId;
  }

  // Find position to insert (after theLayerBefore)
  if (theLayerBefore == Graphic3d_ZLayerId_UNKNOWN || myLayers.IsEmpty())
  {
    // Insert at the end
    myLayers.Append(aNewLayer);
  }
  else
  {
    // Find the layer to insert after
    bool aFound = false;
    for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
         anIter.More(); anIter.Next())
    {
      if (anIter.Value()->LayerId() == theLayerBefore)
      {
        // Move to next position and insert before it (which is after current)
        anIter.Next();
        if (anIter.More())
        {
          myLayers.InsertBefore(aNewLayer, anIter);
        }
        else
        {
          myLayers.Append(aNewLayer);
        }
        aFound = true;
        break;
      }
    }
    if (!aFound)
    {
      // Layer not found, append to end
      myLayers.Append(aNewLayer);
    }
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : RemoveZLayer
// purpose  : Remove a z layer with the given ID
// =======================================================================
void Metal_View::RemoveZLayer(const Graphic3d_ZLayerId theLayerId)
{
  // Cannot remove default layer
  if (theLayerId == Graphic3d_ZLayerId_Default)
  {
    return;
  }

  // Check if layer exists
  if (!myLayerMap.IsBound(theLayerId))
  {
    return;
  }

  // Remove from list
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
       anIter.More(); anIter.Next())
  {
    if (anIter.Value()->LayerId() == theLayerId)
    {
      myLayers.Remove(anIter);
      break;
    }
  }

  // Remove from map
  myLayerMap.UnBind(theLayerId);

  myBackBufferRestored = false;
}

// =======================================================================
// function : SetZLayerSettings
// purpose  : Sets the settings for a single Z layer
// =======================================================================
void Metal_View::SetZLayerSettings(const Graphic3d_ZLayerId theLayerId,
                                   const Graphic3d_ZLayerSettings& theSettings)
{
  occ::handle<Graphic3d_Layer> aLayer = Layer(theLayerId);
  if (!aLayer.IsNull())
  {
    aLayer->SetLayerSettings(theSettings);
    myBackBufferRestored = false;
  }
}

// =======================================================================
// function : ZLayerMax
// purpose  : Returns the maximum Z layer ID
// =======================================================================
int Metal_View::ZLayerMax() const
{
  return myZLayerMax;
}

// =======================================================================
// function : Layers
// purpose  : Returns the list of layers
// =======================================================================
const NCollection_List<occ::handle<Graphic3d_Layer>>& Metal_View::Layers() const
{
  return myLayers;
}

// =======================================================================
// function : Layer
// purpose  : Returns layer with given ID or NULL if undefined
// =======================================================================
occ::handle<Graphic3d_Layer> Metal_View::Layer(const Graphic3d_ZLayerId theLayerId) const
{
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerMap.Seek(theLayerId);
  return (aLayerPtr != nullptr) ? *aLayerPtr : occ::handle<Graphic3d_Layer>();
}

// =======================================================================
// function : FBO
// purpose  : Returns pointer to an assigned framebuffer object
// =======================================================================
occ::handle<Standard_Transient> Metal_View::FBO() const
{
  return myFBO;
}

// =======================================================================
// function : SetFBO
// purpose  : Sets framebuffer object for offscreen rendering
// =======================================================================
void Metal_View::SetFBO(const occ::handle<Standard_Transient>& theFbo)
{
  myFBO = occ::handle<Metal_FrameBuffer>::DownCast(theFbo);
  myBackBufferRestored = false;
}

// =======================================================================
// function : FBOCreate
// purpose  : Generate offscreen FBO
// =======================================================================
occ::handle<Standard_Transient> Metal_View::FBOCreate(const int theWidth, const int theHeight)
{
  if (myContext.IsNull() || !myContext->IsValid())
  {
    return occ::handle<Standard_Transient>();
  }

  // Create new framebuffer with default color and depth formats
  occ::handle<Metal_FrameBuffer> aFrameBuffer = new Metal_FrameBuffer("UserFBO");

  NCollection_Vec2<int> aSize(theWidth, theHeight);
  if (!aFrameBuffer->Init(myContext.get(),
                          aSize,
                          Metal_PixelFormat_BGRA8,
                          Metal_PixelFormat_Depth32F,
                          0)) // No MSAA for user-created FBOs by default
  {
    return occ::handle<Standard_Transient>();
  }

  return aFrameBuffer;
}

// =======================================================================
// function : FBORelease
// purpose  : Remove offscreen FBO
// =======================================================================
void Metal_View::FBORelease(occ::handle<Standard_Transient>& theFbo)
{
  occ::handle<Metal_FrameBuffer> aFrameBuffer = occ::handle<Metal_FrameBuffer>::DownCast(theFbo);
  if (!aFrameBuffer.IsNull())
  {
    aFrameBuffer->Release(myContext.get());
  }
  theFbo.Nullify();
}

// =======================================================================
// function : FBOGetDimensions
// purpose  : Read offscreen FBO configuration
// =======================================================================
void Metal_View::FBOGetDimensions(const occ::handle<Standard_Transient>& theFbo,
                                  int& theWidth,
                                  int& theHeight,
                                  int& theWidthMax,
                                  int& theHeightMax)
{
  occ::handle<Metal_FrameBuffer> aFrameBuffer = occ::handle<Metal_FrameBuffer>::DownCast(theFbo);
  if (aFrameBuffer.IsNull())
  {
    theWidth = 0;
    theHeight = 0;
    theWidthMax = 0;
    theHeightMax = 0;
    return;
  }

  theWidth = aFrameBuffer->GetVPSizeX();
  theHeight = aFrameBuffer->GetVPSizeY();
  theWidthMax = aFrameBuffer->GetSizeX();
  theHeightMax = aFrameBuffer->GetSizeY();
}

// =======================================================================
// function : FBOChangeViewport
// purpose  : Change offscreen FBO viewport
// =======================================================================
void Metal_View::FBOChangeViewport(const occ::handle<Standard_Transient>& theFbo,
                                   const int theWidth,
                                   const int theHeight)
{
  occ::handle<Metal_FrameBuffer> aFrameBuffer = occ::handle<Metal_FrameBuffer>::DownCast(theFbo);
  if (!aFrameBuffer.IsNull())
  {
    aFrameBuffer->ChangeViewport(theWidth, theHeight);
  }
}

// =======================================================================
// function : GradientBackground
// purpose  : Returns gradient background fill colors
// =======================================================================
Aspect_GradientBackground Metal_View::GradientBackground() const
{
  return Aspect_GradientBackground(myBgGradientFrom, myBgGradientTo, myBgGradientMethod);
}

// =======================================================================
// function : SetGradientBackground
// purpose  : Sets gradient background fill colors
// =======================================================================
void Metal_View::SetGradientBackground(const Aspect_GradientBackground& theBackground)
{
  theBackground.Colors(myBgGradientFrom, myBgGradientTo);
  myBgGradientMethod = theBackground.BgGradientFillMethod();
  myBackBufferRestored = false;
}

// =======================================================================
// function : SetBackgroundImage
// purpose  : Sets image texture or environment cubemap as background
// =======================================================================
void Metal_View::SetBackgroundImage(const occ::handle<Graphic3d_TextureMap>& theTextureMap,
                                    bool theToUpdatePBREnv)
{
  (void)theTextureMap;
  (void)theToUpdatePBREnv;
  // Background image support will be implemented in later phases
  myBackBufferRestored = false;
}

// =======================================================================
// function : BackgroundImageStyle
// purpose  : Returns background image fill style
// =======================================================================
Aspect_FillMethod Metal_View::BackgroundImageStyle() const
{
  return myBgImageStyle;
}

// =======================================================================
// function : SetBackgroundImageStyle
// purpose  : Sets background image fill style
// =======================================================================
void Metal_View::SetBackgroundImageStyle(const Aspect_FillMethod theFillStyle)
{
  myBgImageStyle = theFillStyle;
  myBackBufferRestored = false;
}

// =======================================================================
// function : SetImageBasedLighting
// purpose  : Enables or disables IBL
// =======================================================================
void Metal_View::SetImageBasedLighting(bool theToEnableIBL)
{
  (void)theToEnableIBL;
  // IBL support will be implemented in later phases
}

// =======================================================================
// function : SetTextureEnv
// purpose  : Sets environment texture for the view
// =======================================================================
void Metal_View::SetTextureEnv(const occ::handle<Graphic3d_TextureEnv>& theTextureEnv)
{
  (void)theTextureEnv;
  // Environment texture support will be implemented in later phases
}

// =======================================================================
// function : SetLights
// purpose  : Sets list of lights for the view
// =======================================================================
void Metal_View::SetLights(const occ::handle<Graphic3d_LightSet>& theLights)
{
  myLights = theLights;
  myBackBufferRestored = false;
}

// =======================================================================
// function : SetClipPlanes
// purpose  : Sets list of clip planes for the view
// =======================================================================
void Metal_View::SetClipPlanes(const occ::handle<Graphic3d_SequenceOfHClipPlane>& thePlanes)
{
  myClipPlanes = thePlanes;
  myBackBufferRestored = false;
}

// =======================================================================
// function : DiagnosticInformation
// purpose  : Fill in the dictionary with diagnostic info
// =======================================================================
void Metal_View::DiagnosticInformation(
  NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict,
  Graphic3d_DiagnosticInfo theFlags) const
{
  if ((theFlags & Graphic3d_DiagnosticInfo_Device) != 0)
  {
    theDict.Add("GLvendor", "Apple");
    theDict.Add("GLdevice", "Metal");
    if (!myContext.IsNull())
    {
      theDict.Add("GLdeviceInfo", myContext->DeviceName());
    }
  }

  if ((theFlags & Graphic3d_DiagnosticInfo_Memory) != 0)
  {
    if (!myContext.IsNull())
    {
      theDict.Add("GPUmemory", myContext->MemoryInfo());
    }
  }
}

// =======================================================================
// function : StatisticInformation
// purpose  : Returns string with statistic performance info
// =======================================================================
TCollection_AsciiString Metal_View::StatisticInformation() const
{
  TCollection_AsciiString aInfo;
  aInfo += "Metal View\n";
  aInfo += TCollection_AsciiString("  Frame: ") + myFrameCounter + "\n";
  if (!myWindow.IsNull())
  {
    aInfo += TCollection_AsciiString("  Size: ") + myWindow->Width() + "x" + myWindow->Height() + "\n";
    aInfo += TCollection_AsciiString("  Scale: ") + myWindow->ScaleFactor() + "\n";
  }
  return aInfo;
}

// =======================================================================
// function : StatisticInformation
// purpose  : Fills in the dictionary with statistic performance info
// =======================================================================
void Metal_View::StatisticInformation(
  NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict) const
{
  theDict.Add("Frame", TCollection_AsciiString(myFrameCounter));
  if (!myWindow.IsNull())
  {
    theDict.Add("ViewWidth", TCollection_AsciiString(myWindow->Width()));
    theDict.Add("ViewHeight", TCollection_AsciiString(myWindow->Height()));
    theDict.Add("ScaleFactor", TCollection_AsciiString(myWindow->ScaleFactor()));
  }
}

// =======================================================================
// function : displayStructure
// purpose  : Adds the structure to display lists of the view
// =======================================================================
void Metal_View::displayStructure(const occ::handle<Graphic3d_CStructure>& theStructure,
                                  const Graphic3d_DisplayPriority thePriority)
{
  if (theStructure.IsNull())
  {
    return;
  }

  // Get the layer for this structure
  Graphic3d_ZLayerId aLayerId = theStructure->ZLayer();
  occ::handle<Graphic3d_Layer> aLayer = Layer(aLayerId);
  if (aLayer.IsNull())
  {
    // Try default layer
    aLayer = Layer(Graphic3d_ZLayerId_Default);
  }

  if (!aLayer.IsNull())
  {
    aLayer->Add(theStructure.get(), thePriority);
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : eraseStructure
// purpose  : Erases the structure from display lists of the view
// =======================================================================
void Metal_View::eraseStructure(const occ::handle<Graphic3d_CStructure>& theStructure)
{
  if (theStructure.IsNull())
  {
    return;
  }

  // Search all layers for this structure and remove it
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
       anIter.More(); anIter.Next())
  {
    Graphic3d_DisplayPriority aPriority;
    if (anIter.Value()->Remove(theStructure.get(), aPriority))
    {
      break; // Structure found and removed
    }
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : changeZLayer
// purpose  : Change Z layer of a structure already presented in view
// =======================================================================
void Metal_View::changeZLayer(const occ::handle<Graphic3d_CStructure>& theCStructure,
                              const Graphic3d_ZLayerId theNewLayerId)
{
  if (theCStructure.IsNull())
  {
    return;
  }

  // Find and remove from current layer
  Graphic3d_DisplayPriority aPriority = Graphic3d_DisplayPriority_Normal;
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
       anIter.More(); anIter.Next())
  {
    if (anIter.Value()->Remove(theCStructure.get(), aPriority))
    {
      break;
    }
  }

  // Add to new layer
  occ::handle<Graphic3d_Layer> aNewLayer = Layer(theNewLayerId);
  if (aNewLayer.IsNull())
  {
    aNewLayer = Layer(Graphic3d_ZLayerId_Default);
  }
  if (!aNewLayer.IsNull())
  {
    aNewLayer->Add(theCStructure.get(), aPriority);
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : changePriority
// purpose  : Changes the priority of a structure within its Z layer
// =======================================================================
void Metal_View::changePriority(const occ::handle<Graphic3d_CStructure>& theCStructure,
                                const Graphic3d_DisplayPriority theNewPriority)
{
  if (theCStructure.IsNull())
  {
    return;
  }

  // Find the layer containing this structure
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator anIter(myLayers);
       anIter.More(); anIter.Next())
  {
    Graphic3d_DisplayPriority aOldPriority;
    if (anIter.Value()->Remove(theCStructure.get(), aOldPriority, true))
    {
      // Re-add with new priority
      anIter.Value()->Add(theCStructure.get(), theNewPriority, true);
      break;
    }
  }

  myBackBufferRestored = false;
}

// =======================================================================
// function : renderStructures
// purpose  : Render all displayed structures
// =======================================================================
void Metal_View::renderStructures(Metal_Workspace* theWorkspace)
{
  if (theWorkspace == nullptr)
  {
    return;
  }

  // Save original model matrix to restore after each structure
  const NCollection_Mat4<float> aBaseModelMatrix = theWorkspace->ModelMatrix();

  // Iterate through layers in order (they are stored in Z-order)
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
       aLayerIter.More(); aLayerIter.Next())
  {
    const occ::handle<Graphic3d_Layer>& aLayer = aLayerIter.Value();
    if (aLayer.IsNull() || aLayer->NbStructures() == 0)
    {
      continue;
    }

    // Render structures in this layer by priority (lower priority first)
    const Graphic3d_ArrayOfIndexedMapOfStructure& aStructArray = aLayer->ArrayOfStructures();
    for (int aPriorityIdx = 0; aPriorityIdx < Graphic3d_DisplayPriority_NB; ++aPriorityIdx)
    {
      const NCollection_IndexedMap<const Graphic3d_CStructure*>& aStructMap = aStructArray[aPriorityIdx];
      for (int aStructIdx = 1; aStructIdx <= aStructMap.Extent(); ++aStructIdx)
      {
        const Graphic3d_CStructure* aCStruct = aStructMap.FindKey(aStructIdx);
        if (aCStruct == nullptr || !aCStruct->IsVisible())
        {
          continue;
        }

        const Metal_Structure* aMetalStruct = dynamic_cast<const Metal_Structure*>(aCStruct);
        if (aMetalStruct != nullptr)
        {
          // Restore base model matrix and apply structure transformation
          NCollection_Mat4<float> aModelMatrix = aBaseModelMatrix;
          const NCollection_Mat4<float>& aStructTrsf = aMetalStruct->RenderTransformation();
          aModelMatrix = aModelMatrix * aStructTrsf;
          theWorkspace->SetModelMatrix(aModelMatrix);

          // Check for highlighting
          if (aCStruct->highlight != 0)
          {
            theWorkspace->SetHighlighting(true);
            const occ::handle<Graphic3d_PresentationAttributes>& aHighStyle = aCStruct->HighlightStyle();
            if (!aHighStyle.IsNull())
            {
              theWorkspace->SetHighlightColor(aHighStyle->ColorRGBA());
            }
          }

          // Apply uniforms before rendering
          theWorkspace->ApplyUniforms();

          // Render the structure (cast away const as Render is non-const in design)
          const_cast<Metal_Structure*>(aMetalStruct)->Render(theWorkspace);

          // Reset highlighting
          theWorkspace->SetHighlighting(false);
        }
      }
    }
  }

  // Restore original model matrix
  theWorkspace->SetModelMatrix(aBaseModelMatrix);
}

// =======================================================================
// function : initDepthBuffer
// purpose  : Initialize or resize the depth buffer
// =======================================================================
void Metal_View::initDepthBuffer(int theWidth, int theHeight)
{
  if (myContext.IsNull() || myContext->Device() == nil)
  {
    return;
  }

  // Check if we need to resize
  if (myDepthTexture != nil && myDepthWidth == theWidth && myDepthHeight == theHeight)
  {
    return;
  }

  // Create new depth texture
  MTLTextureDescriptor* aDepthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                        width:theWidth
                                                                                       height:theHeight
                                                                                    mipmapped:NO];
  aDepthDesc.storageMode = MTLStorageModePrivate;
  aDepthDesc.usage = MTLTextureUsageRenderTarget;

  myDepthTexture = [myContext->Device() newTextureWithDescriptor:aDepthDesc];
  myDepthWidth = theWidth;
  myDepthHeight = theHeight;
}

// =======================================================================
// function : drawTestTriangle
// purpose  : Draw a test triangle to verify rendering pipeline
// =======================================================================
void Metal_View::drawTestTriangle(void* theEncoderPtr, int theWidth, int theHeight)
{
  (void)theWidth;
  (void)theHeight;

  id<MTLRenderCommandEncoder> aRenderEncoder = (__bridge id<MTLRenderCommandEncoder>)theEncoderPtr;
  if (aRenderEncoder == nil || myContext.IsNull())
  {
    return;
  }

  id<MTLRenderPipelineState> aPipeline = myContext->DefaultPipeline();
  id<MTLDepthStencilState> aDepthState = myContext->DefaultDepthStencilState();

  if (aPipeline == nil)
  {
    return;
  }

  // Set pipeline state
  [aRenderEncoder setRenderPipelineState:aPipeline];
  if (aDepthState != nil)
  {
    [aRenderEncoder setDepthStencilState:aDepthState];
  }

  // Create a simple colored triangle in normalized device coordinates
  // Triangle vertices in NDC space (-1 to 1)
  float aTriangleVertices[] = {
    // Vertex 1: top center
     0.0f,  0.5f, 0.5f,
    // Vertex 2: bottom left
    -0.5f, -0.5f, 0.5f,
    // Vertex 3: bottom right
     0.5f, -0.5f, 0.5f
  };

  // Uniform data: identity matrices + red color
  struct Uniforms {
    float modelViewMatrix[16];
    float projectionMatrix[16];
    float color[4];
  } aUniforms;

  // Identity matrix for modelView
  memset(aUniforms.modelViewMatrix, 0, sizeof(aUniforms.modelViewMatrix));
  aUniforms.modelViewMatrix[0] = 1.0f;
  aUniforms.modelViewMatrix[5] = 1.0f;
  aUniforms.modelViewMatrix[10] = 1.0f;
  aUniforms.modelViewMatrix[15] = 1.0f;

  // Identity matrix for projection
  memset(aUniforms.projectionMatrix, 0, sizeof(aUniforms.projectionMatrix));
  aUniforms.projectionMatrix[0] = 1.0f;
  aUniforms.projectionMatrix[5] = 1.0f;
  aUniforms.projectionMatrix[10] = 1.0f;
  aUniforms.projectionMatrix[15] = 1.0f;

  // Animated color based on frame counter
  float t = (myFrameCounter % 360) / 360.0f;
  aUniforms.color[0] = 0.5f + 0.5f * sinf(t * 6.28f);          // Red
  aUniforms.color[1] = 0.5f + 0.5f * sinf(t * 6.28f + 2.09f);  // Green
  aUniforms.color[2] = 0.5f + 0.5f * sinf(t * 6.28f + 4.18f);  // Blue
  aUniforms.color[3] = 1.0f;

  // Pass vertex data
  [aRenderEncoder setVertexBytes:aTriangleVertices
                          length:sizeof(aTriangleVertices)
                         atIndex:0];

  // Pass uniform data to vertex shader
  [aRenderEncoder setVertexBytes:&aUniforms
                          length:sizeof(aUniforms)
                         atIndex:1];

  // Pass uniform data to fragment shader
  [aRenderEncoder setFragmentBytes:&aUniforms
                            length:sizeof(aUniforms)
                           atIndex:0];

  // Draw the triangle
  [aRenderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                     vertexStart:0
                     vertexCount:3];
}
