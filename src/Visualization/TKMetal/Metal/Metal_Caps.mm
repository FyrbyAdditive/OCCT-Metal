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

#include <Metal_Caps.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Caps, Standard_Transient)

// =======================================================================
// function : Metal_Caps
// purpose  : Constructor - initialize with optimal default values
// =======================================================================
Metal_Caps::Metal_Caps()
: sRGBDisable(false),
  vboDisable(false),
  pntSpritesDisable(false),
  keepArrayData(false),
  swapInterval(1),
  buffersNoSwap(false),
  buffersOpaqueAlpha(true),
  contextDebug(false),
  preferLowPowerGPU(false),
  enableGPUCapture(false),
  useArgumentBuffers(true),
  useTripleBuffering(true),
  maxFramesInFlight(3),
  shaderWarnings(false),
  suppressExtraMsg(true)
{
#ifdef OCCT_DEBUG
  contextDebug = true;
  shaderWarnings = true;
#endif
}

// =======================================================================
// function : ~Metal_Caps
// purpose  : Destructor
// =======================================================================
Metal_Caps::~Metal_Caps()
{
  //
}

// =======================================================================
// function : operator=
// purpose  : Copy assignment
// =======================================================================
Metal_Caps& Metal_Caps::operator=(const Metal_Caps& theCopy)
{
  sRGBDisable         = theCopy.sRGBDisable;
  vboDisable          = theCopy.vboDisable;
  pntSpritesDisable   = theCopy.pntSpritesDisable;
  keepArrayData       = theCopy.keepArrayData;
  swapInterval        = theCopy.swapInterval;
  buffersNoSwap       = theCopy.buffersNoSwap;
  buffersOpaqueAlpha  = theCopy.buffersOpaqueAlpha;
  contextDebug        = theCopy.contextDebug;
  preferLowPowerGPU   = theCopy.preferLowPowerGPU;
  enableGPUCapture    = theCopy.enableGPUCapture;
  useArgumentBuffers  = theCopy.useArgumentBuffers;
  useTripleBuffering  = theCopy.useTripleBuffering;
  maxFramesInFlight   = theCopy.maxFramesInFlight;
  shaderWarnings      = theCopy.shaderWarnings;
  suppressExtraMsg    = theCopy.suppressExtraMsg;
  return *this;
}
