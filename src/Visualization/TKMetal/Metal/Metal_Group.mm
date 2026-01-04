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

#import <Foundation/Foundation.h>

#include <Metal_Group.hxx>
#include <Metal_Structure.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>
#include <Metal_PrimitiveArray.hxx>
#include <Metal_Text.hxx>
#include <Aspect_InteriorStyle.hxx>
#include <Message.hxx>
#include <gp.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Group, Graphic3d_Group)

// =======================================================================
// function : Metal_Group
// purpose  : Constructor
// =======================================================================
Metal_Group::Metal_Group(const occ::handle<Graphic3d_Structure>& theStruct)
: Graphic3d_Group(theStruct),
  myStencilTestEnabled(false),
  myFlippingEnabled(false),
  myFlippingRefPlane(gp::XOY())
{
  //
}

// =======================================================================
// function : ~Metal_Group
// purpose  : Destructor
// =======================================================================
Metal_Group::~Metal_Group()
{
  Release(nullptr);
}

// =======================================================================
// function : Clear
// purpose  : Clear group content
// =======================================================================
void Metal_Group::Clear(const bool theToUpdateStructureMgr)
{
  Release(nullptr);
  Graphic3d_Group::Clear(theToUpdateStructureMgr);
}

// =======================================================================
// function : Aspects
// purpose  : Return fill area aspect
// =======================================================================
occ::handle<Graphic3d_Aspects> Metal_Group::Aspects() const
{
  return myAspect;
}

// =======================================================================
// function : SetGroupPrimitivesAspect
// purpose  : Update aspect
// =======================================================================
void Metal_Group::SetGroupPrimitivesAspect(
  const occ::handle<Graphic3d_Aspects>& theAspect)
{
  myAspect = theAspect;
}

// =======================================================================
// function : SetPrimitivesAspect
// purpose  : Append aspect as an element
// =======================================================================
void Metal_Group::SetPrimitivesAspect(
  const occ::handle<Graphic3d_Aspects>& theAspect)
{
  // For non-bounded groups, we just update the current aspect
  myAspect = theAspect;
}

// =======================================================================
// function : SynchronizeAspects
// purpose  : Update presentation aspects
// =======================================================================
void Metal_Group::SynchronizeAspects()
{
  // Nothing special needed for now
}

// =======================================================================
// function : ReplaceAspects
// purpose  : Replace aspects in the map
// =======================================================================
void Metal_Group::ReplaceAspects(
  const NCollection_DataMap<occ::handle<Graphic3d_Aspects>, occ::handle<Graphic3d_Aspects>>& theMap)
{
  if (myAspect.IsNull())
  {
    return;
  }

  occ::handle<Graphic3d_Aspects> aNewAspect;
  if (theMap.Find(myAspect, aNewAspect))
  {
    myAspect = aNewAspect;
  }
}

// =======================================================================
// function : AddPrimitiveArray
// purpose  : Add primitive array element
// =======================================================================
void Metal_Group::AddPrimitiveArray(const Graphic3d_TypeOfPrimitiveArray theType,
                                    const occ::handle<Graphic3d_IndexBuffer>& theIndices,
                                    const occ::handle<Graphic3d_Buffer>& theAttribs,
                                    const occ::handle<Graphic3d_BoundBuffer>& theBounds,
                                    const bool theToEvalMinMax)
{
  if (theAttribs.IsNull())
  {
    return;
  }

  // Create and store the primitive array
  Metal_PrimitiveArray* aPrimArray = new Metal_PrimitiveArray(theType, theIndices,
                                                               theAttribs, theBounds);
  myPrimitives.Append(aPrimArray);
  Message::SendTrace() << "Metal_Group::AddPrimitiveArray: added primitive type " << (int)theType
                       << " with " << theAttribs->NbElements << " vertices";

  // Update bounding box if requested
  if (theToEvalMinMax)
  {
    Graphic3d_Group::AddPrimitiveArray(theType, theIndices, theAttribs, theBounds, true);
  }
}

