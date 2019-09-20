require "buildrake/version"
require "buildrake/rush"
require "buildrake/config"
require "buildrake/comment"
require "buildrake/github"

module Buildrake
  def self.setup
    generate_rakefile
    generate_gitignore
  end
  
  def self.generate_rakefile
    return if Rush.file?( "Rakefile" )
    
    open( "Rakefile", "wb" ){|f|
      f.puts <<EOS
require "buildrake"

class Config < Buildrake::Config
  method_accessor :srcs
  
  def initialize( *args )
    super( "", Buildrake::Rush.full_dir_path( Buildrake::Rush.dir_path( __FILE__ ) ) )
    
    inc_dirs [ "\#{@root_path}/inc" ]
    
    # Library
    @srcs = [  ]
    library( project_name, @srcs )
    
    @platforms.each{|platform|
      @configs.each{|config|
        case platform
        when :android
          lib_dirs = [ "\#{@root_path}/lib/android/$(ANDROID_NDK_VERSION)_$(CONFIG)" ]
        else
          lib_dirs = [ "\#{@root_path}/lib/$(PLATFORM_PATH)" ]
        end
        lib_dir( platform, config, lib_dirs )
      }
    }
    
    # Execute
    if Buildrake::Rush.windows?
      libs = [  ]
    else
      libs = [  ]
    end
    execute( "", [  ], libs )
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
  
  def self.generate_gitignore
    return if Rush.file?( ".gitignore" )
    
    open( ".gitignore", "wb" ){|f|
      f.puts <<EOS
/build
/lib
EOS
    }
  end
end
