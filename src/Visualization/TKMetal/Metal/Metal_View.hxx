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

#ifndef Metal_View_HeaderFile
#define Metal_View_HeaderFile

#include <Graphic3d_CStructure.hxx>
#include <Graphic3d_CullingTool.hxx>
#include <Graphic3d_CView.hxx>
#include <Graphic3d_DisplayPriority.hxx>
#include <Graphic3d_GraduatedTrihedron.hxx>
#include <Graphic3d_Layer.hxx>
#include <Graphic3d_LightSet.hxx>
#include <Graphic3d_SequenceOfHClipPlane.hxx>
#include <Metal_Caps.hxx>
#include <Metal_Context.hxx>
#include <Metal_FrameBuffer.hxx>
#include <Metal_GraduatedTrihedron.hxx>
#include <Metal_ShadowMap.hxx>
#include <Metal_Texture.hxx>
#include <Metal_Window.hxx>

class Metal_PBREnvironment;
#include <NCollection_DataMap.hxx>
#include <NCollection_List.hxx>
#include <Quantity_Color.hxx>

#ifdef __OBJC__
@protocol MTLTexture;
#endif

class Metal_GraphicDriver;
class Metal_Workspace;

//! Implementation of Metal view.
class Metal_View : public Graphic3d_CView
{
  DEFINE_STANDARD_RTTIEXT(Metal_View, Graphic3d_CView)

public:

  //! Constructor.
  Standard_EXPORT Metal_View(const occ::handle<Graphic3d_StructureManager>& theMgr,
                             const Metal_GraphicDriver* theDriver,
                             const occ::handle<Metal_Caps>& theCaps,
                             const occ::handle<Metal_Context>& theContext);

  //! Destructor.
  Standard_EXPORT ~Metal_View() override;

  //! Release Metal resources.
  Standard_EXPORT virtual void ReleaseGlResources(Metal_Context* theCtx);

  //! Deletes and erases the view.
  Standard_EXPORT void Remove() override;

  //! @param theDrawToFrontBuffer Advanced option to modify rendering mode.
  //! @return previous mode.
  Standard_EXPORT bool SetImmediateModeDrawToFront(const bool theDrawToFrontBuffer) override;

  //! Creates and maps rendering window to the view.
  Standard_EXPORT void SetWindow(const occ::handle<Graphic3d_CView>& theParentVIew,
                                 const occ::handle<Aspect_Window>& theWindow,
                                 const Aspect_RenderingContext theContext) override;

  //! Returns window associated with the view.
  Standard_EXPORT occ::handle<Aspect_Window> Window() const override;

  //! Return Metal window.
  const occ::handle<Metal_Window>& MetalWindow() const { return myWindow; }

  //! Returns True if the window associated to the view is defined.
  bool IsDefined() const override { return !myWindow.IsNull(); }

  //! Handle changing size of the rendering window.
  Standard_EXPORT void Resized() override;

  //! Redraw content of the view.
  Standard_EXPORT void Redraw() override;

  //! Redraw immediate content of the view.
  Standard_EXPORT void RedrawImmediate() override;

  //! Marks BVH tree for given priority list as dirty and marks primitive set for rebuild.
  Standard_EXPORT void Invalidate() override;

  //! Return true if view content cache has been invalidated.
  bool IsInvalidated() override { return myBackBufferRestored == false; }

  //! Dump active rendering buffer into specified memory buffer.
  Standard_EXPORT bool BufferDump(Image_PixMap& theImage,
                                  const Graphic3d_BufferType& theBufferType) override;

  //! Dumps the graphical contents of a shadowmap framebuffer into an image.
  Standard_EXPORT bool ShadowMapDump(Image_PixMap& theImage,
                                     const TCollection_AsciiString& theLightName) override;

  //! Marks BVH tree and the set of BVH primitives as outdated.
  Standard_EXPORT void InvalidateBVHData(const Graphic3d_ZLayerId theLayerId) override;

  //! Add a layer to the view.
  Standard_EXPORT void InsertLayerBefore(const Graphic3d_ZLayerId theNewLayerId,
                                         const Graphic3d_ZLayerSettings& theSettings,
                                         const Graphic3d_ZLayerId theLayerAfter) override;

  //! Add a layer to the view.
  Standard_EXPORT void InsertLayerAfter(const Graphic3d_ZLayerId theNewLayerId,
                                        const Graphic3d_ZLayerSettings& theSettings,
                                        const Graphic3d_ZLayerId theLayerBefore) override;

  //! Remove a z layer with the given ID.
  Standard_EXPORT void RemoveZLayer(const Graphic3d_ZLayerId theLayerId) override;

  //! Sets the settings for a single Z layer.
  Standard_EXPORT void SetZLayerSettings(const Graphic3d_ZLayerId theLayerId,
                                         const Graphic3d_ZLayerSettings& theSettings) override;

