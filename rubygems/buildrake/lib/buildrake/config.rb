require "buildrake/command"

module Buildrake
  class Config
    include BuildrakeCommand
    
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
      
      @c_flags = {}
      @cxx_flags = {}
      @ld_flags = {}
      
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
      
      [ :make, :macos, :ios, :android, :windows ].each{|platform|
        [ :debug, :release ].each{|configuration|
          case platform
          when :windows
            flags = [ "/W4" ]
          else
            flags = [ "-g -Wall" ]
            case configuration
            when :debug
              flags.push "-UNDEBUG"
            when :release
              flags.push "-DNDEBUG"
            end
            
            case platform
            when :macos, :ios
              flags.push "-fembed-bitcode"
            end
          end
          
          c_flag( platform, configuration, flags )
          cxx_flag( platform, configuration, flags )
          ld_flag( platform, configuration, [ "" ] )
        }
      }
    end
    
    def c_flag( platform, configuration, flags )
      @c_flags[ platform ] = {} if ! @c_flags.key?( platform )
      @c_flags[ platform ][ configuration ] = flags
    end
    
    def cxx_flag( platform, configuration, flags )
      @cxx_flags[ platform ] = {} if ! @cxx_flags.key?( platform )
      @cxx_flags[ platform ][ configuration ] = flags
    end
    
    def ld_flag( platform, configuration, flags )
      @ld_flags[ platform ] = {} if ! @ld_flags.key?( platform )
      @ld_flags[ platform ][ configuration ] = flags
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
      mkdir( "build" ){
        generate_common_build_files
        generate_macos_build_files
        generate_ios_build_files
        generate_make_build_files
        generate_android_build_files
        generate_windows_build_files
      }
      generate_appveyor_file
    end
    
    def build( platform, configuration = "debug" )
      env( "CONFIGURATION", configuration.capitalize )
      platforms( platform ).each{|platform|
        chdir( "build/#{platform}" ){
          sh( "rake build" ) if file?( "Rakefile" )
        }
      }
    end
    
    def clean( *args )
      platforms( *args ).each{|platform|
        chdir( "build/#{platform}" ){
          sh( "rake clean" ) if file?( "Rakefile" )
        }
      }
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
        platforms.push :android if env?( "ANDROID_NDK" )
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
    def generate_common_build_files
      open( "#{@project_name}.cmake", "wb" ){|f|
        f.puts <<EOS
project(#{@project_name})

set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_MODULE_LINKER_FLAGS_DEBUG "${CMAKE_MODULE_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")

set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_MODULE_LINKER_FLAGS_RELEASE "${CMAKE_MODULE_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")

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
require "buildrake/command"
extend BuildrakeCommand

env( "CONFIGURATION", "Debug" ) if ! env?( "CONFIGURATION" )
puts "CONFIGURATION=\#{env( 'CONFIGURATION' )}"

def xcodebuild( project, configuration, sdk, arch, build_dir, *args )
  sh( "xcodebuild -project \#{project} -configuration \#{configuration} -sdk \#{sdk} -arch \#{arch} CONFIGURATION_BUILD_DIR=\#{build_dir} \#{args.join( ' ' )}" )
end

def lipo_create( input_libraries, output_library )
  input_libraries = input_libraries.join( ' ' ) if input_libraries.kind_of?( Array )
  sh( "lipo -create \#{input_libraries} -output \#{output_library}" )
end

def lipo_info( library )
  sh( "lipo -info \#{library}" )
end

def platform_dir_path( platform )
  path = env( "\#{platform.upcase}_PLATFORM_DIR" )
  if path.nil?
    case platform
    when :make, :macos
      case RUBY_PLATFORM
      when /darwin/
        path = "macos/\#{\`xcrun --sdk macosx --show-sdk-version\`.chomp}"
      end
    when :ios
      path = "ios/\#{\`xcrun --sdk iphoneos --show-sdk-version\`.chomp}"
    when :android
      path = "android/\#{ENV[ 'ANDROID_NDK' ].split( '-' ).last}"
    else
      path = platform.to_s
    end
  end
  path.chomp( "/" )
end

desc "Build"
task :build do
  find( [ "CMakeLists.txt", "**/CMakeLists.txt" ] ){|path|
    chdir( dirname( path ) ){
      if ! file?( "CMakeCache.txt" )
        cmake
      end
    }
  }
  
  build
end

desc "Clean"
task :clean do
  find( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
    rm( path )
  }
  
  clean
end
EOS
      }
    end
    
    def generate_macos_build_files
      mkdir( "macos" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :macos ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :macos ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :macos ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :macos ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :macos ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :macos ][ :release ].join( ' ' )}")

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
  configuration = env( "CONFIGURATION" )
  #{@macos_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", configuration, "macosx", arch, "out/\#{arch}", "clean build" )
  }
  #{@libraries.keys}.each{|name|
    ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
      ext = extname( library )
      lipo_create( "out/*/*\#{ext}", library )
      lipo_info( library )
    }
  }
  
  src = dirname( __FILE__ )
  dst = "\#{src}/../../lib/\#{platform_dir_path( :macos )}_\#{configuration}"
  #{@libraries.keys}.each{|name|
    find( "lib\#{name}.*" ){|path|
      mkdir( dst )
      mv( "\#{src}/\#{path}", dst )
    }
  }
end

def clean
  find( [ "out", "lib*.*", "*.build", "*.xcodeproj", "Debug", "Release" ] ){|path|
    rm( path )
  }
