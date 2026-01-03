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

#ifndef Metal_FrameBuffer_HeaderFile
#define Metal_FrameBuffer_HeaderFile

#include <Metal_Resource.hxx>
#include <Metal_Texture.hxx>
#include <Graphic3d_BufferType.hxx>
#include <NCollection_Vec2.hxx>
#include <NCollection_Vector.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
@class MTLRenderPassDescriptor;
#endif

class Metal_Context;
class Image_PixMap;

//! Pixel format for Metal framebuffer attachments.
enum Metal_PixelFormat
{
  Metal_PixelFormat_Unknown = 0,
  Metal_PixelFormat_RGBA8   = 1,   //!< MTLPixelFormatRGBA8Unorm
  Metal_PixelFormat_BGRA8   = 2,   //!< MTLPixelFormatBGRA8Unorm
  Metal_PixelFormat_RGBA16F = 3,   //!< MTLPixelFormatRGBA16Float
  Metal_PixelFormat_RGBA32F = 4,   //!< MTLPixelFormatRGBA32Float
  Metal_PixelFormat_Depth32F = 10, //!< MTLPixelFormatDepth32Float
  Metal_PixelFormat_Depth24Stencil8 = 11 //!< MTLPixelFormatDepth24Unorm_Stencil8
};

//! Framebuffer Object for off-screen rendering with Metal.
//! Wraps MTLTexture for color and depth attachments.
class Metal_FrameBuffer : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_FrameBuffer, Metal_Resource)

public:

  //! Empty constructor.
  Standard_EXPORT Metal_FrameBuffer(const TCollection_AsciiString& theResourceId = TCollection_AsciiString());

  //! Destructor.
  Standard_EXPORT ~Metal_FrameBuffer() override;

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return true if framebuffer is valid.
  bool IsValid() const { return myIsValid; }

  //! Return number of MSAA samples.
  int NbSamples() const { return myNbSamples; }

  //! Return number of color attachments.
  int NbColorBuffers() const { return myColorTextures.Length(); }

  //! Return true if framebuffer has color attachment.
  bool HasColor() const { return !myColorFormats.IsEmpty(); }

  //! Return true if framebuffer has depth attachment.
  bool HasDepth() const { return myDepthFormat != Metal_PixelFormat_Unknown; }

  //! Return texture size.
  NCollection_Vec2<int> GetSize() const { return NCollection_Vec2<int>(mySizeX, mySizeY); }

  //! Return texture width.
  int GetSizeX() const { return mySizeX; }

  //! Return texture height.
  int GetSizeY() const { return mySizeY; }

  //! Return viewport size.
  NCollection_Vec2<int> GetVPSize() const { return NCollection_Vec2<int>(myVPSizeX, myVPSizeY); }

  //! Return viewport width.
  int GetVPSizeX() const { return myVPSizeX; }

  //! Return viewport height.
  int GetVPSizeY() const { return myVPSizeY; }

  //! Initialize framebuffer with specified dimensions.
  //! @param theCtx        Metal context
  //! @param theSize       texture width x height
  //! @param theColorFormat color texture format
  //! @param theDepthFormat depth texture format
  //! @param theNbSamples  MSAA number of samples (0 or 1 = no MSAA)
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            const NCollection_Vec2<int>& theSize,
                            Metal_PixelFormat theColorFormat,
                            Metal_PixelFormat theDepthFormat,
                            int theNbSamples = 0);

  //! Initialize framebuffer with multiple color attachments.
  //! @param theCtx        Metal context
  //! @param theSize       texture width x height
  //! @param theColorFormats list of color texture formats
  //! @param theDepthFormat depth texture format
  //! @param theNbSamples  MSAA number of samples (0 or 1 = no MSAA)
  //! @return true on success
  Standard_EXPORT bool Init(Metal_Context* theCtx,
                            const NCollection_Vec2<int>& theSize,
                            const NCollection_Vector<Metal_PixelFormat>& theColorFormats,
                            Metal_PixelFormat theDepthFormat,
                            int theNbSamples = 0);

  //! (Re-)initialize framebuffer lazily (only if size changed).
  Standard_EXPORT bool InitLazy(Metal_Context* theCtx,
                                const NCollection_Vec2<int>& theViewportSize,
                                Metal_PixelFormat theColorFormat,
                                Metal_PixelFormat theDepthFormat,
                                int theNbSamples = 0);

  //! Setup viewport.
  Standard_EXPORT void SetupViewport(Metal_Context* theCtx);

  //! Change viewport size.
  void ChangeViewport(int theVPSizeX, int theVPSizeY)
  {
    myVPSizeX = theVPSizeX;
    myVPSizeY = theVPSizeY;
  }

  //! Bind this framebuffer for rendering.
  Standard_EXPORT void BindBuffer(const occ::handle<Metal_Context>& theCtx);

  //! Unbind this framebuffer.
  Standard_EXPORT void UnbindBuffer(const occ::handle<Metal_Context>& theCtx);

  //! Return color texture at index.
  const occ::handle<Metal_Texture>& ColorTexture(int theIndex = 0) const
  {
    return myColorTextures.Value(theIndex);
  }

  //! Return depth texture.
  const occ::handle<Metal_Texture>& DepthStencilTexture() const { return myDepthStencilTexture; }

  //! Return MSAA color texture (for resolve).
  const occ::handle<Metal_Texture>& ColorTextureMSAA(int theIndex = 0) const
  {
    return myColorTexturesMSAA.Value(theIndex);
  }

  //! Return MSAA depth texture (for resolve).
  const occ::handle<Metal_Texture>& DepthStencilTextureMSAA() const { return myDepthStencilTextureMSAA; }

  //! Return estimated GPU memory usage.
  Standard_EXPORT size_t EstimatedDataSize() const override;