  //! Returns the maximum Z layer ID.
  Standard_EXPORT int ZLayerMax() const override;

  //! Returns the list of layers.
  Standard_EXPORT const NCollection_List<occ::handle<Graphic3d_Layer>>& Layers() const override;

  //! Returns layer with given ID or NULL if undefined.
  Standard_EXPORT occ::handle<Graphic3d_Layer> Layer(const Graphic3d_ZLayerId theLayerId) const override;

  //! Returns the coordinates of the boundary box of all
  //! structures displayed in the view.
  //! If theToIncludeAuxiliary is TRUE, then the boundary box
  //! also includes minimum and maximum limits of graphical elements
  //! forming parts of infinite structures.
  Standard_EXPORT Bnd_Box MinMaxValues(const bool theToIncludeAuxiliary = false) const override;

  //! Returns pointer to an assigned framebuffer object.
  Standard_EXPORT occ::handle<Standard_Transient> FBO() const override;

  //! Sets framebuffer object for offscreen rendering.
  Standard_EXPORT void SetFBO(const occ::handle<Standard_Transient>& theFbo) override;

  //! Generate offscreen FBO in the graphic library.
  Standard_EXPORT occ::handle<Standard_Transient> FBOCreate(const int theWidth, const int theHeight) override;

  //! Remove offscreen FBO from the graphic library.
  Standard_EXPORT void FBORelease(occ::handle<Standard_Transient>& theFbo) override;

  //! Read offscreen FBO configuration.
  Standard_EXPORT void FBOGetDimensions(const occ::handle<Standard_Transient>& theFbo,
                                        int& theWidth,
                                        int& theHeight,
                                        int& theWidthMax,
                                        int& theHeightMax) override;

  //! Change offscreen FBO viewport.
  Standard_EXPORT void FBOChangeViewport(const occ::handle<Standard_Transient>& theFbo,
                                         const int theWidth,
                                         const int theHeight) override;

public: //! @name Graduated Trihedron

  //! Displays Graduated Trihedron.
  Standard_EXPORT void GraduatedTrihedronDisplay(const Graphic3d_GraduatedTrihedron& theTrihedronData) override;

  //! Erases Graduated Trihedron.
  Standard_EXPORT void GraduatedTrihedronErase() override;

  //! Sets minimum and maximum points of scene bounding box for Graduated Trihedron.
  Standard_EXPORT void GraduatedTrihedronMinMaxValues(const NCollection_Vec3<float> theMin,
                                                      const NCollection_Vec3<float> theMax) override;

public: //! @name Background

  //! Returns gradient background fill colors.
  Standard_EXPORT Aspect_GradientBackground GradientBackground() const override;

  //! Sets gradient background fill colors.
  Standard_EXPORT void SetGradientBackground(const Aspect_GradientBackground& theBackground) override;

  //! Sets image texture or environment cubemap as background.
  Standard_EXPORT void SetBackgroundImage(const occ::handle<Graphic3d_TextureMap>& theTextureMap,
                                          bool theToUpdatePBREnv = true) override;

  //! Returns background image fill style.
  Standard_EXPORT Aspect_FillMethod BackgroundImageStyle() const override;

  //! Sets background image fill style.
  Standard_EXPORT void SetBackgroundImageStyle(const Aspect_FillMethod theFillStyle) override;

  //! Enables or disables IBL.
  Standard_EXPORT void SetImageBasedLighting(bool theToEnableIBL) override;

  //! Sets environment texture for the view.
  Standard_EXPORT void SetTextureEnv(const occ::handle<Graphic3d_TextureEnv>& theTextureEnv) override;

public: //! @name Lights and Clipping

  //! Returns list of lights of the view.
  const occ::handle<Graphic3d_LightSet>& Lights() const override { return myLights; }

  //! Sets list of lights for the view.
  Standard_EXPORT void SetLights(const occ::handle<Graphic3d_LightSet>& theLights) override;

  //! Returns list of clip planes set for the view.
  const occ::handle<Graphic3d_SequenceOfHClipPlane>& ClipPlanes() const override { return myClipPlanes; }

  //! Sets list of clip planes for the view.
  Standard_EXPORT void SetClipPlanes(const occ::handle<Graphic3d_SequenceOfHClipPlane>& thePlanes) override;

public: //! @name View Frustum Culling

  //! Returns selector for BVH tree, providing a possibility to store information
  //! about current view volume and to detect which objects are overlapping it.
  const Graphic3d_CullingTool& BVHTreeSelector() const { return myBVHSelector; }

public: //! @name Diagnostics

  //! Fill in the dictionary with diagnostic info.
  Standard_EXPORT void DiagnosticInformation(
    NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict,
    Graphic3d_DiagnosticInfo theFlags) const override;

