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

#include <Metal_LayerList.hxx>

#include <BVH_LinearBuilder.hxx>
#include <Graphic3d_CullingTool.hxx>
#include <Metal_Context.hxx>
#include <Metal_FrameBuffer.hxx>
#include <Metal_RenderFilter.hxx>
#include <Metal_ShaderManager.hxx>
#include <Metal_Structure.hxx>
#include <Metal_View.hxx>
#include <Metal_Workspace.hxx>
#include <Standard_Dump.hxx>

namespace
{
//! Auxiliary class extending sequence iterator with index.
class Metal_IndexedLayerIterator : public NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator
{
public:
  //! Main constructor.
  Metal_IndexedLayerIterator(const NCollection_List<occ::handle<Graphic3d_Layer>>& theSeq)
      : NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator(theSeq),
        myIndex(1)
  {
  }

  //! Return index of current position.
  int Index() const { return myIndex; }

  //! Move to the next position.
  void Next()
  {
    NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator::Next();
    ++myIndex;
  }

private:
  int myIndex;
};

//! Iterator through layers with filter.
class Metal_FilteredIndexedLayerIterator
{
public:
  //! Main constructor.
  Metal_FilteredIndexedLayerIterator(const NCollection_List<occ::handle<Graphic3d_Layer>>& theSeq,
                                     bool                theToDrawImmediate,
                                     Metal_LayerFilter   theFilterMode,
                                     Graphic3d_ZLayerId  theLayersToProcess)
      : myIter(theSeq),
        myFilterMode(theFilterMode),
        myToDrawImmediate(theToDrawImmediate),
        myLayersToProcess(theLayersToProcess)
  {
    next();
  }

  //! Return true if iterator points to the valid value.
  bool More() const { return myIter.More(); }

  //! Return layer at current position.
  const Metal_Layer& Value() const { return *myIter.Value(); }

  //! Return index of current position.
  int Index() const { return myIter.Index(); }

  //! Go to the next item.
  void Next()
  {
    myIter.Next();
    next();
  }

private:
  //! Look for the nearest item passing filters.
  void next()
  {
    for (; myIter.More(); myIter.Next())
    {
      const occ::handle<Graphic3d_Layer>& aLayer = myIter.Value();
      if (aLayer->IsImmediate() != myToDrawImmediate)
      {
        continue;
      }

      switch (myFilterMode)
      {
        case Metal_LF_All: {
          if (aLayer->LayerId() >= myLayersToProcess)
          {
            return;
          }
          break;
        }
        case Metal_LF_Upper: {
          if (aLayer->LayerId() != Graphic3d_ZLayerId_BotOSD
              && (!aLayer->LayerSettings().IsRaytracable() || aLayer->IsImmediate()))
          {
            return;
          }
          break;
        }
        case Metal_LF_Bottom: {
          if (aLayer->LayerId() == Graphic3d_ZLayerId_BotOSD
              && !aLayer->LayerSettings().IsRaytracable())
          {
            return;
          }
          break;
        }
        case Metal_LF_Single: {
          if (aLayer->LayerId() == myLayersToProcess)
          {
            return;
          }
          break;
        }
        case Metal_LF_RayTracable: {
          if (aLayer->LayerSettings().IsRaytracable() && !aLayer->IsImmediate())
          {
            return;
          }
          break;
        }
      }
    }
  }

private:
  Metal_IndexedLayerIterator myIter;
  Metal_LayerFilter          myFilterMode;
  bool                       myToDrawImmediate;
  Graphic3d_ZLayerId         myLayersToProcess;
};

} // namespace

//! Global layer settings for Metal rendering.
struct Metal_GlobalLayerSettings
{
  MTLCompareFunction DepthFunc;
  bool               DepthMask;
};

//=================================================================================================

Metal_LayerList::Metal_LayerList()
    : myBVHBuilder(new BVH_LinearBuilder<double, 3>(BVH_Constants_LeafNodeSizeSingle,
                                                    BVH_Constants_MaxTreeDepth)),
      myNbStructures(0),
      myImmediateNbStructures(0),
      myModifStateOfRaytraceable(0)
{
  //
}

