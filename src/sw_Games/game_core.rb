require 'fiber'

module SW
  class GameCore
    attr_accessor(:on_complete, :on_abort, :user_task, :user_draw)
    attr_reader(:mouse_x, :mouse_y, :onMouseMoveCount)

    @@activated = false
    @@lookaway = true
  
    # Exception class for user code errors
    class GameError < RuntimeError; end
    
    # Exception class for user mouse and keyboard actions
    class GameAbort < RuntimeError; end
        
    
    ###################################
    # Sketchup Tool interface methods
    ###################################
     
    def activate
      # puts 'activate'
      @@activated = true
      @suspended = false
      @user_esc = false
      @cancel_reason = nil
      @enable_redraw = true
    end

    def deactivate(view)
      # puts 'deactivate'
      @@activated = false
      @suspended = false
      @cancel_reason = 'Deactivate - Tool Change'
    end
    
    def onCancel(reason, view)
      # puts 'user esc'  
      # intentioanaly ignoring the reason arguement
      @user_esc = true
      @cancel_reason = 'User Escape'
    end
    
    def suspend(view)
      #puts 'suspend'
      @suspended = true
    end
    
    def resume(view)
      #puts 'resume'
      @suspended = false
    end
    
    def onMouseMove(flags, x, y, view)
      @mouse_x = x 
      @mouse_y = y
      @onMouseMoveCount += 1
    end
    
    def active?
      @@activated
    end
    
    # Redraw the screen presentation of the progress bar 
    #   Rather than having the user insert yield statements in their code the
    #   refresh method hides the details and allows us to change the 
    #   implementation independantly of the user code
    
    def refresh()
      Fiber.yield
    end
    
    ###################################
    #  Draw routine
    #
    # The user sets up the @user_draw method
    #   game_tool.user_draw = method(:my_draw_method)
    #   the method must accept 
    def draw(view)
      if  @user_draw
        @user_draw.call(view) 
      else
        p 'there is no user_draw method'
      end
    end # draw


    #############################################
    #
    # Initializer:
    #   new(on_complete, on_abort, user_task, [id:] ) -> game_tool
    #   new(on_complete, on_abort, [id:]) { |game_tool| block } -> result of block
    #
    # With no associated block, game_tool.new will call the user_task with the
    # game_tool instance as an argument and will return the game_tool
    # instance to the caller. If the optional code block is given, it will be
    # passed the game_tool instance as an argument. If the optional keyword
    # argument id: is present the screen location of the progress bar will
    # be maintained across invocations.
    #
    # params:
    #   on_complete -  the Method to execute when the user_task has ended. 
    #   on_abort -  the Method to execute when there is an Exception/Mouse/Keyboard action.
    #   user_task - the user_task Method to execute.
    #   id: - an object
    #   
    
    def initialize(on_complete, on_abort, user_task = nil, id: nil, &block)

      # Allow only one active progress bar. This is caused f.e. by a double click on a toolbar icon.
      return if active? 

      user_task = block if block_given?
      @id = id
          
      raise GameError, 'Game_tool user_task argument must be a Method of Arity one'\
        unless user_task && [Method, Proc].include?(user_task.class) && user_task.arity == 1
      raise GameError, 'Game_tool on_complete argument must be a Method of Arity zero'\
        unless on_complete && on_complete.is_a?(Method) && on_complete.arity == 0
      raise GameError, 'Game_tool on_abort argument must be a Method of Arity one'\
        unless on_abort && on_abort.is_a?(Method) &&  on_abort.arity == 1
      
      @user_task = user_task
      @on_complete = on_complete
      @on_abort = on_abort
      
      @mouse_x = 0 
      @mouse_y = 0
      @onMouseMoveCount = 0
      
      look_away() if @@lookaway # from the model
      
      # Activate the tool
      Sketchup.active_model.tools.push_tool(self)

      # Start the user task
      redraw_game()
    end
  
    # Schedule the user_task
    def redraw_game()
      Sketchup.active_model.active_view.invalidate if @enable_redraw
      UI.start_timer(0, false) { resume_task() }
      @time_at_start_of_redraw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private :redraw_game
    
    # Execute the user_task 
    def resume_task()
    
      # re-queue the user_task during Orbit and Pan and Section Plane operations
      if active? && @suspended
        UI.start_timer(0.25, false) { resume_task() }
        return
      end
      
      begin
        
        # Abort after a user ESC or a tool change. Copy cancel_reason since
        # pop_tool in the rescue clause triggers deactivate which overwrites it.
        if @user_esc || !@@activated
          cancel_reason = @cancel_reason  
          raise GameAbort, cancel_reason
        end
        
        # Wrap the user_task (a Method or Proc) in a Fiber on first invocation.
        # This must be done in this stack context.  Start the update_flag thread
        if @fiber.nil?
          @fiber = Fiber.new {@user_task.call(self) }
        end

        # Let the fun begin!
        # Execute the user task until it yields, ends, or raises an exception
        result = @fiber.resume()
        
        # waiting, waiting, waiting
        if @fiber.alive?
          redraw_game()
        else
          # The Fiber has ended naturally. Stop the updater thread.
          # Pop the gameTool and call the user's on_complete method.
          look_back() if @@lookaway
          Sketchup.active_model.tools.pop_tool
          Sketchup.active_model.active_view.invalidate
          UI.start_timer(0, false) { @on_complete.call }
        end 

      # Bad things happen even when you have the best intentions. Catch all
      # StandardErrors and user actions that throw an exception
      rescue => exception   
      
        look_back() if @@lookaway
        
        # Because we have left @fiber in limbo, possibly with file handles open,
        # let's abandon the fiber and force a clean-up
        @fiber = nil
        GC.start

        # If the user clicked on a Sketchup Menu, dialog, etc. we'll receive an
        # exception: 'FiberError - fiber called across stack rewinding barrier'
        # In this case we raise the gameAbort exception
        if exception.is_a? FiberError
          exception = GameAbort.new('User Menu-Click Abort')
        end
        
        # Pop the gametool unless this is a tool change where sketchup
        # has already done that for you then call the on_abort method
        Sketchup.active_model.tools.pop_tool if @@activated
        Sketchup.active_model.active_view.invalidate
        UI.start_timer(0, false) { @on_abort.call(exception) }
        
      end # rescue
    end # resume_task
    private :resume_task


    ##############################################
    # look away from the model to save redraw time
    # 
    
    # alternative initializer
    # def self.new_with_lookaway(*args, &block)
    #   pbar = self.new(*args, &block)
    #   pbar.look_away()
    # end
    
    def look_away()
      model = Sketchup.active_model
      camera = model.active_view.camera
      @eye = camera.eye
      @target = camera.target
      @up = camera.up
      bounds = model.bounds
      camera.set(bounds.corner(0), bounds.corner(0) -  bounds.center, @up)
    end
    #protected :look_away 
   
    # restore the camera settings
    def look_back()
      camera = Sketchup.active_model.active_view.camera.set(@eye, @target, @up)
    end
    #private :look_back

    
    
    # A hack for opening a UI::messagesbox from a timer event
    # https://github.com/SketchUp/sketchup-safe-observer-events/blob/master/src/safer_observer_events.rb
    #
    # Example call:
    # SW::game.display_safe_messagebox() { UI.messagebox('Example Completed.') }
    #
     def self.display_safe_messagebox(&block)
      executed = false
      UI.start_timer( 0, false) {
        next if executed # use next when in a proc-closure (for ruby console)
        executed = true 
        block.call
      }
    end
    
  end # game
 
end

nil

