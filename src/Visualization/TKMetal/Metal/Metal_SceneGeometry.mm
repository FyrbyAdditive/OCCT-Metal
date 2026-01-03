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

#import "Metal_SceneGeometry.hxx"
#import "Metal_Context.hxx"

#import <Metal/Metal.h>
#import <simd/simd.h>

IMPLEMENT_STANDARD_RTTIEXT(Metal_GeometryMesh, Metal_Resource)
IMPLEMENT_STANDARD_RTTIEXT(Metal_SceneGeometry, Standard_Transient)

//=================================================================================================
// Metal_GeometryMesh
//=================================================================================================

Metal_GeometryMesh::Metal_GeometryMesh(const TCollection_AsciiString& theId)
: myId(theId),
  myVertexBuffer(nil),
  myNormalBuffer(nil),
  myIndexBuffer(nil),
  myVertexCount(0),
  myTriangleCount(0),
  myMaterialIndex(0),
  myEstimatedSize(0),
  myNeedsUpload(true)
{
}

//=================================================================================================

Metal_GeometryMesh::~Metal_GeometryMesh()
{
  Release(nullptr);
}

//=================================================================================================

void Metal_GeometryMesh::SetVertices(const float* theVertices, int theCount)
{
  myVertexData.Clear();
  myVertexCount = theCount;
  myBounds = Metal_BoundingBox();

  for (int i = 0; i < theCount; ++i)
  {
    float x = theVertices[i * 3 + 0];
    float y = theVertices[i * 3 + 1];
    float z = theVertices[i * 3 + 2];

    myVertexData.Append(x);
    myVertexData.Append(y);
    myVertexData.Append(z);

    myBounds.Add(NCollection_Vec3<float>(x, y, z));
  }

  myNeedsUpload = true;
}

//=================================================================================================

void Metal_GeometryMesh::SetNormals(const float* theNormals, int theCount)
{
  myNormalData.Clear();

  for (int i = 0; i < theCount; ++i)
  {
    myNormalData.Append(theNormals[i * 3 + 0]);
    myNormalData.Append(theNormals[i * 3 + 1]);
    myNormalData.Append(theNormals[i * 3 + 2]);
  }

  myNeedsUpload = true;
}

//=================================================================================================

void Metal_GeometryMesh::SetIndices(const uint32_t* theIndices, int theTriangleCount)
{
  myIndexData.Clear();
  myTriangleCount = theTriangleCount;

  for (int i = 0; i < theTriangleCount * 3; ++i)
  {
    myIndexData.Append(theIndices[i]);
  }

  myNeedsUpload = true;
}

//=================================================================================================

bool Metal_GeometryMesh::Upload(Metal_Context* theCtx)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  if (!myNeedsUpload && myVertexBuffer != nil)
  {
    return true;
  }

  id<MTLDevice> aDevice = theCtx->Device();
  myEstimatedSize = 0;

  // Upload vertices
  if (myVertexData.Size() > 0)
  {
    size_t aSize = myVertexData.Size() * sizeof(float);
    myVertexBuffer = [aDevice newBufferWithBytes:&myVertexData.First()
                                          length:aSize
                                         options:MTLResourceStorageModeShared];
    if (myVertexBuffer == nil)
    {
      return false;
    }
    myEstimatedSize += aSize;
  }

  // Upload normals
  if (myNormalData.Size() > 0)
  {
    size_t aSize = myNormalData.Size() * sizeof(float);
    myNormalBuffer = [aDevice newBufferWithBytes:&myNormalData.First()
                                          length:aSize
                                         options:MTLResourceStorageModeShared];
    if (myNormalBuffer == nil)
    {
      return false;
    }
    myEstimatedSize += aSize;
  }

  // Upload indices
  if (myIndexData.Size() > 0)
  {
    size_t aSize = myIndexData.Size() * sizeof(uint32_t);
    myIndexBuffer = [aDevice newBufferWithBytes:&myIndexData.First()
                                         length:aSize
                                        options:MTLResourceStorageModeShared];
    if (myIndexBuffer == nil)
    {
      return false;
    }
    myEstimatedSize += aSize;
  }

  myNeedsUpload = false;
  return true;
}

//=================================================================================================

void Metal_GeometryMesh::Release(Metal_Context* /*theCtx*/)
{
  myVertexBuffer = nil;
  myNormalBuffer = nil;
  myIndexBuffer = nil;
  myEstimatedSize = 0;
  myNeedsUpload = true;
}

//=================================================================================================
// Metal_SceneGeometry
//=================================================================================================

Metal_SceneGeometry::Metal_SceneGeometry()
: myAccelStructure(nil),
  myInstanceBuffer(nil),
  myIsDirty(true)
{
}

//=================================================================================================

Metal_SceneGeometry::~Metal_SceneGeometry()
{
  Release(nullptr);
}

