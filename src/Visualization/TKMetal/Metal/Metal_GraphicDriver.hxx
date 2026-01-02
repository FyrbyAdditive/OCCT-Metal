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

#ifndef Metal_GraphicDriver_HeaderFile
#define Metal_GraphicDriver_HeaderFile

#include <Graphic3d_GraphicDriver.hxx>
#include <Aspect_DisplayConnection.hxx>
#include <Graphic3d_CView.hxx>
#include <Graphic3d_CStructure.hxx>
#include <NCollection_DataMap.hxx>
#include <NCollection_Map.hxx>
#include <Metal_Caps.hxx>
#include <Metal_Context.hxx>

class Aspect_Window;
class Metal_Structure;
class Metal_View;
class Metal_Window;

//! Tool class to implement consistent state counter for objects inside the same driver instance.
class Metal_StateCounter
{
public:
  Metal_StateCounter() : myCounter(0) {}
  size_t Increment() { return ++myCounter; }

private:
  size_t myCounter;
};

//! This class defines a Metal graphic driver.
class Metal_GraphicDriver : public Graphic3d_GraphicDriver
{
  DEFINE_STANDARD_RTTIEXT(Metal_GraphicDriver, Graphic3d_GraphicDriver)

public:

  //! Constructor.
  //! @param theDisp connection to display (unused on macOS but kept for API compatibility)
  //! @param theToInitialize perform initialization of Metal context on construction
  Standard_EXPORT Metal_GraphicDriver(const occ::handle<Aspect_DisplayConnection>& theDisp,
                                      bool theToInitialize = true);

  //! Destructor.
  Standard_EXPORT ~Metal_GraphicDriver() override;

  //! Release Metal context.
  Standard_EXPORT void ReleaseContext();

  //! Perform initialization of Metal context.
  Standard_EXPORT bool InitContext();

  //! Request limit of graphic resource of specific type.
  Standard_EXPORT int InquireLimit(const Graphic3d_TypeOfLimit theType) const override;

public: //! @name Structure and View management

  Standard_EXPORT occ::handle<Graphic3d_CStructure> CreateStructure(
    const occ::handle<Graphic3d_StructureManager>& theManager) override;

  Standard_EXPORT void RemoveStructure(occ::handle<Graphic3d_CStructure>& theCStructure) override;

  Standard_EXPORT occ::handle<Graphic3d_CView> CreateView(
    const occ::handle<Graphic3d_StructureManager>& theMgr) override;

  Standard_EXPORT void RemoveView(const occ::handle<Graphic3d_CView>& theView) override;

  //! Create Metal window from native window.
  //! @param theNativeWindow native window holder
  //! @param theSizeWindow object defining window dimensions
  Standard_EXPORT virtual occ::handle<Metal_Window> CreateRenderWindow(
    const occ::handle<Aspect_Window>& theNativeWindow,
    const occ::handle<Aspect_Window>& theSizeWindow);

public: //! @name Text and other utilities

  Standard_EXPORT void TextSize(const occ::handle<Graphic3d_CView>& theView,
                                const char* theText,
                                float theHeight,
                                float& theWidth,
                                float& theAscent,
                                float& theDescent) const override;

  Standard_EXPORT float DefaultTextHeight() const override;

  Standard_EXPORT bool ViewExists(const occ::handle<Aspect_Window>& theWindow,
                                  occ::handle<Graphic3d_CView>& theView) override;

public: //! @name Layer management

  Standard_EXPORT void InsertLayerBefore(const Graphic3d_ZLayerId theNewLayerId,
                                         const Graphic3d_ZLayerSettings& theSettings,
                                         const Graphic3d_ZLayerId theLayerAfter) override;

  Standard_EXPORT void InsertLayerAfter(const Graphic3d_ZLayerId theNewLayerId,
                                        const Graphic3d_ZLayerSettings& theSettings,
                                        const Graphic3d_ZLayerId theLayerBefore) override;

  Standard_EXPORT void RemoveZLayer(const Graphic3d_ZLayerId theLayerId) override;

  Standard_EXPORT void SetZLayerSettings(const Graphic3d_ZLayerId theLayerId,
                                         const Graphic3d_ZLayerSettings& theSettings) override;

public: //! @name Options and VBO control

  //! Return the visualization options.
  const Metal_Caps& Options() const { return *myCaps; }

  //! Return the visualization options for modification.
  Metal_Caps& ChangeOptions() { return *myCaps; }

  //! Specify swap buffer behavior.
  Standard_EXPORT void SetBuffersNoSwap(bool theIsNoSwap);

  //! VBO usage control (no-op on Metal, VBOs always used).
  Standard_EXPORT void EnableVBO(bool theToTurnOn) override;

  //! Returns TRUE if vertical synchronization with display refresh rate (VSync) should be used.
  Standard_EXPORT bool IsVerticalSync() const override;

  //! Set if vertical synchronization with display refresh rate (VSync) should be used.
  Standard_EXPORT void SetVerticalSync(bool theToEnable) override;

  //! Returns information about GPU memory usage.
  Standard_EXPORT bool MemoryInfo(size_t& theFreeBytes,
                                  TCollection_AsciiString& theInfo) const override;

public: //! @name Context access

  //! Method to retrieve valid Metal context.
  //! Could return NULL-handle if no window created by this driver.
  Standard_EXPORT const occ::handle<Metal_Context>& GetSharedContext() const;

  //! Set device lost flag for redrawn views.
  Standard_EXPORT void setDeviceLost();

public: //! @name State counters

  //! State counter for Metal structures.
  Metal_StateCounter* GetStateCounter() const { return &myStateCounter; }

  //! Returns unique ID for primitive arrays.
  size_t GetNextPrimitiveArrayUID() const { return myUIDGenerator.Increment(); }

protected:

  occ::handle<Metal_Caps>    myCaps;           //!< Capabilities configuration
  occ::handle<Metal_Context> mySharedContext;  //!< Shared Metal context

  NCollection_Map<occ::handle<Metal_View>>   myMapOfView;      //!< Map of views
  NCollection_DataMap<int, Metal_Structure*> myMapOfStructure; //!< Map of structures

  mutable Metal_StateCounter myStateCounter;   //!< State counter for structures
  mutable Metal_StateCounter myUIDGenerator;   //!< Unique ID counter for primitive arrays
};

#endif // Metal_GraphicDriver_HeaderFile
