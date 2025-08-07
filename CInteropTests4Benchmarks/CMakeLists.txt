cmake_minimum_required(VERSION 3.6)
project(ebur128)

set(CMAKE_CXX_STANDARD 17)
set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")

add_library(ebur128_lib ebur128.c ebur128.h)

if (ENABLE_CLANG_TIDY)
    set_target_properties(ebur128_lib PROPERTIES CXX_CLANG_TIDY "${CLANG_TIDY_COMMAND}")
endif ()

if (ENABLE_TEST)
        enable_testing()
        if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
                cmake_policy(SET CMP0135 NEW)
        endif()

        if (NOT GTest_FOUND)
            # Specify release version from https://github.com/google/googletest/releases
            set(GTEST_VERSION "v1.14.0")
            MESSAGE(STATUS "Fetching GoogleTest ${GTEST_VERSION} from GitHub")
            # Let CMake fetch Google Test for us.
            # https://github.com/google/googletest/tree/main/googletest#incorporating-into-an-existing-cmake-project
            include(FetchContent)

            FetchContent_Declare(
                    googletest
                    URL "https://github.com/google/googletest/archive/refs/tags/${GTEST_VERSION}.zip"
            )
            # For Windows: Prevent overriding the parent project's compiler/linker settings
            set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
            FetchContent_MakeAvailable(googletest)
        endif()

        # Download real-world test audio file
        set(TEST_AUDIO_URL "https://upload.wikimedia.org/wikipedia/commons/6/69/Internationale-ru.ogg")
        set(TEST_AUDIO_FILE "${CMAKE_CURRENT_BINARY_DIR}/Internationale-ru.ogg")
        
        if(NOT EXISTS "${TEST_AUDIO_FILE}")
            MESSAGE(STATUS "Downloading real-world test audio file: ${TEST_AUDIO_URL}")
            file(DOWNLOAD "${TEST_AUDIO_URL}" "${TEST_AUDIO_FILE}"
                 SHOW_PROGRESS
                 STATUS DOWNLOAD_STATUS
                 LOG DOWNLOAD_LOG)
            
            list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
            if(NOT STATUS_CODE EQUAL 0)
                MESSAGE(WARNING "Failed to download test audio file: ${DOWNLOAD_LOG}")
            else()
                MESSAGE(STATUS "Successfully downloaded test audio file to: ${TEST_AUDIO_FILE}")
            endif()
        endif()

        # Test target declarations.
        add_executable(ebur128_test ebur128_test.cpp)
        target_include_directories(ebur128_test PRIVATE "${GMOCK_INCLUDE_DIRS}" "${GTEST_INCLUDE_DIRS}")
        target_link_libraries(ebur128_test GTest::gtest_main ebur128_lib)
        
        # Define the path to the test audio file for the test executable
        target_compile_definitions(ebur128_test PRIVATE TEST_AUDIO_FILE_PATH="${TEST_AUDIO_FILE}")
        
        include(GoogleTest)
        gtest_discover_tests(ebur128_test)

        add_custom_target(
                runebur128Test
                COMMAND ${CMAKE_CURRENT_BINARY_DIR}/ebur128_test
        )
        add_dependencies(runebur128Test ebur128_test)
endif ()