//=================================================================================================

Metal_LayerList::~Metal_LayerList() = default;

//=================================================================================================

void Metal_LayerList::SetFrustumCullingBVHBuilder(const occ::handle<BVH_Builder3d>& theBuilder)
{
  myBVHBuilder = theBuilder;
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
       aLayerIter.More();
       aLayerIter.Next())
  {
    aLayerIter.ChangeValue()->SetFrustumCullingBVHBuilder(theBuilder);
  }
}

//=================================================================================================

void Metal_LayerList::InsertLayerBefore(const Graphic3d_ZLayerId        theNewLayerId,
                                        const Graphic3d_ZLayerSettings& theSettings,
                                        const Graphic3d_ZLayerId        theLayerAfter)
{
  if (myLayerIds.IsBound(theNewLayerId))
  {
    return;
  }

  occ::handle<Graphic3d_Layer> aNewLayer = new Graphic3d_Layer(theNewLayerId, myBVHBuilder);
  aNewLayer->SetLayerSettings(theSettings);

  occ::handle<Graphic3d_Layer> anOtherLayer;
  if (theLayerAfter != Graphic3d_ZLayerId_UNKNOWN && myLayerIds.Find(theLayerAfter, anOtherLayer))
  {
    for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
         aLayerIter.More();
         aLayerIter.Next())
    {
      if (aLayerIter.Value() == anOtherLayer)
      {
        myLayers.InsertBefore(aNewLayer, aLayerIter);
        break;
      }
    }
  }
  else
  {
    myLayers.Prepend(aNewLayer);
  }

  myLayerIds.Bind(theNewLayerId, aNewLayer);
  myTransparentToProcess.Allocate(myLayers.Size());
}

//=================================================================================================

void Metal_LayerList::InsertLayerAfter(const Graphic3d_ZLayerId        theNewLayerId,
                                       const Graphic3d_ZLayerSettings& theSettings,
                                       const Graphic3d_ZLayerId        theLayerBefore)
{
  if (myLayerIds.IsBound(theNewLayerId))
  {
    return;
  }

  occ::handle<Graphic3d_Layer> aNewLayer = new Graphic3d_Layer(theNewLayerId, myBVHBuilder);
  aNewLayer->SetLayerSettings(theSettings);

  occ::handle<Graphic3d_Layer> anOtherLayer;
  if (theLayerBefore != Graphic3d_ZLayerId_UNKNOWN && myLayerIds.Find(theLayerBefore, anOtherLayer))
  {
    for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
         aLayerIter.More();
         aLayerIter.Next())
    {
      if (aLayerIter.Value() == anOtherLayer)
      {
        myLayers.InsertAfter(aNewLayer, aLayerIter);
        break;
      }
    }
  }
  else
  {
    myLayers.Append(aNewLayer);
  }

  myLayerIds.Bind(theNewLayerId, aNewLayer);
  myTransparentToProcess.Allocate(myLayers.Size());
}

//=================================================================================================

void Metal_LayerList::RemoveLayer(const Graphic3d_ZLayerId theLayerId)
{
  occ::handle<Graphic3d_Layer> aLayerToRemove;
  if (theLayerId <= 0 || !myLayerIds.Find(theLayerId, aLayerToRemove))
  {
    return;
  }

  // move all displayed structures to first layer
  myLayerIds.Find(Graphic3d_ZLayerId_Default)->Append(*aLayerToRemove);

  // remove layer
  myLayers.Remove(aLayerToRemove);
  myLayerIds.UnBind(theLayerId);

  myTransparentToProcess.Allocate(myLayers.Size());
}

//=================================================================================================

