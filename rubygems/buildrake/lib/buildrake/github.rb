module Buildrake
  class Github
    def self.asset_urls( base_url )
      asset_urls = []
      require "nokogiri"
      require "open-uri"
      base_uri = URI.parse( base_url )
      document = Nokogiri::HTML.parse( open( base_url ).readlines.join )
      document.xpath( '//a' ).each{|element|
        href = element.attribute( "href" )
        case Rush.ext_name( href )
        when "zip"
          asset_urls.push base_uri.merge( href ).to_s
        end
      }
      asset_urls
    end
    
    def self.download_assets( base_url )
      asset_urls( base_url ).each{|asset_url|
        asset_uri = URI.parse( asset_url )
        file_name = Rush.base_name( asset_uri.path )
        Rush.sh( "wget -q #{asset_url}" )
        Rush.sh( "unzip -q #{file_name}" )
        Rush.remove( file_name )
      }
    end
  end
end
