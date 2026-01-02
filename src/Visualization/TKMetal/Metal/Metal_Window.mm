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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  #import <UIKit/UIKit.h>
#else
  #import <Cocoa/Cocoa.h>
#endif

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Now include OCCT headers
#include <Metal_Window.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Window, Standard_Transient)

// =======================================================================
// function : Metal_Window
// purpose  : Constructor
// =======================================================================
Metal_Window::Metal_Window(const occ::handle<Metal_Context>& theContext,
                           const occ::handle<Aspect_Window>& thePlatformWindow,
                           const occ::handle<Aspect_Window>& theSizeWindow)
: myContext(theContext),
  myPlatformWindow(thePlatformWindow),
  mySizeWindow(theSizeWindow),
  myMetalLayer(nil),
  myNSView(nil),
  mySize(0, 0),
  mySizePt(0, 0),
  myScaleFactor(1.0f),
  myColorFormat(80), // MTLPixelFormatBGRA8Unorm = 80
  myDepthFormat(252), // MTLPixelFormatDepth32Float = 252
  mySwapInterval(1),
  myIsInitialized(false)
{
  //
}

// =======================================================================
// function : ~Metal_Window
// purpose  : Destructor
// =======================================================================
Metal_Window::~Metal_Window()
{
  if (myMetalLayer != nil)
  {
    // Remove the Metal layer from the view
    if (myNSView != nil)
    {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
      // On iOS, the layer is the view's layer - don't remove it
#else
      [myMetalLayer removeFromSuperlayer];
#endif
    }
    myMetalLayer = nil;
  }
  myNSView = nil;
}

// =======================================================================
// function : Init
// purpose  : Initialize the Metal layer for this window
// =======================================================================
bool Metal_Window::Init()
{
  if (myIsInitialized)
  {
    return true;
  }

  if (myContext.IsNull() || !myContext->IsValid())
  {
    return false;
  }

  if (myPlatformWindow.IsNull())
  {
    return false;
  }

  // Get the native view from the platform window
  void* aNativeHandle = (void*)myPlatformWindow->NativeHandle();
  if (aNativeHandle == nullptr)
  {
    return false;
  }

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  UIView* aView = (__bridge UIView*)aNativeHandle;
  myNSView = nil; // Not used on iOS

  // On iOS, we need to make the view's layer a CAMetalLayer
  // This requires the view class to return CAMetalLayer from layerClass
  // For now, check if layer is already a CAMetalLayer
  if ([aView.layer isKindOfClass:[CAMetalLayer class]])
  {
    myMetalLayer = (CAMetalLayer*)aView.layer;
  }
  else
  {
    // Create and add a CAMetalLayer as a sublayer
    myMetalLayer = [CAMetalLayer layer];
    myMetalLayer.frame = aView.bounds;
    [aView.layer addSublayer:myMetalLayer];
  }
#else
  NSView* aView = (__bridge NSView*)aNativeHandle;
  myNSView = aView;

  // Check if the view already has a CAMetalLayer
  CAMetalLayer* anExistingLayer = nil;
  if ([aView.layer isKindOfClass:[CAMetalLayer class]])
  {
    anExistingLayer = (CAMetalLayer*)aView.layer;
  }
  else
  {
    for (CALayer* aSubLayer in aView.layer.sublayers)
    {
      if ([aSubLayer isKindOfClass:[CAMetalLayer class]])
      {
        anExistingLayer = (CAMetalLayer*)aSubLayer;
        break;
      }
    }
  }

  if (anExistingLayer != nil)
  {
    myMetalLayer = anExistingLayer;
  }
  else
  {
    // Make sure the view is layer-backed
    [aView setWantsLayer:YES];

    // Create the Metal layer
    myMetalLayer = [CAMetalLayer layer];

    // Configure the layer
    myMetalLayer.contentsScale = [aView.window backingScaleFactor];
    myMetalLayer.frame = aView.bounds;

    // Add as sublayer (not replacing the backing layer)
    [aView.layer addSublayer:myMetalLayer];
  }
#endif

  // Configure the Metal layer
  myMetalLayer.device = myContext->Device();
  myMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  myColorFormat = (int)MTLPixelFormatBGRA8Unorm;

  // Enable sRGB if supported and not disabled
  // MTLPixelFormatBGRA8Unorm_sRGB = 81
  // For now, use linear color space for simplicity
  // myMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

  // Configure framebuffer-only for better performance (can't read back)
  myMetalLayer.framebufferOnly = YES;

  // Configure display sync (VSync)
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  // iOS always syncs to display
#else
  if (@available(macOS 10.13, *))
  {
    myMetalLayer.displaySyncEnabled = (mySwapInterval != 0);
  }
#endif

  // Update size
  Resize();

  myIsInitialized = true;
  return true;
}

