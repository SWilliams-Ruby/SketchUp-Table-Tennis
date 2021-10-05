

path = File.join(SW::Games::PLUGIN_DIR, "pong_logo.rb")
require path

#  Pong is a simple game that runs via Game Tool's draw method, 
#  so just think of this as a very complicated progressbar.
#
#  We hook the SU::Tool interface http://ruby.sketchup.com/Sketchup/Tool.html of the Game Tool
#  to define a new method for :onSetCursor

module SW
  module Games
    module Pong
      #####################
      # Structures
      #
      Paddle = Struct.new(:x, :y, :time)
      Ball_Path = Struct.new(:start, :end)

      ################################
      # Bouncing ball sound for windows
      # if we are on windows with Ruby 2.2.0 or newer
      WIN_OS = ( Sketchup.platform == :platform_win rescue RUBY_PLATFORM !~ /(darwin)/i )
      
      if WIN_OS && (RUBY_VERSION.to_f >= 2.2)
        # Can we load the Sound module
        begin
          require File.join(SW::Games::PLUGIN_DIR, "sound/win32-sound.rb")
          include Win32Sound
          SOUND = true
        rescue LoadError
          puts "You might need to install the ffi Gem for sound. GEM.install 'ffi'"
          SOUND = false
        end
      else
        SOUND = false
      end
        
      ######################################
      # Start a game
      # initalize a GameCore instance and set up custom methods 
      # and game variables
      #
      def self.start()
        @game_tool = SW::GameCore.new(
          method(:on_complete),
          method(:on_abort),
          method(:play)
        )
        return unless @game_tool
        
        # define the game draw method 
        @game_tool.user_draw = method(:user_draw)

        # Setup up Game Tool initial mouse location
        @game_tool.instance_variable_set(:@mouse_x, 1200)
        @game_tool.instance_variable_set(:@mouse_y, 400)
             
        # Have the Game tool show the custom little dot for the cursor
        path = __FILE__
        path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)
        cpath = File.join(File.dirname(path), 'cursors')
        pong_cursor ||= UI.create_cursor(File.join(cpath, "pong.png"), 0, 12)
        
        @game_tool.instance_variable_set(:@pong_cursor, pong_cursor)
        @game_tool.define_singleton_method(:onSetCursor) {
          UI.set_cursor(@pong_cursor)
        }

        # Create the puck perimeter
        center = Geom::Point3d.new(0, 0, 0)
        rotate_around_vector = Geom::Vector3d.new(0, 0, 1)
        angle = 7.2.degrees
        tr = Geom::Transformation.rotation([0,0,0], rotate_around_vector, angle)
        @radius = 15
        radius = Geom::Vector3d.new(@radius, 0, 0)
        @puck_perimeter ||= 51.times.map {center + radius.transform!(tr) }
        
        # Paddle sizes
        @half_paddle_height = 30
        @user_paddle_outline = [[0, @half_paddle_height,0],
                          [12, @half_paddle_height,0],
                          [12, -@half_paddle_height, 0], [0,
                          -@half_paddle_height,0]]
        
        @hal_paddle_outline = [[0, @half_paddle_height,0],
                          [-12, @half_paddle_height,0],
                          [-12, -@half_paddle_height, 0], [0,
                          -@half_paddle_height,0]]
        
        
        # Cache of Paddle structures, the elements are Paddle structures
        @user_paddle_cache = []
        @hal_paddle_cache = []
        @hal_paddle_x = 150
        @hal_paddle_y = 400
        @hal_paddle_cache << Paddle.new(@hal_paddle_x, @hal_paddle_y, Time.now) 
        
        # Arena size
        @top = 100
        @bottom = 600
        @left = 50
        @right = 1000
        @arena = [[ @left, @top, 0],[ @right, @top, 0],[ @right, @bottom, 0],[ @left, @bottom, 0]]
        
        # Regulate ball speed and frame rate
        @last_draw_time = Time.now - 0.01
        @last_yield_time = Time.now
        @start_time = Time.now
        @frame_count = 0 # for statistics

        # Ball location, direction, and speed
        @ball_location = Geom::Point3d.new( @right - 100, @top + 200, 0)
        @ball_vector = Geom::Vector3d.new( -1, 0.5 - rand(), 0).normalize!
        @last_ball_location = @ball_location
        @ball_speed = 0.5

        # Game length and state
        @game_tool_length = 20
        @in_play = true
      end # start
      
      # Play for @game_tool_length time in seconds
      def self.play(game_tool)
        while @in_play && (Time.now - @start_time) < @game_tool_length
          # Redraws are tied to the monitor refresh rate,  50hz or 60hz
          game_tool.refresh
        end
      end
      
      
      #################################################################
      #
      # Some ugly code follows. sorry abou that
      #
      
      def self.user_draw(view)
        @frame_count += 1 # statistics
     
        view.line_stipple = '' # Solid line
        view.line_width = 2
        
        # Draw a white background 
        view.drawing_color = Sketchup::Color.new(256, 256, 256)
        view.draw2d(GL_POLYGON, @arena)
        
        # Draw arena outline
        view.drawing_color = Sketchup::Color.new(64, 64, 64)
        view.draw2d(GL_LINE_STRIP, @arena << [ @left, @top, 0])
        
        ###############
        # Draw the Sketchup Logo
        #
        draw_logo(view)
        
        # Add the current paddle location to the paddle cache
        # note:  paddle_y is the vertical center of the paddle
        #paddle_x = @game_tool.instance_variable_get(:@mouse_x)
        #paddle_y = @game_tool.instance_variable_get(:@mouse_y)
        paddle_x = @game_tool.mouse_x
        paddle_y = @game_tool.mouse_y
        paddle_y = @top if paddle_y < @top
        paddle_y = @bottom if paddle_y  > @bottom
        @user_paddle_cache << Paddle.new(paddle_x, paddle_y, Time.now) 
        
        ######################################################
        # update the ball location, compensating for refresh interval
        #
        @last_ball_location = @ball_location.clone  
        dif = (Time.now - @last_draw_time) * 1000
        @last_draw_time = Time.now
        @ball_location.x = @ball_location.x + (@ball_vector.x * @ball_speed * dif)
        @ball_location.y = @ball_location.y + (@ball_vector.y * @ball_speed * dif)
        
        # Save the ball movement in Sketchup Line format
        ball_path = Ball_Path.new(@last_ball_location, @ball_location)

        ###########################################
        # Determine if the ball ball hit a wall?
        # TODO: add true reflection at the point of contact

        # test the top wall if the ball is moving up
        if ball_path.end.y < ball_path.start.y && (@ball_location.y - @radius) < @top 
          @ball_vector.y = -@ball_vector.y
        end

        # test the bottom wall if the ball is moving down
        if ball_path.end.y > ball_path.start.y &&  (@ball_location.y + @radius) > @bottom
          @ball_vector.y = -@ball_vector.y
        end
        
        #############################################
        # Check for a user hit
        #
        # TODO:  split the ball_path into two paths after a rebound from the top or bottom wall 
        #
        hit_paddle_num = test_user_paddle(ball_path)
        if hit_paddle_num
          @ball_vector.x = -@ball_vector.x
          @ball_speed += 0.07
          wav = "c:\\windows\\media\\Speech Misrecognition.wav" if SOUND 
          Sound.play(wav, Sound::ASYNC) if SOUND
        end
        
        ########################
        # move the computer's paddle
        move_hals_paddle(ball_path, dif)
        
        # Draw the paddles
        view.drawing_color = Sketchup::Color.new(64, 128, 64)
        
        tr = Geom::Transformation.translation( [paddle_x, paddle_y, 0])
        paddle_pts = @user_paddle_outline.collect{|pt| pt.transform(tr)} 
        view.draw2d(GL_POLYGON, paddle_pts)

        tr = Geom::Transformation.translation( [@hal_paddle_x, @hal_paddle_y, 0])
        paddle_pts = @hal_paddle_outline.collect{|pt| pt.transform(tr)} 
        view.draw2d(GL_POLYGON, paddle_pts)
    
        # Draw the ball
        tr = Geom::Transformation.translation(@ball_location)
        perimeter = @puck_perimeter.collect{|pt| pt.transform(tr)}
        view.drawing_color = Sketchup::Color.new(64, 128, 64)
        view.draw2d(GL_POLYGON, perimeter)
        
        #Add the Time Remaining label
        point = Geom::Point3d.new(@left + 7, @top + 20, 0)
        view.draw_text(point, "Time Remaining: #{(@game_tool_length - (Time.now - @start_time)).round(1)}")

        # add some debugging info
        point = Geom::Point3d.new(@left + 7, @top + 40, 0)
        x =  @last_ball_location.x - @ball_location.x
        y =  @last_ball_location.y - @ball_location.y
        @hop_distance = Math.sqrt(x**2 + y**2).round
        view.draw_text(point, "Hop Length: #{@hop_distance} pixels")

        # Did anyone whiff?  
        if @ball_location.x > @right ||
          @ball_location.x < @left
          # Game Over
          @in_play = false
        end
      end #user_draw
     
     
      ##################
      #
      #  Move Hal's paddle and check for a hit
      #
      def self.move_hals_paddle(ball_path, dif)
          
        # Find the shortest path to the moving ball
        
        # This is a line coming straight out of the screen at the center of the paddle
        hal_paddle_line = [Geom::Point3d.new(@hal_paddle_x, @hal_paddle_y, 0),
          Geom::Point3d.new(@hal_paddle_x, @hal_paddle_y, 100)]
          
        crossing_point = Geom.closest_points(ball_path.to_a, hal_paddle_line)[0]
        
        # Throw in a chip shot if the ball is moving close to horizontally
        # We accomplish this by trying to hit the ball with the end of the paddle
        # and sometimes we miss! 
        
        if @ball_vector.x < -0.98
          # chip shot down or up?
          if crossing_point.y < @bottom - (@bottom - @top)/2
            crossing_point.y += @half_paddle_height 
          else
            crossing_point.y -= @half_paddle_height 
          end
        end
             
        # Move the padddle partially toward the crossing point  
        #  or back to the resting spot
        j = 200
        if crossing_point && (@ball_vector.x < 0)
          # @hal_paddle_y += (crossing_point.y - @hal_paddle_y) / 12
          # @hal_paddle_x += (crossing_point.x - @hal_paddle_x) / 12
          @hal_paddle_y += (crossing_point.y - @hal_paddle_y) * dif / j
          @hal_paddle_x += (crossing_point.x - @hal_paddle_x) * dif / j
        else
          j= 180
          # @hal_paddle_y += ( (@bottom - (@bottom -@top)/2) - @hal_paddle_y) / 15
          # @hal_paddle_x += (@left + 50 - @hal_paddle_x) / 15
          @hal_paddle_y += ( (@bottom - (@bottom -@top)/2) - @hal_paddle_y) * dif / j
          @hal_paddle_x += (@left + 50 - @hal_paddle_x) * dif / j
        end
       
        # limit the paddle to the playing area
        @hal_paddle_y = @top if  @hal_paddle_y < @top
        @hal_paddle_y = @bottom if  @hal_paddle_y > @bottom
        @hal_paddle_cache << Paddle.new(@hal_paddle_x, @hal_paddle_y, Time.now)
       
        # check for a hit
        hit = test_hal_paddles(ball_path)
        if hit
          @ball_vector.x = -@ball_vector.x
          @ball_speed += 0.07
          
          wav = "c:\\windows\\media\\Speech Misrecognition.wav" if SOUND 
          Sound.play(wav, Sound::ASYNC) if SOUND
        end
        
      end
      
      
      
      ####################################################################
      #
      # In a Discrete Time System we must test the current paddle location
      #  and a set of of the recent paddle locations to insure the ball
      #  doesn't simply hop over the moving paddle and out of range
      #
      # We age out old paddles and test the remaining paddles for a hit
      #  Returns nil on a miss or the index of the paddle that was hit

      def self.test_user_paddle(ball_path)
      
        # Remove paddles older than some time X
        @user_paddle_cache = @user_paddle_cache.drop_while {|pdl| (Time.now - pdl.time) > 0.1 }
        
        # Return if the ball is moving to the left
        return nil if ball_path.end.x < ball_path.start.x

        # Return the index of the hit paddle or nil. Testing the most recent paddle first
        @user_paddle_cache.reverse.index {|paddle| test_paddle(paddle, ball_path)}
        
      end
      
      def self.test_hal_paddles(ball_path)
      
        # Remove paddles older than some time X
        @hal_paddle_cache = @hal_paddle_cache.drop_while {|pdl| (Time.now - pdl.time) > 0.1 }
        
        # Return if the ball is moving to the right
        return nil if ball_path.end.x > ball_path.start.x

        # Return the index of the hit paddle or nil. Testing the most recent paddle first
        @hal_paddle_cache.reverse.index {|paddle| test_paddle(paddle, ball_path)}
        
      end
      
      
      ##########################################
      # Does the ball hit this paddle.
      #   Moves the ball to the 'hit' location,
      #   nudges the ball direction on contact.
      #   Returns true of false
      
      def self.test_paddle(paddle, ball_path)
        paddle_line = [Geom::Point3d.new(paddle.x, 0, 0), Geom::Point3d.new(paddle.x, 100, 0)]
        hit_point = Geom.intersect_line_line(ball_path.to_a, paddle_line)
        return false if hit_point.nil? 

        # If the ball path crosses the line between the paddle's ends
        # and the ball jumped across the line,  then we have a hit
        # 
        if hit_point.y > (paddle.y - @half_paddle_height) &&
          hit_point.y < (paddle.y + @half_paddle_height) &&
          ((hit_point.x > @last_ball_location.x) ^ 
          (hit_point.x > @ball_location.x)) # Xor
                
          # Move the ball to the hit point
          @ball_location = hit_point
          # On each good hit nudge the ball back toward the horizontal direction
          if @ball_vector.x > 0
            @ball_vector.x += 0.2
          else
            @ball_vector.x -= 0.2
          end
          @ball_vector.normalize!
          true
            

        #  Test if the ball hit the end of the paddle
        #  (i.e. a slightly larger paddle) if so then send it off in a new direction.
        #  This proves to be truly agrivatin'
        elsif  hit_point.y > paddle.y - (@half_paddle_height * 1.5) &&
          hit_point.y < paddle.y + (@half_paddle_height  * 1.5) &&
         ((hit_point.x > @last_ball_location.x) ^ 
          (hit_point.x > @ball_location.x)) # Xor
          @ball_location = hit_point
          
          # chip the ball up or down
          if hit_point.y < paddle.y
            @ball_vector.y = -@ball_vector.y.abs
            @ball_vector.y -= 0.17
            @ball_vector.normalize!
            true 

          else
            @ball_vector.y = @ball_vector.y.abs
            @ball_vector.y += 0.17
            @ball_vector.normalize!
            true 
          end
        else
          # no hit
          false
        end
      end    
      
       
      def self.on_complete
        puts 'Good One Ping' if @in_play == true
        puts 'Too Bad Pong' if @in_play == false
        
        # print statistics
        elapsed = Time.now - @start_time
        puts "fps: #{@frame_count / elapsed}" # frames per secong
        puts "mps: #{@game_tool.onMouseMoveCount/elapsed}" # mouse moves
        puts "final hop: #{@hop_distance}"
     
        wav = "c:\\windows\\media\\chimes.wav" if SOUND
        Sound.play(wav, Sound::ASYNC) if SOUND
        
      end

      def self.on_abort(exception)
        # Did the user ESC or change tools?
        if exception.is_a? SW::GameCore::GameAbort
           puts 'So Long Pong'
        else
          raise exception
        end
      end

    end
  end
end