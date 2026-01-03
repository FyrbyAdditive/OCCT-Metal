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

#ifndef Metal_BackgroundRenderer_HeaderFile
#define Metal_BackgroundRenderer_HeaderFile

#include <Aspect_GradientFillMethod.hxx>
#include <Graphic3d_TextureEnv.hxx>
#include <NCollection_Vec4.hxx>

class Metal_Context;
class Metal_Texture;
class Metal_Workspace;

//! Background rendering for Metal views.
//! Supports solid color, gradient, textured, and cubemap backgrounds.
class Metal_BackgroundRenderer
{
public:

  //! Background fill method.
  enum FillMethod
  {
    FillMethod_None,        //!< no background (clear only)
    FillMethod_Solid,       //!< solid color fill
    FillMethod_Gradient,    //!< two-color gradient
    FillMethod_Texture,     //!< 2D texture background
    FillMethod_Cubemap,     //!< environment cubemap
    FillMethod_Skybox       //!< procedural skybox
  };

public:

  //! Default constructor.
  Metal_BackgroundRenderer()
  : myFillMethod(FillMethod_Solid),
    myGradientMethod(Aspect_GradientFillMethod_Horizontal),
    myColor1(0.2f, 0.2f, 0.3f, 1.0f),
    myColor2(0.1f, 0.1f, 0.15f, 1.0f),
    myTextureScale(1.0f, 1.0f),
    myTextureOffset(0.0f, 0.0f),
    myIsDirty(true)
  {}

  //! Destructor.
  ~Metal_BackgroundRenderer() {}

  //! Return fill method.
  FillMethod GetFillMethod() const { return myFillMethod; }

  //! Set fill method.
  void SetFillMethod(FillMethod theMethod)
  {
    myFillMethod = theMethod;
    myIsDirty = true;
  }

  //! Set solid color background.
  void SetColor(float theR, float theG, float theB, float theA = 1.0f)
  {
    myColor1 = NCollection_Vec4<float>(theR, theG, theB, theA);
    myFillMethod = FillMethod_Solid;
    myIsDirty = true;
  }

  //! Set gradient background.
  void SetGradient(const NCollection_Vec4<float>& theColor1,
                   const NCollection_Vec4<float>& theColor2,
                   Aspect_GradientFillMethod theMethod = Aspect_GradientFillMethod_Vertical)
  {
    myColor1 = theColor1;
    myColor2 = theColor2;
    myGradientMethod = theMethod;
    myFillMethod = FillMethod_Gradient;
    myIsDirty = true;
  }

  //! Return first color.
  const NCollection_Vec4<float>& Color1() const { return myColor1; }

  //! Return second color.
  const NCollection_Vec4<float>& Color2() const { return myColor2; }

  //! Return gradient fill method.
  Aspect_GradientFillMethod GradientMethod() const { return myGradientMethod; }

  //! Set background texture.
  void SetTexture(const occ::handle<Metal_Texture>& theTexture)
  {
    myTexture = theTexture;
    myFillMethod = FillMethod_Texture;
    myIsDirty = true;
  }

  //! Return background texture.
  const occ::handle<Metal_Texture>& Texture() const { return myTexture; }

  //! Set cubemap for environment background.
  void SetCubemap(const occ::handle<Metal_Texture>& theCubemap)
  {
    myCubemap = theCubemap;
    myFillMethod = FillMethod_Cubemap;
    myIsDirty = true;
  }

  //! Return cubemap texture.
  const occ::handle<Metal_Texture>& Cubemap() const { return myCubemap; }

  //! Set texture scale.
  void SetTextureScale(float theScaleX, float theScaleY)
  {
    myTextureScale = NCollection_Vec2<float>(theScaleX, theScaleY);
    myIsDirty = true;
  }

  //! Set texture offset.
  void SetTextureOffset(float theOffsetX, float theOffsetY)
  {
    myTextureOffset = NCollection_Vec2<float>(theOffsetX, theOffsetY);
    myIsDirty = true;
  }

  //! Return true if state has changed.
  bool IsDirty() const { return myIsDirty; }

  //! Mark as clean (after rendering).
  void SetClean() { myIsDirty = false; }

  //! Render background.
  //! @param theWorkspace Metal workspace
  //! @param theWidth  viewport width
  //! @param theHeight viewport height
  void Render(Metal_Workspace* theWorkspace, int theWidth, int theHeight);

  //! Release resources.
  void Release(Metal_Context* theCtx);

private:

  FillMethod                   myFillMethod;     //!< fill method
  Aspect_GradientFillMethod    myGradientMethod; //!< gradient method
  NCollection_Vec4<float>      myColor1;         //!< first color
  NCollection_Vec4<float>      myColor2;         //!< second color
  occ::handle<Metal_Texture>   myTexture;        //!< background texture
  occ::handle<Metal_Texture>   myCubemap;        //!< environment cubemap
  NCollection_Vec2<float>      myTextureScale;   //!< texture scale
  NCollection_Vec2<float>      myTextureOffset;  //!< texture offset
  bool                         myIsDirty;        //!< dirty flag
};

#endif // Metal_BackgroundRenderer_HeaderFile
