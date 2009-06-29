require "open-uri"
require "stringio"
require "fileutils"
require "open3"

require File.join(File.dirname(__FILE__), '/image_temp_file')

module MiniMagick
  class MiniMagickError < RuntimeError; end

  class Image
    attr :path
    attr :tempfile
    attr :output

    # Class Methods
    # -------------
    class << self
      def from_blob(blob, ext = nil)
        begin
          tempfile = ImageTempFile.new(ext)
          tempfile.binmode
          tempfile.write(blob)
        ensure
          tempfile.close if tempfile
        end

        return self.new(tempfile.path, tempfile)
      end

      # Use this if you don't want to overwrite the image file
      def open(image_path)
        File.open(image_path, "rb") do |f|
          self.from_blob(f.read, File.extname(image_path))
        end
      end
      alias_method :from_file, :open
    end

    # Instance Methods
    # ----------------
    def initialize(input_path, tempfile=nil)
      @path = input_path
      @tempfile = tempfile # ensures that the tempfile will stick around until this image is garbage collected.

      # Ensure that the file is an image
      CommandRunner::run("identify", @path)
    end

    # For reference see http://www.imagemagick.org/script/command-line-options.php#format
    def [](value)
      # Why do I go to the trouble of putting in newlines? Because otherwise animated gifs screw everything up
      case value.to_s
      when "format"
        CommandRunner::run("identify", "-format", format_option("%m"), @path).split("\n")[0]
      when "height"
        CommandRunner::run("identify", "-format", format_option("%h"), @path).split("\n")[0].to_i
      when "width"
        CommandRunner::run("identify", "-format", format_option("%w"), @path).split("\n")[0].to_i
      when "dimensions"
        CommandRunner::run("identify", "-format", format_option("%w %h"), @path).split("\n")[0].split.map{|v|v.to_i}
      when "size"
        File.size(@path) # Do this because calling identify -format "%b" on an animated gif fails!
      when "original_at"
        # Get the EXIF original capture as a Time object
        Time.local(*self["EXIF:DateTimeOriginal"].split(/:|\s+/)) rescue nil
      when /^EXIF\:/i
        CommandRunner::run('identify', '-format', "\"%[#{value}]\"", @path).chop
      else
        CommandRunner::run('identify', '-format', "\"#{value}\"", @path).split("\n")[0]
      end
    end

    # Sends raw commands to imagemagick's mogrify command. The image path is automatically appended to the command
    def <<(*args)
      CommandRunner::run("mogrify", *args << @path)
    end

    # This is a 'special' command because it needs to change @path to reflect the new extension
    # Formatting an animation into a non-animated type will result in ImageMagick creating multiple
    # pages (starting with 0).  You can choose which page you want to manipulate.  We default to the
    # first page.
    def format(format, page=0)
      CommandRunner::run("mogrify", "-format", format, @path)

      old_path = @path.dup
      @path.sub!(/(\.\w+)?$/, ".#{format}")
      File.delete(old_path) unless old_path == @path

      unless File.exists?(@path)
        begin
          FileUtils.copy_file(@path.sub(".#{format}", "-#{page}.#{format}"), @path)
        rescue e
          raise MiniMagickError, "Unable to format to #{format}; #{e}" unless File.exist?(@path)
        end
      end
    ensure
      Dir[@path.sub(/(\.\w+)?$/, "-[0-9]*.#{format}")].each do |fname|
        File.unlink(fname)
      end
    end

    # Writes the temporary image that we are using for processing to the output path
    def write(output_path)
      FileUtils.copy_file @path, output_path
      CommandRunner::run "identify", output_path # Verify that we have a good image
    end

    # Give you raw data back
    def to_blob
      f = File.new @path
      f.binmode
      f.read
    ensure
      f.close if f
    end

    # If an unknown method is called then it is sent through the morgrify program
    # Look here to find all the commands (http://www.imagemagick.org/script/mogrify.php)
    def method_missing(symbol, *args)
      args.push(@path) # push the path onto the end
      CommandRunner::run("mogrify", "-#{symbol}", *args)
      self
    end

    # You can use multiple commands together using this method
    def combine_options(&block)
      c = CommandBuilder.new
      block.call c
      CommandRunner::run("mogrify", *c.args << @path)
    end

    # Check to see if we are running on win32 -- we need to escape things differently
    def windows?
      !(RUBY_PLATFORM =~ /win32/).nil?
    end

    # Outputs a carriage-return delimited format string for Unix and Windows
    def format_option(format)
      windows? ? "#{format}\\n" : "#{format}\\\\n"
    end

  end
  

  # Composes two images together via ImageMagick's 'composite' script
  class Composite
    
    # Class Methods
    # -------------
    
    # To create a composite simply call Composite.new with the images you want composite,
    # the path to the output file and any command line options you may want. Note that the
    # images should be passed in the order you want them stacked (first image is on top, second
    # image is in back). You will be returned a MiniMagick::Image instance for the new composited image:
    #
    #   image1 = MiniMagick::Image.open('foreground.png')
    #   image2 = MiniMagick::Image.open('background.png')
    #   output_image = MiniMagick::Composite.new(image1, image2, 'jpg', :gravity => 'NorthEast')
    #   output_image.write('combined_image.jpg')
    #
    # The above example would combine the two images into a new JPEG file and, if the two images are 
    # different sizes it will stick the top image into the upper right (north east) corner of the bottom image.
    # The the image is saved using the standard Image.save method.
    #
    # The 'composite' script has several options, see here: http://www.imagemagick.org/script/composite.php
    def self.new(*args)

      image1 = args[0]
      image2 = args[1]
      output_extension = args[2] || 'jpg'
      opts = args[3] || {}
      
      begin
        tempfile = ImageTempFile.new(output_extension)
        tempfile.binmode
      ensure
        tempfile.close
      end
      
      args = opts.collect { |key,value| "-#{key.to_s} #{value.to_s}" }  # collect hash parts into arguments
      args.push(image1.path)
      args.push(image2.path)
      args.push(tempfile.path)

      CommandRunner::run('composite',*args)
      
      return Image.open(tempfile.path)
    end
    
  end
  
  
  # Does the job of running commands in the shell.
  class CommandRunner
    
    # Class Methods
    # -------------
    def self.run(command, *args)
      args.collect! do |arg|        
        # args can contain characters like '>' so we must escape them, but don't quote switches
        if arg !~ /^\+|\-/
          "\"#{arg}\""
        else
          arg.to_s
        end
      end

      command = "#{command} #{args.join(' ')}"
      output = `#{command} 2>&1`

      if $?.exitstatus != 0
        raise MiniMagickError, "ImageMagick command (#{command.inspect}) failed: #{{:status_code => $?, :output => output}.inspect}"
      else
        output
      end
    end
    
  end
  

  class CommandBuilder
    attr :args

    def initialize
      @args = []
    end

    def method_missing(symbol, *args)
      @args << "-#{symbol}"
      @args += args
    end

    def +(value)
      @args << "+#{value}"
    end
  end
end
