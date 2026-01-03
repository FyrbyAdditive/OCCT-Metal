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

#ifndef Metal_ShaderObject_HeaderFile
#define Metal_ShaderObject_HeaderFile

#include <Metal_Resource.hxx>
#include <Graphic3d_ShaderObject.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLFunction;
@protocol MTLLibrary;
#endif

class Metal_Context;

//! Shader type enumeration for Metal.
enum Metal_ShaderType
{
  Metal_ShaderType_Vertex,
  Metal_ShaderType_Fragment,
  Metal_ShaderType_Compute,
  Metal_ShaderType_Tile
};

//! Wrapper for Metal shader function (MTLFunction).
//! Represents a compiled shader that can be used in a pipeline.
class Metal_ShaderObject : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_ShaderObject, Metal_Resource)

public:

  //! Create uninitialized shader object.
  Standard_EXPORT Metal_ShaderObject(Metal_ShaderType theType);

  //! Destructor.
  Standard_EXPORT ~Metal_ShaderObject() override;

  //! Return shader type.
  Metal_ShaderType Type() const { return myType; }

  //! Return TRUE if shader is compiled and valid.
  bool IsValid() const { return myFunction != nullptr; }

  //! Return estimated GPU memory usage (minimal for functions).
  size_t EstimatedDataSize() const override { return 0; }

  //! Return shader function name.
  const TCollection_AsciiString& FunctionName() const { return myFunctionName; }

  //! Compile shader from MSL source code.
  //! @param theCtx Metal context
  //! @param theSource MSL source code
  //! @param theFunctionName name of the function in the source
  //! @return true on success
  Standard_EXPORT bool Compile(Metal_Context* theCtx,
                               const TCollection_AsciiString& theSource,
                               const TCollection_AsciiString& theFunctionName);

  //! Load shader function from existing library.
  //! @param theCtx Metal context
  //! @param theLibrary compiled Metal library
  //! @param theFunctionName name of the function to load
  //! @return true on success
#ifdef __OBJC__
  Standard_EXPORT bool LoadFromLibrary(Metal_Context* theCtx,
                                       id<MTLLibrary> theLibrary,
                                       const TCollection_AsciiString& theFunctionName);
#endif

  //! Compile shader from Graphic3d shader object.
  //! @param theCtx Metal context
  //! @param theShader high-level shader definition
  //! @return true on success
  Standard_EXPORT bool CompileFromSource(Metal_Context* theCtx,
                                         const occ::handle<Graphic3d_ShaderObject>& theShader);

  //! Return compilation log (errors/warnings).
  const TCollection_AsciiString& CompileLog() const { return myCompileLog; }

  //! Release Metal resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

#ifdef __OBJC__
  //! Return native Metal function object.
  id<MTLFunction> Function() const { return myFunction; }
#endif

protected:

#ifdef __OBJC__
  id<MTLFunction> myFunction;   //!< Metal function object
  id<MTLLibrary>  myLibrary;    //!< Owning library (if compiled from source)
#else
  void* myFunction;
  void* myLibrary;
#endif
  Metal_ShaderType        myType;         //!< shader type
  TCollection_AsciiString myFunctionName; //!< function name
  TCollection_AsciiString myCompileLog;   //!< compilation log
};

DEFINE_STANDARD_HANDLE(Metal_ShaderObject, Metal_Resource)

#endif // Metal_ShaderObject_HeaderFile