// =======================================================================
// function : Resize
// purpose  : Resize the window
// =======================================================================
void Metal_Window::Resize()
{
  if (myMetalLayer == nil)
  {
    return;
  }

  // Get size from the size window (which may differ from platform window)
  int aWidth = 0, aHeight = 0;
  if (!mySizeWindow.IsNull())
  {
    mySizeWindow->Size(aWidth, aHeight);
  }
  else if (!myPlatformWindow.IsNull())
  {
    myPlatformWindow->Size(aWidth, aHeight);
  }

  if (aWidth <= 0 || aHeight <= 0)
  {
    return;
  }

  mySizePt.x() = aWidth;
  mySizePt.y() = aHeight;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  UIView* aView = nil;
  if (!myPlatformWindow.IsNull())
  {
    aView = (__bridge UIView*)(void*)myPlatformWindow->NativeHandle();
  }
  myScaleFactor = (aView != nil) ? [aView contentScaleFactor] : 1.0f;
#else
  if (myNSView != nil)
  {
    NSWindow* aWindow = [myNSView window];
    myScaleFactor = (aWindow != nil) ? [aWindow backingScaleFactor] : 1.0f;

    // Update layer frame to match view bounds
    myMetalLayer.frame = myNSView.bounds;
    myMetalLayer.contentsScale = myScaleFactor;
  }
  else
  {
    myScaleFactor = 1.0f;
  }
#endif

  // Calculate pixel size (accounting for Retina)
  mySize.x() = int(float(mySizePt.x()) * myScaleFactor);
  mySize.y() = int(float(mySizePt.y()) * myScaleFactor);

  // Update drawable size
  myMetalLayer.drawableSize = CGSizeMake(mySize.x(), mySize.y());
}

// =======================================================================
// function : NextDrawable
// purpose  : Get next drawable for rendering
// =======================================================================
id<CAMetalDrawable> Metal_Window::NextDrawable()
{
  if (myMetalLayer == nil)
  {
    return nil;
  }

  // Get next drawable from the layer
  // This may block if all drawables are in use
  id<CAMetalDrawable> aDrawable = [myMetalLayer nextDrawable];
  return aDrawable;
}

// =======================================================================
// function : Present
// purpose  : Present the drawable
// =======================================================================
void Metal_Window::Present(id<CAMetalDrawable> theDrawable)
{
  if (theDrawable == nil)
  {
    return;
  }

  // Present is typically done through the command buffer:
  // [commandBuffer presentDrawable:theDrawable];
  // But we can also present directly:
  [theDrawable present];
}

// =======================================================================
// function : SetSwapInterval
// purpose  : Set VSync interval
// =======================================================================
void Metal_Window::SetSwapInterval(int theInterval)
{
  mySwapInterval = theInterval;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
  // iOS always syncs to display
#else
  if (myMetalLayer != nil)
  {
    if (@available(macOS 10.13, *))
    {
      myMetalLayer.displaySyncEnabled = (theInterval != 0);
    }
  }
#endif
}
