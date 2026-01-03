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

#ifndef Metal_LayerFilter_HeaderFile
#define Metal_LayerFilter_HeaderFile

//! Tool object to specify processed Metal layers
//! for intermixed rendering of raytracable and non-raytracable layers.
enum Metal_LayerFilter
{
  Metal_LF_All,        //!< process all layers
  Metal_LF_Upper,      //!< process only top non-raytracable layers
  Metal_LF_Bottom,     //!< process only Graphic3d_ZLayerId_BotOSD
  Metal_LF_Single,     //!< process single layer
  Metal_LF_RayTracable //!< process only normal raytracable layers (save the bottom layer)
};

#endif // Metal_LayerFilter_HeaderFile
