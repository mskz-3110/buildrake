require "fileutils"

module Buildrake
  class Config
    def self.method_accessor( *names )
      names.each{|name|
        class_eval <<EOS
def #{name}( *args )
  args.empty? ? @#{name} : @#{name} = args.first
end
EOS
      }
    end
    
    method_accessor :project_name
    method_accessor :inc_dirs, :lib_dirs
    method_accessor :c_flags, :cxx_flags, :ld_flags
    method_accessor :windows_c_flags, :windows_cxx_flags, :windows_ld_flags
    method_accessor :windows_archs, :windows_artifact_name, :windows_visual_studio_versions
    method_accessor :macos_archs, :ios_archs
    method_accessor :android_archs, :android_stl, :android_api_level
    method_accessor :cmake_version
    method_accessor :appveyor
    
    EXECUTE = "execute"
    LIBRARY = "library"
    
    def initialize( project_name )
      @project_name = project_name
      
      @inc_dirs = []
      @lib_dirs = []
      
      @c_flags = []
      @cxx_flags = []
      @ld_flags = []
      
      @windows_c_flags = []
      @windows_cxx_flags = []
      @windows_ld_flags = []
      
      @windows_archs = [ "Win32", "x64" ]
      @windows_artifact_name = "$(ARTIFACT_PREFIX)_$(CONFIGURATION)"
      @windows_visual_studio_versions = [ 2012, 2013, 2015, 2017 ]
      
      @macos_archs = [ "i386", "x86_64" ]
      @ios_archs = [ "armv7", "armv7s", "arm64" ]
      
      @android_archs = [ "x86", "armeabi", "armeabi-v7a", "arm64-v8a" ]
      @android_stl = ""
      @android_api_level = 16
      
      @cmake_version = "2.8"
      
      @appveyor = nil
      
      @executes = {}
      @libraries = {}
    end
    
    def execute( name, srcs, libs = [] )
      @executes[ name ] = { :srcs => srcs, :libs => libs }
    end
    
    def library( name, srcs, libs = [] )
      @libraries[ name ] = { :srcs => srcs, :libs => libs }
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
    
    def platform( action, platform )
      Dir.chdir( "build/#{platform}" ){
        sh( "rake #{action}" ) if File.exists?( "Rakefile" )
      }
    end
    
    def build( *args )
      platforms( *args ).each{|platform|
        platform( :build, platform )
      }
    end
    
    def clean( *args )
      platforms( *args ).each{|platform|
        platform( :clean, platform )
      }
    end
    
    def sh( command )
      system( command )
      exitstatus = $?.exitstatus
      raise "Command failed with status (#{exitstatus}): #{command}" if 0 != exitstatus
    end
    
    def platforms( *args )
      platforms = []
      if args.empty?
        case RUBY_PLATFORM
        when /darwin/
          platforms = [ :make, :macos, :ios ]
        else
          platforms = [ :make ]
        end
        platforms.push :android if ENV.key?( "ANDROID_NDK" )
      else
        platforms = args
      end
      platforms
    end
    
    def os_name
      case RUBY_PLATFORM
      when /darwin/
        "macos #{`xcrun --sdk macosx --show-sdk-version`.chomp}"
      else
        RUBY_PLATFORM
      end
    end
    
  private
    def dir( dir, &block )
      FileUtils.mkdir_p( dir ) if ! Dir.exists?( dir )
      Dir.chdir( dir, &block )
    end
    
    def build_files
      open( "#{@project_name}.cmake", "wb" ){|f|
        f.puts <<EOS
project(#{@project_name})

if(${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} #{@windows_c_flags.join( ' ' )}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} #{@windows_cxx_flags.join( ' ' )}")
  set(CMAKE_LD_FLAGS "${CMAKE_LD_FLAGS} #{@windows_ld_flags.join( ' ' )}")
else()
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} #{@c_flags.join( ' ' )}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} #{@cxx_flags.join( ' ' )}")
  set(CMAKE_LD_FLAGS "${CMAKE_LD_FLAGS} #{@ld_flags.join( ' ' )}")
endif()

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_LD_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${CMAKE_LD_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_LD_FLAGS}")
set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} ${CMAKE_LD_FLAGS}")

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/..)

