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

#include <Metal_Structure.hxx>
#include <Metal_Group.hxx>
#include <Metal_GraphicDriver.hxx>
#include <Metal_Context.hxx>
#include <Metal_Workspace.hxx>

#include <Graphic3d_GraphicDriver.hxx>
#include <Graphic3d_StructureManager.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Structure, Graphic3d_CStructure)

// =======================================================================
// function : MetalDriver
// purpose  : Access graphic driver
// =======================================================================
Metal_GraphicDriver* Metal_Structure::MetalDriver() const
{
  return dynamic_cast<Metal_GraphicDriver*>(myGraphicDriver.get());
}

// =======================================================================
// function : Metal_Structure
// purpose  : Constructor
// =======================================================================
Metal_Structure::Metal_Structure(const occ::handle<Graphic3d_StructureManager>& theManager)
: Graphic3d_CStructure(theManager),
  myInstancedStructure(nullptr),
  myModificationState(0),
  myIsMirrored(false)
{
  updateLayerTransformation();
}

// =======================================================================
// function : ~Metal_Structure
// purpose  : Destructor
// =======================================================================
Metal_Structure::~Metal_Structure()
{
  Release(nullptr);
}

// =======================================================================
// function : OnVisibilityChanged
// purpose  : Handle visibility change
// =======================================================================
void Metal_Structure::OnVisibilityChanged()
{
  // Nothing special needed for Metal
}

// =======================================================================
// function : Clear
// purpose  : Clear graphic data
// =======================================================================
void Metal_Structure::Clear()
{
  Clear(nullptr);
}

// =======================================================================
// function : Clear
// purpose  : Clear with Metal context
// =======================================================================
void Metal_Structure::Clear(Metal_Context* theCtx)
{
  // Release all groups
  for (NCollection_Sequence<occ::handle<Graphic3d_Group>>::Iterator aGroupIter(myGroups);
       aGroupIter.More(); aGroupIter.Next())
  {
    Metal_Group* aGroup = dynamic_cast<Metal_Group*>(aGroupIter.Value().get());
    if (aGroup != nullptr)
    {
      aGroup->Release(theCtx);
    }
  }
  myGroups.Clear();

  myBndBox.Clear();
  ++myModificationState;
}

// =======================================================================
// function : Connect
// purpose  : Connect other structure
// =======================================================================
void Metal_Structure::Connect(Graphic3d_CStructure& theStructure)
{
  Metal_Structure* aStruct = dynamic_cast<Metal_Structure*>(&theStructure);
  if (aStruct != nullptr)
  {
    myInstancedStructure = aStruct;
    ++myModificationState;
  }
}

// =======================================================================
// function : Disconnect
// purpose  : Disconnect other structure
// =======================================================================
void Metal_Structure::Disconnect(Graphic3d_CStructure& theStructure)
{
  Metal_Structure* aStruct = dynamic_cast<Metal_Structure*>(&theStructure);
  if (myInstancedStructure == aStruct)
  {
    myInstancedStructure = nullptr;
    ++myModificationState;
  }
}

// =======================================================================
// function : SetTransformation
// purpose  : Synchronize structure transformation
// =======================================================================
void Metal_Structure::SetTransformation(const occ::handle<TopLoc_Datum3D>& theTrsf)
{
  Graphic3d_CStructure::SetTransformation(theTrsf);
  updateLayerTransformation();
  ++myModificationState;
}

// =======================================================================
// function : SetTransformPersistence
// purpose  : Set transformation persistence
// =======================================================================
void Metal_Structure::SetTransformPersistence(
  const occ::handle<Graphic3d_TransformPers>& theTrsfPers)
{
  Graphic3d_CStructure::SetTransformPersistence(theTrsfPers);
  ++myModificationState;
}

// =======================================================================
// function : SetZLayer
// purpose  : Set z layer
// =======================================================================
void Metal_Structure::SetZLayer(const Graphic3d_ZLayerId theLayerIndex)
{
  Graphic3d_CStructure::SetZLayer(theLayerIndex);
  ++myModificationState;
}

// =======================================================================
// function : GraphicHighlight
// purpose  : Highlight structure
// =======================================================================
void Metal_Structure::GraphicHighlight(
  const occ::handle<Graphic3d_PresentationAttributes>& theStyle)
{
  myHighlightStyle = theStyle;
  highlight = 1;
  ++myModificationState;
}

// =======================================================================
// function : GraphicUnhighlight
// purpose  : Unhighlight structure
// =======================================================================
void Metal_Structure::GraphicUnhighlight()
{
  highlight = 0;
  myHighlightStyle.Nullify();
  ++myModificationState;
}

