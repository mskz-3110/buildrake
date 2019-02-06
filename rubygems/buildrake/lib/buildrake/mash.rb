require "fileutils"

module Buildrake
  module Mash
    extend self
    
    def sh( command, &block )
      puts "[#{pwd}] #{command}"
      system( command )
      status = $?
      if block_given?
        block.call( status )
      else
        raise "Command failed with status (#{status.exitstatus}): #{command}" if 0 != status.exitstatus
      end
    end
    
    def file?( path, &block )
      is_exist = File.exists?( path )
      block.call( path ) if block_given? && is_exist
      is_exist
    end
    
    def dir?( path, &block )
      is_exist = Dir.exists?( path )
      block.call( path ) if block_given? && is_exist
      is_exist
    end
    
    def chdir( dir, &block )
      Dir.chdir( dir, &block ) if block_given?
    end
    
    def mkdir( dir, &block )
      FileUtils.mkdir_p( dir ) if ! dir?( dir )
      chdir( dir, &block )
    end
    
    def rm( path )
      FileUtils.rm_rf( path ) if file?( path ) || dir?( path )
    end
    
    def cp( src, dst )
      FileUtils.cp( src, dst )
    end
    
    def mv( src, dst )
      FileUtils.mv( src, dst )
    end
    
    def find( pattern, &block )
      Dir.glob( pattern, &block )
    end
    
    def dirname( path )
      File.dirname( path )
    end
    
    def basename( path, suffix = "" )
      File.basename( path, suffix )
    end
    
    def extname( path )
      File.extname( path )
    end
    
    def fullpath( path, base_dir )
      File.expand_path( path, base_dir )
    end
    
    def pwd
      Dir.pwd
    end
    
    def env?( key )
      ENV.key?( key )
    end
    
    def env( key, value = nil )
      if value.nil? && env?( key )
        value = ENV[ key ]
      else
        ENV[ key ] = value
      end
      value
    end
  end
end
