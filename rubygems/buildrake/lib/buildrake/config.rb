module Buildrake
  class Config
    def self.run( argv )
      self.new.public_send( argv.shift, *argv ) if ! argv.empty?
    end
    
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
    method_accessor :root_path
    method_accessor :inc_dirs
    method_accessor :lib_dirs
    method_accessor :c_flags, :cxx_flags, :ld_flags
    method_accessor :platforms, :configs
    method_accessor :windows_runtimes
    method_accessor :macos_archs, :ios_archs
    method_accessor :android_archs, :android_api_level
    method_accessor :cmake_version
    
    def initialize( project_name, root_path )
      @project_name = project_name
      
      @root_path = root_path
      
      @inc_dirs = []
      
      @lib_dirs = {}
      
      @c_flags = {}
      @cxx_flags = {}
      @ld_flags = {}
      
      @platforms = [ :macos, :ios, :android, :linux, :windows ]
      @configs = [ :debug, :release ]
      
      @windows_runtimes = [ "MT", "MD" ]
      
      @macos_archs = [ "x86_64" ]
      @ios_archs = [ "armv7", "armv7s", "arm64" ]
      
      @android_archs = [ "x86", "armeabi-v7a", "arm64-v8a" ]
      @android_api_level = 21
      
      @cmake_version = "2.8"
      
      @executes = {}
      @libraries = {}
      
      @platforms.each{|platform|
        @configs.each{|config|
          c_flags   = []
          cxx_flags = []
          ld_flags  = []
          case platform
          when :windows
            c_flags = [ "/W4" ]
            cxx_flags = c_flags.clone
          else
            c_flags = [ "-g -Wall" ]
            case config
            when :debug
              c_flags.push "-UNDEBUG"
            when :release
              c_flags.push "-DNDEBUG"
            end
            
            case platform
            when :macos, :ios
              c_flags.push "-fembed-bitcode"
            end
            cxx_flags = c_flags.clone
            
            case platform
            when :android
              cxx_flags.push "-fexceptions -frtti"
            end
          end
          
          lib_dir( platform, config, [] )
          c_flag( platform, config, c_flags )
          cxx_flag( platform, config, cxx_flags )
          ld_flag( platform, config, ld_flags )
        }
      }
    end
    
    def lib_dir( platform, config, dirs )
      @lib_dirs[ platform ] = {} if ! @lib_dirs.key?( platform )
      @lib_dirs[ platform ][ config ] = dirs
    end
    
    def c_flag( platform, config, flags )
      @c_flags[ platform ] = {} if ! @c_flags.key?( platform )
      @c_flags[ platform ][ config ] = flags
    end
    
    def cxx_flag( platform, config, flags )
      @cxx_flags[ platform ] = {} if ! @cxx_flags.key?( platform )
      @cxx_flags[ platform ][ config ] = flags
    end
    
    def ld_flag( platform, config, flags )
      @ld_flags[ platform ] = {} if ! @ld_flags.key?( platform )
      @ld_flags[ platform ][ config ] = flags
    end
    
    def execute( name, srcs, libs = [] )
      @executes[ name ] = { :srcs => srcs, :libs => libs }
    end
    
    def library( name, srcs, libs = [] )
      @libraries[ name ] = { :srcs => srcs, :libs => libs }
    end
    
    def setup
      generate
    end
    
    def build
      platform = Rush.env( "PLATFORM" )
      config = Rush.env( "CONFIG" )
      if platform.nil? || config.nil?
        help
      else
        Rush.changed( "build/#{platform}" ){
          Rush.sh( "rake build" ) if Rush.file?( "Rakefile" )
        }
      end
    end
    
    def help
      puts "rake setup"
      puts "rake help"
      @platforms.each{|platform|
        @configs.each{|config|
          case platform
          when :android
            puts "ANDROID_NDK=/tmp/android-ndk-r10e PLATFORM=#{platform} CONFIG=#{config} rake build"
            puts "ANDROID_NDK=/tmp/android-ndk-r10e ANDROID_STL=c++_static PLATFORM=#{platform} CONFIG=#{config} rake build"
            puts "ANDROID_NDK=/tmp/android-ndk-r10e ANDROID_STL=gnustl_static PLATFORM=#{platform} CONFIG=#{config} rake build"
          when :windows
            @windows_runtimes.each{|runtime|
              [ "Win32", "x64" ].each{|arch|
                puts "WINDOWS_VISUAL_STUDIO_VERSION=2017 WINDOWS_RUNTIME=#{runtime} WINDOWS_ARCH=#{arch} CMAKE_GENERATOR=\"Visual Studio 15 2017\" PLATFORM=#{platform} CONFIG=#{config} rake build"
              }
            }
          else
            puts "PLATFORM=#{platform} CONFIG=#{config} rake build"
          end
        }
      }
    end
    
  private
    def lib_name( name )
      lib_name = name
      if /lib([a-zA-Z0-9_]+)\.a/ =~ name
        lib_name = $1
      end
      lib_name
    end
    
    def generate
      Rush.remaked( "build" ){
        generate_common_build_files
        generate_macos_build_files
        generate_ios_build_files
        generate_linux_build_files
        generate_android_build_files
        generate_windows_build_files
      }
    end
    
    def generate_common_build_files
      open( "#{@project_name}.cmake", "wb" ){|f|
        f.puts <<EOS
message(CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
string(TOUPPER #{@project_name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE} #{@project_name.upcase}_LINK_DIRS)
set(#{@project_name.upcase}_LINK_DIRS ${${#{@project_name.upcase}_LINK_DIRS}})
foreach(link_dir IN LISTS #{@project_name.upcase}_LINK_DIRS)
  message(#{@project_name.upcase}_LINK_DIRS=${link_dir})
  link_directories(${link_dir})
endforeach()

project(#{@project_name})

set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")

set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")

EOS
        
        @inc_dirs.each{|dir|
          dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
          f.puts <<EOS
include_directories(#{dir})
EOS
        }
        
        f.puts ""
        
        @executes.each{|name, data|
          f.puts "set(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS)"
          data[ :srcs ].each{|src|
            src = "${#{@project_name.upcase}_ROOT_DIR}/#{src}" if src =~ /^\./
            f.puts "set(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS ${#{@project_name.upcase}_EXE_#{name.upcase}_SRCS} #{src})"
          }
          
          link_lib_names = []
          data[ :libs ].each{|name|
            link_lib_names.push name
          }
          
          f.puts <<EOS

add_executable(#{name} ${#{@project_name.upcase}_EXE_#{name.upcase}_SRCS})
target_link_libraries(#{name} #{link_lib_names.join( ' ' )})
EOS
        }
        
        @libraries.each{|name, data|
          f.puts "set(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)"
          data[ :srcs ].each{|src|
            src = "${#{@project_name.upcase}_ROOT_DIR}/#{src}" if src =~ /^\./
            f.puts "set(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS} #{src})"
          }
          
          link_lib_names = []
          data[ :libs ].each{|name|
            link_lib_name = "#{@project_name.upcase}_LIB_#{name.upcase}"
            f.puts <<EOS
find_library(#{link_lib_name} NAMES lib#{name}.a #{name} PATHS ${#{@project_name.upcase}_LINK_DIRS}})
message(#{link_lib_name}=${#{link_lib_name}})
EOS
            link_lib_names.push "${#{link_lib_name}}"
          }
          
          f.puts <<EOS

add_library(#{name}-shared SHARED ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS})
target_link_libraries(#{name}-shared #{link_lib_names.join( ' ' )})
SET_TARGET_PROPERTIES(#{name}-shared PROPERTIES OUTPUT_NAME #{name})

add_library(#{name}-static STATIC ${#{@project_name.upcase}_LIB_#{name.upcase}_SRCS})
target_link_libraries(#{name}-static #{link_lib_names.join( ' ' )})
SET_TARGET_PROPERTIES(#{name}-static PROPERTIES OUTPUT_NAME #{name})
EOS
        }
      }
      
      open( "#{@project_name}.rb", "wb" ){|f|
        f.puts <<EOS
require "buildrake"

def lipo_create( input_libraries, output_library )
  input_libraries = input_libraries.join( ' ' ) if input_libraries.kind_of?( Array )
  Buildrake::Rush.sh( "lipo -create \#{input_libraries} -output \#{output_library}" )
end

def lipo_info( library )
  Buildrake::Rush.sh( "lipo -info \#{library}" )
end

def platform_path( platform, config )
  path = ""
  case platform
  when "linux"
    if Buildrake::Rush.file?( "/etc/system-release" )
      line = `head -n 1 /etc/system-release`
    else
      line = "unsupported"
    end
    values = line.split( "\s" )
    linux_name = values.shift.downcase
    values.each{|value|
      if /^([0-9]+)\./ =~ value
        linux_name = "\#{linux_name}\#{$1}"
        break
      end
    }
    path = "linux/\#{linux_name}"
  when "macos"
    path = "macos/\#{\`xcrun --sdk macosx --show-sdk-version\`.chomp}"
  when "ios"
    path = "ios/\#{\`xcrun --sdk iphoneos --show-sdk-version\`.chomp}"
  when "android"
    android_ndk_version = Buildrake::Rush.env( "ANDROID_NDK" ).split( '-' ).last.chomp( '/' )
    Buildrake::Rush.env( "ANDROID_NDK_VERSION", android_ndk_version )
    path = "android/\#{android_ndk_version}"
    path = "\#{path}_\#{Buildrake::Rush.env( 'ANDROID_STL' )}" if Buildrake::Rush.env?( 'ANDROID_STL' ) && ! Buildrake::Rush.env( 'ANDROID_STL' ).empty?
  when "windows"
    windows_visual_studio_version = Buildrake::Rush.env( "WINDOWS_VISUAL_STUDIO_VERSION" )
    windows_runtime = Buildrake::Rush.env( "WINDOWS_RUNTIME" )
    windows_arch = Buildrake::Rush.env( "WINDOWS_ARCH" )
    path = "windows/\#{windows_visual_studio_version}_\#{windows_runtime}_\#{windows_arch}"
  end
  "\#{path}_\#{config}"
end

def cmake_files( prefix = "" )
  [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ].map{|path| "\#{prefix}\#{path}"}
end

desc "Build"
task :build do
  Buildrake::Rush.find( cmake_files ){|path|
    Buildrake::Rush.remove( path )
  }
  
  build
end

if Buildrake::Rush.env?( "CONFIG" )
  config = Buildrake::Rush.env( "CONFIG", Buildrake::Rush.pascal_case( Buildrake::Rush.env( 'CONFIG' ) ) )
else
  config = Buildrake::Rush.env( "CONFIG", "Debug" )
end
puts "CONFIG=\#{config}"
Buildrake::Rush.env( "PLATFORM_PATH", "\#{platform_path( Buildrake::Rush.base_name( Buildrake::Rush.full_dir_path ), config )}" ) if ! Buildrake::Rush.env?( "PLATFORM_PATH" )
puts "PLATFORM_PATH=\#{Buildrake::Rush.env( 'PLATFORM_PATH' )}"
EOS
      }
    end
    
    def generate_macos_build_files
      Rush.maked( "macos" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

project(#{@project_name})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :macos ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :macos ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :macos ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :macos ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :macos ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :macos ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :macos ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :macos ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_RELEASE ${#{@project_name.upcase}_LINK_DIRS_RELEASE} #{dir})
EOS
          }
          
          f.puts <<EOS
include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}", File.dirname( __FILE__ ) )

def build
  config = Buildrake::Rush.env( "CONFIG" )
  platform_path = platform_path( "macos", config )
  Buildrake::Rush.remaked( Buildrake::Rush.base_name( platform_path ) ){
    #{@macos_archs}.each{|arch|
      Buildrake::Rush.remaked( arch ){
        Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{config} -DCMAKE_OSX_ARCHITECTURES=\#{arch} --no-warn-unused-cli -DPLATFORM=macos -DCONFIG=\#{config} -DPLATFORM_PATH=\#{platform_path}" )
        Buildrake::Rush.sh( "make clean all" )
      }
    }
    
    #{@libraries.keys}.each{|name|
      ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
        ext_name = Buildrake::Rush.ext_name( library )
        lipo_create( "*/*.\#{ext_name}", library )
        lipo_info( library )
      }
    }
    
    src = Buildrake::Rush.full_dir_path
    dst = "\#{src}/../../../lib/\#{platform_path}"
    #{@libraries.keys}.each{|name|
      Buildrake::Rush.find( "lib\#{name}.*" ){|path|
        Buildrake::Rush.maked( dst ){
          Buildrake::Rush.rename( "\#{src}/\#{path}", "." )
        }
      }
    }
  }
end
EOS
        }
      }
    end
    
    def generate_ios_build_files
      Rush.maked( "ios" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

project(#{@project_name})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :ios ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :ios ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :ios ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :ios ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :ios ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :ios ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :ios ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :ios ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_RELEASE ${#{@project_name.upcase}_LINK_DIRS_RELEASE} #{dir})
EOS
          }
          
          f.puts <<EOS
include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}", File.dirname( __FILE__ ) )

def build
  config = Buildrake::Rush.env( "CONFIG" )
  platform_path = platform_path( "ios", config )
  Buildrake::Rush.remaked( Buildrake::Rush.base_name( platform_path ) ){
    #{@macos_archs}.each{|arch|
      Buildrake::Rush.remaked( arch ){
        Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{config} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=iphonesimulator --no-warn-unused-cli -DPLATFORM=ios -DCONFIG=\#{config} -DPLATFORM_PATH=\#{platform_path}" )
        Buildrake::Rush.sh( "make clean all" )
      }
    }
    
    #{@ios_archs}.each{|arch|
      Buildrake::Rush.remaked( arch ){
        Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{config} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=iphoneos --no-warn-unused-cli -DPLATFORM=ios -DCONFIG=\#{config} -DPLATFORM_PATH=\#{platform_path}" )
        Buildrake::Rush.sh( "make clean all" )
      }
    }
    
    #{@libraries.keys}.each{|name|
      ["lib\#{name}.a", "lib\#{name}.dylib"].each{|library|
        ext_name = Buildrake::Rush.ext_name( library )
        lipo_create( "*/*.\#{ext_name}", library )
        lipo_info( library )
      }
    }
    
    src = Buildrake::Rush.full_dir_path
    dst = "\#{src}/../../../lib/\#{platform_path}"
    #{@libraries.keys}.each{|name|
      Buildrake::Rush.find( "lib\#{name}.*" ){|path|
        Buildrake::Rush.maked( dst ){
          Buildrake::Rush.rename( "\#{src}/\#{path}", "." )
        }
      }
    }
  }
end
EOS
        }
      }
    end
    
    def generate_linux_build_files
      Rush.maked( "linux" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

project(#{@project_name})

if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :linux ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :linux ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :linux ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :linux ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :linux ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :linux ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :linux ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :linux ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_RELEASE ${#{@project_name.upcase}_LINK_DIRS_RELEASE} #{dir})
EOS
          }
          
          f.puts <<EOS
include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}", File.dirname( __FILE__ ) )

def build
  config = Buildrake::Rush.env( "CONFIG" )
  platform_path = platform_path( "linux", config )
  Buildrake::Rush.remaked( Buildrake::Rush.base_name( platform_path ) ){
    Buildrake::Rush.sh( "cmake .. -DCMAKE_BUILD_TYPE=\#{config} --no-warn-unused-cli -DPLATFORM=linux -DCONFIG=\#{config} -DPLATFORM_PATH=\#{platform_path}" )
    Buildrake::Rush.sh( "make clean all" )
    
    src = Buildrake::Rush.full_dir_path
    dst = "\#{src}/../../../lib/\#{platform_path}"
    #{@libraries.keys}.each{|name|
      Buildrake::Rush.find( "lib\#{name}.*" ){|path|
        Buildrake::Rush.maked( dst ){
          Buildrake::Rush.rename( "\#{src}/\#{path}", "." )
        }
      }
    }
  }
end
EOS
        }
      }
    end
    
    def generate_android_build_files
      project_name = @project_name.upcase
      Rush.maked( "android" ){
        Rush.maked( "jni" ){
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
            
            local_settings.push "ifeq ($(APP_OPTIM),debug)"
            @lib_dirs[ :android ][ :debug ].each{|dir|
              dir = "$(#{@project_name.upcase}_ROOT_DIR)/#{dir}" if dir =~ /^\./
              local_settings.push "  LOCAL_LDLIBS += -L#{dir}/libs/$(TARGET_ARCH_ABI)"
            }
            local_settings.push "else"
            @lib_dirs[ :android ][ :release ].each{|dir|
              dir = "$(#{@project_name.upcase}_ROOT_DIR)/#{dir}" if dir =~ /^\./
              local_settings.push "  LOCAL_LDLIBS += -L#{dir}/libs/$(TARGET_ARCH_ABI)"
            }
            local_settings.push "endif"
            
            @executes.each{|name, data|
              f.puts "#{@project_name.upcase}_EXE_#{name.upcase}_SRCS :="
              data[ :srcs ].each{|src|
                src = "$(#{@project_name.upcase}_ROOT_DIR)/#{src}" if src =~ /^\./
                f.puts "#{@project_name.upcase}_EXE_#{name.upcase}_SRCS += #{src}"
              }
              
              ld_libs = []
              data[ :libs ].each{|lib|
                case Rush.ext_name( lib )
                when "a"
                  ld_libs.push "LOCAL_LDLIBS += -l#{lib_name( lib )}"
                else
                  ld_libs.push "LOCAL_LDLIBS += -l#{lib}"
                end
              }
              
              f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_EXE_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ld_libs.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_EXECUTABLE)
EOS
            }
            
            @libraries.each{|name, data|
              f.puts "#{@project_name.upcase}_LIB_#{name.upcase}_SRCS :="
              data[ :srcs ].each{|src|
                src = "$(#{@project_name.upcase}_ROOT_DIR)/#{src}" if src =~ /^\./
                f.puts "#{@project_name.upcase}_LIB_#{name.upcase}_SRCS += #{src}"
              }
              
              ld_libs = []
              data[ :libs ].each{|lib|
                case Rush.ext_name( lib )
                when "a"
                  ld_libs.push "LOCAL_LDLIBS += -l#{lib_name( lib )}"
                else
                  ld_libs.push "LOCAL_LDLIBS += -l#{lib}"
                end
              }
              
              f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-static
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ld_libs.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-shared
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{@project_name.upcase}_LIB_#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
#{ld_libs.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_SHARED_LIBRARY)
EOS
            }
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}", File.dirname( __FILE__ ) )

def build
  android_ndk = Buildrake::Rush.env( "ANDROID_NDK" )
  abort( "Not found ANDROID_NDK: \#{android_ndk}" ) if android_ndk.nil? || ! Buildrake::Rush.dir?( android_ndk )
  android_stl = Buildrake::Rush.env( "ANDROID_STL" )
  puts "ANDROID_NDK=\#{android_ndk}"
  puts "ANDROID_STL=\#{android_stl}"
  config = Buildrake::Rush.env( "CONFIG" )
  app_optim = config.downcase
  puts "APP_OPTIM=\#{app_optim}"
  platform_path = platform_path( "android", config )
  Buildrake::Rush.remaked( Buildrake::Rush.base_name( platform_path ) ){
    ndk_out_dir = "./ndk_out"
    ndk_build = "\#{android_ndk}/ndk-build -B NDK_APP_DST_DIR='\#{ndk_out_dir}/${TARGET_ARCH_ABI}' NDK_OUT='\#{ndk_out_dir}' APP_OPTIM=\#{app_optim} PLATFORM=android CONFIG=\#{config} PLATFORM_PATH=\#{platform_path} ANDROID_NDK_VERSION=\#{Buildrake::Rush.env( 'ANDROID_NDK_VERSION' )}"
    ndk_build = "\#{ndk_build} APP_STL=\#{android_stl}" if ! android_stl.nil? && ! android_stl.empty?
    Buildrake::Rush.sh( ndk_build )
    
    src = Buildrake::Rush.full_dir_path
    dst = "\#{src}/../../../lib/\#{platform_path}/libs"
    #{@libraries.keys}.each{|name|
      Buildrake::Rush.find( "\#{src}/\#{ndk_out_dir}/local/*/lib\#{name}.*" ){|path|
        arch = Buildrake::Rush.base_name( Buildrake::Rush.dir_path( path ) )
        Buildrake::Rush.maked( "\#{dst}/\#{arch}" ){
          Buildrake::Rush.rename( path, "." )
        }
      }
    }
  }
end
EOS
        }
      }
    end
    
    def generate_windows_build_files
      Rush.maked( "windows" ){
        open( "windows.cmake", "wb" ){|f|
          f.puts <<EOS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{@c_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{@cxx_flags[ :windows ][ :debug ].join( ' ' )}")
set(CMAKE_LD_FLAGS_DEBUG "${CMAKE_LD_FLAGS_DEBUG} #{@ld_flags[ :windows ][ :debug ].join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{@c_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{@cxx_flags[ :windows ][ :release ].join( ' ' )}")
set(CMAKE_LD_FLAGS_RELEASE "${CMAKE_LD_FLAGS_RELEASE} #{@ld_flags[ :windows ][ :release ].join( ' ' )}")

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :windows ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
                  f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :windows ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_RELEASE ${#{@project_name.upcase}_LINK_DIRS_RELEASE} #{dir})
EOS
          }
          
          f.puts <<EOS
include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        @windows_runtimes.each{|runtime|
          Rush.maked( "#{runtime}" ){
            open( "CMakeLists.txt", "wb" ){|f|
              f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

project(#{@project_name})

include(${CMAKE_CURRENT_LIST_DIR}/../windows.cmake)

set(Flags
  CMAKE_C_FLAGS
  CMAKE_C_FLAGS_DEBUG
  CMAKE_C_FLAGS_RELEASE
  CMAKE_CXX_FLAGS
  CMAKE_CXX_FLAGS_DEBUG
  CMAKE_CXX_FLAGS_RELEASE
)
foreach(Flag ${Flags})
  string(REPLACE "/MD" "/#{runtime}" ${Flag} "${${Flag}}")
  string(REGEX REPLACE "/Z[i|I]" "/Z7" ${Flag} "${${Flag}}")
endforeach()
EOS
            }
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}", File.dirname( __FILE__ ) )

def build
  config = Buildrake::Rush.env( "CONFIG" )
  windows_visual_studio_version = Buildrake::Rush.env( "WINDOWS_VISUAL_STUDIO_VERSION" )
  windows_runtime = Buildrake::Rush.env( "WINDOWS_RUNTIME" )
  windows_arch = Buildrake::Rush.env( "WINDOWS_ARCH" )
  cmake_generator = Buildrake::Rush.env( "CMAKE_GENERATOR" )
  platform_path = platform_path( "windows", config )
  Buildrake::Rush.remaked( Buildrake::Rush.base_name( platform_path ) ){
    Buildrake::Rush.sh( "cmake ../\#{windows_runtime} -DCMAKE_CONFIGURATION_TYPES=\#{config} -G\\"\#{cmake_generator}\\" -A\\"\#{windows_arch}\\" --no-warn-unused-cli -DPLATFORM=windows -DCONFIG=\#{config} -DPLATFORM_PATH=\#{platform_path}" )
    Buildrake::Rush.sh( "msbuild #{@project_name}.sln /m /t:Rebuild /p:Configuration=\#{config} /p:Platform=\\"\#{windows_arch}\\"" )
    
    built_files = []
    Buildrake::Rush.changed( config ){
      Buildrake::Rush.find( "\#{Buildrake::Rush.full_dir_path}/*" ){|path|
        built_files.push path
      }
    }
    Buildrake::Rush.maked( "../../../lib/\#{platform_path}" ){
      built_files.each{|built_file|
        Buildrake::Rush.rename( built_file, "." )
      }
    }
  }
end
EOS
        }
      }
    end
  end
end
