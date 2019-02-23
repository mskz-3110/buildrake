module Buildrake
  module Comment
    def self.parse( path, &block )
      open( path, "rb" ){|f|
        head_line = 0
        tail_line = 0
        comments = []
        f.each_line.each{|line|
          line.chomp!
          tail_line = tail_line + 1
          if 0 < head_line
            if /^(.*)\*\/$/ =~ line
              block.call( comments.join( "\n" ), head_line, tail_line ) if ! comments.empty?
              head_line = 0
              comments = []
            else
              comments.push line
            end
          else
            if /\/\/(.*)$/ =~ line
              block.call( $1, tail_line, tail_line ) if ! $1.empty?
            elsif /\/\*(.*)$/ =~ line
              comments.push $1 if ! $1.empty?
              head_line = tail_line
            end
          end
        }
      }
    end
    
    def self.parse_class( path, &block )
      class_values = {
        :namespace => "",
        :class_name => "",
        :elements => []
      }
      Comment.parse( path ){|comment, head_line, tail_line|
        next if /\s*\[cc\:(.+?)\]\s*(.*)/m !~ comment
        
        type = $1
        value = $2.strip
        case type
        when "namespace"
          class_values[ :namespace ] = value
        when "class_name"
          class_values[ :class_name ] = value
        when "enum_name"
          class_values[ :elements ].push( { :type => :enum, :name => value, :values => [] } )
        when "enum_value"
          class_values[ :elements ].last[ :values ].push value
        when "struct_name"
          class_values[ :elements ].push( { :type => :struct, :name => value, :members => [] } )
        when "struct_member"
          class_values[ :elements ].last[ :members ].push value
        when "api"
          if /(.+)\s(.+)\((.*)\)/ =~ value
            api = {
              :return_type => $1,
              :name => $2,
              :args => $3.strip
            }
            api[ :call_args ] = api[ :args ].split( "," ).map{|v| v.split( /\s/ ).last}.join( ", " )
            api[ :interface_code ] = "#{api[ :return_type ]} #{api[ :name ]}( #{api[ :args ]} )"
            api[ :call_code ] = "#{api[ :name ]}( #{api[ :call_args ]} )"
            return_code = ( "void" == api[ :return_type ] ) ? "" : "return "
            api[ :class_interface_code ] = "#{api[ :return_type ]} #{Mash.pascalcase( api[ :name ] )}( #{api[ :args ]} ){ #{return_code}#{api[ :call_code ]}; }"
            class_values[ :elements ].push( { :type => :api, :value => api } )
          else
            class_values[ :elements ].push( { :type => :api } )
          end
        else
          class_values[ :elements ].push( { :type => type.to_sym, :value => value } )
        end
      }
      block.call( class_values ) if ! class_values[ :class_name ].empty?
    end
    
    def self.generate_class_code_type_cs( dll_name, class_values )
      codes = []
      codes.push <<EOS
#if ! UNITY_EDITOR && ( UNITY_IOS || UNITY_WEBGL )
  #define DLL_INTERNAL
#endif

using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
EOS
      
      codes.push "namespace #{class_values[ :namespace ]} {" if ! class_values[ :namespace ].empty?
      codes.push "public class #{class_values[ :class_name ]} {"
      
      class_values[ :elements ].each{|element|
        case element[ :type ]
        when :callback
          codes.push <<EOS.chomp
  public delegate #{element[ :value ]};
  
EOS
        when :api
          codes.push <<EOS.chomp
#if DLL_INTERNAL
  [DllImport("__Internal")]
#else
  [DllImport("#{dll_name}")]
#endif
EOS
          
          if element.key?( :value )
            codes.push <<EOS.chomp
  static public extern #{element[ :value ][ :interface_code ]};
  static public #{element[ :value ][ :class_interface_code ]}
  
EOS
          end
        when :code
          codes.push <<EOS.chomp
  #{element[ :value ]}
  
EOS
        when :enum
          codes.push <<EOS.chomp
  public enum #{element[ :name ]} {
    #{element[ :values ].join( ",\n    " )}
  };
  
EOS
        when :struct
          codes.push <<EOS.chomp
  public struct #{element[ :name ]} {
    public #{element[ :members ].join( ";\n    public " )};
  };
  
EOS
        end
      }
      
      codes.push "}" if ! class_values[ :namespace ].empty?
      codes.push "}"
      
      codes.join( "\n" )
    end
  end
end
