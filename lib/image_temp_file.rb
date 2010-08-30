require "tempfile"

module MiniMagick
  class ImageTempFile < Tempfile
    def make_tmpname(ext)
      'mini_magick%d-%d%s' % [$$, Time.now.to_f, ext ? ".#{ext}" : '']
    end
  end
end