// =======================================================================
// function : AddText
// purpose  : Add text for display
// =======================================================================
void Metal_Group::AddText(const occ::handle<Graphic3d_Text>& theTextParams,
                          const bool theToEvalMinMax)
{
  if (theTextParams.IsNull())
  {
    return;
  }

  // Create Metal text element
  occ::handle<Metal_Text> aText = new Metal_Text(theTextParams);
  myTexts.Append(aText);

  // Update bounding box if requested
  if (theToEvalMinMax)
  {
    const gp_Pnt& aPos = theTextParams->Position();
    myBounds.Add(NCollection_Vec4<float>(float(aPos.X()), float(aPos.Y()), float(aPos.Z()), 1.0f));
  }
}

// =======================================================================
// function : SetStencilTestOptions
// purpose  : Add stencil test element
// =======================================================================
void Metal_Group::SetStencilTestOptions(const bool theIsEnabled)
{
  myStencilTestEnabled = theIsEnabled;
}

// =======================================================================
// function : SetFlippingOptions
// purpose  : Add flipping element
// =======================================================================
void Metal_Group::SetFlippingOptions(const bool theIsEnabled,
                                     const gp_Ax2& theRefPlane)
{
  myFlippingEnabled = theIsEnabled;
  myFlippingRefPlane = theRefPlane;
}

// =======================================================================
// function : MetalStruct
// purpose  : Return parent Metal structure
// =======================================================================
Metal_Structure* Metal_Group::MetalStruct() const
{
  if (myStructure == nullptr)
  {
    return nullptr;
  }
  return dynamic_cast<Metal_Structure*>(myStructure->CStructure().get());
}

