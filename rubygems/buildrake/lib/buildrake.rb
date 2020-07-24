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
          link:
            dirs:
              - 
            libs:
              - 
        release:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link:
            dirs:
              - 
            libs:
              - 
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
          link:
            dirs:
              - 
            libs:
              - 
        release:
          c_flags: -g -Wall -fembed-bitcode
          cxx_flags: -g -Wall -fembed-bitcode
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link:
            dirs:
              - 
            libs:
              - 
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
          link:
            dirs:
              - 
            libs:
              - 
        release:
          c_flags: -g -Wall
          cxx_flags: -g -Wall -fexceptions -frtti
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link:
            dirs:
              - 
            libs:
              - 
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
          link:
            dirs:
              - 
            libs:
              - 
        release:
          c_flags: -g -Wall
          cxx_flags: -g -Wall
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link:
            dirs:
              - 
            libs:
              - 
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
          link:
            dirs:
              - 
            libs:
              - 
        release:
          c_flags: /W4
          cxx_flags: /W4
          exe_linker_flags: 
          static_linker_flags: 
          shared_linker_flags: 
          link:
            dirs:
              - 
            libs:
              - 
EOS
    }
  end
  
  def self.generate_rakefile
    open( "Rakefile", "wb" ){|f|
      f.puts <<EOS
require "buildrake"

desc "Show help message"
task :help do
  yaml = YAML.load_file( "./buildrake.yaml" )
  yaml[ "config" ][ "platforms" ].each{|platform, platform_value|
    platform_value[ "configurations" ].each{|configuration, configuration_value|
      puts "rake build \#{platform} \#{configuration}"
    }
  }
  puts "rake help"
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
      Buildrake::Rush.sh( "BR_CONFIGURATION=\#{configuration} ruby ./build.rb" )
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
Gemfile.lock
EOS
    }
  end
  
  def self.generate_cmakefiles( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path )
    Buildrake::Rush.find( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
      Buildrake::Rush.remove( path )
    }
    
    root_dir_path = Buildrake::Rush.full_dir_path( Buildrake::Rush.dir_path( yaml_file_path ) )
    yaml = YAML.load_file( yaml_file_path )
    config = yaml[ "config" ]
    cmake_version = safe_string( config[ "cmake_version" ] )
    project_name = safe_string( config[ "project_name" ] )
    
    open( common_cmake_file_path, "wb" ){|f|
      f.puts <<EOS
set(CMAKE_VERBOSE_MAKEFILE 1)
set(CMAKE_MACOSX_RPATH 1)
project(#{project_name})
set(#{project_name.upcase}_ROOT_DIR #{root_dir_path})
message(#{project_name.upcase}_ROOT_DIR:${#{project_name.upcase}_ROOT_DIR})
message(CMAKE_BUILD_TYPE:${CMAKE_BUILD_TYPE})
string(TOUPPER ${CMAKE_BUILD_TYPE} CMAKE_BUILD_TYPE_UPPER)
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
        f.puts <<EOS
message(#{name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE_UPPER}:${#{name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE_UPPER}})
link_directories(${#{name.upcase}_LINK_DIRS_${CMAKE_BUILD_TYPE_UPPER}})
message(#{name.upcase}_LINK_LIBS_${CMAKE_BUILD_TYPE_UPPER}:${#{name.upcase}_LINK_LIBS_${CMAKE_BUILD_TYPE_UPPER}})
EOS
        
        f.puts "set(#{name.upcase}_SRCS)"
        build[ "srcs" ].each{|src|
          src = "${#{name.upcase}_ROOT_DIR}/#{src}" if src =~ /^\./
          f.puts "set(#{name.upcase}_SRCS ${#{name.upcase}_SRCS} #{src})"
        }
        f.puts ""
        
        # TODO
        
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
          # TODO
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
    release = config[ "platforms" ][ platform ][ "configurations" ][ "release" ]
    release_c_flags = safe_array( release[ "c_flags" ] )
    release_cxx_flags = safe_array( release[ "cxx_flags" ] )
    release_exe_linker_flags = safe_array( release[ "exe_linker_flags" ] )
    release_static_linker_flags = safe_array( release[ "static_linker_flags" ] )
    release_shared_linker_flags = safe_array( release[ "shared_linker_flags" ] )
    
    open( platform_cmake_file_path, "wb" ){|f|
      f.puts <<EOS
cmake_minimum_required(VERSION #{cmake_version})

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{debug_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{debug_cxx_flags.join( ' ' )}")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")

set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} #{debug_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} #{debug_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} #{debug_shared_linker_flags.join( ' ' )}")

set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} #{release_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} #{release_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} #{release_shared_linker_flags.join( ' ' )}")

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

def get_build_path( platform, configuration )
  "\#{get_platform_build_name( platform )}_\#{configuration}"
end

def build_cmake( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path )
  if ! Buildrake::Rush.file?( platform_cmake_file_path ) || Buildrake::Rush.file_stat( platform_cmake_file_path ).mtime < Buildrake::Rush.file_stat( yaml_file_path ).mtime
    Buildrake::generate_cmakefiles( platform, yaml_file_path, common_cmake_file_path, platform_cmake_file_path )
  end
  
  yaml = YAML.load_file( yaml_file_path )
  configuration = Buildrake::Rush.env_get( "BR_CONFIGURATION" ).capitalize
  targets = Buildrake::Rush.env_get( "BR_TARGETS", "" ).split( " " )
  targets = Buildrake.safe_array( yaml[ "config" ][ "platforms" ][ platform ][ "targets" ] ) if targets.empty?
  build_path = get_build_path( platform, configuration )
  Buildrake::Rush.maked( build_path ){
    yield( configuration, targets )
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
build_cmake( "#{platform}", "../../buildrake.yaml", "../common.cmake", "./CMakeLists.txt" ){|configuration, targets|
  targets.each{|target|
    arch = target
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} --no-warn-unused-cli" )
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{Buildrake::Rush.dir_name}" )
  [ "lib#{name}.a", "lib#{name}.dylib" ].each{|lib_name|
    lipo_create( [ "*/\#{lib_name}" ], lib_name )
    lipo_info( lib_name )
    Buildrake::Rush.rename( lib_name, "\#{lib_dir_path}/." )
  }
}
EOS
        when "ios"
          f.puts <<EOS
build_cmake( "#{platform}", "../../buildrake.yaml", "../common.cmake", "./CMakeLists.txt" ){|configuration, targets|
  targets.each{|target|
    sysroot, arch = target.split( "." )
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake ../.. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=\#{sysroot} --no-warn-unused-cli" )
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{Buildrake::Rush.dir_name}" )
  [ "lib#{name}.a", "lib#{name}.dylib" ].each{|lib_name|
    lipo_create( [ "*/\#{lib_name}" ], lib_name )
    lipo_info( lib_name )
    Buildrake::Rush.rename( lib_name, "\#{lib_dir_path}/." )
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
    value = value[ 0 ] if value.instance_of?( Array )
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
