require File.join(SW::Games::PLUGIN_DIR, 'game_core.rb')
require File.join(SW::Games::PLUGIN_DIR, 'pong.rb')


module SW
  module Games
    def self.load_menus()
          
      # Load Menu Items  
      if !@loaded
        toolbar = UI::Toolbar.new "SW Games"
        
        cmd = UI::Command.new("Play Pong") {Games::Pong.start()}
        cmd.large_icon = cmd.small_icon =  File.join(SW::Games::PLUGIN_DIR, "icons/pong.png")
        cmd.tooltip = "Play Pong"
        cmd.status_bar_text = "Start a Game"
        toolbar = toolbar.add_item cmd
        
        toolbar.show
      @loaded = true
      end
    end
    load_menus()
  end
end