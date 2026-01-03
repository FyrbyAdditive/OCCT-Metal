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

#include <Metal_Workspace.hxx>
#include <Metal_Context.hxx>
#include <Metal_View.hxx>
#include <Metal_ShaderManager.hxx>
#include <Metal_Clipping.hxx>
#include <Aspect_InteriorStyle.hxx>

IMPLEMENT_STANDARD_RTTIEXT(Metal_Workspace, Standard_Transient)

// =======================================================================
// function : Metal_Workspace
// purpose  : Constructor
// =======================================================================
Metal_Workspace::Metal_Workspace(Metal_Context* theCtx, Metal_View* theView)
: myContext(theCtx),
  myView(theView),
  myEncoder(nil),
  myCurrentPipeline(nil),
  myDepthStencilState(nil),
  myHighlightColor(1.0f, 1.0f, 1.0f, 1.0f),
  myIsHighlighting(false),
  myEdgeColor(0.0f, 0.0f, 0.0f, 1.0f),
  myIsEdgeRendering(false),
  myIsWireframeMode(false),
  myIsTransparentMode(false),
  myShaderManager(nullptr),
  myClipping(nullptr),
  myShadingModel(Graphic3d_TypeOfShadingModel_Phong),
  myRenderFilter(Metal_RenderFilter_Empty),
  myUseDepthWrite(true),
  myNbSkippedTransparent(0)
{
  myModelMatrix.InitIdentity();
  myProjectionMatrix.InitIdentity();
}

// =======================================================================
// function : ~Metal_Workspace
// purpose  : Destructor
// =======================================================================
Metal_Workspace::~Metal_Workspace()
{
  myEncoder = nil;
  myCurrentPipeline = nil;
  myDepthStencilState = nil;
}

// =======================================================================
// function : SetEncoder
// purpose  : Set current render command encoder
// =======================================================================
void Metal_Workspace::SetEncoder(id<MTLRenderCommandEncoder> theEncoder)
{
  myEncoder = theEncoder;
}

// =======================================================================
// function : SetAspect
// purpose  : Set current aspect
// =======================================================================
void Metal_Workspace::SetAspect(const occ::handle<Graphic3d_Aspects>& theAspect)
{
  myAspect = theAspect;

  // When aspect changes, we need to update pipeline state
  // This will be more sophisticated when we have proper shader programs
}

// =======================================================================
// function : ApplyPipelineState
// purpose  : Apply current pipeline state to encoder
// =======================================================================
void Metal_Workspace::ApplyPipelineState()
{
  if (myEncoder == nil || myContext == nullptr)
  {
    return;
  }

  // Get pipeline from context based on current aspect
  id<MTLRenderPipelineState> aPipeline = myContext->DefaultPipeline();
  if (aPipeline != nil && aPipeline != myCurrentPipeline)
  {
    [myEncoder setRenderPipelineState:aPipeline];
    myCurrentPipeline = aPipeline;
  }

  // Apply depth-stencil state
  id<MTLDepthStencilState> aDepthState = myContext->DefaultDepthStencilState();
  if (aDepthState != nil && aDepthState != myDepthStencilState)
  {
    [myEncoder setDepthStencilState:aDepthState];
    myDepthStencilState = aDepthState;
  }

  // Set cull mode based on aspect
  if (!myAspect.IsNull())
  {
    // For now, use back-face culling for solid geometry
    if (myAspect->ToDrawEdges() && !myAspect->ToDrawSilhouette())
    {
      [myEncoder setCullMode:MTLCullModeNone];
    }
    else
    {
      [myEncoder setCullMode:MTLCullModeBack];
    }
  }
  else
  {
    [myEncoder setCullMode:MTLCullModeBack];
  }
}