//=================================================================================================

int Metal_SceneGeometry::AddMesh(const occ::handle<Metal_GeometryMesh>& theMesh)
{
  int anIndex = myMeshes.Size();
  myMeshes.Append(theMesh);
  myIsDirty = true;
  return anIndex;
}

//=================================================================================================

int Metal_SceneGeometry::AddInstance(const Metal_GeometryInstance& theInstance)
{
  int anIndex = myInstances.Size();
  myInstances.Append(theInstance);
  myIsDirty = true;
  return anIndex;
}

//=================================================================================================

void Metal_SceneGeometry::Clear()
{
  myMeshes.Clear();
  myInstances.Clear();
  myIsDirty = true;
}

//=================================================================================================

Metal_BoundingBox Metal_SceneGeometry::ComputeBoundingBox() const
{
  Metal_BoundingBox aBounds;

  for (int i = 0; i < myInstances.Size(); ++i)
  {
    const Metal_GeometryInstance& anInst = myInstances.Value(i);
    if (!anInst.Visible || anInst.Mesh.IsNull())
    {
      continue;
    }

    const Metal_BoundingBox& aMeshBounds = anInst.Mesh->BoundingBox();
    if (!aMeshBounds.IsValid())
    {
      continue;
    }

    // Transform 8 corners of mesh bounding box
    NCollection_Vec3<float> corners[8] = {
      NCollection_Vec3<float>(aMeshBounds.Min.x(), aMeshBounds.Min.y(), aMeshBounds.Min.z()),
      NCollection_Vec3<float>(aMeshBounds.Max.x(), aMeshBounds.Min.y(), aMeshBounds.Min.z()),
      NCollection_Vec3<float>(aMeshBounds.Min.x(), aMeshBounds.Max.y(), aMeshBounds.Min.z()),
      NCollection_Vec3<float>(aMeshBounds.Max.x(), aMeshBounds.Max.y(), aMeshBounds.Min.z()),
      NCollection_Vec3<float>(aMeshBounds.Min.x(), aMeshBounds.Min.y(), aMeshBounds.Max.z()),
      NCollection_Vec3<float>(aMeshBounds.Max.x(), aMeshBounds.Min.y(), aMeshBounds.Max.z()),
      NCollection_Vec3<float>(aMeshBounds.Min.x(), aMeshBounds.Max.y(), aMeshBounds.Max.z()),
      NCollection_Vec3<float>(aMeshBounds.Max.x(), aMeshBounds.Max.y(), aMeshBounds.Max.z())
    };

    for (int c = 0; c < 8; ++c)
    {
      NCollection_Vec4<float> v4(corners[c].x(), corners[c].y(), corners[c].z(), 1.0f);
      NCollection_Vec4<float> transformed = anInst.Transform * v4;
      aBounds.Add(NCollection_Vec3<float>(transformed.x(), transformed.y(), transformed.z()));
    }
  }

  return aBounds;
}

//=================================================================================================

bool Metal_SceneGeometry::UploadMeshes(Metal_Context* theCtx)
{
  for (int i = 0; i < myMeshes.Size(); ++i)
  {
    if (!myMeshes.Value(i)->Upload(theCtx))
    {
      return false;
    }
  }
  return true;
}

//=================================================================================================

