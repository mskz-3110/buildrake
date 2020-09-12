require "buildrake/version"
require "buildrake/rush"
require "buildrake/config"
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
    - 21.x86
    - 21.armeabi-v7a
    - 21.arm64-v8a
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

desc "Show help message"
task :help do
  yaml = YAML.load_file( "\#{Buildrake::Rush.full_dir_path( __FILE__ )}/buildrake.yaml" )
  yaml[ "anchors" ][ "platforms" ].each{|platform, _|
    [ "debug", "release" ].each{|configuration|
      puts "rake build \#{platform} \#{configuration}"
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
  
  def self.generate_cmakefile( platform, root_dir_path, project_name, buildrake, build, name, configurations )
    Buildrake::Rush.find( [ "CMakeCache.txt", "CMakeFiles", "CMakeScripts", "Makefile", "cmake_install.cmake" ] ){|path|
      Buildrake::Rush.remove( path )
    }
    
    open( "./CMakeLists.txt", "wb" ){|f|
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
      
      debug = configurations[ "debug" ]
      debug_c_flags = safe_array( debug[ "c_flags" ] )
      debug_cxx_flags = safe_array( debug[ "cxx_flags" ] )
      debug_exe_linker_flags = safe_array( debug[ "exe_linker_flags" ] )
      debug_static_linker_flags = safe_array( debug[ "static_linker_flags" ] )
      debug_shared_linker_flags = safe_array( debug[ "shared_linker_flags" ] )
      debug_link_dirs = safe_array( debug[ "link_dirs" ] ).map{|link_dir|
        link_dir = "${#{project_name.upcase}_ROOT_DIR}/#{link_dir}" if link_dir =~ /^\./
        link_dir
      }
      release = configurations[ "release" ]
      release_c_flags = safe_array( release[ "c_flags" ] )
      release_cxx_flags = safe_array( release[ "cxx_flags" ] )
      release_exe_linker_flags = safe_array( release[ "exe_linker_flags" ] )
      release_static_linker_flags = safe_array( release[ "static_linker_flags" ] )
      release_shared_linker_flags = safe_array( release[ "shared_linker_flags" ] )
      release_link_dirs = safe_array( release[ "link_dirs" ] ).map{|link_dir|
        link_dir = "${#{project_name.upcase}_ROOT_DIR}/#{link_dir}" if link_dir =~ /^\./
        link_dir
      }
      
      f.puts <<EOS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} #{debug_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} #{debug_cxx_flags.join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_DEBUG "${CMAKE_EXE_LINKER_FLAGS_DEBUG} #{debug_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_DEBUG "${CMAKE_STATIC_LINKER_FLAGS_DEBUG} #{debug_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_DEBUG "${CMAKE_SHARED_LINKER_FLAGS_DEBUG} #{debug_shared_linker_flags.join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_DEBUG #{debug_link_dirs.join( " " )})
set(#{name.upcase}_LINK_LIBS_DEBUG #{safe_array( debug[ "link_libs" ] ).join( " " )})

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} #{release_c_flags.join( ' ' )}")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "${CMAKE_EXE_LINKER_FLAGS_RELEASE} #{release_exe_linker_flags.join( ' ' )}")
set(CMAKE_STATIC_LINKER_FLAGS_RELEASE "${CMAKE_STATIC_LINKER_FLAGS_RELEASE} #{release_static_linker_flags.join( ' ' )}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} #{release_shared_linker_flags.join( ' ' )}")
set(#{project_name.upcase}_LINK_DIRS_RELEASE #{release_link_dirs.join( " " )})
set(#{name.upcase}_LINK_LIBS_RELEASE #{safe_array( release[ "link_libs" ] ).join( " " )})

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
      
      safe_array( build[ "inc_dirs" ] ).each{|inc_dir|
        inc_dir = "${#{project_name.upcase}_ROOT_DIR}/#{inc_dir}" if inc_dir =~ /^\./
        f.puts <<EOS
include_directories(#{inc_dir})
EOS
      }
      
      f.puts "set(#{name.upcase}_SRCS)"
      safe_array( build[ "srcs" ] ).each{|src|
        src = "${#{project_name.upcase}_ROOT_DIR}/#{src}" if src =~ /^\./
        f.puts "set(#{name.upcase}_SRCS ${#{name.upcase}_SRCS} #{src})"
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
  buildrake = yaml[ "buildrake" ]
  root_dir_path = Buildrake::Rush.full_dir_path( yaml_file_path )
  configuration = Buildrake::Rush.env_get( "BUILDRAKE_CONFIGURATION" ).capitalize
  build_key = get_build_key( platform, configuration )
  cmake_options = [
#    "--no-warn-unused-cli",
    "-DBUILDRAKE_PLATFORM=\#{platform}",
    "-DBUILDRAKE_CONFIGURATION=\#{configuration}",
    "-DBUILDRAKE_BUILD_KEY=\#{build_key}",
  ]
  Buildrake::Rush.maked( build_key ){
    buildrake[ "builds" ].each{|build|
      if build[ "platforms" ].key?( platform )
        block.call( root_dir_path, cmake_options.join( " " ), buildrake, build, build[ "name" ], build[ "platforms" ][ platform ][ "targets" ], configuration, build[ "platforms" ][ platform ][ "configurations" ] )
      end
    }
  }
end

def build_cmake( platform, yaml_file_path, &block )
  project_name = Buildrake::Rush.dir_name( yaml_file_path )
  build( platform, yaml_file_path ){|root_dir_path, cmake_option, buildrake, build, name, targets, configuration, configurations|
    Buildrake::Rush.maked( name ){
      is_generated_cmakefile = false
      if ! Buildrake::Rush.file?( "./CMakeLists.txt" ) || Buildrake::Rush.file_stat( "./CMakeLists.txt" ).mtime < Buildrake::Rush.file_stat( yaml_file_path ).mtime
        is_generated_cmakefile = true
        Buildrake::generate_cmakefile( platform, root_dir_path, project_name, buildrake, build, name, configurations )
      end
      block.call( is_generated_cmakefile, name, cmake_option, configuration, targets )
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
build_cmake( "#{platform}", "\#{__DIR__}/../../buildrake.yaml" ){|is_generated_cmakefile, name, cmake_option, configuration, targets|
  targets.each{|target|
    arch = target
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake .. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} \#{cmake_option}" ) if is_generated_cmakefile
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  dir_name = Buildrake::Rush.dir_name( "." )
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{dir_name}" )
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
build_cmake( "#{platform}", "\#{__DIR__}/../../buildrake.yaml" ){|is_generated_cmakefile, name, cmake_option, configuration, targets|
  targets.each{|target|
    sysroot, arch = target.split( "." )
    Buildrake::Rush.maked( arch ){
      Buildrake::Rush.sh( "cmake .. -DCMAKE_BUILD_TYPE=\#{configuration} -DCMAKE_OSX_ARCHITECTURES=\#{arch} -DCMAKE_OSX_SYSROOT=\#{sysroot} \#{cmake_option}" ) if is_generated_cmakefile
      Buildrake::Rush.sh( "make clean all" )
    }
  }
  
  dir_name = Buildrake::Rush.dir_name( "." )
  lib_dir_path = Buildrake::Rush.maked( "../../../lib/#{platform}/\#{dir_name}" )
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
    if ! value.is_a?( String )
      value = value.is_a?( Array ) ? value.join( " " ) : value.to_s
    end
    value
  end
  
  def self.safe_array( value, default_value = [] )
    value = safe_nil( value, default_value )
    if ! value.is_a?( Array )
      value = value.is_a?( String ) ? value.split( " " ) : [ value ]
    end
    value
  end
  
  def self.safe_nil( value, default_value )
    value.nil? ? default_value : value
  end
end
