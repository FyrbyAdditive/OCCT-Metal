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

#ifndef Metal_Caps_HeaderFile
#define Metal_Caps_HeaderFile

#include <Standard_Type.hxx>
#include <Standard_Transient.hxx>

//! Class to define Metal graphic driver capabilities and configuration options.
class Metal_Caps : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Caps, Standard_Transient)

public: //! @name flags to disable particular functionality

  //! Disables sRGB rendering (OFF by default)
  bool sRGBDisable;

  //! Disallow VBO usage for debugging purposes (OFF by default)
  bool vboDisable;

  //! Flag permits Point Sprites usage (OFF by default)
  bool pntSpritesDisable;

  //! Disables freeing CPU memory after building GPU buffers (OFF by default)
  bool keepArrayData;

  //! Controls swap interval - 0 for VSync off and 1 for VSync on, 1 by default
  int swapInterval;

public: //! @name context creation parameters

  //! Specify that driver should not present drawable at the end of frame.
  //! Useful when OCCT Viewer is integrated into existing Metal rendering pipeline.
  //! OFF by default.
  bool buffersNoSwap;

  //! Specify whether alpha component within color buffer should be written or not.
  //! ON by default.
  bool buffersOpaqueAlpha;

  //! Request debug Metal context with validation layer enabled.
  //! When turned on Metal runtime emits error and warning messages.
  //! Affects performance - should not be turned on in release builds.
  //! OFF by default.
  bool contextDebug;

  //! Prefer low-power GPU when multiple GPUs are available.
  //! OFF by default (prefer high-performance GPU).
  bool preferLowPowerGPU;

  //! Request GPU capture scope to be enabled for debugging with Xcode.
  //! OFF by default.
  bool enableGPUCapture;

public: //! @name Metal-specific feature flags

  //! Use argument buffers for resource binding when available.
  //! ON by default on supported hardware.
  bool useArgumentBuffers;

  //! Enable triple-buffering for dynamic resources.
  //! ON by default.
  bool useTripleBuffering;

  //! Maximum number of frames that can be in flight simultaneously.
  //! 3 by default for triple-buffering.
  int maxFramesInFlight;

public: //! @name flags to activate verbose output

  //! Print shader compilation warnings, if any. OFF by default.
  bool shaderWarnings;

  //! Suppress redundant messages. ON by default.
  bool suppressExtraMsg;

public: //! @name class methods

  //! Default constructor - initialize with most optimal values.
  Standard_EXPORT Metal_Caps();

  //! Destructor.
  Standard_EXPORT ~Metal_Caps() override;

  //! Copy assignment operator.
  Standard_EXPORT Metal_Caps& operator=(const Metal_Caps& theCopy);

private:
  //! Not implemented
  Metal_Caps(const Metal_Caps&) = delete;
};

#endif // Metal_Caps_HeaderFile
