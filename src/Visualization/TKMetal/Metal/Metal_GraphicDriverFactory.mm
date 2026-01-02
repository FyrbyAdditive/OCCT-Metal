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

#include <Metal_GraphicDriverFactory.hxx>
#include <Metal_GraphicDriver.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_GraphicDriverFactory, Graphic3d_GraphicDriverFactory)

namespace
{
  //! Auto-registration of Metal driver factory on library load.
  //! This will register the Metal driver as the preferred driver on macOS.
  static class Metal_AutoRegisterFactory
  {
  public:
    Metal_AutoRegisterFactory()
    {
      // Only register if Metal is available
      if (@available(macOS 10.13, *))
      {
        occ::handle<Metal_GraphicDriverFactory> aFactory = new Metal_GraphicDriverFactory();
        // Register as preferred on macOS (theIsPreferred = true)
        Graphic3d_GraphicDriverFactory::RegisterFactory(aFactory, true);
      }
    }
  } theAutoRegistration;
}

// =======================================================================
// function : Metal_GraphicDriverFactory
// purpose  : Constructor
// =======================================================================
Metal_GraphicDriverFactory::Metal_GraphicDriverFactory()
: Graphic3d_GraphicDriverFactory("TKMetal"),
  myDefaultCaps(new Metal_Caps())
{
  //
}

// =======================================================================
// function : CreateDriver
// purpose  : Create Metal graphic driver
// =======================================================================
occ::handle<Graphic3d_GraphicDriver> Metal_GraphicDriverFactory::CreateDriver(
  const occ::handle<Aspect_DisplayConnection>& theDisp)
{
  occ::handle<Metal_GraphicDriver> aDriver = new Metal_GraphicDriver(theDisp, false);
  aDriver->ChangeOptions() = *myDefaultCaps;
  aDriver->InitContext();
  return aDriver;
}
