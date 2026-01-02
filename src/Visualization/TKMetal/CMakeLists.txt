project(TKMetal)

# TKMetal is only available on Apple platforms
if (APPLE)
  OCCT_INCLUDE_CMAKE_FILE (adm/cmake/occt_toolkit)

  # Disable PCH for Objective-C++ compatibility
  set_target_properties(TKMetal PROPERTIES DISABLE_PRECOMPILE_HEADERS ON)

  # Link Metal frameworks
  target_link_libraries(TKMetal PRIVATE
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
  )

  # Enable ARC for Objective-C++ files
  target_compile_options(TKMetal PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
  )
endif()