end
EOS
        }
      }
    end
    
    def generate_ios_build_files
      mkdir( "ios" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :ios ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :ios ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :ios ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :ios ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :ios ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :ios ][ :release ].join( ' ' )}")

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
  return if #{@libraries.empty?}
  
  configuration = env( "CONFIGURATION" )
  #{@macos_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", configuration, "iphonesimulator", arch, "out/\#{arch}", "clean build" )
  }
  #{@ios_archs}.each{|arch|
    xcodebuild( "#{@project_name}.xcodeproj", configuration, "iphoneos", arch, "out/\#{arch}", "clean build" )
  }
  
  #{@libraries.keys}.each{|name|
    ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
      ext = extname( library )
      lipo_create( "out/*/*\#{ext}", library )
      lipo_info( library )
    }
  }
  
  src = dirname( __FILE__ )
  dst = "\#{src}/../../lib/\#{platform_dir_path( :ios )}_\#{configuration}"
  #{@libraries.keys}.each{|name|
    find( "lib\#{name}.*" ){|path|
      mkdir( dst )
      mv( "\#{src}/\#{path}", dst )
    }
  }
end

def clean
  find( [ "out", "lib*.*", "*.build", "*.xcodeproj", "Debug", "Release" ] ){|path|
    rm( path )
  }
end
EOS
        }
      }
    end
    
    def generate_make_build_files
      mkdir( "make" ){
        mkdir( "Debug" ){
          open( "CMakeLists.txt", "wb" ){|f|
            f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} #{@c_flags[ :make ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} #{@cxx_flags[ :make ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS "${CMAKE_LD_FLAGS} #{@ld_flags[ :make ][ :debug ].join( ' ' )}")

set(#{@project_name.upcase}_PLATFORM_PATH make)
include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
EOS
          }
        }
        
        mkdir( "Release" ){
          open( "CMakeLists.txt", "wb" ){|f|
            f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} #{@c_flags[ :make ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} #{@cxx_flags[ :make ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS "${CMAKE_LD_FLAGS} #{@ld_flags[ :make ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_PLATFORM_PATH make)
include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
EOS
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  sh( "cmake ." )
end

def build
  configuration = env( "CONFIGURATION" )
  chdir( configuration ){
    sh( "make" )
    
    src = "\#{dirname( __FILE__ )}/\#{basename( pwd )}"
    dst = "\#{src}/../../../lib/\#{platform_dir_path( :make )}_\#{configuration}"
    #{@libraries.keys}.each{|name|
      find( "lib\#{name}.*" ){|path|
        mkdir( dst )
        mv( "\#{src}/\#{path}", dst )
      }
    }
  }
end

def clean
  find( [ "lib*.*" ] ){|path|
    rm( path )
  }
end
EOS
        }
      }
    end
    
    def generate_android_build_files
      project_name = @project_name.upcase
      mkdir( "android" ){
        mkdir( "jni" ){
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
ifeq ($(APP_OPTIM),debug)
  APP_CFLAGS := #{@c_flags[ :android ][ :debug ].join( ' ' )}
  APP_CPPFLAGS := #{@cxx_flags[ :android ][ :debug ].join( ' ' )}
  APP_LDFLAGS := #{@ld_flags[ :android ][ :debug ].join( ' ' )}
else
  APP_CFLAGS := #{@c_flags[ :android ][ :release ].join( ' ' )}
  APP_CPPFLAGS := #{@cxx_flags[ :android ][ :release ].join( ' ' )}
  APP_LDFLAGS := #{@ld_flags[ :android ][ :release ].join( ' ' )}
endif
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
  android_ndk = env( "ANDROID_NDK" )
  puts "ANDROID_NDK=\#{android_ndk}"
  configuration = env( "CONFIGURATION" )
  app_optim = configuration.downcase
  puts "APP_OPTIM=\#{app_optim}"
  sh( "\#{android_ndk}/ndk-build NDK_LIBS_OUT=./out NDK_OUT=./out APP_OPTIM=\#{app_optim} -B" )
  rm( "libs" )
  find( [ "out/local/*/*.*" ] ).each{|path|
    arch = basename( dirname( path ) )
    mkdir( "libs/\#{arch}" )
    cp( path, "libs/\#{arch}/." )
  }
  
  src = dirname( __FILE__ )
  dst = "\#{src}/../../lib/\#{platform_dir_path( :android )}_\#{configuration}"
  #{@libraries.keys}.each{|name|
    find( "libs/**/lib\#{name}.*" ){|path|
      mkdir( "\#{dst}/\#{path}" )
      mv( "\#{src}/\#{path}", "\#{dst}/\#{path}" )
    }
  }
end

def clean
  find( [ "out", "libs" ] ){|path|
    rm( path )
  }
end
EOS
        }
      }
    end
    
    def generate_windows_build_files
      mkdir( "windows" ){
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
            mkdir( "#{version}_#{arch}_MD" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :windows ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :windows ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_PLATFORM_PATH windows/libs/#{version}_#{arch}_MD)
include(${CMAKE_CURRENT_LIST_DIR}/../../#{@project_name}.cmake)
EOS
              }
            }
            
            mkdir( "#{version}_#{arch}_MT" ){
              open( "CMakeLists.txt", "wb" ){|f|
                f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :windows ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :windows ][ :release ].join( ' ' )}")

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
  find( [ "libs" ] ){|path|
    rm( path )
  }
end
EOS
        }
      }
    end
    
    def generate_appveyor_file
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
