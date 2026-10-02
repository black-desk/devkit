cmake_minimum_required(VERSION 3.20)

project(devkit-cmake-test LANGUAGES C CXX)

add_executable(devkit-cmake-test main.cpp)
enable_testing()
add_test(NAME run COMMAND devkit-cmake-test)