void Metal_LayerList::AddStructure(const Metal_Structure*          theStruct,
                                   const Graphic3d_ZLayerId        theLayerId,
                                   const Graphic3d_DisplayPriority thePriority,
                                   bool                            isForChangePriority)
{
  // add structure to associated layer,
  // if layer doesn't exists, display structure in default layer
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerIds.Seek(theLayerId);
  const occ::handle<Graphic3d_Layer>& aLayer =
    aLayerPtr != nullptr ? *aLayerPtr : myLayerIds.Find(Graphic3d_ZLayerId_Default);
  aLayer->Add(theStruct, thePriority, isForChangePriority);
  ++myNbStructures;
  if (aLayer->IsImmediate())
  {
    ++myImmediateNbStructures;
  }
}

//=================================================================================================

void Metal_LayerList::RemoveStructure(const Metal_Structure* theStructure)
{
  const Graphic3d_ZLayerId            aLayerId  = theStructure->ZLayer();
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerIds.Seek(aLayerId);
  const occ::handle<Graphic3d_Layer>& aLayer =
    aLayerPtr != nullptr ? *aLayerPtr : myLayerIds.Find(Graphic3d_ZLayerId_Default);

  Graphic3d_DisplayPriority aPriority = Graphic3d_DisplayPriority_INVALID;

  // remove structure from associated list
  // if the structure is not found there,
  // scan through layers and remove it
  if (aLayer->Remove(theStructure, aPriority))
  {
    --myNbStructures;
    if (aLayer->IsImmediate())
    {
      --myImmediateNbStructures;
    }

    if (aLayer->LayerSettings().IsRaytracable())
    {
      ++myModifStateOfRaytraceable;
    }

    return;
  }

  // scan through layers and remove it
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
       aLayerIter.More();
       aLayerIter.Next())
  {
    const occ::handle<Graphic3d_Layer>& aLayerEx = aLayerIter.ChangeValue();
    if (aLayerEx == aLayer)
    {
      continue;
    }

    if (aLayerEx->Remove(theStructure, aPriority))
    {
      --myNbStructures;
      if (aLayerEx->IsImmediate())
      {
        --myImmediateNbStructures;
      }

      if (aLayerEx->LayerSettings().IsRaytracable())
      {
        ++myModifStateOfRaytraceable;
      }
      return;
    }
  }
}

//=================================================================================================

void Metal_LayerList::InvalidateBVHData(const Graphic3d_ZLayerId theLayerId)
{
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerIds.Seek(theLayerId);
  const occ::handle<Graphic3d_Layer>& aLayer =
    aLayerPtr != nullptr ? *aLayerPtr : myLayerIds.Find(Graphic3d_ZLayerId_Default);
  aLayer->InvalidateBVHData();
}

//=================================================================================================

void Metal_LayerList::ChangeLayer(const Metal_Structure*   theStructure,
                                  const Graphic3d_ZLayerId theOldLayerId,
                                  const Graphic3d_ZLayerId theNewLayerId)
{
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerIds.Seek(theOldLayerId);
  const occ::handle<Graphic3d_Layer>& aLayer =
    aLayerPtr != nullptr ? *aLayerPtr : myLayerIds.Find(Graphic3d_ZLayerId_Default);

  Graphic3d_DisplayPriority aPriority = Graphic3d_DisplayPriority_INVALID;

  // take priority and remove structure from list found by <theOldLayerId>
  // if the structure is not found there, scan through all other layers
  if (aLayer->Remove(theStructure, aPriority, false))
  {
    if (aLayer->LayerSettings().IsRaytracable() && !aLayer->LayerSettings().IsImmediate())
    {
      ++myModifStateOfRaytraceable;
    }

    --myNbStructures;
    if (aLayer->IsImmediate())
    {
      --myImmediateNbStructures;
    }

    // isForChangePriority should be false below, because we want
    // the BVH tree in the target layer to be updated with theStructure
    AddStructure(theStructure, theNewLayerId, aPriority);
    return;
  }

  // scan through layers and remove it
  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
       aLayerIter.More();
       aLayerIter.Next())
  {
    const occ::handle<Metal_Layer>& aLayerEx = aLayerIter.ChangeValue();
    if (aLayerEx == aLayer)
    {
      continue;
    }

    // try to remove structure and get priority value from this layer
    if (aLayerEx->Remove(theStructure, aPriority, true))
    {
      if (aLayerEx->LayerSettings().IsRaytracable() && !aLayerEx->LayerSettings().IsImmediate())
      {
        ++myModifStateOfRaytraceable;
      }

      --myNbStructures;
      if (aLayerEx->IsImmediate())
      {
        --myImmediateNbStructures;
      }

      // isForChangePriority should be false below, because we want
      // the BVH tree in the target layer to be updated with theStructure
      AddStructure(theStructure, theNewLayerId, aPriority);
      return;
    }
  }
}

