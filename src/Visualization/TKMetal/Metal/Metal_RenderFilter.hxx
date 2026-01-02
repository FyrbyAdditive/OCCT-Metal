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

#ifndef Metal_RenderFilter_HeaderFile
#define Metal_RenderFilter_HeaderFile

//! Filter for rendering elements.
//! Used to control which elements are rendered during different passes.
enum Metal_RenderFilter
{
  Metal_RenderFilter_Empty = 0x000, //!< disabled filter (render everything)

  //! Render only opaque elements and non-filling elements
  //! (conflicts with Metal_RenderFilter_TransparentOnly)
  Metal_RenderFilter_OpaqueOnly = 0x001,

  //! Render only semitransparent elements
  //! (conflicts with Metal_RenderFilter_OpaqueOnly)
  Metal_RenderFilter_TransparentOnly = 0x002,

  //! Render only elements suitable for ray-tracing
  Metal_RenderFilter_NonRaytraceableOnly = 0x004,

  //! Render only filled elements (not wireframe)
  Metal_RenderFilter_FillModeOnly = 0x008,

  //! Render only normal 3D objects without transformation persistence
  Metal_RenderFilter_SkipTrsfPersistence = 0x010,
};

#endif // Metal_RenderFilter_HeaderFile