bool Metal_SceneGeometry::BuildAccelerationStructure(Metal_Context* theCtx)
{
  if (theCtx == nullptr || theCtx->Device() == nil)
  {
    return false;
  }

  // Check for ray tracing support
  id<MTLDevice> aDevice = theCtx->Device();
  if (![aDevice supportsFamily:MTLGPUFamilyApple6])
  {
    NSLog(@"Metal_SceneGeometry: Device does not support ray tracing");
    return false;
  }

  // Flatten all geometry
  NCollection_Vector<float> aVertices;
  NCollection_Vector<uint32_t> aIndices;
  flattenGeometry(aVertices, aIndices);

  if (aVertices.Size() == 0 || aIndices.Size() == 0)
  {
    return false;
  }

  // Create vertex/index buffers
  id<MTLBuffer> aVertexBuffer = [aDevice newBufferWithBytes:&aVertices.First()
                                                     length:aVertices.Size() * sizeof(float)
                                                    options:MTLResourceStorageModeShared];

  id<MTLBuffer> anIndexBuffer = [aDevice newBufferWithBytes:&aIndices.First()
                                                     length:aIndices.Size() * sizeof(uint32_t)
                                                    options:MTLResourceStorageModeShared];

  // Create geometry descriptor
  MTLAccelerationStructureTriangleGeometryDescriptor* aGeomDesc =
    [[MTLAccelerationStructureTriangleGeometryDescriptor alloc] init];
  aGeomDesc.vertexBuffer = aVertexBuffer;
  aGeomDesc.vertexStride = sizeof(float) * 3;
  aGeomDesc.indexBuffer = anIndexBuffer;
  aGeomDesc.indexType = MTLIndexTypeUInt32;
  aGeomDesc.triangleCount = (NSUInteger)(aIndices.Size() / 3);

  // Create primitive acceleration structure descriptor
  MTLPrimitiveAccelerationStructureDescriptor* aPrimDesc =
    [[MTLPrimitiveAccelerationStructureDescriptor alloc] init];
  aPrimDesc.geometryDescriptors = @[aGeomDesc];

  // Get acceleration structure sizes
  MTLAccelerationStructureSizes aSizes = [aDevice accelerationStructureSizesWithDescriptor:aPrimDesc];

  // Create acceleration structure
  myAccelStructure = [aDevice newAccelerationStructureWithSize:aSizes.accelerationStructureSize];
  if (myAccelStructure == nil)
  {
    NSLog(@"Metal_SceneGeometry: Failed to create acceleration structure");
    return false;
  }

  // Create scratch buffer
  id<MTLBuffer> aScratchBuffer = [aDevice newBufferWithLength:aSizes.buildScratchBufferSize
                                                      options:MTLResourceStorageModePrivate];

  // Build the acceleration structure
  id<MTLCommandQueue> aQueue = theCtx->CommandQueue();
  id<MTLCommandBuffer> aCommandBuffer = [aQueue commandBuffer];
  id<MTLAccelerationStructureCommandEncoder> anEncoder = [aCommandBuffer accelerationStructureCommandEncoder];

  [anEncoder buildAccelerationStructure:myAccelStructure
                             descriptor:aPrimDesc
                          scratchBuffer:aScratchBuffer
                    scratchBufferOffset:0];

  [anEncoder endEncoding];
  [aCommandBuffer commit];
  [aCommandBuffer waitUntilCompleted];

  myIsDirty = false;
  NSLog(@"Metal_SceneGeometry: Built acceleration structure with %d triangles",
        (int)(aIndices.Size() / 3));

  return true;
}

//=================================================================================================

void Metal_SceneGeometry::flattenGeometry(
  NCollection_Vector<float>& theVertices,
  NCollection_Vector<uint32_t>& theIndices) const
{
  theVertices.Clear();
  theIndices.Clear();

  uint32_t aVertexOffset = 0;

  for (int i = 0; i < myInstances.Size(); ++i)
  {
    const Metal_GeometryInstance& anInst = myInstances.Value(i);
    if (!anInst.Visible || anInst.Mesh.IsNull())
    {
      continue;
    }

    const occ::handle<Metal_GeometryMesh>& aMesh = anInst.Mesh;
    int aVertCount = aMesh->VertexCount();
    int aTriCount = aMesh->TriangleCount();

    // Transform and append vertices
    const NCollection_Vector<float>& aSrcVerts = aMesh->myVertexData;
    for (int v = 0; v < aVertCount; ++v)
    {
      NCollection_Vec4<float> p(
        aSrcVerts.Value(v * 3 + 0),
        aSrcVerts.Value(v * 3 + 1),
        aSrcVerts.Value(v * 3 + 2),
        1.0f);

      NCollection_Vec4<float> transformed = anInst.Transform * p;

      theVertices.Append(transformed.x());
      theVertices.Append(transformed.y());
      theVertices.Append(transformed.z());
    }

    // Append indices with offset
    const NCollection_Vector<uint32_t>& aSrcInds = aMesh->myIndexData;
    for (int t = 0; t < aTriCount * 3; ++t)
    {
      theIndices.Append(aSrcInds.Value(t) + aVertexOffset);
    }

    aVertexOffset += aVertCount;
  }
}

//=================================================================================================

void Metal_SceneGeometry::Release(Metal_Context* theCtx)
{
  for (int i = 0; i < myMeshes.Size(); ++i)
  {
    myMeshes.ChangeValue(i)->Release(theCtx);
  }

  myAccelStructure = nil;
  myInstanceBuffer = nil;
  myIsDirty = true;
}

//=================================================================================================

int Metal_SceneGeometry::TotalTriangleCount() const
{
  int aTotal = 0;
  for (int i = 0; i < myInstances.Size(); ++i)
  {
    const Metal_GeometryInstance& anInst = myInstances.Value(i);
    if (anInst.Visible && !anInst.Mesh.IsNull())
    {
      aTotal += anInst.Mesh->TriangleCount();
    }
  }
  return aTotal;
}

//=================================================================================================

int Metal_SceneGeometry::TotalVertexCount() const
{
  int aTotal = 0;
  for (int i = 0; i < myInstances.Size(); ++i)
  {
    const Metal_GeometryInstance& anInst = myInstances.Value(i);
    if (anInst.Visible && !anInst.Mesh.IsNull())
    {
      aTotal += anInst.Mesh->VertexCount();
    }
  }
  return aTotal;
}