//=================================================================================================

void Metal_LayerList::ChangePriority(const Metal_Structure*          theStructure,
                                     const Graphic3d_ZLayerId        theLayerId,
                                     const Graphic3d_DisplayPriority theNewPriority)
{
  const occ::handle<Graphic3d_Layer>* aLayerPtr = myLayerIds.Seek(theLayerId);
  const occ::handle<Graphic3d_Layer>& aLayer =
    aLayerPtr != nullptr ? *aLayerPtr : myLayerIds.Find(Graphic3d_ZLayerId_Default);

  Graphic3d_DisplayPriority anOldPriority = Graphic3d_DisplayPriority_INVALID;
  if (aLayer->Remove(theStructure, anOldPriority, true))
  {
    --myNbStructures;
    if (aLayer->IsImmediate())
    {
      --myImmediateNbStructures;
    }

    AddStructure(theStructure, theLayerId, theNewPriority, true);
    return;
  }

  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayerIter(myLayers);
       aLayerIter.More();
       aLayerIter.Next())
  {
    const occ::handle<Metal_Layer>& aLayerEx = aLayerIter.ChangeValue();
    if (aLayerEx == aLayer)
    {
      continue;
    }

    if (aLayerEx->Remove(theStructure, anOldPriority, true))
    {
      --myNbStructures;
      if (aLayerEx->IsImmediate())
      {
        --myImmediateNbStructures;
      }

      AddStructure(theStructure, theLayerId, theNewPriority, true);
      return;
    }
  }
}

//=================================================================================================

void Metal_LayerList::SetLayerSettings(const Graphic3d_ZLayerId        theLayerId,
                                       const Graphic3d_ZLayerSettings& theSettings)
{
  Graphic3d_Layer& aLayer = Layer(theLayerId);
  if (aLayer.LayerSettings().IsRaytracable() != theSettings.IsRaytracable()
      && aLayer.NbStructures() != 0)
  {
    ++myModifStateOfRaytraceable;
  }
  if (aLayer.LayerSettings().IsImmediate() != theSettings.IsImmediate())
  {
    if (theSettings.IsImmediate())
    {
      myImmediateNbStructures += aLayer.NbStructures();
    }
    else
    {
      myImmediateNbStructures -= aLayer.NbStructures();
    }
  }
  aLayer.SetLayerSettings(theSettings);
}

//=================================================================================================

void Metal_LayerList::UpdateCulling(const occ::handle<Metal_Workspace>& theWorkspace,
                                    const bool                          theToDrawImmediate)
{
  // Culling update - simplified for now since BVHTreeSelector is not yet implemented in Metal_View
  // This will be enhanced when view frustum culling is fully implemented
  (void)theWorkspace;
  (void)theToDrawImmediate;
}

//=================================================================================================

