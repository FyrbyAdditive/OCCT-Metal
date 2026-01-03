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

#import <Metal/Metal.h>

#include <Metal_ShaderObject.hxx>
#include <Metal_Context.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_ShaderObject, Metal_Resource)

// =======================================================================
// function : Metal_ShaderObject
// purpose  : Constructor
// =======================================================================
Metal_ShaderObject::Metal_ShaderObject(Metal_ShaderType theType)
: myFunction(nil),
  myLibrary(nil),
  myType(theType)
{
  //
}

// =======================================================================
// function : ~Metal_ShaderObject
// purpose  : Destructor
// =======================================================================
Metal_ShaderObject::~Metal_ShaderObject()
{
  Release(nullptr);
}

// =======================================================================
// function : Compile
// purpose  : Compile shader from MSL source
// =======================================================================
bool Metal_ShaderObject::Compile(Metal_Context* theCtx,
                                 const TCollection_AsciiString& theSource,
                                 const TCollection_AsciiString& theFunctionName)
{
  Release(theCtx);

  if (theCtx == nullptr || !theCtx->IsValid())
  {
    myCompileLog = "Invalid Metal context";
    return false;
  }

  if (theSource.IsEmpty() || theFunctionName.IsEmpty())
  {
    myCompileLog = "Empty source or function name";
    return false;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  if (aDevice == nil)
  {
    myCompileLog = "No Metal device";
    return false;
  }

  // Compile the source code
  NSError* anError = nil;
  NSString* aSource = [NSString stringWithUTF8String:theSource.ToCString()];

  MTLCompileOptions* anOptions = [[MTLCompileOptions alloc] init];
  anOptions.fastMathEnabled = YES;
  anOptions.languageVersion = MTLLanguageVersion2_4;

  myLibrary = [aDevice newLibraryWithSource:aSource options:anOptions error:&anError];

  if (anError != nil)
  {
    myCompileLog = [[anError localizedDescription] UTF8String];
    if (myLibrary == nil)
    {
      return false;
    }
    // Library compiled with warnings
  }

  // Get the function
  NSString* aFuncName = [NSString stringWithUTF8String:theFunctionName.ToCString()];
  myFunction = [myLibrary newFunctionWithName:aFuncName];

  if (myFunction == nil)
  {
    myCompileLog = TCollection_AsciiString("Function '") + theFunctionName + "' not found in library";
    return false;
  }

  myFunctionName = theFunctionName;
  return true;
}

// =======================================================================
// function : LoadFromLibrary
// purpose  : Load function from existing library
// =======================================================================
bool Metal_ShaderObject::LoadFromLibrary(Metal_Context* theCtx,
                                         id<MTLLibrary> theLibrary,
                                         const TCollection_AsciiString& theFunctionName)
{
  Release(theCtx);

  if (theLibrary == nil || theFunctionName.IsEmpty())
  {
    myCompileLog = "Invalid library or function name";
    return false;
  }

  NSString* aFuncName = [NSString stringWithUTF8String:theFunctionName.ToCString()];
  myFunction = [theLibrary newFunctionWithName:aFuncName];

  if (myFunction == nil)
  {
    myCompileLog = TCollection_AsciiString("Function '") + theFunctionName + "' not found in library";
    return false;
  }

  myFunctionName = theFunctionName;
  // Don't store the library reference - it's owned externally
  return true;
}

// =======================================================================
// function : CompileFromSource
// purpose  : Compile from Graphic3d shader object
// =======================================================================
bool Metal_ShaderObject::CompileFromSource(Metal_Context* theCtx,
                                           const occ::handle<Graphic3d_ShaderObject>& theShader)
{
  if (theShader.IsNull())
  {
    myCompileLog = "Null shader object";
    return false;
  }

  // Get source code from shader object
  TCollection_AsciiString aSource = theShader->Source();
  if (aSource.IsEmpty())
  {
    myCompileLog = "Empty shader source";
    return false;
  }

  // Determine function name based on shader type
  TCollection_AsciiString aFuncName;
  switch (myType)
  {
    case Metal_ShaderType_Vertex:
      aFuncName = "vertexMain";
      break;
    case Metal_ShaderType_Fragment:
      aFuncName = "fragmentMain";
      break;
    case Metal_ShaderType_Compute:
      aFuncName = "computeMain";
      break;
    case Metal_ShaderType_Tile:
      aFuncName = "tileMain";
      break;
  }

  return Compile(theCtx, aSource, aFuncName);
}

// =======================================================================
// function : Release
// purpose  : Release Metal resources
// =======================================================================
void Metal_ShaderObject::Release(Metal_Context* /*theCtx*/)
{
  myFunction = nil;
  myLibrary = nil;
  myFunctionName.Clear();
  myCompileLog.Clear();
}
