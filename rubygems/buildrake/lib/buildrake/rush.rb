require "fileutils"

module Buildrake
  module Rush
    extend self
    
    def sh( command, options = {}, &block )
      caption = "[#{full_dir_path}] #{command}"
      puts caption
      system( command, options )
      status = $?
      if block_given?
        block.call( status )
      else
        raise "Failed(#{status.exitstatus}): #{caption}" if 0 != status.exitstatus
      end
    end
    
    def which?( name )
      Rush.sh( "which #{name}", :out => "/dev/null", :err => "/dev/null" ){|status| return ( 0 == status )}
    end
    
    def file?( path )
      File.exists?( path )
    end
    
    def dir?( path )
      Dir.exists?( path )
    end
    
    def changed( path, &block )
      Dir.chdir( path ){
        block.call
      }
    end
    
    def maked( path, &block )
      FileUtils.mkdir_p( path ) if ! Rush.dir?( path )
      Rush.changed( path, &block ) if block_given?
      path
    end
    
    def remaked( path, &block )
      Rush.remove( path )
      Rush.maked( path, &block )
    end
    
    def copy( src, dst )
      FileUtils.cp_r( src, dst )
    end
    
    def rename( src, dst )
      FileUtils.mv( src, dst )
    end
    
    def remove( path )
      FileUtils.rm_rf( path ) if Rush.file?( path ) || Rush.dir?( path )
    end
    
    def find( pattern, &block )
      Dir.glob( pattern, &block )
    end
    
    def base_name( path )
      File.basename( path )
    end
    
    def ext_name( path )
      File.extname( path ).gsub( /^\./, "" )
    end
    
    def dir_name( path = "." )
      Rush.base_name( Rush.full_dir_path( File.dirname( path ) ) )
    end
    
    def full_dir_path( path = "." )
      path = File.dirname( path ) if Rush.file?( path )
      Rush.changed( path ){
        path = Dir.pwd
      }
      path
    end
    
    def full_file_path( path = "." )
      dir_path = Buildrake::Rush.full_dir_path( path )
      "#{dir_path}/#{File.basename( path )}"
    end
    
    def env?( key )
      ENV.key?( key )
    end
    
    def env_get( key, default_value = nil )
      env?( key ) ? ENV[ key ] : default_value
    end
    
    def env_set( key, value )
      ENV[ key ] = value
    end
    
    def pascal_case( name )
      name.split( "_" ).map{|v| v.capitalize}.join
    end
    
    def os_type
      os_type = RbConfig::CONFIG[ "host_os" ]
      case os_type
      when /darwin/
        os_type = "macos"
      when /linux/
        os_type = "linux"
      when /mingw/
        os_type = "windows"
      end
      os_type
    end
    
    def macos?
      ( "macos" == Rush.os_type )
    end
    
    def linux?
      ( "linux" == Rush.os_type )
    end
    
    def windows?
      ( "windows" == Rush.os_type )
    end
    
    def file_stat( path )
      File::Stat.new( path )
    end
  end
end