void Metal_LayerList::renderLayer(const occ::handle<Metal_Workspace>& theWorkspace,
                                  const Metal_GlobalLayerSettings&    theDefaultSettings,
                                  const Graphic3d_Layer&              theLayer) const
{
  const occ::handle<Metal_Context>& aCtx = theWorkspace->GetContext();

  const Graphic3d_ZLayerSettings& aLayerSettings = theLayer.LayerSettings();

  // Handle depth test
  if (aLayerSettings.ToEnableDepthTest())
  {
    aCtx->SetDepthFunc(theDefaultSettings.DepthFunc);
  }
  else
  {
    aCtx->SetDepthFunc(MTLCompareFunctionAlways);
  }

  // handle depth offset
  const Graphic3d_PolygonOffset anAppliedOffsetParams =
    theWorkspace->SetDefaultPolygonOffset(aLayerSettings.PolygonOffset());

  // handle depth write
  theWorkspace->UseDepthWrite() =
    aLayerSettings.ToEnableDepthWrite() && theDefaultSettings.DepthMask;
  aCtx->SetDepthMask(theWorkspace->UseDepthWrite());

  // render priority list
  const int aViewId = theWorkspace->View()->Identification();
  for (int aPriorityIter = Graphic3d_DisplayPriority_Bottom;
       aPriorityIter <= Graphic3d_DisplayPriority_Topmost;
       ++aPriorityIter)
  {
    const NCollection_IndexedMap<const Graphic3d_CStructure*>& aStructures =
      theLayer.Structures((Graphic3d_DisplayPriority)aPriorityIter);
    for (Metal_Structure::StructIterator aStructIter(aStructures); aStructIter.More();
         aStructIter.Next())
    {
      const Metal_Structure* aStruct = aStructIter.Value();
      if (aStruct->IsCulled() || !aStruct->IsVisible(aViewId))
      {
        continue;
      }

      aStruct->Render(theWorkspace.get());
    }
  }

  // always restore polygon offset between layers rendering
  theWorkspace->SetDefaultPolygonOffset(anAppliedOffsetParams);
}

//=================================================================================================

void Metal_LayerList::Render(const occ::handle<Metal_Workspace>& theWorkspace,
                             const bool                          theToDrawImmediate,
                             const Metal_LayerFilter             theFilterMode,
                             const Graphic3d_ZLayerId            theLayersToProcess,
                             Metal_FrameBuffer*                  theReadDrawFbo,
                             Metal_FrameBuffer*                  theOitAccumFbo) const
{
  const occ::handle<Metal_Context>& aCtx = theWorkspace->GetContext();

  // Remember global settings for depth function and write mask.
  Metal_GlobalLayerSettings aPrevSettings;
  aPrevSettings.DepthFunc = (MTLCompareFunction)aCtx->DepthFunc();
  aPrevSettings.DepthMask = aCtx->DepthMask();
  Metal_GlobalLayerSettings aDefaultSettings = aPrevSettings;

  // Two render filters are used to support transparency draw
  const int aPrevFilter =
    theWorkspace->RenderFilter()
    & ~(int)(Metal_RenderFilter_OpaqueOnly | Metal_RenderFilter_TransparentOnly);
  theWorkspace->SetRenderFilter((Metal_RenderFilter)(aPrevFilter | Metal_RenderFilter_OpaqueOnly));

  myTransparentToProcess.Clear();

  Metal_LayerStack::iterator aStackIter(myTransparentToProcess.Origin());
  int                        aClearDepthLayerPrev = -1, aClearDepthLayer = -1;

  for (Metal_FilteredIndexedLayerIterator aLayerIter(myLayers,
                                                      theToDrawImmediate,
                                                      theFilterMode,
                                                      theLayersToProcess);
       aLayerIter.More();
       aLayerIter.Next())
  {
    const Metal_Layer& aLayer = aLayerIter.Value();

    // make sure to clear depth of previous layers even if layer has no structures
    if (aLayer.LayerSettings().ToClearDepth())
    {
      aClearDepthLayer = aLayerIter.Index();
    }

    if (aLayer.IsCulled())
    {
      continue;
    }

    // Render opaque elements
    theWorkspace->ResetSkippedCounter();
    renderLayer(theWorkspace, aDefaultSettings, aLayer);

    if (theWorkspace->NbSkippedTransparentElements() > 0)
    {
      myTransparentToProcess.Push(&aLayer);
    }

    // Handle depth clearing between layers
    if (aClearDepthLayer > aClearDepthLayerPrev)
    {
      aClearDepthLayerPrev = aClearDepthLayer;
      aCtx->SetDepthMask(true);
      aCtx->ClearDepth();
    }
  }

  // Render transparent layers
  if (!myTransparentToProcess.IsEmpty())
  {
    renderTransparent(theWorkspace, aStackIter, aPrevSettings, theReadDrawFbo, theOitAccumFbo);
  }

  aCtx->SetDepthMask(aPrevSettings.DepthMask);
  aCtx->SetDepthFunc(aPrevSettings.DepthFunc);
  theWorkspace->SetRenderFilter((Metal_RenderFilter)aPrevFilter);
}

