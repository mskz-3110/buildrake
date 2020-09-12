require "buildrake/version"
require "buildrake/rush"
require "buildrake/comment"
require "buildrake/github"
require "yaml"

module Buildrake
  def self.setup
    yaml_file_path = "buildrake.yaml"
    generate_yamlfile( yaml_file_path )
    yaml = YAML.load_file( yaml_file_path )
    generate_rakefile
    generate_gitignore
    Rush.remaked( "build" ){
      generate_common_buildfiles
      yaml[ "anchors" ][ "platforms" ].each{|platform, _|
        generate_platform_buildfiles( platform )
      }
    }
    true
  end
  
  def self.generate_yamlfile( path )
    open( path, "wb" ){|f|
      f.puts <<EOS
anchors:
  configuration: &configuration
    c_flags:
    cxx_flags:
    exe_linker_flags:
    static_linker_flags:
    shared_linker_flags:
    link_dirs:
    link_libs:
  xcode_configuration: &xcode_configuration
    <<: *configuration
    c_flags: -g -Wall -fembed-bitcode
    cxx_flags: -g -Wall -fembed-bitcode
  android_configuration: &android_configuration
    <<: *configuration
    c_flags: -g -Wall
    cxx_flags: -g -Wall -fexceptions -frtti
  linux_configuration: &linux_configuration
    <<: *configuration
    c_flags: -g -Wall
    cxx_flags: -g -Wall
  windows_configuration: &windows_configuration
    <<: *configuration
    c_flags: /W4
    cxx_flags: /W4
  macos_targets: &macos_targets
    - x86_64
  ios_targets: &ios_targets
    - iphonesimulator.x86_64
    - iphoneos.arm64
  android_targets: &android_targets
    - x86
    - armeabi-v7a
    - arm64-v8a
  linux_targets: &linux_targets
    - x86_64
  windows_targets: &windows_targets
    - 2017.MD.Win32
    - 2017.MD.x64
    - 2017.MT.Win32
    - 2017.MT.x64
    - 2017.ARM.Win32
    - 2017.ARM.x64
    - 2017.ARM64.Win32
    - 2017.ARM64.x64
  platforms: &platforms
    macos:
      targets: *macos_targets
      configurations:
        debug:
          <<: *xcode_configuration
        release:
          <<: *xcode_configuration
    ios:
      targets: *ios_targets
      configurations:
        debug:
          <<: *xcode_configuration
        release:
          <<: *xcode_configuration
    android:
      targets: *android_targets
      configurations:
        debug:
          <<: *android_configuration
        release:
          <<: *android_configuration
    linux:
      targets: *linux_targets
      configurations:
        debug:
          <<: *linux_configuration
        release:
          <<: *linux_configuration
    windows:
      targets: *windows_targets
      configurations:
        debug:
          <<: *windows_configuration
        release:
          <<: *windows_configuration
  build_exe: &build_exe
    type: exe
    inc_dirs:
      - ./inc
  build_lib: &build_lib
    type: lib
    inc_dirs:
      - ./inc
buildrake:
  cmake_version: 2.8
  builds:
    - <<: *build_lib
      name: lib_name
      srcs:
        - ./src/
      platforms:
        <<: *platforms
    - <<: *build_exe
      name: exe_name
      srcs:
        - ./src/
      platforms:
        <<: *platforms
EOS
    }
  end
  
  def self.generate_rakefile
    open( "Rakefile", "wb" ){|f|
      f.puts <<EOS
require "buildrake"

desc "Setup"
task :setup do
  Buildrake.setup
end

desc "Show help message"
task :help do
  yaml = YAML.load_file( "\#{Buildrake::Rush.full_dir_path( __FILE__ )}/buildrake.yaml" )
  yaml[ "anchors" ][ "platforms" ].each{|platform, _|
    [ "debug", "release" ].each{|configuration|
      case platform
      when "android"
        android_ndk = "/tmp/android-ndk-r10e"
        puts "BUILDRAKE_ANDROID_NDK=\#{android_ndk} rake build \#{platform} \#{configuration}"
        puts "BUILDRAKE_ANDROID_NDK=\#{android_ndk} BUILDRAKE_ANDROID_STL=c++_static rake build \#{platform} \#{configuration}"
        puts "BUILDRAKE_ANDROID_NDK=\#{android_ndk} BUILDRAKE_ANDROID_STL=gnustl_static rake build \#{platform} \#{configuration}"
      when "windows"
        
      else
        puts "rake build \#{platform} \#{configuration}"
      end
    }
  }
end

desc "Build <platform> <configuration>"
task :build do
  ARGV.shift
  platform = ARGV.shift
  configuration = ARGV.shift
  if platform.nil? || configuration.nil?
    Rake::Task[ "help" ].invoke
  else
    Buildrake::Rush.changed( "build/\#{platform}" ){
      Buildrake::Rush.sh( "BUILDRAKE_CONFIGURATION=\#{configuration} ruby ./build.rb" )
    }
  end
  exit 0
end
EOS
    }
  end
  
  def self.generate_gitignore
    open( ".gitignore", "wb" ){|f|
      f.puts <<EOS
/build
/lib
/Gemfile.lock
EOS
    }
  end
  
  def self.generate_cmakefile( platform, root_dir_path, project_name, buildrake, build, name, targets, configurations )
    Buildrake::Rush.find( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
      Buildrake::Rush.remove( path )
    }
    
    open( "CMakeLists.txt", "wb" ){|f|
      f.puts <<EOS
cmake_minimum_required(VERSION #{safe_string( buildrake[ "cmake_version" ] )})
set(#{project_name.upcase}_ROOT_DIR #{root_dir_path})
set(CMAKE_VERBOSE_MAKEFILE 1)
if (DEFINED CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_MACOSX_RPATH 1)
endif()
project(#{project_name})
EOS
      f.puts ""
      
      debug = safe_array_configuration( project_name, configurations[ "debug" ] )
      release = safe_array_configuration( project_name, configurations[ "release" ] )
      
      f.puts <<EOS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{debug[ 'c_flags' ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{debug[ 'cxx_flags' ].join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} #{debug[ 'exe_linker_flags' ].join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} #{debug[ 'static_linker_flags' ].join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} #{debug[ 'shared_linker_flags' ].join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_DEBUG #{debug[ 'link_dirs' ].join( ' ' )})
set(#{name.upcase}_LINK_LIBS_DEBUG #{debug[ 'link_libs' ].join( ' ' )})

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{release[ 'c_flags' ].join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{release[ 'c_flags' ].join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} #{release[ 'exe_linker_flags' ].join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} #{release[ 'static_linker_flags' ].join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} #{release[ 'shared_linker_flags' ].join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_RELEASE #{release[ 'link_dirs' ].join( ' ' )})
set(#{name.upcase}_LINK_LIBS_RELEASE #{release[ 'link_libs' ].join( ' ' )})

message(#{project_name.upcase}_ROOT_DIR:${#{project_name.upcase}_ROOT_DIR})
message(CMAKE_BUILD_TYPE:${CMAKE_BUILD_TYPE})
string(TOUPPER ${CMAKE_BUILD_TYPE} CMAKE_BUILD_TYPE_UPPER)
foreach(__LINK_DIR__ IN LISTS #{project_name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE_UPPER})
  message(#{project_name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE_UPPER}:${__LINK_DIR__})
  link_directories(${__LINK_DIR__})
endforeach()
message(BUILDRAKE_PLATFORM:${BUILDRAKE_PLATFORM})
message(BUILDRAKE_CONFIGURATION:${BUILDRAKE_CONFIGURATION})
message(BUILDRAKE_BUILD_KEY:${BUILDRAKE_BUILD_KEY})
EOS
      
      safe_array( build[ "inc_dirs" ] ).each{|path|
        f.puts <<EOS
include_directories(#{project_root_path( project_name, path )})
EOS
      }
      
      f.puts "set(#{name.upcase}_SRCS)"
      safe_array( build[ "srcs" ] ).each{|path|
        f.puts "set(#{name.upcase}_SRCS ${#{name.upcase}_SRCS} #{project_root_path( project_name, path )})"
      }
      
      case safe_string( build[ "type" ] )
      when "lib"
        f.puts <<EOS
add_library(#{name}-shared SHARED ${#{name.upcase}_SRCS})
target_link_libraries(#{name}-shared ${#{name.upcase}_LINK_LIBS_${CMAKE_BUILD_TYPE_UPPER}})
SET_TARGET_PROPERTIES(#{name}-shared PROPERTIES OUTPUT_NAME #{name})
add_library(#{name}-static STATIC ${#{name.upcase}_SRCS})
target_link_libraries(#{name}-static ${#{name.upcase}_LINK_LIBS_${CMAKE_BUILD_TYPE_UPPER}})
SET_TARGET_PROPERTIES(#{name}-static PROPERTIES OUTPUT_NAME #{name})
EOS
      when "exe"
        f.puts <<EOS
add_executable(#{name} ${#{name.upcase}_SRCS})
target_link_libraries(#{name} ${#{name.upcase}_LINK_LIBS_${CMAKE_BUILD_TYPE_UPPER}})
EOS
      end
    }
  end
  
  def self.generate_ndkfile( platform, root_dir_path, project_name, buildrake, build, name, targets, configurations )
    modules = name
    case safe_string( build[ "type" ] )
    when "lib"
      modules = "#{name}-static #{name}-shared"
    end
    
    debug = safe_array_configuration( project_name, configurations[ "debug" ] )
    release = safe_array_configuration( project_name, configurations[ "release" ] )
    
    open( "Application.mk", "wb" ){|f|
      f.puts <<EOS
APP_MODULES := #{modules}
APP_PLATFORM := android-#{Rush.env_get( "BUILDRAKE_ANDROID_API_LEVEL", "21" )}
APP_ABI := #{targets.join( ' ' )}
ifeq ($(APP_OPTIM),debug)
  APP_CFLAGS := #{debug[ 'c_flags' ].join( ' ' )}
  APP_CPPFLAGS := #{debug[ 'cxx_flags' ].join( ' ' )}
  APP_LDFLAGS := #{debug[ 'static_linker_flags' ].join( ' ' )} #{debug[ 'shared_linker_flags' ].join( ' ' )}
else
  APP_CFLAGS := #{release[ 'c_flags' ].join( ' ' )}
  APP_CPPFLAGS := #{release[ 'cxx_flags' ].join( ' ' )}
  APP_LDFLAGS := #{release[ 'static_linker_flags' ].join( ' ' )} #{release[ 'shared_linker_flags' ].join( ' ' )}
endif
EOS
    }
    
    open( "Android.mk", "wb" ){|f|
      f.puts <<EOS
LOCAL_PATH := $(call my-dir)/..

#{project_name.upcase}_ROOT_DIR := #{root_dir_path}

EOS
      
      local_settings = [
        "LOCAL_CFLAGS := ",
        "LOCAL_CXXFLAGS := ",
        "LOCAL_LDLIBS := ",
      ]
      
      safe_array( build[ "inc_dirs" ] ).each{|path|
        path = project_root_path( project_name, path )
        local_settings.push "LOCAL_CFLAGS += -I#{path}"
        local_settings.push "LOCAL_CXXFLAGS += -I#{path}"
      }
      
      local_settings.push "ifeq ($(APP_OPTIM),debug)"
      debug[ "link_dirs" ].each{|path|
        local_settings.push "  LOCAL_LDLIBS += -L#{project_root_path( project_name, path )}/libs/$(TARGET_ARCH_ABI)"
      }
      debug[ "link_libs" ].each{|lib|
        local_settings.push "  LOCAL_LDLIBS += -l#{lib}"
      }
      local_settings.push "else"
      release[ "link_dirs" ].each{|path|
        local_settings.push "  LOCAL_LDLIBS += -L#{project_root_path( project_name, path )}/libs/$(TARGET_ARCH_ABI)"
      }
      release[ "link_libs" ].each{|lib|
        local_settings.push "  LOCAL_LDLIBS += -l#{lib}"
      }
      local_settings.push "endif"
      
      f.puts "#{name.upcase}_SRCS := "
      safe_array( build[ "srcs" ] ).each{|path|
        f.puts "#{name.upcase}_SRCS += #{project_root_path( project_name, path )}"
      }
      f.puts ""
      
      case safe_string( build[ "type" ] )
      when "exe"
        f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}
LOCAL_SRC_FILES := $(#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_EXECUTABLE)
EOS
      when "lib"
        f.puts <<EOS
include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-static
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := #{name}-shared
LOCAL_MODULE_FILENAME := lib#{name}
LOCAL_SRC_FILES := $(#{name.upcase}_SRCS)
#{local_settings.join( "\n" )}
$(info LOCAL_CFLAGS=$(LOCAL_CFLAGS))
$(info LOCAL_CXXFLAGS=$(LOCAL_CXXFLAGS))
$(info LOCAL_LDLIBS=$(LOCAL_LDLIBS))
include $(BUILD_SHARED_LIBRARY)
EOS
      end
    }
  end
  
  def self.generate_common_buildfiles
    open( "common.rb", "wb" ){|f|
      f.puts <<EOS
require "buildrake"

def get_platform_build_name( platform )
  case platform
  when "macos"
    "\#{\`xcrun --sdk macosx --show-sdk-version\`.chomp}"
  when "ios"
    "\#{\`xcrun --sdk iphoneos --show-sdk-version\`.chomp}"
  when "android"
    android_stl = Buildrake::Rush.env_get( "BUILDRAKE_ANDROID_STL", "" )
    android_ndk = Buildrake::Rush.env_get( "BUILDRAKE_ANDROID_NDK", "" )
    abort( "Invalid android ndk: BUILDRAKE_ANDROID_NDK=\#{android_ndk}" ) if android_ndk.empty?
    android_ndk_version = android_ndk.split( '-' ).last.chomp( '/' )
    Buildrake::Rush.env_set( "BUILDRAKE_ANDROID_NDK_VERSION", android_ndk_version )
    path = "\#{android_ndk_version}"
    path = "\#{path}_\#{android_stl}" if ! android_stl .empty?
    path
  when "linux"
    # TODO
  when "windows"
    # TODO
  end
end

def get_build_key( platform, configuration )
  "\#{get_platform_build_name( platform )}_\#{configuration}"
end

def build( platform, yaml_file_path, &block )
  yaml = YAML.load_file( yaml_file_path )
  buildrake = yaml[ "buildrake" ]
  root_dir_path = Buildrake::Rush.full_dir_path( yaml_file_path )
  configuration = Buildrake::Rush.env_get( "BUILDRAKE_CONFIGURATION" ).capitalize
  build_key = get_build_key( platform, configuration )
  case platform
  when "android"
    android_ndk_version = Buildrake::Rush.env_get( "BUILDRAKE_ANDROID_NDK_VERSION", "" )
    options = [
      "-B",
      "APP_OPTIM=\#{configuration.downcase}",
      "BUILDRAKE_ANDROID_NDK_VERSION=\#{android_ndk_version}",
      "BUILDRAKE_PLATFORM=\#{platform}",
      "BUILDRAKE_CONFIGURATION=\#{configuration}",
      "BUILDRAKE_BUILD_KEY=\#{build_key}",
    ]
    android_stl = Buildrake::Rush.env_get( "BUILDRAKE_ANDROID_STL", "" )
    options.push( "APP_STL=\#{android_stl}" ) if ! android_stl.empty?
  else
    options = [
#      "--no-warn-unused-cli",
      "-DBUILDRAKE_PLATFORM=\#{platform}",
      "-DBUILDRAKE_CONFIGURATION=\#{configuration}",
      "-DBUILDRAKE_BUILD_KEY=\#{build_key}",
    ]
  end
  Buildrake::Rush.maked( build_key ){
    buildrake[ "builds" ].each{|build|
      if build[ "platforms" ].key?( platform )
        block.call( root_dir_path, options.join( ' ' ), buildrake, build, build[ "name" ], build[ "platforms" ][ platform ][ "targets" ], configuration, build_key, build[ "platforms" ][ platform ][ "configurations" ] )
      end
    }
  }
end

def build_cmake( platform, yaml_file_path, &block )
  project_name = Buildrake::Rush.dir_name( yaml_file_path )
  build( platform, yaml_file_path ){|root_dir_path, option, buildrake, build, name, targets, configuration, build_key, configurations|
    Buildrake::Rush.maked( name ){
      is_generated_buildfile = false
      if ! Buildrake::Rush.file?( "CMakeLists.txt" ) || Buildrake::Rush.file_stat( "CMakeLists.txt" ).mtime < Buildrake::Rush.file_stat( yaml_file_path ).mtime
        is_generated_buildfile = true
        Buildrake::generate_cmakefile( platform, root_dir_path, project_name, buildrake, build, name, targets, configurations )
      end
      block.call( is_generated_buildfile, name, option, configuration, targets, build_key )
    }
  }
end

def build_ndk( platform, yaml_file_path, &block )
  project_name = Buildrake::Rush.dir_name( yaml_file_path )
  build( platform, yaml_file_path ){|root_dir_path, option, buildrake, build, name, targets, configuration, build_key, configurations|
    Buildrake::Rush.maked( name ){
      is_generated_buildfile = false
      if ! Buildrake::Rush.file?( "Android.mk" ) || Buildrake::Rush.file_stat( "Android.mk" ).mtime < Buildrake::Rush.file_stat( yaml_file_path ).mtime
        is_generated_buildfile = true
        Buildrake::Rush.maked( "jni" ){
          Buildrake::generate_ndkfile( platform, root_dir_path, project_name, buildrake, build, name, targets, configurations )
        }
      end
      block.call( name, option, configuration, targets, build_key )
    }
  }
end

def lipo_create( inputs, output )
  Buildrake::Rush.sh( "lipo -create \#{inputs.join( ' ' )} -output \#{output}" )
end

def lipo_info( *args )
  Buildrake::Rush.sh( "lipo -info \#{args.join( ' ' )}" )
end
EOS
    }
  end
  
  def self.generate_platform_buildfiles( platform )
    Rush.remaked( platform ){
      open( "build.rb", "wb" ){|f|
        f.puts <<EOS
require "../common"

__DIR__ = Buildrake::Rush.full_dir_path( __FILE__ )

EOS
        
        case platform
        when "macos"
          f.puts <<EOS
build_cmake( "#{platform}", "\#{__DIR__}/../../buildrake.yaml" ){|is_generated_buildfile, name, option, configuration, targets, build_key|
  targets.each{|target|
    arch = target
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake .. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} \#{option}" ) if is_generated_buildfile
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../../lib/#{platform}/\#{build_key}" )
  [ "lib\#{name}.a", "lib\#{name}.dylib" ].each{|lib_name|
    if ! Buildrake::Rush.find( "*/\#{lib_name}" ).empty?
      lipo_create( [ "*/\#{lib_name}" ], lib_name )
      lipo_info( lib_name )
      Buildrake::Rush.rename( lib_name, "\#{lib_dir_path}/." )
    end
  }
}
EOS
        when "ios"
          f.puts <<EOS
build_cmake( "#{platform}", "\#{__DIR__}/../../buildrake.yaml" ){|is_generated_buildfile, name, option, configuration, targets, build_key|
  targets.each{|target|
    sysroot, arch = target.split( "." )
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake .. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=\#{sysroot} \#{option}" ) if is_generated_buildfile
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../../lib/#{platform}/\#{build_key}" )
  [ "lib\#{name}.a", "lib\#{name}.dylib" ].each{|lib_name|
    if ! Buildrake::Rush.find( "*/\#{lib_name}" ).empty?
      lipo_create( [ "*/\#{lib_name}" ], lib_name )
      lipo_info( lib_name )
      Buildrake::Rush.rename( lib_name, "\#{lib_dir_path}/." )
    end
  }
}
EOS
        when "android"
          f.puts <<EOS
android_ndk = Buildrake::Rush.env_get( "BUILDRAKE_ANDROID_NDK", "" )
build_ndk( "#{platform}", "\#{__DIR__}/../../buildrake.yaml" ){|name, option, configuration, targets, build_key|
  ndk_out_dir = "./ndk_out"
  Buildrake::Rush.sh( "\#{android_ndk}/ndk-build NDK_APP_DST_DIR='\#{ndk_out_dir}/${TARGET_ARCH_ABI}' NDK_OUT='\#{ndk_out_dir}' \#{option}" )
  
  lib_dir_path = Buildrake::Rush.maked( "../../../../lib/#{platform}/\#{build_key}/libs" )
  [ "lib\#{name}.a", "lib\#{name}.so" ].each{|lib_name|
    Buildrake::Rush.find( "\#{ndk_out_dir}/local/*/\#{lib_name}" ){|path|
      path = Buildrake::Rush.full_file_path( path )
      Buildrake::Rush.maked( "\#{lib_dir_path}/\#{Buildrake::Rush.dir_name( path )}" ){
        Buildrake::Rush.rename( path, "." )
      }
    }
  }
}
EOS
        when "linux"
          # TODO
        when "windows"
          # TODO
        end
      }
    }
  end
  
  def self.safe_string( value, default_value = "" )
    value = safe_nil( value, default_value )
    if ! value.is_a?( String )
      value = value.is_a?( Array ) ? value.join( ' ' ) : value.to_s
    end
    value
  end
  
  def self.safe_array( value, default_value = [] )
    value = safe_nil( value, default_value )
    if ! value.is_a?( Array )
      value = value.is_a?( String ) ? value.split( ' ' ) : [ value ]
    end
    value
  end
  
  def self.safe_nil( value, default_value )
    value.nil? ? default_value : value
  end
  
  def self.safe_array_configuration( project_name, configuration )
    configuration[ "c_flags" ] = safe_array( configuration[ "c_flags" ] )
    configuration[ "cxx_flags" ] = safe_array( configuration[ "cxx_flags" ] )
    configuration[ "exe_linker_flags" ] = safe_array( configuration[ "exe_linker_flags" ] )
    configuration[ "static_linker_flags" ] = safe_array( configuration[ "static_linker_flags" ] )
    configuration[ "shared_linker_flags" ] = safe_array( configuration[ "shared_linker_flags" ] )
    configuration[ "link_dirs" ] = safe_array( configuration[ "link_dirs" ] ).map{|path|
      project_root_path( project_name, path )
    }
    configuration[ "link_libs" ] = safe_array( configuration[ "link_libs" ] )
    configuration
  end
  
  def self.project_root_path( project_name, path )
    path = "${#{project_name.upcase}_ROOT_DIR}/#{path}" if path =~ /^\./
    path
  end
end
