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

#ifndef Metal_Resource_HeaderFile
#define Metal_Resource_HeaderFile

#include <Standard_Type.hxx>
#include <Standard_Transient.hxx>
#include <TCollection_AsciiString.hxx>

class Metal_Context;

//! Interface for Metal GPU resource with following lifecycle:
//!  - object can be constructed at any time;
//!  - should be explicitly initialized within active Metal context;
//!  - should be explicitly released within active Metal context (virtual Release() method);
//!  - can be destroyed at any time.
//! Destruction of object with unreleased GPU resources will cause leaks
//! which will be ignored in release mode and will immediately stop program execution in debug mode.
class Metal_Resource : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_Resource, Standard_Transient)

public:

  //! Empty constructor
  Standard_EXPORT Metal_Resource();

  //! Destructor
  Standard_EXPORT ~Metal_Resource() override;

  //! Release GPU resources.
  //! Notice that implementation should be SAFE for several consecutive calls
  //! (thus should invalidate internal structures / ids to avoid multiple-free errors).
  //! @param theCtx - bound Metal context, shouldn't be NULL.
  Standard_EXPORT virtual void Release(Metal_Context* theCtx) = 0;

  //! Returns estimated GPU memory usage for holding data without considering overheads
  //! and allocation alignment rules.
  virtual size_t EstimatedDataSize() const = 0;

  //! Dumps the content of me into the stream
  virtual void DumpJson(Standard_OStream& theOStream, int theDepth = -1) const
  {
    (void)theOStream;
    (void)theDepth;
  }

private:

  //! Copy should be performed only within Handles!
  Metal_Resource(const Metal_Resource&) = delete;
  Metal_Resource& operator=(const Metal_Resource&) = delete;
};

//! Named Metal resource object for shared resource management.
class Metal_NamedResource : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_NamedResource, Metal_Resource)

public:

  //! Constructor with resource ID
  Metal_NamedResource(const TCollection_AsciiString& theId)
  : myResourceId(theId)
  {
  }

  //! Return resource name.
  const TCollection_AsciiString& ResourceId() const { return myResourceId; }

protected:
  TCollection_AsciiString myResourceId; //!< resource name
};

#endif // Metal_Resource_HeaderFile