// =======================================================================
// function : ShadowLink
// purpose  : Create shadow link
// =======================================================================
occ::handle<Graphic3d_CStructure> Metal_Structure::ShadowLink(
  const occ::handle<Graphic3d_StructureManager>& theManager) const
{
  // Shadow structures are used for instancing - create a new structure
  // that references this one
  occ::handle<Metal_Structure> aShadow = new Metal_Structure(theManager);
  aShadow->myInstancedStructure = const_cast<Metal_Structure*>(this);
  return aShadow;
}

// =======================================================================
// function : NewGroup
// purpose  : Create new group
// =======================================================================
occ::handle<Graphic3d_Group> Metal_Structure::NewGroup(
  const occ::handle<Graphic3d_Structure>& theStruct)
{
  occ::handle<Metal_Group> aGroup = new Metal_Group(theStruct);
  myGroups.Append(aGroup);
  ++myModificationState;
  return aGroup;
}

// =======================================================================
// function : RemoveGroup
// purpose  : Remove group
// =======================================================================
void Metal_Structure::RemoveGroup(const occ::handle<Graphic3d_Group>& theGroup)
{
  Metal_Group* aGroup = dynamic_cast<Metal_Group*>(theGroup.get());
  if (aGroup == nullptr)
  {
    return;
  }

  for (NCollection_Sequence<occ::handle<Graphic3d_Group>>::Iterator aGroupIter(myGroups);
       aGroupIter.More(); aGroupIter.Next())
  {
    if (aGroupIter.Value() == theGroup)
    {
      aGroup->Release(nullptr);
      myGroups.Remove(aGroupIter);
      ++myModificationState;
      return;
    }
  }
}

// =======================================================================
// function : Release
// purpose  : Release resources
// =======================================================================
void Metal_Structure::Release(Metal_Context* theCtx)
{
  Clear(theCtx);
  myInstancedStructure = nullptr;
}

// =======================================================================
// function : Render
// purpose  : Render the structure
// =======================================================================
void Metal_Structure::Render(Metal_Workspace* theWorkspace) const
{
  if (!visible)
  {
    return;
  }

  // Render instanced structure first
  if (myInstancedStructure != nullptr)
  {
    myInstancedStructure->Render(theWorkspace);
  }

  // Render all groups
  bool aHasClosed = false;
  renderGeometry(theWorkspace, aHasClosed);
}

// =======================================================================
// function : renderGeometry
// purpose  : Render groups
// =======================================================================
void Metal_Structure::renderGeometry(Metal_Workspace* theWorkspace,
                                     bool& theHasClosed) const
{
  theHasClosed = false;

  for (GroupIterator aGroupIter(myGroups); aGroupIter.More(); aGroupIter.Next())
  {
    const Metal_Group* aGroup = aGroupIter.Value();
    if (aGroup != nullptr)
    {
      if (aGroup->IsClosed())
      {
        theHasClosed = true;
      }
      aGroup->Render(theWorkspace);
    }
  }
}

// =======================================================================
// function : updateLayerTransformation
// purpose  : Update render transformation matrix
// =======================================================================
void Metal_Structure::updateLayerTransformation()
{
  myRenderTrsf.InitIdentity();
  myIsMirrored = false;

  if (!myTrsf.IsNull())
  {
    const gp_Trsf& aTrsf = myTrsf->Trsf();

    // Copy transformation to render matrix
    myRenderTrsf.SetValue(0, 0, static_cast<float>(aTrsf.Value(1, 1)));
    myRenderTrsf.SetValue(0, 1, static_cast<float>(aTrsf.Value(1, 2)));
    myRenderTrsf.SetValue(0, 2, static_cast<float>(aTrsf.Value(1, 3)));
    myRenderTrsf.SetValue(0, 3, static_cast<float>(aTrsf.Value(1, 4)));

    myRenderTrsf.SetValue(1, 0, static_cast<float>(aTrsf.Value(2, 1)));
    myRenderTrsf.SetValue(1, 1, static_cast<float>(aTrsf.Value(2, 2)));
    myRenderTrsf.SetValue(1, 2, static_cast<float>(aTrsf.Value(2, 3)));
    myRenderTrsf.SetValue(1, 3, static_cast<float>(aTrsf.Value(2, 4)));

    myRenderTrsf.SetValue(2, 0, static_cast<float>(aTrsf.Value(3, 1)));
    myRenderTrsf.SetValue(2, 1, static_cast<float>(aTrsf.Value(3, 2)));
    myRenderTrsf.SetValue(2, 2, static_cast<float>(aTrsf.Value(3, 3)));
    myRenderTrsf.SetValue(2, 3, static_cast<float>(aTrsf.Value(3, 4)));

    myRenderTrsf.SetValue(3, 0, 0.0f);
    myRenderTrsf.SetValue(3, 1, 0.0f);
    myRenderTrsf.SetValue(3, 2, 0.0f);
    myRenderTrsf.SetValue(3, 3, 1.0f);

    // Check if transformation mirrors the geometry
    myIsMirrored = aTrsf.IsNegative();
  }
}
