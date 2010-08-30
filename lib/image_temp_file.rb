require "tempfile"

module MiniMagick
  class ImageTempFile < Tempfile
    def make_tmpname(ext, n)
      puts "ext: #{ext.to_s}"
      puts "n: #{n.to_s}"
      n = Time.now.to_f if n.nil?
      'mini_magick%s-%s%s' % [$$.to_s, n.to_s, ext ? ".#{ext}" : '']
    end
  end
end
