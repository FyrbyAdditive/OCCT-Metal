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

#ifndef Metal_SceneGeometry_HeaderFile
#define Metal_SceneGeometry_HeaderFile

#include <Metal_Resource.hxx>
#include <NCollection_Vec3.hxx>
#include <NCollection_Vec4.hxx>
#include <NCollection_Mat4.hxx>
#include <NCollection_Vector.hxx>
#include <NCollection_DataMap.hxx>
#include <TCollection_AsciiString.hxx>

#ifdef __OBJC__
@protocol MTLBuffer;
@protocol MTLAccelerationStructure;
#endif

class Metal_Context;

//! Bounding box structure for scene geometry.
struct Metal_BoundingBox
{
  NCollection_Vec3<float> Min;  //!< minimum corner
  NCollection_Vec3<float> Max;  //!< maximum corner

  //! Default constructor - invalid bounds.
  Metal_BoundingBox()
  : Min(FLT_MAX, FLT_MAX, FLT_MAX),
    Max(-FLT_MAX, -FLT_MAX, -FLT_MAX) {}

  //! Return true if bounds are valid.
  bool IsValid() const { return Min.x() <= Max.x(); }

  //! Expand bounds to include point.
  void Add(const NCollection_Vec3<float>& thePnt)
  {
    Min.x() = std::min(Min.x(), thePnt.x());
    Min.y() = std::min(Min.y(), thePnt.y());
    Min.z() = std::min(Min.z(), thePnt.z());
    Max.x() = std::max(Max.x(), thePnt.x());
    Max.y() = std::max(Max.y(), thePnt.y());
    Max.z() = std::max(Max.z(), thePnt.z());
  }

  //! Expand bounds to include another box.
  void Add(const Metal_BoundingBox& theBox)
  {
    if (theBox.IsValid())
    {
      Add(theBox.Min);
      Add(theBox.Max);
    }
  }

  //! Return center of bounds.
  NCollection_Vec3<float> Center() const
  {
    return NCollection_Vec3<float>(
      (Min.x() + Max.x()) * 0.5f,
      (Min.y() + Max.y()) * 0.5f,
      (Min.z() + Max.z()) * 0.5f);
  }

  //! Return size of bounds.
  NCollection_Vec3<float> Size() const
  {
    return NCollection_Vec3<float>(
      Max.x() - Min.x(),
      Max.y() - Min.y(),
      Max.z() - Min.z());
  }
};

//! Geometry mesh data for ray tracing - stores vertices, normals, indices.
class Metal_GeometryMesh : public Metal_Resource
{
  DEFINE_STANDARD_RTTIEXT(Metal_GeometryMesh, Metal_Resource)

public:

  //! Constructor.
  Standard_EXPORT Metal_GeometryMesh(const TCollection_AsciiString& theId = "");

  //! Destructor.
  Standard_EXPORT ~Metal_GeometryMesh() override;

  //! Return mesh identifier.
  const TCollection_AsciiString& Id() const { return myId; }

  //! Set vertex data.
  //! @param theVertices array of vertex positions (3 floats per vertex)
  //! @param theCount number of vertices
  Standard_EXPORT void SetVertices(const float* theVertices, int theCount);

  //! Set normal data.
  //! @param theNormals array of vertex normals (3 floats per normal)
  //! @param theCount number of normals
  Standard_EXPORT void SetNormals(const float* theNormals, int theCount);

  //! Set index data.
  //! @param theIndices array of triangle indices (3 per triangle)
  //! @param theTriangleCount number of triangles
  Standard_EXPORT void SetIndices(const uint32_t* theIndices, int theTriangleCount);

  //! Set material index for all triangles.
  void SetMaterialIndex(int theMaterialId) { myMaterialIndex = theMaterialId; }

  //! Return material index.
  int MaterialIndex() const { return myMaterialIndex; }

  //! Return vertex count.
  int VertexCount() const { return myVertexCount; }

  //! Return triangle count.
  int TriangleCount() const { return myTriangleCount; }

  //! Return bounding box.
  const Metal_BoundingBox& BoundingBox() const { return myBounds; }

  //! Upload to GPU buffers.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool Upload(Metal_Context* theCtx);

  //! Return true if GPU buffers are ready.
  bool IsUploaded() const { return myVertexBuffer != nullptr; }

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx) override;

  //! Return estimated GPU memory usage.
  size_t EstimatedDataSize() const override { return myEstimatedSize; }

#ifdef __OBJC__
  //! Return vertex buffer.
  id<MTLBuffer> VertexBuffer() const { return myVertexBuffer; }

  //! Return normal buffer.
  id<MTLBuffer> NormalBuffer() const { return myNormalBuffer; }

  //! Return index buffer.
  id<MTLBuffer> IndexBuffer() const { return myIndexBuffer; }
#endif

protected:

  TCollection_AsciiString myId;                    //!< mesh identifier
  NCollection_Vector<float> myVertexData;          //!< CPU vertex data
  NCollection_Vector<float> myNormalData;          //!< CPU normal data
  NCollection_Vector<uint32_t> myIndexData;        //!< CPU index data

#ifdef __OBJC__
  id<MTLBuffer> myVertexBuffer;                    //!< GPU vertex buffer
  id<MTLBuffer> myNormalBuffer;                    //!< GPU normal buffer
  id<MTLBuffer> myIndexBuffer;                     //!< GPU index buffer
#else
  void* myVertexBuffer;
  void* myNormalBuffer;
  void* myIndexBuffer;