// =======================================================================
// function : ApplyUniforms
// purpose  : Apply uniform data to encoder
// =======================================================================
void Metal_Workspace::ApplyUniforms()
{
  if (myEncoder == nil)
  {
    return;
  }

  // Create uniform buffer with matrices and material properties
  struct Uniforms
  {
    float modelViewMatrix[16];
    float projectionMatrix[16];
    float color[4];
  } aUniforms;

  // Copy matrices
  for (int i = 0; i < 16; ++i)
  {
    aUniforms.modelViewMatrix[i] = myModelMatrix.GetData()[i];
    aUniforms.projectionMatrix[i] = myProjectionMatrix.GetData()[i];
  }

  // Get color from aspect or use default
  if (!myAspect.IsNull())
  {
    Quantity_ColorRGBA aColor = myAspect->InteriorColorRGBA();
    if (myIsHighlighting)
    {
      aColor = myHighlightColor;
    }
    aUniforms.color[0] = aColor.GetRGB().Red();
    aUniforms.color[1] = aColor.GetRGB().Green();
    aUniforms.color[2] = aColor.GetRGB().Blue();
    aUniforms.color[3] = aColor.Alpha();
  }
  else
  {
    aUniforms.color[0] = 1.0f;
    aUniforms.color[1] = 1.0f;
    aUniforms.color[2] = 1.0f;
    aUniforms.color[3] = 1.0f;
  }

  // Pass uniforms to vertex shader at buffer index 1
  // (buffer index 0 is typically for vertex data)
  [myEncoder setVertexBytes:&aUniforms
                     length:sizeof(aUniforms)
                    atIndex:1];

  // Pass uniforms to fragment shader as well
  [myEncoder setFragmentBytes:&aUniforms
                       length:sizeof(aUniforms)
                      atIndex:0];
}

// =======================================================================
// function : SetLightSources
// purpose  : Update light sources for rendering
// =======================================================================
void Metal_Workspace::SetLightSources(const occ::handle<Graphic3d_LightSet>& theLights)
{
  myLightSources = theLights;

  // Update shader manager if available
  if (myShaderManager != nullptr)
  {
    myShaderManager->UpdateLightSources(theLights);
  }
}

// =======================================================================
// function : SetClippingPlanes
// purpose  : Update clipping planes for rendering
// =======================================================================
void Metal_Workspace::SetClippingPlanes(const Graphic3d_SequenceOfHClipPlane& thePlanes)
{
  // Update clipping manager if available
  if (myClipping != nullptr)
  {
    myClipping->Reset();
    myClipping->Add(myContext, thePlanes);
  }

  // Update shader manager if available
  if (myShaderManager != nullptr)
  {
    myShaderManager->UpdateClippingPlanes(thePlanes);
  }
}

// =======================================================================
// function : ApplyLightingUniforms
// purpose  : Apply lighting uniforms to encoder
// =======================================================================
void Metal_Workspace::ApplyLightingUniforms()
{
  if (myEncoder == nil || myShaderManager == nullptr)
  {
    return;
  }

  const Metal_LightUniforms& aLightUniforms = myShaderManager->LightUniforms();

  // Pass lighting uniforms to fragment shader at buffer index 1
  [myEncoder setFragmentBytes:&aLightUniforms
                       length:sizeof(aLightUniforms)
                      atIndex:1];

  // Also pass to vertex shader for Gouraud shading
  [myEncoder setVertexBytes:&aLightUniforms
                     length:sizeof(aLightUniforms)
                    atIndex:3];
}

// =======================================================================
// function : ApplyClippingUniforms
// purpose  : Apply clipping uniforms to encoder
// =======================================================================
void Metal_Workspace::ApplyClippingUniforms()
{
  if (myEncoder == nil || myShaderManager == nullptr)
  {
    return;
  }

  const Metal_ClipPlaneUniforms& aClipUniforms = myShaderManager->ClipPlaneUniforms();

  if (aClipUniforms.PlaneCount > 0)
  {
    // Pass clipping uniforms to fragment shader at buffer index 2
    [myEncoder setFragmentBytes:&aClipUniforms
                         length:sizeof(aClipUniforms)
                        atIndex:2];
  }
}

// =======================================================================
// function : ApplyEdgeUniforms
// purpose  : Apply edge uniforms (uses edge color instead of face color)
// =======================================================================
void Metal_Workspace::ApplyEdgeUniforms()
{
  if (myEncoder == nil)
  {
    return;
  }

  // Create uniform buffer with matrices and edge color
  struct Uniforms
  {
    float modelViewMatrix[16];
    float projectionMatrix[16];
    float color[4];
  } aUniforms;

  // Copy matrices
  for (int i = 0; i < 16; ++i)
  {
    aUniforms.modelViewMatrix[i] = myModelMatrix.GetData()[i];
    aUniforms.projectionMatrix[i] = myProjectionMatrix.GetData()[i];
  }

  // Use edge color
  aUniforms.color[0] = myEdgeColor.GetRGB().Red();
  aUniforms.color[1] = myEdgeColor.GetRGB().Green();
  aUniforms.color[2] = myEdgeColor.GetRGB().Blue();
  aUniforms.color[3] = myEdgeColor.Alpha();

  // Pass uniforms to shaders
  [myEncoder setVertexBytes:&aUniforms
                     length:sizeof(aUniforms)
                    atIndex:1];

  [myEncoder setFragmentBytes:&aUniforms
                       length:sizeof(aUniforms)
                      atIndex:0];
}

