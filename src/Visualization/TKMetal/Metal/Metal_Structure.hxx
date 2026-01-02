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

#ifndef Metal_Structure_HeaderFile
#define Metal_Structure_HeaderFile

#include <Graphic3d_CStructure.hxx>
#include <NCollection_List.hxx>
#include <NCollection_Mat4.hxx>

class Metal_GraphicDriver;
class Metal_Group;
class Metal_Context;
class Metal_Workspace;

//! Implementation of low-level graphic structure for Metal.
class Metal_Structure : public Graphic3d_CStructure
{
  friend class Metal_Group;
  DEFINE_STANDARD_RTTIEXT(Metal_Structure, Graphic3d_CStructure)

public:

  //! Auxiliary wrapper to iterate Metal_Structure sequence.
  typedef SubclassStructIterator<Metal_Structure> StructIterator;

  //! Auxiliary wrapper to iterate Metal_Group sequence.
  typedef SubclassGroupIterator<Metal_Group> GroupIterator;

public:

  //! Create empty structure.
  Standard_EXPORT Metal_Structure(const occ::handle<Graphic3d_StructureManager>& theManager);

  //! Destructor.
  Standard_EXPORT ~Metal_Structure() override;

  //! Setup structure graphic state.
  Standard_EXPORT void OnVisibilityChanged() override;

  //! Clear graphic data.
  Standard_EXPORT void Clear() override;

  //! Connect other structure to this one.
  Standard_EXPORT void Connect(Graphic3d_CStructure& theStructure) override;

  //! Disconnect other structure from this one.
  Standard_EXPORT void Disconnect(Graphic3d_CStructure& theStructure) override;

  //! Synchronize structure transformation.
  Standard_EXPORT void SetTransformation(const occ::handle<TopLoc_Datum3D>& theTrsf) override;

  //! Set transformation persistence.
  Standard_EXPORT void SetTransformPersistence(
    const occ::handle<Graphic3d_TransformPers>& theTrsfPers) override;

  //! Set z layer ID to display the structure in specified layer.
  Standard_EXPORT void SetZLayer(const Graphic3d_ZLayerId theLayerIndex) override;

  //! Highlights structure according to the given style.
  Standard_EXPORT void GraphicHighlight(
    const occ::handle<Graphic3d_PresentationAttributes>& theStyle) override;

  //! Unhighlights the structure.
  Standard_EXPORT void GraphicUnhighlight() override;

  //! Create shadow link to this structure.
  Standard_EXPORT occ::handle<Graphic3d_CStructure> ShadowLink(
    const occ::handle<Graphic3d_StructureManager>& theManager) const override;

  //! Create new group within this structure.
  Standard_EXPORT occ::handle<Graphic3d_Group> NewGroup(
    const occ::handle<Graphic3d_Structure>& theStruct) override;

  //! Remove group from this structure.
  Standard_EXPORT void RemoveGroup(const occ::handle<Graphic3d_Group>& theGroup) override;

public:

  //! Access graphic driver.
  Standard_EXPORT Metal_GraphicDriver* MetalDriver() const;

  //! Clear with Metal context.
  Standard_EXPORT void Clear(Metal_Context* theCtx);

  //! Render the structure.
  Standard_EXPORT virtual void Render(Metal_Workspace* theWorkspace) const;

  //! Release structure resources.
  Standard_EXPORT virtual void Release(Metal_Context* theCtx);

  //! Returns instanced Metal structure.
  const Metal_Structure* InstancedStructure() const { return myInstancedStructure; }

  //! Returns structure modification state.
  size_t ModificationState() const { return myModificationState; }

  //! Resets structure modification state.
  void ResetModificationState() const { myModificationState = 0; }

  //! Update render transformation matrix.
  Standard_EXPORT void updateLayerTransformation() override;

  //! Returns the render transformation matrix.
  const NCollection_Mat4<float>& RenderTransformation() const { return myRenderTrsf; }

  //! Returns true if the structure contains mirrored geometry.
  bool IsMirrored() const { return myIsMirrored; }

protected:

  //! Render groups of structure.
  Standard_EXPORT void renderGeometry(Metal_Workspace* theWorkspace,
                                      bool& theHasClosed) const;

protected:

  Metal_Structure*        myInstancedStructure;
  NCollection_Mat4<float> myRenderTrsf;       //!< transformation for rendering
  mutable size_t          myModificationState;
  bool                    myIsMirrored;       //!< mirrored geometry flag
};

#endif // Metal_Structure_HeaderFile
