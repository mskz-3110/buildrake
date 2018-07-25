require "buildrake/comment"

module Buildrake
  module CommentClass
    def self.generate( dll_name, input_file_path, output_file_path )
      ext_name = File.extname( output_file_path ).split( "." ).last
      class_name = File.basename( output_file_path, ".*" )
      items = []
      Comment.parse( input_file_path ){|comment, head_line, tail_line|
        if /\s*\[#{ext_name}\:(.+?)\]\s*(.+)/m =~ comment
          type = $1
          value = $2
          case type
          when "value"
            items.last[ :values ].push value
          when "api"
            if /(.+)\s(.+)\((.*)\)/ =~ value
              api = { :return_type => $1, :name => $2, :args => $3 }
              api[ :class_api_name ] = api[ :name ].split( "_" ).map{|v| v.capitalize}.join.gsub( /^#{class_name}/, "" )
              api[ :call_args ] = api[ :args ].split( "," ).map{|v| v.split( /\s/ ).last}.join( ", " )
              api[ :call_args ] = " #{api[ :call_args ]} " if ! api[ :call_args ].empty?
              api[ :return ] = ( "void" == api[ :return_type ] ) ? "" : "return "
              items.push({ :type => type, :values => [ api ] })
            end
          else
            items.push({ :type => type, :values => [ value ] })
          end
        end
      }
      
      return if items.empty?
      
      case ext_name
      when "cs"
        open( output_file_path, "wb" ){|f|
          f.puts <<EOS
#if ! UNITY_EDITOR && ( UNITY_IOS || UNITY_WEBGL )
  #define DLL_INTERNAL
#endif

using System;
using System.Runtime.InteropServices;

public class #{class_name} {
EOS
          
          items.each{|item|
            case item[ :type ]
            when "api"
              f.puts <<EOS
  #if DLL_INTERNAL
  [DllImport("__Internal")]
  #else
  [DllImport("#{dll_name}")]
  #endif
EOS
              
              api = item[ :values ].first
              case api[ :return_type ].downcase
              when "string"
                f.puts <<EOS
  private static extern IntPtr #{api[ :name ]}(#{api[ :args ]});
  public static #{api[ :return_type ]} #{api[ :class_api_name ]}(#{api[ :args ]}){ return Marshal.PtrToStringAuto( #{api[ :name ]}(#{api[ :call_args ]}) ); }
EOS
              else
                f.puts <<EOS
  private static extern #{api[ :return_type ]} #{api[ :name ]}(#{api[ :args ]});
  public static #{api[ :return_type ]} #{api[ :class_api_name ]}(#{api[ :args ]}){ #{api[ :return ]}#{api[ :name ]}(#{api[ :call_args ]}); }
EOS
              end
            when "enum"
              f.puts <<EOS
  public enum #{item[ :values ].first} {
    #{item[ :values ].slice( 1..-1 ).join( ",\n    " )}
  };
EOS
            when "callback"
              item[ :values ].each{|callback|
                f.puts <<EOS
  public delegate #{callback};
EOS
              }
            when "code"
              f.puts <<EOS
  #{item[ :values ].join( "\n" ).split( "\n" ).join( "\n  " )}
EOS
            end
            
            f.puts "  "
          }
          
          f.puts <<EOS
}
EOS
        }
      end
    end
  end
end
