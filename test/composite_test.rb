require 'test/unit'
require File.join(File.dirname(__FILE__), '../lib/mini_magick')

class Composite < Test::Unit::TestCase
  include MiniMagick

  CURRENT_DIR = File.dirname(File.expand_path(__FILE__)) + "/"

  TOP_IMAGE_PATH = CURRENT_DIR + "simple.gif"
  BOTTOM_IMAGE_PATH = CURRENT_DIR + "leaves.tiff"

  def test_composite_from_images
    begin
      image1 = Image.open(TOP_IMAGE_PATH)
      image2 = Image.open(BOTTOM_IMAGE_PATH)
      output_path = CURRENT_DIR + 'combined.jpg'
      output_image = Composite.new(image1, image2, output_path)
      
      assert_equal output_image.class, MiniMagick::Image
      assert File.exists?(output_path)
      assert_match(/^jpeg$/i, output_image[:format])
    ensure
      File.delete output_path
    end
  end
  
end