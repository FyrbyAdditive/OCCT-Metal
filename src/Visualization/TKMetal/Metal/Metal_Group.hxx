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

#ifndef Metal_Group_HeaderFile
#define Metal_Group_HeaderFile

#include <Graphic3d_Group.hxx>
#include <Graphic3d_Structure.hxx>
#include <Graphic3d_Aspects.hxx>
#include <NCollection_List.hxx>

class Metal_Structure;
class Metal_Context;
class Metal_Workspace;
class Metal_PrimitiveArray;

//! Implementation of low-level graphic group for Metal.
class Metal_Group : public Graphic3d_Group
{
  DEFINE_STANDARD_RTTIEXT(Metal_Group, Graphic3d_Group)

public:

  //! Create empty group.
  Standard_EXPORT Metal_Group(const occ::handle<Graphic3d_Structure>& theStruct);

  //! Destructor.
  Standard_EXPORT ~Metal_Group() override;

  //! Clear group content.
  Standard_EXPORT void Clear(const bool theToUpdateStructureMgr) override;

  //! Return fill area aspect.
  Standard_EXPORT occ::handle<Graphic3d_Aspects> Aspects() const override;

  //! Update aspect.
  Standard_EXPORT void SetGroupPrimitivesAspect(
    const occ::handle<Graphic3d_Aspects>& theAspect) override;

  //! Append aspect as an element.
  Standard_EXPORT void SetPrimitivesAspect(
    const occ::handle<Graphic3d_Aspects>& theAspect) override;

  //! Update presentation aspects after their modification.
  Standard_EXPORT void SynchronizeAspects() override;

  //! Replace aspects specified in the replacement map.
  Standard_EXPORT void ReplaceAspects(
    const NCollection_DataMap<occ::handle<Graphic3d_Aspects>, occ::handle<Graphic3d_Aspects>>&
      theMap) override;

  //! Add primitive array element.
  Standard_EXPORT void AddPrimitiveArray(const Graphic3d_TypeOfPrimitiveArray      theType,
                                         const occ::handle<Graphic3d_IndexBuffer>& theIndices,
                                         const occ::handle<Graphic3d_Buffer>&      theAttribs,
                                         const occ::handle<Graphic3d_BoundBuffer>& theBounds,
                                         const bool theToEvalMinMax) override;

  //! Add text for display.
  Standard_EXPORT void AddText(const occ::handle<Graphic3d_Text>& theTextParams,
                               const bool theToEvalMinMax) override;

  //! Add stencil test element.
  Standard_EXPORT void SetStencilTestOptions(const bool theIsEnabled) override;

  //! Add flipping element.
  Standard_EXPORT void SetFlippingOptions(const bool theIsEnabled,
                                          const gp_Ax2& theRefPlane) override;

public:

  //! Return parent Metal structure.
  Metal_Structure* MetalStruct() const;

  //! Render the group.
  Standard_EXPORT virtual void Render(Metal_Workspace* theWorkspace) const;

  //! Release GPU resources.
  Standard_EXPORT virtual void Release(Metal_Context* theCtx);

  //! Return TRUE if group contains primitives with transform persistence.
  bool HasPersistence() const
  {
    return !myTrsfPers.IsNull()
           || (myStructure != nullptr && !myStructure->TransformPersistence().IsNull());
  }

protected:

  occ::handle<Graphic3d_Aspects>          myAspect;      //!< group aspect
  NCollection_List<Metal_PrimitiveArray*> myPrimitives;  //!< list of primitive arrays
};

#endif // Metal_Group_HeaderFile
