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

#ifndef Metal_Window_HeaderFile
#define Metal_Window_HeaderFile

#include <Aspect_Window.hxx>
#include <Metal_Context.hxx>
#include <NCollection_Vec2.hxx>
#include <Standard_Transient.hxx>

#ifdef __OBJC__
@class CAMetalLayer;
@protocol CAMetalDrawable;
@class NSView;
#endif

//! This class represents low-level wrapper over window with Metal layer.
//! The window itself should be provided to constructor.
class Metal_Window : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Window, Standard_Transient)

public:

  //! Constructor.
  //! @param theContext shared Metal context
  //! @param thePlatformWindow platform window (Cocoa_Window)
  //! @param theSizeWindow window object defining dimensions
  Standard_EXPORT Metal_Window(const occ::handle<Metal_Context>& theContext,
                               const occ::handle<Aspect_Window>& thePlatformWindow,
                               const occ::handle<Aspect_Window>& theSizeWindow);

  //! Destructor.
  Standard_EXPORT ~Metal_Window() override;

  //! Initialize the Metal layer for this window.
  Standard_EXPORT bool Init();

  //! Resize the window.
  Standard_EXPORT virtual void Resize();

  //! Return platform window.
  const occ::handle<Aspect_Window>& PlatformWindow() const { return myPlatformWindow; }

  //! Return window object defining dimensions.
  const occ::handle<Aspect_Window>& SizeWindow() const { return mySizeWindow; }

  //! Return window width in pixels.
  int Width() const { return mySize.x(); }

  //! Return window height in pixels.
  int Height() const { return mySize.y(); }

  //! Return window size in pixels.
  const NCollection_Vec2<int>& Size() const { return mySize; }

  //! Return window size in logical points (for Retina displays).
  const NCollection_Vec2<int>& SizePoints() const { return mySizePt; }

  //! Return Metal context.
  const occ::handle<Metal_Context>& GetContext() const { return myContext; }

  //! Return pixel format (MTLPixelFormat) for color attachment.
  int ColorPixelFormat() const { return myColorFormat; }

  //! Return pixel format (MTLPixelFormat) for depth attachment.
  int DepthPixelFormat() const { return myDepthFormat; }

  //! Return drawable scale factor (Retina).
  float ScaleFactor() const { return myScaleFactor; }

public: //! @name Frame management

#ifdef __OBJC__
  //! Return the Metal layer.
  CAMetalLayer* MetalLayer() const { return myMetalLayer; }

  //! Get next drawable for rendering.
  //! Returns nil if no drawable is available.
  Standard_EXPORT id<CAMetalDrawable> NextDrawable();

  //! Present the drawable.
  Standard_EXPORT void Present(id<CAMetalDrawable> theDrawable);
#endif

  //! Set VSync interval.
  Standard_EXPORT void SetSwapInterval(int theInterval);

protected:

  occ::handle<Metal_Context> myContext;        //!< Metal context
  occ::handle<Aspect_Window> myPlatformWindow; //!< Platform window wrapper
  occ::handle<Aspect_Window> mySizeWindow;     //!< Window object defining dimensions

#ifdef __OBJC__
  CAMetalLayer*     myMetalLayer;       //!< Metal rendering layer
  NSView*           myNSView;           //!< Cocoa view
#else
  void*             myMetalLayer;
  void*             myNSView;
#endif

  NCollection_Vec2<int> mySize;         //!< Window size in pixels
  NCollection_Vec2<int> mySizePt;       //!< Window size in logical points
  float                 myScaleFactor;  //!< Scale factor for Retina displays
  int                   myColorFormat;  //!< Color pixel format (MTLPixelFormat)
  int                   myDepthFormat;  //!< Depth pixel format (MTLPixelFormat)
  int                   mySwapInterval; //!< VSync interval
  bool                  myIsInitialized; //!< Initialization flag
};

#endif // Metal_Window_HeaderFile