#ifdef __OBJC__
  //! Return Metal render pass descriptor configured for this framebuffer.
  //! @param theToClear   whether to clear attachments
  //! @param theClearColor clear color (RGBA)
  //! @param theClearDepth clear depth value
  Standard_EXPORT MTLRenderPassDescriptor* RenderPassDescriptor(bool theToClear = true,
                                                                  const float* theClearColor = nullptr,
                                                                  float theClearDepth = 1.0f);

  //! Return raw Metal texture for color attachment.
  id<MTLTexture> MetalColorTexture(int theIndex = 0) const;

  //! Return raw Metal texture for depth attachment.
  id<MTLTexture> MetalDepthTexture() const;

  //! Read color buffer pixels into CPU memory (synchronous).
  //! @param theCtx     Metal context
  //! @param theData    destination buffer (must be large enough)
  //! @param theIndex   color attachment index
  //! @return true on success
  Standard_EXPORT bool ReadColorPixels(Metal_Context* theCtx,
                                        Standard_Byte* theData,
                                        int theIndex = 0) const;

  //! Read depth buffer pixels into CPU memory (synchronous).
  //! @param theCtx  Metal context
  //! @param theData destination buffer for float depth values
  //! @return true on success
  Standard_EXPORT bool ReadDepthPixels(Metal_Context* theCtx,
                                        float* theData) const;

  //! Async texture readback handle for tracking pending operations.
  struct AsyncReadbackHandle
  {
    id<MTLCommandBuffer> CommandBuffer; //!< command buffer for completion tracking
    id<MTLBuffer>        ReadbackBuffer; //!< shared buffer containing pixel data
    size_t               DataSize;       //!< size of data in bytes
    int                  Width;          //!< texture width
    int                  Height;         //!< texture height
    int                  BytesPerPixel;  //!< bytes per pixel
    bool                 IsDepth;        //!< whether this is a depth readback
    bool                 IsComplete;     //!< whether readback has completed

    AsyncReadbackHandle() : CommandBuffer(nil), ReadbackBuffer(nil), DataSize(0),
                            Width(0), Height(0), BytesPerPixel(0), IsDepth(false), IsComplete(false) {}
  };

  //! Begin asynchronous color buffer readback.
  //! Returns a handle that can be polled for completion.
  //! @param theCtx     Metal context
  //! @param theIndex   color attachment index
  //! @return readback handle (check IsComplete or use WaitForReadback)
  Standard_EXPORT AsyncReadbackHandle BeginAsyncColorReadback(Metal_Context* theCtx,
                                                               int theIndex = 0);

  //! Begin asynchronous depth buffer readback.
  //! @param theCtx  Metal context
  //! @return readback handle
  Standard_EXPORT AsyncReadbackHandle BeginAsyncDepthReadback(Metal_Context* theCtx);

  //! Check if async readback is complete (non-blocking).
  //! @param theHandle readback handle from BeginAsync* method
  //! @return true if readback data is ready
  Standard_EXPORT static bool IsReadbackComplete(AsyncReadbackHandle& theHandle);

  //! Wait for async readback to complete and copy data.
  //! @param theHandle readback handle
  //! @param theData   destination buffer
  //! @param theTimeoutMs maximum wait time in milliseconds (0 = infinite)
  //! @return true on success
  Standard_EXPORT static bool WaitForReadback(AsyncReadbackHandle& theHandle,
                                               void* theData,
                                               unsigned int theTimeoutMs = 0);

  //! Copy readback data after completion (non-blocking, returns false if not ready).
  //! @param theHandle readback handle
  //! @param theData   destination buffer
  //! @return true if data was copied
  Standard_EXPORT static bool TryCopyReadbackData(AsyncReadbackHandle& theHandle,
                                                   void* theData);
#endif

protected:

  //! Create texture for attachment.
  Standard_EXPORT bool createTexture(Metal_Context* theCtx,
                                      occ::handle<Metal_Texture>& theTexture,
                                      int theWidth, int theHeight,
                                      Metal_PixelFormat theFormat,
                                      int theNbSamples,
                                      bool theIsRenderTarget);

protected:

  TCollection_AsciiString myResourceId;       //!< resource identifier
  int mySizeX;                                //!< texture width
  int mySizeY;                                //!< texture height
  int myVPSizeX;                              //!< viewport width
  int myVPSizeY;                              //!< viewport height
  int myNbSamples;                            //!< MSAA samples
  bool myIsValid;                             //!< validity flag

  NCollection_Vector<Metal_PixelFormat> myColorFormats;  //!< color attachment formats
  Metal_PixelFormat myDepthFormat;                       //!< depth attachment format

  NCollection_Vector<occ::handle<Metal_Texture>> myColorTextures;     //!< color textures (resolve target for MSAA)
  occ::handle<Metal_Texture> myDepthStencilTexture;                   //!< depth texture (resolve target for MSAA)

  NCollection_Vector<occ::handle<Metal_Texture>> myColorTexturesMSAA; //!< MSAA color textures
  occ::handle<Metal_Texture> myDepthStencilTextureMSAA;               //!< MSAA depth texture
};

#endif // Metal_FrameBuffer_HeaderFile
