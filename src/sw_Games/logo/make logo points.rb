
module SW
module Whirly
  def self.round(fl)
         (1000000 * fl).round().to_f / 1000000
  end


  model = Sketchup.active_model
  #ents = model.active_entities
  sel = model.selection
  face = sel[0]
  ents = face.outer_loop.edges
 

  a = []
  ents.each{|e|
    a << e.start.position.to_a.map{|e| round(e)}
    #a << e.end.position.to_a.map{|e| round(e)}
  }
  a
end
end
