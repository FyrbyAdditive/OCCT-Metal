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

#ifndef Metal_Sampler_HeaderFile
#define Metal_Sampler_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_TextureParams.hxx>

#ifdef __OBJC__
@protocol MTLSamplerState;
#endif

class Metal_Context;

//! Sampler wrapper for Metal MTLSamplerState.
//! Encapsulates texture filtering and addressing modes.
class Metal_Sampler : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_Sampler, Metal_Resource)

public:

  //! Create uninitialized sampler.
  Standard_EXPORT Metal_Sampler();

  //! Destructor.
  Standard_EXPORT ~Metal_Sampler() override;

  //! @return true if current object was initialized
  bool IsValid() const { return mySampler != nullptr; }

  //! Return estimated GPU memory usage (negligible for samplers).
  size_t EstimatedDataSize() const override { return 0; }

  //! Create sampler from Graphic3d texture parameters.
  //! @param theCtx Metal context
  //! @param theParams texture parameters
  //! @return true on success
  Standard_EXPORT bool Create(Metal_Context* theCtx,
                              const occ::handle<Graphic3d_TextureParams>& theParams);

  //! Create sampler with explicit settings.
  //! @param theCtx Metal context
  //! @param theMinFilter minification filter (nearest/linear)
  //! @param theMagFilter magnification filter (nearest/linear)
  //! @param theMipFilter mip filter (none/nearest/linear)
  //! @param theRepeatU whether to repeat (true) or clamp (false) in U
  //! @param theRepeatV whether to repeat (true) or clamp (false) in V
  //! @param theAnisotropy max anisotropy level (1-16)
  //! @return true on success
  Standard_EXPORT bool Create(Metal_Context* theCtx,
                              Graphic3d_TypeOfTextureFilter theMinFilter,
                              Graphic3d_TypeOfTextureFilter theMagFilter,
                              Graphic3d_TypeOfTextureFilter theMipFilter,
                              bool theRepeatU,
                              bool theRepeatV,
                              int theAnisotropy = 1);

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal sampler state object.
  id<MTLSamplerState> Sampler() const { return mySampler; }
#endif

protected:

#ifdef __OBJC__
  id<MTLSamplerState> mySampler; //!< Metal sampler state object
#else
  void*               mySampler; //!< Metal sampler state object (opaque)
#endif
};

#endif // Metal_Sampler_HeaderFile