// =======================================================================
// function : Render
// purpose  : Render the group
// =======================================================================
void Metal_Group::Render(Metal_Workspace* theWorkspace) const
{
  if (theWorkspace == nullptr)
  {
    return;
  }

  // Apply stencil test if enabled for this group
  const bool aPrevStencilTest = theWorkspace->IsStencilTestEnabled();
  if (myStencilTestEnabled != aPrevStencilTest)
  {
    theWorkspace->SetStencilTest(myStencilTestEnabled);
    theWorkspace->ApplyStencilTestState();
  }

  // Apply flipping if enabled for this group
  if (myFlippingEnabled)
  {
    theWorkspace->PushModelMatrix();
    theWorkspace->ApplyFlipping(myFlippingRefPlane);
  }

  // Apply aspect to workspace
  if (!myAspect.IsNull())
  {
    theWorkspace->SetAspect(myAspect);
    // Apply pipeline state for current shading model
    theWorkspace->ApplyPipelineState();
    // Apply material uniforms after setting aspect (binds material to shader)
    theWorkspace->ApplyMaterialUniforms();
  }

  // Determine rendering mode from aspect
  bool aDrawFaces = true;
  bool aDrawEdges = false;

  if (!myAspect.IsNull())
  {
    // Check interior style for wireframe mode
    Aspect_InteriorStyle aStyle = myAspect->InteriorStyle();
    if (aStyle == Aspect_IS_EMPTY)
    {
      aDrawFaces = false;
      aDrawEdges = myAspect->ToDrawEdges();
    }
    else if (aStyle == Aspect_IS_HOLLOW)
    {
      // Hollow = wireframe, show only edges
      aDrawFaces = false;
      aDrawEdges = true;
    }
    else
    {
      // Solid modes - optionally draw edges on top
      aDrawEdges = myAspect->ToDrawEdges();
    }
  }

  // Initialize and render all primitives
  Metal_Context* aCtx = theWorkspace->Context();

  // First pass: render faces (if enabled)
  NSLog(@"Metal_Group::Render: aDrawFaces=%d myPrimitives.Size=%d", (int)aDrawFaces, (int)myPrimitives.Size());
  if (aDrawFaces)
  {
    int aPrimCount = 0;
    for (NCollection_List<Metal_PrimitiveArray*>::Iterator aPrimIter(myPrimitives);
         aPrimIter.More(); aPrimIter.Next())
    {
      Metal_PrimitiveArray* aPrimArray = aPrimIter.Value();
      if (aPrimArray != nullptr)
      {
        // Lazy initialization
        if (!aPrimArray->IsInitialized())
        {
          aPrimArray->Init(aCtx);
        }
        aPrimArray->Render(theWorkspace);
        ++aPrimCount;
      }
    }
    if (aPrimCount > 0)
    {
      NSLog(@"Metal_Group::Render: rendered %d primitives", aPrimCount);
    }
  }

  // Second pass: render edges (if enabled)
  if (aDrawEdges && !myAspect.IsNull())
  {
    // Check if MeshEdges mode is available (smooth anti-aliased wireframe)
    const bool aUseMeshEdges = theWorkspace->IsMeshEdgesMode()
                            && !theWorkspace->GeometryEmulator().IsNull();

    if (aUseMeshEdges)
    {
      // Use geometry emulator for smooth anti-aliased wireframe overlay
      theWorkspace->SetMeshEdgesColor(myAspect->EdgeColorRGBA());
      theWorkspace->ApplyMeshEdgesPipelineState();

      for (NCollection_List<Metal_PrimitiveArray*>::Iterator aPrimIter(myPrimitives);
           aPrimIter.More(); aPrimIter.Next())
      {
        Metal_PrimitiveArray* aPrimArray = aPrimIter.Value();
        if (aPrimArray != nullptr)
        {
          // Lazy initialization
          if (!aPrimArray->IsInitialized())
          {
            aPrimArray->Init(aCtx);
          }
          // Render with MeshEdges (processed vertices with edge distances)
          aPrimArray->RenderMeshEdges(theWorkspace);
        }
      }

      // Restore normal rendering mode
      theWorkspace->SetMeshEdgesMode(false);
      theWorkspace->ApplyPipelineState();
    }
    else
    {
      // Fallback: simple line-based edge rendering
      theWorkspace->SetEdgeRendering(true);
      theWorkspace->SetEdgeColor(myAspect->EdgeColorRGBA());
      theWorkspace->ApplyEdgePipelineState();
      theWorkspace->ApplyEdgeUniforms();

      for (NCollection_List<Metal_PrimitiveArray*>::Iterator aPrimIter(myPrimitives);
           aPrimIter.More(); aPrimIter.Next())
      {
        Metal_PrimitiveArray* aPrimArray = aPrimIter.Value();
        if (aPrimArray != nullptr)
        {
          // Lazy initialization
          if (!aPrimArray->IsInitialized())
          {
            aPrimArray->Init(aCtx);
          }
          aPrimArray->RenderEdges(theWorkspace);
        }
      }

      // Restore normal rendering mode
      theWorkspace->SetEdgeRendering(false);
      theWorkspace->ApplyPipelineState();
    }
  }

  // Render text elements
  for (NCollection_List<occ::handle<Metal_Text>>::Iterator aTextIter(myTexts);
       aTextIter.More(); aTextIter.Next())
  {
    const occ::handle<Metal_Text>& aText = aTextIter.Value();
    if (!aText.IsNull())
    {
      aText->Render(theWorkspace);
    }
  }

  // Restore flipping if we applied it
  if (myFlippingEnabled)
  {
    theWorkspace->PopModelMatrix();
  }

  // Restore previous stencil test state if we changed it
  if (myStencilTestEnabled != aPrevStencilTest)
  {
    theWorkspace->SetStencilTest(aPrevStencilTest);
    theWorkspace->ApplyStencilTestState();
  }
}

// =======================================================================
// function : Release
// purpose  : Release GPU resources
// =======================================================================
void Metal_Group::Release(Metal_Context* theCtx)
{
  // Release primitive arrays
  for (NCollection_List<Metal_PrimitiveArray*>::Iterator aPrimIter(myPrimitives);
       aPrimIter.More(); aPrimIter.Next())
  {
    Metal_PrimitiveArray* aPrimArray = aPrimIter.Value();
    if (aPrimArray != nullptr)
    {
      aPrimArray->Release(theCtx);
      delete aPrimArray;
    }
  }
  myPrimitives.Clear();

  // Release text elements
  for (NCollection_List<occ::handle<Metal_Text>>::Iterator aTextIter(myTexts);
       aTextIter.More(); aTextIter.Next())
  {
    occ::handle<Metal_Text>& aText = aTextIter.ChangeValue();
    if (!aText.IsNull())
    {
      aText->Release(theCtx);
    }
  }
  myTexts.Clear();
}