//=================================================================================================

void Metal_LayerList::renderTransparent(const occ::handle<Metal_Workspace>& theWorkspace,
                                        Metal_LayerStack::iterator&         theLayerIter,
                                        const Metal_GlobalLayerSettings&    theGlobalSettings,
                                        Metal_FrameBuffer*                  theReadDrawFbo,
                                        Metal_FrameBuffer*                  theOitAccumFbo) const
{
  // Check if current iterator has already reached the end of the stack.
  if (theLayerIter == myTransparentToProcess.Back())
  {
    return;
  }

  const occ::handle<Metal_Context>& aCtx = theWorkspace->GetContext();
  const Metal_LayerStack::iterator  aLayerFrom = theLayerIter;

  const int aPrevFilter =
    theWorkspace->RenderFilter()
    & ~(int)(Metal_RenderFilter_OpaqueOnly | Metal_RenderFilter_TransparentOnly);
  theWorkspace->SetRenderFilter((Metal_RenderFilter)(aPrevFilter | Metal_RenderFilter_TransparentOnly));
  aCtx->SetBlendEnabled(true);
  aCtx->SetBlendFunc(MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha);

  // During blended order-independent transparency pass the depth test
  // should be enabled to discard fragments covered by opaque geometry
  // and depth writing should be disabled.
  Metal_GlobalLayerSettings aGlobalSettings = theGlobalSettings;
  aGlobalSettings.DepthMask = false;
  aCtx->SetDepthMask(false);

  for (theLayerIter = aLayerFrom; theLayerIter != myTransparentToProcess.Back(); ++theLayerIter)
  {
    renderLayer(theWorkspace, aGlobalSettings, *(*theLayerIter));
  }

  // Restore state
  aCtx->SetBlendEnabled(false);
  aCtx->SetBlendFunc(MTLBlendFactorOne, MTLBlendFactorZero);
  aCtx->SetDepthMask(theGlobalSettings.DepthMask);
  aCtx->SetDepthFunc(theGlobalSettings.DepthFunc);

  theWorkspace->SetRenderFilter((Metal_RenderFilter)(aPrevFilter | Metal_RenderFilter_OpaqueOnly));

  // Handle OIT compositing if FBOs are provided (for future enhancement)
  (void)theReadDrawFbo;
  (void)theOitAccumFbo;
}

//=================================================================================================

void Metal_LayerList::DumpJson(Standard_OStream& theOStream, int theDepth) const
{
  OCCT_DUMP_CLASS_BEGIN(theOStream, Metal_LayerList)

  for (NCollection_List<occ::handle<Graphic3d_Layer>>::Iterator aLayersIt(myLayers);
       aLayersIt.More();
       aLayersIt.Next())
  {
    const occ::handle<Graphic3d_Layer>& aLayerId = aLayersIt.Value();
    OCCT_DUMP_FIELD_VALUES_DUMPED(theOStream, theDepth, aLayerId.get())
  }

  OCCT_DUMP_FIELD_VALUE_NUMERICAL(theOStream, myNbStructures)
  OCCT_DUMP_FIELD_VALUE_NUMERICAL(theOStream, myImmediateNbStructures)
  OCCT_DUMP_FIELD_VALUE_NUMERICAL(theOStream, myModifStateOfRaytraceable)
}
