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
              comments.push $1 if ! $1.empty?
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
  end
end
