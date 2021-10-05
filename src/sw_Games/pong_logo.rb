module SW
  module Games
    module Pong
      outline =[[120.993074, -55.086041, 0.0], [54.290469, -36.476233, 0.0], [40.637556, -79.046411, 0.0],\
      [32.976898, -132.058256, 0.0], [94.648788, -140.970364, 0.0], [128.269946, -114.76906, 0.0]]

      one = [[82.507143, -124.092516, 0.0], [42.809806, -118.289651, 0.0], [39.17308, -126.726735, 0.0],\
      [93.649645, -133.828338, 0.0], [119.698181, -113.466544, 0.0], [96.549889, -109.41604, 0.0]]

      two = [[69.556034, -95.398689, 0.0], [49.470557, -91.742694, 0.0], [45.698003, -101.138622, 0.0],\
      [83.201705, -108.332889, 0.0], [96.119952, -91.460386, 0.0], [74.941447, -86.239653, 0.0]]

      three = [[75.768526, -68.00366, 0.0], [55.74553, -62.917137, 0.0], [52.138132, -73.242619, 0.0], [70.906612, -77.521246, 0.0]]
      
      
      center = Geom::Point3d.new(475, 425, 0)
      rotate_around_vector = Geom::Vector3d.new(0, 0, 1)
      angle = 0.0.degrees
      
      tr = Geom::Transformation.rotation([100,100,0], rotate_around_vector, angle)
      tr = Geom::Transformation.translation(center) * tr
      
      
      Outline = outline.map {|pt| pt.transform(tr)}
      Inner_One = one.map {|pt| pt.transform(tr)}
      Inner_Two = two.map {|pt| pt.transform(tr)}
      Inner_Three = three.map {|pt| pt.transform(tr)}
      
      def self.draw_logo(view)
        point = Geom::Point3d.new(460, 425, 0)
        text = 'Trimble Arena'
        
        if RUBY_VERSION.to_f >= 2.2
          view.draw_text(point, text, options = {:font => "Arial", :size => 20, :bold => true, color: "LightGrey"})
        end
        
        view.drawing_color = Sketchup::Color.new(256, 200, 200)
        view.draw2d(GL_POLYGON, *Outline)

        view.drawing_color = Sketchup::Color.new(256, 256, 256)
        view.draw2d(GL_POLYGON, *Inner_One)
        view.draw2d(GL_POLYGON, *Inner_Two)
        view.draw2d(GL_POLYGON, *Inner_Three)
      end
    end
  end
end