#endif

  Metal_BoundingBox myBounds;                      //!< bounding box
  int myVertexCount;                               //!< number of vertices
  int myTriangleCount;                             //!< number of triangles
  int myMaterialIndex;                             //!< material index
  size_t myEstimatedSize;                          //!< GPU memory estimate
  bool myNeedsUpload;                              //!< dirty flag
};

//! Geometry instance - references a mesh with transformation.
struct Metal_GeometryInstance
{
  occ::handle<Metal_GeometryMesh> Mesh;           //!< referenced mesh
  NCollection_Mat4<float> Transform;               //!< instance transform
  NCollection_Mat4<float> TransformInverse;        //!< inverse transform (for normals)
  int MaterialOverride;                            //!< material override (-1 = use mesh material)
  bool Visible;                                    //!< visibility flag

  //! Default constructor.
  Metal_GeometryInstance()
  : MaterialOverride(-1),
    Visible(true)
  {
    Transform.InitIdentity();
    TransformInverse.InitIdentity();
  }

  //! Set transform and compute inverse.
  void SetTransform(const NCollection_Mat4<float>& theTransform)
  {
    Transform = theTransform;
    TransformInverse = theTransform.IsIdentity() ?
      NCollection_Mat4<float>() : theTransform.IsInvertible() ?
        theTransform.IsInverted() : NCollection_Mat4<float>();
  }
};

//! Scene geometry manager for ray tracing.
//! Manages meshes, instances, and builds acceleration structures.
class Metal_SceneGeometry : public Standard_Transient
{
  DEFINE_STANDARD_RTTIEXT(Metal_SceneGeometry, Standard_Transient)

public:

  //! Constructor.
  Standard_EXPORT Metal_SceneGeometry();

  //! Destructor.
  Standard_EXPORT ~Metal_SceneGeometry();

  //! Add a geometry mesh to the scene.
  //! @param theMesh geometry mesh
  //! @return mesh index in scene
  Standard_EXPORT int AddMesh(const occ::handle<Metal_GeometryMesh>& theMesh);

  //! Get mesh by index.
  const occ::handle<Metal_GeometryMesh>& Mesh(int theIndex) const
  {
    return myMeshes.Value(theIndex);
  }

  //! Return number of meshes.
  int MeshCount() const { return myMeshes.Size(); }

  //! Add geometry instance.
  //! @param theInstance instance data
  //! @return instance index
  Standard_EXPORT int AddInstance(const Metal_GeometryInstance& theInstance);

  //! Get instance by index.
  Metal_GeometryInstance& Instance(int theIndex)
  {
    return myInstances.ChangeValue(theIndex);
  }

  //! Return number of instances.
  int InstanceCount() const { return myInstances.Size(); }

  //! Clear all geometry.
  Standard_EXPORT void Clear();

  //! Return scene bounding box (transformed).
  Standard_EXPORT Metal_BoundingBox ComputeBoundingBox() const;

  //! Upload all meshes to GPU.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool UploadMeshes(Metal_Context* theCtx);

  //! Build acceleration structure for ray tracing.
  //! @param theCtx Metal context
  //! @return true on success
  Standard_EXPORT bool BuildAccelerationStructure(Metal_Context* theCtx);

  //! Return true if acceleration structure is valid.
  bool HasAccelerationStructure() const { return myAccelStructure != nullptr; }

  //! Mark geometry as modified (needs rebuild).
  void SetDirty() { myIsDirty = true; }

  //! Return true if geometry was modified.
  bool IsDirty() const { return myIsDirty; }

  //! Release GPU resources.
  Standard_EXPORT void Release(Metal_Context* theCtx);

  //! Return total triangle count.
  Standard_EXPORT int TotalTriangleCount() const;

  //! Return total vertex count.
  Standard_EXPORT int TotalVertexCount() const;

#ifdef __OBJC__
  //! Return acceleration structure.
  id<MTLAccelerationStructure> AccelerationStructure() const { return myAccelStructure; }

  //! Return instance buffer for instanced ray tracing.
  id<MTLBuffer> InstanceBuffer() const { return myInstanceBuffer; }

  //! Return per-triangle material index buffer.
  id<MTLBuffer> MaterialIndexBuffer() const { return myMaterialIndexBuffer; }
#endif

  //! Return material indices array (one per triangle).
  const NCollection_Vector<int32_t>& MaterialIndices() const { return myMaterialIndices; }

protected:

  //! Flatten geometry into single vertex/index/material arrays for BVH build.
  Standard_EXPORT void flattenGeometry(
    NCollection_Vector<float>& theVertices,
    NCollection_Vector<uint32_t>& theIndices,
    NCollection_Vector<int32_t>& theMaterialIndices) const;

protected:

  NCollection_Vector<occ::handle<Metal_GeometryMesh>> myMeshes;    //!< geometry meshes
  NCollection_Vector<Metal_GeometryInstance> myInstances;          //!< instances

#ifdef __OBJC__
  id<MTLAccelerationStructure> myAccelStructure;                  //!< BVH acceleration structure
  id<MTLBuffer> myInstanceBuffer;                                 //!< instance transforms buffer
  id<MTLBuffer> myMaterialIndexBuffer;                            //!< per-triangle material indices
#else
  void* myAccelStructure;
  void* myInstanceBuffer;
  void* myMaterialIndexBuffer;
#endif

  NCollection_Vector<int32_t> myMaterialIndices;                  //!< per-triangle material indices (CPU)
  bool myIsDirty;                                                 //!< geometry modified flag
};

DEFINE_STANDARD_HANDLE(Metal_GeometryMesh, Metal_Resource)
DEFINE_STANDARD_HANDLE(Metal_SceneGeometry, Standard_Transient)

#endif // Metal_SceneGeometry_HeaderFile
