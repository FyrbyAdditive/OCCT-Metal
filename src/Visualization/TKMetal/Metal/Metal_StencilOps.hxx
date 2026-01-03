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

#ifndef Metal_StencilOps_HeaderFile
#define Metal_StencilOps_HeaderFile

#include <Standard_TypeDef.hxx>

//! Stencil operation type (maps to MTLStencilOperation).
enum Metal_StencilOp
{
  Metal_StencilOp_Keep = 0,        //!< keep current value
  Metal_StencilOp_Zero,            //!< set to zero
  Metal_StencilOp_Replace,         //!< replace with reference value
  Metal_StencilOp_IncrClamp,       //!< increment and clamp
  Metal_StencilOp_DecrClamp,       //!< decrement and clamp
  Metal_StencilOp_Invert,          //!< bitwise invert
  Metal_StencilOp_IncrWrap,        //!< increment and wrap
  Metal_StencilOp_DecrWrap         //!< decrement and wrap
};

//! Stencil compare function (maps to MTLCompareFunction).
enum Metal_StencilFunc
{
  Metal_StencilFunc_Never = 0,     //!< never pass
  Metal_StencilFunc_Less,          //!< pass if ref < stencil
  Metal_StencilFunc_Equal,         //!< pass if ref == stencil
  Metal_StencilFunc_LessEqual,     //!< pass if ref <= stencil
  Metal_StencilFunc_Greater,       //!< pass if ref > stencil
  Metal_StencilFunc_NotEqual,      //!< pass if ref != stencil
  Metal_StencilFunc_GreaterEqual,  //!< pass if ref >= stencil
  Metal_StencilFunc_Always         //!< always pass
};

//! Stencil test configuration for Metal.
//! Configures stencil buffer testing and operations.
struct Metal_StencilTest
{
  Metal_StencilFunc Function;      //!< compare function
  Metal_StencilOp   StencilFail;   //!< operation when stencil test fails
  Metal_StencilOp   DepthFail;     //!< operation when depth test fails
  Metal_StencilOp   DepthPass;     //!< operation when both tests pass
  uint32_t          ReadMask;      //!< stencil read mask
  uint32_t          WriteMask;     //!< stencil write mask
  uint32_t          Reference;     //!< reference value for comparison

  //! Default constructor - disabled stencil test.
  Metal_StencilTest()
  : Function(Metal_StencilFunc_Always),
    StencilFail(Metal_StencilOp_Keep),
    DepthFail(Metal_StencilOp_Keep),
    DepthPass(Metal_StencilOp_Keep),
    ReadMask(0xFF),
    WriteMask(0xFF),
    Reference(0)
  {}

  //! Return true if stencil test is effectively disabled.
  bool IsDisabled() const
  {
    return Function == Metal_StencilFunc_Always
        && StencilFail == Metal_StencilOp_Keep
        && DepthFail == Metal_StencilOp_Keep
        && DepthPass == Metal_StencilOp_Keep;
  }

  //! Compare two stencil configurations.
  bool operator==(const Metal_StencilTest& theOther) const
  {
    return Function == theOther.Function
        && StencilFail == theOther.StencilFail
        && DepthFail == theOther.DepthFail
        && DepthPass == theOther.DepthPass
        && ReadMask == theOther.ReadMask
        && WriteMask == theOther.WriteMask
        && Reference == theOther.Reference;
  }

  bool operator!=(const Metal_StencilTest& theOther) const { return !(*this == theOther); }
};

//! Stencil state manager for Metal.
//! Manages front and back face stencil operations.
class Metal_StencilState
{
public:

  //! Default constructor.
  Metal_StencilState()
  : myEnabled(false)
  {}

  //! Return true if stencil testing is enabled.
  bool IsEnabled() const { return myEnabled; }

  //! Enable/disable stencil testing.
  void SetEnabled(bool theValue) { myEnabled = theValue; }

  //! Return front face stencil configuration.
  const Metal_StencilTest& Front() const { return myFront; }

  //! Return front face stencil configuration for modification.
  Metal_StencilTest& ChangeFront() { return myFront; }

  //! Return back face stencil configuration.
  const Metal_StencilTest& Back() const { return myBack; }

  //! Return back face stencil configuration for modification.
  Metal_StencilTest& ChangeBack() { return myBack; }

  //! Set same configuration for front and back faces.
  void SetBothFaces(const Metal_StencilTest& theConfig)
  {
    myFront = theConfig;
    myBack = theConfig;
  }

  //! Configure for simple stencil masking (draw to stencil buffer).
  void SetMaskMode(uint32_t theRef = 1)
  {
    myEnabled = true;
    myFront.Function = Metal_StencilFunc_Always;
    myFront.StencilFail = Metal_StencilOp_Keep;
    myFront.DepthFail = Metal_StencilOp_Keep;
    myFront.DepthPass = Metal_StencilOp_Replace;
    myFront.Reference = theRef;
    myFront.WriteMask = 0xFF;
    myBack = myFront;
  }

  //! Configure for clipping against stencil mask.
  void SetClipMode(uint32_t theRef = 1)
  {
    myEnabled = true;
    myFront.Function = Metal_StencilFunc_Equal;
    myFront.StencilFail = Metal_StencilOp_Keep;
    myFront.DepthFail = Metal_StencilOp_Keep;
    myFront.DepthPass = Metal_StencilOp_Keep;
    myFront.Reference = theRef;
    myFront.ReadMask = 0xFF;
    myFront.WriteMask = 0x00;  // don't modify stencil when clipping
    myBack = myFront;
  }

  //! Configure for outline rendering (stencil for silhouettes).
  void SetOutlineMode()
  {
    myEnabled = true;
    // First pass: write to stencil
    myFront.Function = Metal_StencilFunc_Always;
    myFront.DepthPass = Metal_StencilOp_Replace;
    myFront.Reference = 1;
    myBack = myFront;
  }

  //! Reset to disabled state.
  void Reset()
  {
    myEnabled = false;
    myFront = Metal_StencilTest();
    myBack = Metal_StencilTest();
  }

private:

  bool             myEnabled;  //!< enabled flag
  Metal_StencilTest myFront;   //!< front face config
  Metal_StencilTest myBack;    //!< back face config
};

#endif // Metal_StencilOps_HeaderFile