  //! Returns string with statistic performance info.
  Standard_EXPORT TCollection_AsciiString StatisticInformation() const override;

  //! Fills in the dictionary with statistic performance info.
  Standard_EXPORT void StatisticInformation(
    NCollection_IndexedDataMap<TCollection_AsciiString, TCollection_AsciiString>& theDict) const override;

private: //! @name Structure management (required by Graphic3d_CView)

  //! Adds the structure to display lists of the view.
  void displayStructure(const occ::handle<Graphic3d_CStructure>& theStructure,
                        const Graphic3d_DisplayPriority thePriority) override;

  //! Erases the structure from display lists of the view.
  void eraseStructure(const occ::handle<Graphic3d_CStructure>& theStructure) override;

  //! Change Z layer of a structure already presented in view.
  void changeZLayer(const occ::handle<Graphic3d_CStructure>& theCStructure,
                    const Graphic3d_ZLayerId theNewLayerId) override;

  //! Changes the priority of a structure within its Z layer.
  void changePriority(const occ::handle<Graphic3d_CStructure>& theCStructure,
                      const Graphic3d_DisplayPriority theNewPriority) override;

private: //! @name Internal rendering helpers

  //! Render all displayed structures.
  void renderStructures(Metal_Workspace* theWorkspace);

  //! Initialize or resize the depth buffer.
  void initDepthBuffer(int theWidth, int theHeight);

  //! Draw gradient background.
  void drawGradientBackground(void* theEncoder, int theWidth, int theHeight);

  //! Draw textured background.
  void drawTexturedBackground(void* theEncoder, int theWidth, int theHeight);

protected:

  const Metal_GraphicDriver*        myDriver;          //!< Graphic driver
  occ::handle<Metal_Caps>           myCaps;            //!< Driver capabilities
  occ::handle<Metal_Context>        myContext;         //!< Metal context
  occ::handle<Metal_Window>         myWindow;          //!< Metal window
  occ::handle<Aspect_Window>        myPlatformWindow;  //!< Platform window

  occ::handle<Graphic3d_LightSet>   myLights;          //!< Lights
  occ::handle<Graphic3d_SequenceOfHClipPlane> myClipPlanes; //!< Clip planes

  // Framebuffer support
  occ::handle<Metal_FrameBuffer>    myFBO;             //!< Current FBO for offscreen rendering
  occ::handle<Metal_FrameBuffer>    myMainFBO;         //!< Main scene FBO (for MSAA)

  // Gradient background
  Quantity_Color                    myBgGradientFrom;   //!< Gradient start color
  Quantity_Color                    myBgGradientTo;     //!< Gradient end color
  Aspect_GradientFillMethod         myBgGradientMethod; //!< Gradient fill method

  Aspect_FillMethod                 myBgImageStyle;    //!< Background image style
  occ::handle<Metal_Texture>        myBgTexture;       //!< Background texture
  occ::handle<Metal_Texture>        myEnvCubemap;      //!< Environment cubemap texture

  // IBL (Image-Based Lighting)
  occ::handle<Metal_PBREnvironment> myPBREnvironment;  //!< PBR environment for IBL
  bool                              myIBLEnabled;      //!< IBL enabled flag

  // Shadow mapping
  NCollection_Sequence<occ::handle<Metal_ShadowMap>> myShadowMaps; //!< Shadow maps for lights

  // Layer management
  NCollection_List<occ::handle<Graphic3d_Layer>> myLayers; //!< Z-layers (ordered list)
  NCollection_DataMap<Graphic3d_ZLayerId, occ::handle<Graphic3d_Layer>> myLayerMap; //!< Layer lookup map
  int                               myZLayerMax;        //!< Maximum Z-layer ID

  // Frame state
  bool                              myBackBufferRestored; //!< Back buffer restored flag
  bool                              myToDrawImmediate;    //!< Draw immediate structures flag
  int                               myFrameCounter;       //!< Frame counter

  // Depth buffer
#ifdef __OBJC__
  id<MTLTexture>                    myDepthTexture;       //!< Depth texture for rendering
#else
  void*                             myDepthTexture;       //!< Depth texture (opaque)
#endif
  int                               myDepthWidth;         //!< Depth texture width
  int                               myDepthHeight;        //!< Depth texture height

  // View frustum culling
  Graphic3d_CullingTool             myBVHSelector;        //!< Selector for BVH tree frustum culling

  // Graduated trihedron
  Metal_GraduatedTrihedron          myGraduatedTrihedron; //!< Graduated trihedron renderer
  bool                              myToShowGradTrihedron; //!< Flag to show graduated trihedron
  NCollection_Vec3<float>           myGradTrihedronMin;   //!< Graduated trihedron min bounds
  NCollection_Vec3<float>           myGradTrihedronMax;   //!< Graduated trihedron max bounds
};

#endif // Metal_View_HeaderFile
