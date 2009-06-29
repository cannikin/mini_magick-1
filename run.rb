#!/usr/bin/env ruby

require 'lib/mini_magick'

image1 = MiniMagick::Image.open('test/simple.gif')
image2 = MiniMagick::Image.open('test/leaves.tiff')

output = MiniMagick::Composite.new(image1,image2)
output.write('test/composition.jpg')
