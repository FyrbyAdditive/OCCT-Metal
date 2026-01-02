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

#ifndef Metal_GraphicDriverFactory_HeaderFile
#define Metal_GraphicDriverFactory_HeaderFile

#include <Graphic3d_GraphicDriverFactory.hxx>
#include <Metal_Caps.hxx>

//! Factory class for creation of Metal_GraphicDriver.
class Metal_GraphicDriverFactory : public Graphic3d_GraphicDriverFactory
{
  DEFINE_STANDARD_RTTIEXT(Metal_GraphicDriverFactory, Graphic3d_GraphicDriverFactory)

public:

  //! Empty constructor.
  Standard_EXPORT Metal_GraphicDriverFactory();

  //! Creates new Metal graphic driver.
  Standard_EXPORT occ::handle<Graphic3d_GraphicDriver> CreateDriver(
    const occ::handle<Aspect_DisplayConnection>& theDisp) override;

  //! Return default driver options.
  const occ::handle<Metal_Caps>& DefaultOptions() const { return myDefaultCaps; }

  //! Set default driver options.
  void SetDefaultOptions(const occ::handle<Metal_Caps>& theOptions) { myDefaultCaps = theOptions; }

protected:

  occ::handle<Metal_Caps> myDefaultCaps;
};

#endif // Metal_GraphicDriverFactory_HeaderFile
