require "fileutils"

module Buildrake
  class Config
    EXECUTE = "execute"
    LIBRARY = "library"
    
    def initialize
      @project_name = ""
      
      @inc_dirs = []
      @lnk_dirs = []
      @srcs = []
      
      @c_flags = []
      @cxx_flags = []
      @ld_flags = []
      
      @macos_archs = [ "i386", "x86_64" ]
      @android_archs = [ "x86", "armeabi-v7a" ]
      @ios_archs = [ "armv7", "armv7s", "arm64" ]
      @windows_visual_studio_versions = [ 2012, 2013, 2015, 2017 ]
      
      @cmake_version = "3.0"
    end
    
    def run( argv )
      send( argv.shift, *argv ) if ! argv.empty?
    end
    
    def generate( *args )
      dir( "build" ){
        build_files
        macos_dir
        ios_dir
        make_dir
        android_dir
        windows_dir
      }
      appveyor_file
    end
    
    def build( *args )
      
    end
    
    def package( *args )
      
    end
    
  private
    def dir( dir, &block )
      FileUtils.mkdir( dir ) if ! Dir.exists?( dir )
      Dir.chdir( dir, &block )
    end
    
    def build_files
      project_name = @project_name.upcase
      
      open( "#{@project_name}.cmake", "wb" ){|f|
        f.puts <<EOS
project(#{@project_name})

set(#{project_name}_LIB_DIR ${CMAKE_CURRENT_LIST_DIR}/lib/${#{project_name}_PLATFORM})
set(#{project_name}_SHARED_LIBS #{@project_name})
set(#{project_name}_STATIC_LIBS ${#{project_name}_LIB_DIR}/lib#{@project_name}.a)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} #{@c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} #{@cxx_flags.join( ' ' )}")

set(#{project_name}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/..)

EOS
        
        @inc_dirs.each{|dir|
          f.puts <<EOS
include_directories(${CMAKE_CURRENT_LIST_DIR}/#{dir})
EOS
        }
        
        @lnk_dirs.each{|dir|
          f.puts <<EOS
link_directories(${CMAKE_CURRENT_LIST_DIR}/#{dir})
EOS
        }
        
        f.puts <<EOS
set(#{project_name}_SRCS)
EOS
        
        @srcs.each{|src|
          f.puts "set(#{project_name}_SRCS ${#{project_name}_SRCS} ${#{project_name}_ROOT_DIR}/#{src})"
        }
        
        case @type
        when LIBRARY
          f.puts <<EOS
add_library(#{@project_name}-shared SHARED ${#{project_name}_SRCS})
SET_TARGET_PROPERTIES(#{@project_name}-shared PROPERTIES OUTPUT_NAME #{@project_name})

add_library(#{@project_name}-static STATIC ${#{project_name}_SRCS})
SET_TARGET_PROPERTIES(#{@project_name}-static PROPERTIES OUTPUT_NAME #{@project_name})
EOS
        end
      }
      
      open( "#{@project_name}_rake.rb", "wb" ){|f|
        f.puts <<EOS
def xcodebuild( project, configuration, sdk, arch, build_dir, *args )
  other_cflags = "-fembed-bitcode"
  other_cplusplusflags = "-fembed-bitcode"
  other_cflags = "\#{other_cflags} \#{ENV[ 'OTHER_CFLAGS' ]}" if ENV.key?( "OTHER_CFLAGS" )
  other_cplusplusflags = "\#{other_cplusplusflags} \#{ENV[ 'OTHER_CPLUSPLUSFLAGS' ]}" if ENV.key?( "OTHER_CPLUSPLUSFLAGS" )
  args.push "OTHER_CFLAGS=\\\"\#{other_cflags}\\\""
  args.push "OTHER_CPLUSPLUSFLAGS=\\\"\#{other_cplusplusflags}\\\""
  
  sh( "xcodebuild -project \#{project} -configuration \#{configuration} -sdk \#{sdk} -arch \#{arch} CONFIGURATION_BUILD_DIR=\#{build_dir} \#{args.join( ' ' )}" )
end

def lipo_create( input_libraries, output_library )
  input_libraries = input_libraries.join( ' ' ) if input_libraries.kind_of?( Array )
  sh( "lipo -create \#{input_libraries} -output \#{output_library}" )
end

def lipo_info( library )
  sh( "lipo -info \#{library}" )
end

desc "Build"
task :build do
  if File.exists?( "CMakeLists.txt" )
    if ! File.exists?( "CMakeCache.txt" )
      cmake
    end
  end
  
  build
end
EOS
      }
    end
    
    def macos_dir
      dir( "macos" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  sh( "cmake -G Xcode ." )
end

def build
  #{@macos_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", "Debug", "macosx", arch, "lib/\#{arch}" )
  }
  ["lib#{@project_name}.a", "lib#{@project_name}.dylib"].each{|library|
    ext = File.extname( library )
    lipo_create( "lib/*/*\#{ext}", library )
    lipo_info( library )
  }
end
EOS
        }
      }
    end
    
    def ios_dir
      dir( "ios" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  sh( "cmake -G Xcode ." )
end

def build
  #{@macos_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", "Debug", "iphonesimulator", arch, "lib/\#{arch}" )
  }
  #{@ios_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", "Debug", "iphoneos", arch, "lib/\#{arch}" )
  }
  ["lib#{@project_name}.a", "lib#{@project_name}.dylib"].each{|library|
    ext = File.extname( library )
    lipo_create( "lib/*/*\#{ext}", library )
    lipo_info( library )
  }
end
EOS
        }
      }
    end
    
    def make_dir
      dir( "make" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  sh( "cmake ." )
end

def build
  sh( "make" )
end
EOS
        }
      }
    end
    
    def android_dir
      project_name = @project_name.upcase
      dir( "android" ){
        dir( "jni" ){
          open( "Application.mk", "wb" ){|f|
            case @type
            when EXECUTE
              f.puts <<EOS
APP_MODULES := sqlite
EOS
            when LIBRARY
              f.puts <<EOS
APP_MODULES := sqlite-static sqlite-shared
EOS
            end
            
            f.puts <<EOS
APP_PLATFORM := android-16
APP_ABI := armeabi-v7a x86
APP_OPTIM := debug
APP_CFLAGS := #{@c_flags.join( ' ' )}
APP_CPPFLAGS := #{@cxx_flags.join( ' ' )}
APP_LDFLAGS := #{@ld_flags.join( ' ' )}
EOS
          }
          
          open( "Android.mk", "wb" ){|f|
            f.puts <<EOS
LOCAL_PATH := $(call my-dir)/..

#{project_name}_ROOT_DIR := $(LOCAL_PATH)/../..
#{project_name}_SRCS :=

EOS
            
            @srcs.each{|src|
              f.puts "#{project_name}_SRCS += $(#{project_name}_ROOT_DIR)/#{src}"
            }
            
            case @type
            when LIBRARY
              f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{@project_name}-static
LOCAL_MODULE_FILENAME := lib#{@project_name}
LOCAL_SRC_FILES := $(#{project_name}_SRCS)
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := #{@project_name}-shared
LOCAL_MODULE_FILENAME := lib#{@project_name}
LOCAL_SRC_FILES := $(#{project_name}_SRCS)
include $(BUILD_SHARED_LIBRARY)
EOS
            end
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def build
  puts "ANDROID_NDK=\#{ENV[ 'ANDROID_NDK' ]}"
  ndk_build = "ndk-build"
  ndk_build = "\#{ENV[ 'ANDROID_NDK' ]}/\#{ndk_build}" if ENV.key?( "ANDROID_NDK" )
  sh( "\#{ndk_build} NDK_LIBS_OUT=./lib NDK_OUT=./lib" )
end
EOS
        }
      }
    end
    
    def windows_dir
      dir( "windows" ){
        open( "windows_MT.cmake", "wb" ){|f|
          f.puts <<EOS
set(VariableNames
  CMAKE_C_FLAGS
  CMAKE_C_FLAGS_DEBUG
  CMAKE_C_FLAGS_RELEASE
  CMAKE_CXX_FLAGS
  CMAKE_CXX_FLAGS_DEBUG
  CMAKE_CXX_FLAGS_RELEASE
)
foreach(VariableName ${VariableNames})
  string(REPLACE "/MD" "/MT" ${VariableName} "${${VariableName}}")
endforeach()
EOS
        }
        
        @windows_visual_studio_versions.each{|version|
          [ 32, 64 ].each{|bits|
            dir( "#{version}_#{bits}_MD" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
EOS
              }
            }
            
            dir( "#{version}_#{bits}_MT" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../windows_MT.cmake)
EOS
              }
            }
          }
        }
      }
    end
    
    def appveyor_file
      open( "appveyor.yml", "wb" ){|f|
        f.puts <<EOS
environment:
  matrix:
EOS
        
        @windows_visual_studio_versions.each{|version|
          [ 32, 64 ].each{|bits|
            [ "MD", "MT" ].each{|option|
              case version
              when 2012
                f.puts <<EOS
    - APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2013
      GENERATOR: "Visual Studio 11 2012"
EOS
              when 2013
                f.puts <<EOS
    - APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2013
      GENERATOR: "Visual Studio 12 2013"
EOS
              when 2015
                f.puts <<EOS
    - APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2015
      GENERATOR: "Visual Studio 14 2015"
EOS
              when 2017
                f.puts <<EOS
    - APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2017
      GENERATOR: "Visual Studio 15 2017"
EOS
              end
              
              f.puts <<EOS
      NAME: #{version}_#{bits}_#{option}
      DIR: build\\windows\\#{version}_#{bits}_#{option}
EOS
              case bits
              when 32
                f.puts <<EOS
      PLATFORM: Win32
EOS
              when 64
                f.puts <<EOS
      PLATFORM: x64
EOS
              end
              
              f.puts ""
            }
          }
        }
        
        f.puts <<EOS
configuration:
  - Debug
  - Release

before_build:
  - cd "%DIR%"
  - cmake -G"%GENERATOR%" -A"%PLATFORM%" .

build:
  parallel: false

after_build:
  - dir
  - dir "%CONFIGURATION%"

artifacts:
  - path: $(DIR)\\$(CONFIGURATION)
    name: $(NAME)_$(CONFIGURATION)
EOS
      }
    end
  end
end
