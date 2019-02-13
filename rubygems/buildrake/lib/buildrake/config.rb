require "buildrake/mash"

module Buildrake
  class Config
    include Buildrake::Mash
    
    def self.run( argv )
      self.new.send( argv.shift, *argv ) if ! argv.empty?
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
    method_accessor :inc_dirs
    method_accessor :lib_dirs
    method_accessor :c_flags, :cxx_flags, :ld_flags
    method_accessor :windows_visual_studio_versions, :windows_runtimes, :windows_archs, :windows_artifact_name
    method_accessor :macos_archs, :ios_archs
    method_accessor :android_archs, :android_api_level
    method_accessor :cmake_version
    method_accessor :appveyor
    
    EXECUTE = "execute"
    LIBRARY = "library"
    
    def initialize( project_name )
      @project_name = project_name
      
      @inc_dirs = []
      
      @lib_dirs = {}
      
      @c_flags = {}
      @cxx_flags = {}
      @ld_flags = {}
      
      @windows_visual_studio_versions = [ 2012, 2013, 2015, 2017 ]
      @windows_runtimes = [ "MT", "MD" ]
      @windows_archs = [ "Win32", "x64" ]
      @windows_artifact_name = "$(ARTIFACT_PREFIX)_$(CONFIGURATION)"
      
      @macos_archs = [ "x86_64" ]
      @ios_archs = [ "armv7", "armv7s", "arm64" ]
      
      @android_archs = [ "x86", "armeabi-v7a", "arm64-v8a" ]
      @android_api_level = 16
      
      @cmake_version = "2.8"
      
      @appveyor = nil
      
      @executes = {}
      @libraries = {}
      
      [ :linux, :macos, :ios, :android, :windows ].each{|platform|
        [ :debug, :release ].each{|configuration|
          c_flags   = []
          cxx_flags = []
          ld_flags  = []
          case platform
          when :windows
            c_flags = [ "/W4" ]
            cxx_flags = c_flags.clone
          else
            c_flags = [ "-g -Wall" ]
            case configuration
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
          
          lib_dir( platform, configuration, [] )
          c_flag( platform, configuration, c_flags )
          cxx_flag( platform, configuration, cxx_flags )
          ld_flag( platform, configuration, ld_flags )
        }
      }
    end
    
    def lib_dir( platform, configuration, dirs )
      @lib_dirs[ platform ] = {} if ! @lib_dirs.key?( platform )
      @lib_dirs[ platform ][ configuration ] = dirs
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
    
    def setup( *args )
      generate
    end
    
    def generate( *args )
      mkdir( "build" ){
        generate_common_build_files
        generate_macos_build_files
        generate_ios_build_files
        generate_linux_build_files
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
    
    def download_lib( url, lib_dir )
      require "nokogiri"
      require "open-uri"
      mkdir( lib_dir ){
        document = Nokogiri::HTML.parse( open( url ).readlines.join )
        document.xpath( '//strong' ).children.each{|element|
          filename = element.text
          extname = extname( filename )
          case extname
          when ""
          when ".zip"
            dirname = basename( filename, extname )
            rm( dirname ) if dir?( dirname )
            rm( filename ) if file?( filename )
            url = url.gsub( /\/releases\/tag\//, "/releases/download/" ) if url =~ /^https\:\/\/github\.com\//
            sh( "wget #{url}/#{filename}" )
            sh( "unzip #{filename}" )
            rm( filename )
          else
            abort( "Unsupported extname: #{extname}" )
          end
        }
      }
    end
    
  private
    def platforms( *args )
      platforms = []
      if args.empty?
        case RUBY_PLATFORM
        when /darwin/
          platforms = [ :linux, :macos, :ios ]
        else
          platforms = [ :linux ]
        end
        platforms.push :android if env?( "ANDROID_NDK" )
      else
        platforms = args
      end
      platforms
    end
    
    def help
      puts <<EOS
<build command list>
EOS
      [ :linux, :android, :macos, :ios, :windows ].each{|platform|
        [ :debug, :release ].each{|configuration|
          puts "build #{platform} #{configuration}"
        }
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
endforeach()

project(#{@project_name})

set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_MODULE_LINKER_FLAGS_DEBUG "${CMAKE_MODULE_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} ${CMAKE_LD_FLAGS_DEBUG}")

set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
set(CMAKE_MODULE_LINKER_FLAGS_RELEASE "${CMAKE_MODULE_LINKER_FLAGS_RELEASE} ${CMAKE_LD_FLAGS_RELEASE}")
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
            link_lib_name = "#{@project_name.upcase}_LIB_#{name.upcase}"
            f.puts <<EOS
find_library(#{link_lib_name} NAMES lib#{name}.a #{name} PATHS ${#{@project_name.upcase}_LINK_DIRS})
message(#{link_lib_name}=${#{link_lib_name}})
EOS
            link_lib_names.push "${#{link_lib_name}}"
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
      
      open( "#{@project_name}_rake.rb", "wb" ){|f|
        f.puts <<EOS
require "buildrake"
extend Buildrake::Mash

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

def platform_path( platform )
  path = nil
  case platform
  when :linux, :macos
    case RUBY_PLATFORM
    when /darwin/
      path = "macos/\#{\`xcrun --sdk macosx --show-sdk-version\`.chomp}"
    else
      # TODO
    end
  when :ios
    path = "ios/\#{\`xcrun --sdk iphoneos --show-sdk-version\`.chomp}"
  when :android
    if env?( "ANDROID_NDK" )
      path = "android/\#{env( 'ANDROID_NDK' ).split( '-' ).last.chomp( '/' )}"
      path = "\#{path}_\#{env( 'ANDROID_STL' )}" if env?( 'ANDROID_STL' )
    end
  end
  path.nil? ? platform.to_s : path.chomp( '/' )
end

def lib_platform_path( platform, configuration )
  "\#{platform_path( platform )}_\#{configuration}"
end

def cmake_files( prefix = "" )
  [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ].map{|path| "\#{prefix}\#{path}"}
end

desc "Build"
task :build do
  find( cmake_files ){|path|
    rm( path )
  }
  clean
  
  cmake if ! find( "CMakeLists.txt" ).empty?
  build
end

env( "CONFIGURATION", "Debug" ) if ! env?( "CONFIGURATION" )
puts "CONFIGURATION=\#{env( 'CONFIGURATION' )}"
env( "LIB_PLATFORM_PATH", "\#{lib_platform_path( basename( pwd ).to_sym, env( 'CONFIGURATION' ) )}" ) if ! env?( "LIB_PLATFORM_PATH" )
puts "LIB_PLATFORM_PATH=\#{env( 'LIB_PLATFORM_PATH' )}"
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

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :macos ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :macos ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
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
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  configuration = env( "CONFIGURATION" )
  sh( "cmake . -DCMAKE_BUILD_TYPE=\#{configuration} -G Xcode" )
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
  dst = "\#{src}/../../lib/\#{lib_platform_path( :macos, configuration )}"
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

set(#{@project_name.upcase}_ROOT_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(#{@project_name.upcase}_LINK_DIRS_DEBUG)
set(#{@project_name.upcase}_LINK_DIRS_RELEASE)
EOS
          
          @lib_dirs[ :ios ][ :debug ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :ios ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
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
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  configuration = env( "CONFIGURATION" )
  sh( "cmake . -DCMAKE_BUILD_TYPE=\#{configuration} -G Xcode" )
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
  dst = "\#{src}/../../lib/\#{lib_platform_path( :ios, configuration)}"
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
    
    def generate_linux_build_files
      mkdir( "linux" ){
        open( "CMakeLists.txt", "wb" ){|f|
          f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

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
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :linux ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
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
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def cmake
  configuration = env( "CONFIGURATION" )
  sh( "cmake . -DCMAKE_BUILD_TYPE=\#{configuration}" )
end

def build
  configuration = env( "CONFIGURATION" )
  sh( "make" )
  
  src = "\#{dirname( __FILE__ )}"
  dst = "\#{src}/../../lib/\#{lib_platform_path( :linux, configuration )}"
  #{@libraries.keys}.each{|name|
    find( "lib\#{name}.*" ){|path|
      mkdir( dst )
      mv( "\#{src}/\#{path}", dst )
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
              f.puts ""
              
              ld_libs = []
              data[ :libs ].each{|lib|
                ld_libs.push "LOCAL_LDLIBS += -l#{lib}"
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
                ld_libs.push "LOCAL_LDLIBS += -l#{lib}"
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
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def build
  android_ndk = env( "ANDROID_NDK" )
  abort( "Not found ANDROID_NDK: \#{android_ndk}" ) if android_ndk.nil? || ! dir?( android_ndk )
  env( "ANDROID_NDK_VERSION", android_ndk.split( '-' ).last.chomp( '/' ) )
  android_stl = env( "ANDROID_STL" )
  puts "ANDROID_NDK=\#{android_ndk}"
  puts "ANDROID_STL=\#{android_stl}"
  configuration = env( "CONFIGURATION" )
  app_optim = configuration.downcase
  puts "APP_OPTIM=\#{app_optim}"
  ndk_build = "\#{android_ndk}/ndk-build -B NDK_LIBS_OUT=./out NDK_OUT=./out APP_OPTIM=\#{app_optim}"
  ndk_build = "\#{ndk_build} APP_STL=\#{android_stl}" if ! android_stl.nil?
  sh( ndk_build )
  rm( "libs" )
  find( [ "out/local/*/*.*" ] ).each{|path|
    arch = basename( dirname( path ) )
    mkdir( "libs/\#{arch}" )
    cp( path, "libs/\#{arch}/." )
  }
  
  src = dirname( __FILE__ )
  dst = "\#{src}/../../lib/\#{lib_platform_path( :android, configuration )}"
  #{@libraries.keys}.each{|name|
    find( "libs/**/lib\#{name}.*" ){|path|
      mkdir( "\#{dst}/\#{dirname( path )}" )
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
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
                  f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_DEBUG ${#{@project_name.upcase}_LINK_DIRS_DEBUG} #{dir})
EOS
          }
          
          @lib_dirs[ :windows ][ :release ].each{|dir|
            dir = "${#{@project_name.upcase}_ROOT_DIR}/#{dir}" if dir =~ /^\./
            dir = dir.gsub( /\(/, "ENV{" ).gsub( /\)/, "}" )
            f.puts <<EOS
set(#{@project_name.upcase}_LINK_DIRS_RELEASE ${#{@project_name.upcase}_LINK_DIRS_RELEASE} #{dir})
EOS
          }
          
          f.puts <<EOS
include(${CMAKE_CURRENT_LIST_DIR}/../#{@project_name}.cmake)
EOS
        }
        
        @windows_visual_studio_versions.each{|version|
          @windows_runtimes.each{|runtime|
            @windows_archs.each{|arch|
              mkdir( "#{version}_#{runtime}_#{arch}" ){
                open( "CMakeLists.txt", "wb" ){|f|
                  f.puts <<EOS
cmake_minimum_required(VERSION #{@cmake_version})

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
endforeach()
EOS
                }
              }
            }
          }
        }
        
        open( "Rakefile", "wb" ){|f|
          f.puts <<EOS
require File.expand_path( "../#{@project_name}_rake", File.dirname( __FILE__ ) )

def build
  # TODO
end

def clean
  # TODO
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
          @windows_runtimes.each{|runtime|
            @windows_archs.each{|arch|
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
              
              artifact_prefix = "#{version}_#{runtime}_#{arch}"
              f.puts <<EOS
      ARTIFACT_PREFIX: #{artifact_prefix}
      DIR: build\\windows\\#{artifact_prefix}
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
  - cmake . -G"%GENERATOR%" -A"%PLATFORM%" -DCMAKE_BUILD_TYPE=%CONFIGURATION%

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
