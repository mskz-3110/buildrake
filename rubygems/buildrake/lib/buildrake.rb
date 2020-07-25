require "buildrake/version"
require "buildrake/rush"
require "buildrake/config"
require "buildrake/comment"
require "buildrake/github"
require "yaml"

module Buildrake
  def self.setup
    name = Rush.dir_name
    Rush.remaked( "build" ){
      generate_common_buildfiles
      [ "macos", "ios", "android", "linux", "windows" ].each{|platform|
        generate_platform_buildfiles( platform, name )
      }
    }
    generate_yaml( name )
    generate_rakefile
    generate_gitignore
  end
  
  def self.generate_yaml( name )
    open( "buildrake.yaml", "wb" ){|f|
      f.puts <<EOS
config:
  cmake_version: 2.8
  project_name: #{name}
  inc_dirs:
    - ./inc
  builds:
    - type: lib
      name: #{name}
      srcs:
        - ./src/**/*.c
    - type: exe
      name: #{name}
      srcs:
        - ./src/**/*.c
  platforms:
    macos:
      targets:
        - x86_64
      configurations:
        debug:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
        release:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
    ios:
      targets:
        - iphonesimulator.x86_64
        - iphoneos.arm64
      configurations:
        debug:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
        release:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
    android:
      targets:
        - 21.x86
        - 21.armeabi-v7a
        - 21.arm64-v8a
      configurations:
        debug:
          c_flags: -g -Wall
          cxx_flags: -g -Wall -fexceptions -frtti
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
        release:
          c_flags: -g -Wall
          cxx_flags: -g -Wall -fexceptions -frtti
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
    linux:
      targets:
        - 
      configurations:
        debug:
          c_flags: -g -Wall
          cxx_flags: -g -Wall
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
        release:
          c_flags: -g -Wall
          cxx_flags: -g -Wall
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
    windows:
      targets:
        - 2017.MD.Win32
        - 2017.MD.x64
        - 2017.MT.Win32
        - 2017.MT.x64
      configurations:
        debug:
          c_flags: /W4
          cxx_flags: /W4
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
        release:
          c_flags: /W4
          cxx_flags: /W4
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link_dirs: 
          link_libs: 
EOS
    }
  end
  
  def self.generate_rakefile
    open( "Rakefile", "wb" ){|f|
      f.puts <<EOS
require "buildrake"

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
  
  def self.generate_cmakefiles( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path )
    Buildrake::Rush.find( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
      Buildrake::Rush.remove( path )
    }
    
    yaml = YAML.load_file( yaml_file_path )
    config = yaml[ "config" ]
    project_name = safe_string( config[ "project_name" ] )
    
    open( common_cmake_file_path, "wb" ){|f|
      f.puts <<EOS
set(CMAKE_VERBOSE_MAKEFILE 1)
if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
  set(CMAKE_MACOSX_RPATH 1)
endif()
project(#{project_name})
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
      
      config[ "inc_dirs" ].each{|inc_dir|
        inc_dir = "${#{project_name.upcase}_ROOT_DIR}/#{inc_dir}" if inc_dir =~ /^\./
        f.puts <<EOS
include_directories(#{inc_dir})
EOS
      }
      f.puts ""
      
      config[ "builds" ].each{|build|
        type = safe_string( build[ "type" ] )
        name = safe_string( build[ "name" ] )
        f.puts "set(#{name.upcase}_SRCS)"
        build[ "srcs" ].each{|src|
          src = "${#{project_name.upcase}_ROOT_DIR}/#{src}" if src =~ /^\./
          f.puts "set(#{name.upcase}_SRCS ${#{name.upcase}_SRCS} #{src})"
        }
        
        case type
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
        f.puts ""
      }
    }
    
    debug = config[ "platforms" ][ platform ][ "configurations" ][ "debug" ]
    debug_c_flags = safe_array( debug[ "c_flags" ] )
    debug_cxx_flags = safe_array( debug[ "cxx_flags" ] )
    debug_exe_linker_flags = safe_array( debug[ "exe_linker_flags" ] )
    debug_static_linker_flags = safe_array( debug[ "static_linker_flags" ] )
    debug_shared_linker_flags = safe_array( debug[ "shared_linker_flags" ] )
    debug_link_dirs = safe_array( debug[ "link_dirs" ] ).map{|link_dir|
      link_dir = "${#{project_name.upcase}_ROOT_DIR}/#{link_dir}" if link_dir =~ /^\./
      link_dir
    }
    release = config[ "platforms" ][ platform ][ "configurations" ][ "release" ]
    release_c_flags = safe_array( release[ "c_flags" ] )
    release_cxx_flags = safe_array( release[ "cxx_flags" ] )
    release_exe_linker_flags = safe_array( release[ "exe_linker_flags" ] )
    release_static_linker_flags = safe_array( release[ "static_linker_flags" ] )
    release_shared_linker_flags = safe_array( release[ "shared_linker_flags" ] )
    release_link_dirs = safe_array( release[ "link_dirs" ] ).map{|link_dir|
      link_dir = "${#{project_name.upcase}_ROOT_DIR}/#{link_dir}" if link_dir =~ /^\./
      link_dir
    }
    
    open( platform_cmake_file_path, "wb" ){|f|
      f.puts <<EOS
cmake_minimum_required(VERSION #{safe_string( config[ "cmake_version" ] )})

set(#{project_name.upcase}_ROOT_DIR #{Buildrake::Rush.full_dir_path( Buildrake::Rush.dir_path( yaml_file_path ) )})

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{debug_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{debug_cxx_flags.join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} #{debug_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} #{debug_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} #{debug_shared_linker_flags.join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_DEBUG #{debug_link_dirs.join( " " )})

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} #{release_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} #{release_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} #{release_shared_linker_flags.join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_RELEASE #{release_link_dirs.join( " " )})

EOS
      
      config[ "builds" ].each{|build|
        name = safe_string( build[ "name" ] )
        f.puts <<EOS
set(#{name.upcase}_LINK_LIBS_DEBUG #{safe_array( debug[ "link_libs" ] ).join( " " )})
set(#{name.upcase}_LINK_LIBS_RELEASE #{safe_array( release[ "link_libs" ] ).join( " " )})
EOS
      }
      
      f.puts <<EOS

include(${CMAKE_CURRENT_LIST_DIR}/../common.cmake)
EOS
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
    # TODO
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
  configuration = Buildrake::Rush.env_get( "BUILDRAKE_CONFIGURATION" ).capitalize
  targets = Buildrake::Rush.env_get( "BUILDRAKE_TARGETS", "" ).split( " " )
  targets = Buildrake.safe_array( yaml[ "config" ][ "platforms" ][ platform ][ "targets" ] ) if targets.empty?
  build_key = get_build_key( platform, configuration )
  Buildrake::Rush.maked( build_key ){
    cmake_options = [
#      "--no-warn-unused-cli",
      "-DBUILDRAKE_PLATFORM=\#{platform}",
      "-DBUILDRAKE_CONFIGURATION=\#{configuration}",
      "-DBUILDRAKE_BUILD_KEY=\#{build_key}",
    ]
    block.call( cmake_options.join( " " ), configuration, targets )
  }
end

def build_cmake( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path, &block )
  is_generated_cmakefiles = false
  if ! Buildrake::Rush.file?( platform_cmake_file_path ) || Buildrake::Rush.file_stat( platform_cmake_file_path ).mtime < Buildrake::Rush.file_stat( yaml_file_path ).mtime
    Buildrake::generate_cmakefiles( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path )
    is_generated_cmakefiles = true
  end
  
  build( platform, yaml_file_path ){|cmake_option, configuration, targets|
    block.call( is_generated_cmakefiles, cmake_option, configuration, targets )
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
  
  def self.generate_platform_buildfiles( platform, name )
    Rush.remaked( platform ){
      open( "build.rb", "wb" ){|f|
        f.puts <<EOS
require "../common"

EOS
        
        case platform
        when "macos"
          f.puts <<EOS
build_cmake( "#{platform}", "../../buildrake.yaml", "../common.cmake", "./CMakeLists.txt" ){|is_generated_cmakefiles, cmake_option, configuration, targets|
  targets.each{|target|
    arch = target
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} \#{cmake_option}" ) if is_generated_cmakefiles
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{Buildrake::Rush.dir_name}" )
  [ "lib#{name}.a", "lib#{name}.dylib" ].each{|lib_name|
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
build_cmake( "#{platform}", "../../buildrake.yaml", "../common.cmake", "./CMakeLists.txt" ){|is_generated_cmakefiles, cmake_option, configuration, targets|
  targets.each{|target|
    sysroot, arch = target.split( "." )
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=\#{sysroot} \#{cmake_option}" ) if is_generated_cmakefiles
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{Buildrake::Rush.dir_name}" )
  [ "lib#{name}.a", "lib#{name}.dylib" ].each{|lib_name|
    if ! Buildrake::Rush.find( "*/\#{lib_name}" ).empty?
      lipo_create( [ "*/\#{lib_name}" ], lib_name )
      lipo_info( lib_name )
      Buildrake::Rush.rename( lib_name, "\#{lib_dir_path}/." )
    end
  }
}
EOS
        when "android"
          # TODO
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
    value = value.join( " " ) if value.instance_of?( Array )
    value
  end
  
  def self.safe_array( value, default_value = [] )
    value = safe_nil( value, default_value )
    value = [ value ] if ! value.instance_of?( Array )
    value
  end
  
  def self.safe_nil( value, default_value )
    value.nil? ? default_value : value
  end
end