EOS
        
        @inc_dirs.each{|dir|
          dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
          f.puts <<EOS
include_directories(#{dir})
EOS
        }
        
        lib_dirs = []
        @lib_dirs.each{|dir|
          dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
          dir = "#{dir}/${#{@project_name.upcase}_PLATFORM_PATH}"
          lib_dirs.push dir
          f.puts <<EOS
link_directories(#{dir})
EOS
        }
        
        f.puts ""
        
        @executes.each{|name, data|
          f.puts "set(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS)"
          data[ :srcs ].each{|src|
            f.puts "set(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS ${#{@project_name.upcase}_EXE_#{name.upcase}_SRCS} ${#{@project_name.upcase}_ROOT_DIR}/#{src})"
          }
          
          lib_names = []
          data[ :libs ].each{|name|
            f.puts <<EOS
find_library(#{@project_name.upcase}_LIB_#{name.upcase} NAMES lib#{name}.a #{name} PATHS #{lib_dirs.join( ' ' )})
message(#{@project_name.upcase}_LIB_#{name.upcase}=${#{@project_name.upcase}_LIB_#{name.upcase}})
EOS
            lib_names.push "${#{@project_name.upcase}_LIB_#{name.upcase}}"
          }
          
          f.puts <<EOS

add_executable(#{name} ${#{@project_name.upcase}_EXE_#{name.upcase}_SRCS})
target_link_libraries(#{name} #{lib_names.join( ' ' )})
EOS
        }
        
        @libraries.each{|name, data|
          f.puts "set(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)"
          data[ :srcs ].each{|src|
            f.puts "set(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS} ${#{@project_name.upcase}_ROOT_DIR}/#{src})"
          }
          
          lib_names = []
          data[ :libs ].each{|name|
            f.puts <<EOS
find_library(#{@project_name.upcase}_LIB_#{name.upcase} NAMES lib#{name}.a #{name} PATHS #{lib_dirs.join( ' ' )})
message(#{@project_name.upcase}_LIB_#{name.upcase}=${#{@project_name.upcase}_LIB_#{name.upcase}})
EOS
            lib_names.push "${#{@project_name.upcase}_LIB_#{name.upcase}}"
          }
          
          f.puts <<EOS

add_library(#{name}-shared SHARED ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS})
target_link_libraries(#{name}-shared #{lib_names.join( ' ' )})
SET_TARGET_PROPERTIES(#{name}-shared PROPERTIES OUTPUT_NAME #{name})

add_library(#{name}-static STATIC ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS})
target_link_libraries(#{name}-static #{lib_names.join( ' ' )})
SET_TARGET_PROPERTIES(#{name}-static PROPERTIES OUTPUT_NAME #{name})
EOS
        }
      }
      
      open( "#{@project_name}_rake.rb", "wb" ){|f|
        f.puts <<EOS
require "fileutils"

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

def dir( dir, &block )
  FileUtils.mkdir_p( dir ) if ! Dir.exists?( dir )
  Dir.chdir( dir, &block )
end

def platform_dir( platform )
  return ENV[ "\#{platform.upcase}_PLATFORM_DIR" ] if ENV.key?( "\#{platform.upcase}_PLATFORM_DIR" )
  
  case platform
  when :make, :macos
    case RUBY_PLATFORM
    when /darwin/
      "macos/\#{\`xcrun --sdk macosx --show-sdk-version\`.chomp}"
    end
  when :ios
    "ios/\#{\`xcrun --sdk iphoneos --show-sdk-version\`.chomp}"
  when :android
    "android/\#{ENV[ 'ANDROID_NDK' ].split( '-' ).last}"
  else
    platform
  end
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

desc "Clean"
task :clean do
  Dir.glob( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
    FileUtils.rm_rf( path )
  }
  
  clean
end
EOS
      }
    end
    
    def macos_dir
      dir( "macos" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(#{@project_name.upcase}_PLATFORM_PATH macos)
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
  configuration = "Debug"
  configuration = ENV[ 'CONFIGURATION' ] if ENV.key?( 'CONFIGURATION' )
  #{@macos_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", configuration, "macosx", arch, "out/\#{arch}" )
  }
  #{@libraries.keys}.each{|name|
    ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
      ext = File.extname( library )
      lipo_create( "out/*/*\#{ext}", library )
      lipo_info( library )
    }
  }
  
  build_dir = File.dirname( __FILE__ )
  dst = "\#{build_dir}/../../lib/\#{platform_dir( :macos )}"
  #{@libraries.keys}.each{|name|
    Dir.glob( "lib\#{name}.*" ){|path|
      dir( dst )
      FileUtils.move( "\#{build_dir}/\#{path}", dst )
    }
  }
end

def clean
  Dir.glob( [ "out", "lib*.*", "*.build", "*.xcodeproj", "Debug", "Release" ] ){|path|
    FileUtils.rm_rf( path )
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

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(#{@project_name.upcase}_PLATFORM_PATH ios)
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
  if ! #{@libraries.empty?}
    configuration = "Debug"
    configuration = ENV[ 'CONFIGURATION' ] if ENV.key?( 'CONFIGURATION' )
    #{@macos_archs}.each{|arch|
      xcodebuild( "#{@project_name}.xcodeproj", configuration, "iphonesimulator", arch, "out/\#{arch}" )
    }
    #{@ios_archs}.each{|arch|
      xcodebuild( "#{@project_name}.xcodeproj", configuration, "iphoneos", arch, "out/\#{arch}" )
    }
  end
  
  #{@libraries.keys}.each{|name|
    ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
      ext = File.extname( library )
      lipo_create( "out/*/*\#{ext}", library )
      lipo_info( library )
    }
  }
  
  build_dir = File.dirname( __FILE__ )
  dst = "\#{build_dir}/../../lib/\#{platform_dir( :ios )}"
  #{@libraries.keys}.each{|name|
    Dir.glob( "lib\#{name}.*" ){|path|
      dir( dst )
      FileUtils.move( "\#{build_dir}/\#{path}", dst )
    }
  }
end

def clean
  Dir.glob( [ "out", "lib*.*", "*.build", "*.xcodeproj", "Debug", "Release" ] ){|path|
    FileUtils.rm_rf( path )
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

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(#{@project_name.upcase}_PLATFORM_PATH make)
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
  
  build_dir = File.dirname( __FILE__ )
  dst = "\#{build_dir}/../../lib/\#{platform_dir( :make )}"
  #{@libraries.keys}.each{|name|
    Dir.glob( "lib\#{name}.*" ){|path|
      dir( dst )
      FileUtils.move( "\#{build_dir}/\#{path}", dst )
    }
  }
end

def clean
  Dir.glob( [ "lib*.*" ] ){|path|
    FileUtils.rm_rf( path )
  }
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
            modules = []
            @executes.each{|name, data|
              modules.push name
            }
            @libraries.each{|name, data|
              modules.push "#{name}-static #{name}-shared"
            }
            
            f.puts <<EOS
APP_MODULES := #{modules.join( ' ' )}
APP_PLATFORM := android-#{@android_api_level}
APP_ABI := #{@android_archs.join( ' ' )}
APP_OPTIM := debug
APP_CFLAGS := #{@c_flags.join( ' ' )}
APP_CPPFLAGS := #{@cxx_flags.join( ' ' )}
APP_LDFLAGS := #{@ld_flags.join( ' ' )}
EOS
            f.puts "APP_STL := #{@android_stl}" if ! @android_stl.empty?
          }
          
          open( "Android.mk", "wb" ){|f|
            f.puts <<EOS
LOCAL_PATH := $(call my-dir)/..

#{@project_name.upcase}_ROOT_DIR := $(LOCAL_PATH)/../..

EOS
            
            local_settings = [
              "LOCAL_CFLAGS := ",
              "LOCAL_CXXFLAGS := ",
              "LOCAL_LDLIBS := ",
            ]
            
            @inc_dirs.each{|dir|
              dir = "$(#{@project_name.upcase}_ROOT_DIR)/#{dir}" if dir =~ /^\./
              local_settings.push "LOCAL_CFLAGS += -I#{dir}"
              local_settings.push "LOCAL_CXXFLAGS += -I#{dir}"
            }
            
            @lib_dirs.each{|dir|
              dir = "$(#{@project_name.upcase}_ROOT_DIR)/#{dir}" if dir =~ /^\./
              local_settings.push "LOCAL_LDLIBS += -L#{dir}/android/libs/$(TARGET_ARCH_ABI)"
            }
            
            @executes.each{|name, data|
              f.puts "#{@project_name.upcase}_EXE_#{name.upcase}_SRCS :="
              data[ :srcs ].each{|src|
                f.puts "#{@project_name.upcase}_EXE_#{name.upcase}_SRCS += $(#{@project_name.upcase}_ROOT_DIR)/#{src}"
              }
              f.puts ""
              
              ldlibs = []
              data[ :libs ].each{|lib|
                ldlibs.push "LOCAL_LDLIBS += -l#{lib}"
              }
              
              f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ldlibs.join( "\n" )}
include $(BUILD_EXECUTABLE)
EOS
            }
            
            @libraries.each{|name, data|
              f.puts "#{@project_name.upcase}_LIB_#{name.upcase}_SRCS :="
              data[ :srcs ].each{|src|
                f.puts "#{@project_name.upcase}_LIB_#{name.upcase}_SRCS += $(#{@project_name.upcase}_ROOT_DIR)/#{src}"
              }
              
              ldlibs = []
              data[ :libs ].each{|lib|
                ldlibs.push "LOCAL_LDLIBS += -l#{lib}"
              }
              
              f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-static
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ldlibs.join( "\n" )}
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-shared
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ldlibs.join( "\n" )}
include $(BUILD_SHARED_LIBRARY)
EOS
            }
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def build
  puts "ANDROID_NDK=\#{ENV[ 'ANDROID_NDK' ]}"
  sh( "\#{ENV[ 'ANDROID_NDK' ]}/ndk-build NDK_LIBS_OUT=./out NDK_OUT=./out" )
  FileUtils.rm_rf( "libs" ) if Dir.exists?( "libs" )
  Dir.glob( [ "out/local/*/*.*" ] ).each{|path|
    arch = File.basename( File.dirname( path ) )
    FileUtils.mkdir_p( "libs/\#{arch}" ) if ! Dir.exists?( "libs/\#{arch}" )
    FileUtils.cp( path, "libs/\#{arch}/." )
  }
  
  build_dir = File.dirname( __FILE__ )
  dst = "\#{build_dir}/../../lib/\#{platform_dir( :android )}"
  #{@libraries.keys}.each{|name|
    Dir.glob( "libs/**/lib\#{name}.*" ){|path|
      dir( "\#{dst}/\#{path}" )
      FileUtils.move( "\#{build_dir}/\#{path}", "\#{dst}/\#{path}" )
    }
  }
end

def clean
  Dir.glob( [ "out", "libs" ] ){|path|
    FileUtils.rm_rf( path )
  }
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
          @windows_archs.each{|arch|
            dir( "#{version}_#{arch}_MD" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

set(#{@project_name.upcase}_PLATFORM_PATH windows/libs/#{version}_#{arch}_MD)
include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
EOS
              }
            }
            
            dir( "#{version}_#{arch}_MT" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

set(#{@project_name.upcase}_PLATFORM_PATH windows/libs/#{version}_#{arch}_MT)
include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../windows_MT.cmake)
EOS
              }
            }
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def build
end

def clean
  Dir.glob( [ "libs" ] ){|path|
    FileUtils.rm_rf( path )
  }
end
EOS
        }
      }
    end
    
    def appveyor_file
      return if @appveyor.nil?
      
      open( @appveyor, "wb" ){|f|
        f.puts <<EOS
environment:
  matrix:
EOS
        
        @windows_visual_studio_versions.each{|version|
          @windows_archs.each{|arch|
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
      ARTIFACT_PREFIX: #{version}_#{arch}_#{option}
      DIR: build\\windows\\#{version}_#{arch}_#{option}
      PLATFORM: #{arch}
EOS
              
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
  parallel: true

after_build:
  - dir
  - dir "%CONFIGURATION%"
  - mkdir artifacts
  - rename "%CONFIGURATION%" "artifacts/#{@windows_artifact_name.gsub( /(\$\(|\))/, '%' )}"
  - dir /S artifacts

artifacts:
  - path: $(DIR)\\artifacts
    name: #{@windows_artifact_name}

skip_tags: true

EOS
      }
    end
  end
end