// =======================================================================
// function : ApplyEdgePipelineState
// purpose  : Apply pipeline state for edge/line rendering
// =======================================================================
void Metal_Workspace::ApplyEdgePipelineState()
{
  if (myEncoder == nil || myContext == nullptr)
  {
    return;
  }

  // Use line pipeline for edge rendering
  id<MTLRenderPipelineState> aPipeline = myContext->LinePipeline();
  if (aPipeline != nil && aPipeline != myCurrentPipeline)
  {
    [myEncoder setRenderPipelineState:aPipeline];
    myCurrentPipeline = aPipeline;
  }

  // Apply depth-stencil state
  id<MTLDepthStencilState> aDepthState = myContext->DefaultDepthStencilState();
  if (aDepthState != nil && aDepthState != myDepthStencilState)
  {
    [myEncoder setDepthStencilState:aDepthState];
    myDepthStencilState = aDepthState;
  }

  // Disable culling for edge rendering (edges should be visible from both sides)
  [myEncoder setCullMode:MTLCullModeNone];
}

// =======================================================================
// function : ApplyBlendingPipelineState
// purpose  : Apply pipeline state for transparent objects
// =======================================================================
void Metal_Workspace::ApplyBlendingPipelineState()
{
  if (myEncoder == nil || myContext == nullptr)
  {
    return;
  }

  // Use blending pipeline for transparent objects
  id<MTLRenderPipelineState> aPipeline = myContext->BlendingPipeline();
  if (aPipeline != nil && aPipeline != myCurrentPipeline)
  {
    [myEncoder setRenderPipelineState:aPipeline];
    myCurrentPipeline = aPipeline;
  }

  // Use transparent depth state (depth test but no write)
  ApplyTransparentDepthState();

  // Back-face culling is typically kept for transparent objects
  [myEncoder setCullMode:MTLCullModeBack];
}

// =======================================================================
// function : ApplyTransparentDepthState
// purpose  : Apply depth-stencil state for transparent objects
// =======================================================================
void Metal_Workspace::ApplyTransparentDepthState()
{
  if (myEncoder == nil || myContext == nullptr)
  {
    return;
  }

  // Use depth state that tests but doesn't write (for correct transparency)
  id<MTLDepthStencilState> aDepthState = myContext->TransparentDepthStencilState();
  if (aDepthState != nil && aDepthState != myDepthStencilState)
  {
    [myEncoder setDepthStencilState:aDepthState];
    myDepthStencilState = aDepthState;
  }
}

// =======================================================================
// function : ShouldRender
// purpose  : Check if aspect should be rendered based on current filter
// =======================================================================
bool Metal_Workspace::ShouldRender(const occ::handle<Graphic3d_Aspects>& theAspect) const
{
  if (myRenderFilter == Metal_RenderFilter_Empty)
  {
    return true; // No filter, render everything
  }

  if (theAspect.IsNull())
  {
    return true; // No aspect to check, render by default
  }

  // Check opaque vs transparent filter
  const bool isTransparent = theAspect->InteriorColorRGBA().Alpha() < 1.0f;

  if ((myRenderFilter & Metal_RenderFilter_OpaqueOnly) != 0)
  {
    // Render only opaque elements
    if (isTransparent)
    {
      return false;
    }
  }

  if ((myRenderFilter & Metal_RenderFilter_TransparentOnly) != 0)
  {
    // Render only transparent elements
    if (!isTransparent)
    {
      return false;
    }
  }

  // Check fill mode filter
  if ((myRenderFilter & Metal_RenderFilter_FillModeOnly) != 0)
  {
    // Only render filled (solid) geometry, skip wireframe
    if (theAspect->InteriorStyle() == Aspect_IS_EMPTY ||
        theAspect->InteriorStyle() == Aspect_IS_HOLLOW)
    {
      return false;
    }
  }

  return true;
}
