require "buildrake/version"
require "buildrake/config"
require "buildrake/comment"
require "buildrake/github"

module Buildrake
  def self.setup
    generate_rakefile
  end
  
  def self.generate_rakefile
    return if Mash.file?( "Rakefile" )
    
    open( "Rakefile", "wb" ){|f|
      f.puts <<EOS
require "buildrake"
extend Buildrake::Mash

ROOT_DIR = File.expand_path( ".", File.dirname( __FILE__ ) )

class Config < Buildrake::Config
  method_accessor :srcs
  
  def initialize( *args )
    # Project name
    super( "" )
    
    # Include
    inc_dirs [ "\#{ROOT_DIR}/inc" ]
    
    # Library
    @srcs = Dir.glob( "\#{ROOT_DIR}/src/**/*.c" )
    library( project_name, srcs )
    
    @platforms.each{|platform|
      @configs.each{|config|
        lib_dirs = [ "\#{ROOT_DIR}/lib/$(LIB_PLATFORM_PATH)" ]
        lib_dir( platform, config, lib_dirs )
      }
    }
    
    # Execute
    libs = [  ]
    execute( "", [ "\#{ROOT_DIR}/src/**/*.c" ], libs )
  end
end

desc "Setup"
task :setup do
  Config.run( [ "setup" ] )
  exit( 0 )
end

desc "Show help message"
task :help do
  Config.run( [ "help" ] )
  exit( 0 )
end

desc "Build"
task :build do
  Config.run( [ "build" ] )
  exit( 0 )
end
EOS
    }
  end
end
