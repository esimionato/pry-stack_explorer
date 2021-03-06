require 'helper'

describe PryStackExplorer::Commands do

  before do
    Pry.config.hooks.add_hook(:when_started, :save_caller_bindings, WhenStartedHook)
    Pry.config.hooks.add_hook(:after_session, :delete_frame_manager, AfterSessionHook)

    @o = Object.new
    class << @o; attr_accessor :first_method, :second_method, :third_method; end
    def @o.bing() bong end
    def @o.bong() bang end
    def @o.bang() Pry.start(binding) end
  end

  after do
    Pry.config.hooks.delete_hook(:when_started, :save_caller_bindings)
    Pry.config.hooks.delete_hook(:after_session, :delete_frame_manager)
  end

  describe "up" do
    it 'should move up the call stack one frame at a time' do
      redirect_pry_io(InputTester.new("@first_method = __method__",
                                      "up",
                                      "@second_method = __method__",
                                      "up",
                                      "@third_method = __method__",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      @o.first_method.should  == :bang
      @o.second_method.should == :bong
      @o.third_method.should  == :bing
    end

    it 'should move up the call stack two frames at a time' do
      redirect_pry_io(InputTester.new("@first_method = __method__",
                                      "up 2",
                                      "@second_method = __method__",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      @o.first_method.should  == :bang
      @o.second_method.should == :bing
    end

    describe "by method name regex" do
      it 'should move to the method name that matches the regex' do
        redirect_pry_io(InputTester.new("@first_method = __method__",
                                        "up bi",
                                        "@second_method = __method__",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        @o.first_method.should  == :bang
        @o.second_method.should == :bing
      end

      it 'should move through all methods that match regex in order' do
        redirect_pry_io(InputTester.new("@first_method = __method__",
                                        "up b",
                                        "@second_method = __method__",
                                        "up b",
                                        "@third_method = __method__",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        @o.first_method.should  == :bang
        @o.second_method.should == :bong
        @o.third_method.should  == :bing
      end

      it 'should error if it cant find frame to match regex' do
        redirect_pry_io(InputTester.new("up conrad_irwin",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        out.string.should =~ /Error: No frame that matches/
      end
    end
  end

  describe "down" do
    it 'should move down the call stack one frame at a time' do
      def @o.bang() Pry.start(binding, :initial_frame => 1) end

      redirect_pry_io(InputTester.new("@first_method = __method__",
                                      "down",
                                      "@second_method = __method__",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      @o.first_method.should  == :bong
      @o.second_method.should == :bang
    end

    it 'should move down the call stack two frames at a time' do
      def @o.bang() Pry.start(binding, :initial_frame => 2) end

      redirect_pry_io(InputTester.new("@first_method = __method__",
                                      "down 2",
                                      "@second_method = __method__",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      @o.first_method.should  == :bing
      @o.second_method.should == :bang
    end

    describe "by method name regex" do
      it 'should move to the method name that matches the regex' do
        redirect_pry_io(InputTester.new("frame -1",
                                        "down bo",
                                        "@first_method = __method__",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        @o.first_method.should == :bong
      end

      it 'should move through all methods that match regex in order' do
        redirect_pry_io(InputTester.new("frame bing",
                                        "@first_method = __method__",
                                        "down b",
                                        "@second_method = __method__",
                                        "down b",
                                        "@third_method = __method__",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        @o.first_method.should  == :bing
        @o.second_method.should == :bong
        @o.third_method.should  == :bang
      end

      it 'should error if it cant find frame to match regex' do
        redirect_pry_io(InputTester.new("frame -1",
                                        "down conrad_irwin",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        out.string.should =~ /Error: No frame that matches/
      end
    end

  end

  describe "frame" do
    describe "by method name regex" do
      it 'should jump to correct stack frame when given method name' do
        redirect_pry_io(InputTester.new("frame bi",
                                        "@first_method = __method__",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        @o.first_method.should == :bing
      end

      it 'should NOT jump to frames lower down stack when given method name' do
        redirect_pry_io(InputTester.new("frame -1",
                                        "frame bang",
                                        "exit-all"), out=StringIO.new) do
          @o.bing
        end

        out.string.should =~ /Error: No frame that matches/
      end

    end

    it 'should move to the given frame in the call stack' do
      redirect_pry_io(InputTester.new("frame 2",
                                      "@first_method = __method__",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      @o.first_method.should == :bing
    end

    it 'should return info on current frame when given no parameters' do
      redirect_pry_io(InputTester.new("frame",
                                      "exit-all"), out=StringIO.new) do
        @o.bing
      end

      out.string.should =~ /\#0.*?bang/
      out.string.should.not =~ /\#1/
    end

    describe "negative indices" do
      it 'should work with negative frame numbers' do
        o = Object.new
        class << o; attr_accessor :frame; end
        def o.alpha() binding end
        def o.beta()  binding end
        def o.gamma() binding end

        call_stack   = [o.alpha, o.beta, o.gamma]
        method_names = call_stack.map { |v| v.eval('__method__') }.reverse
        (1..3).each_with_index do |v, idx|
          redirect_pry_io(InputTester.new("frame -#{v}",
                                          "@frame = __method__",
                                          "exit-all"), out=StringIO.new) do
            Pry.start(o, :call_stack => call_stack)
          end
          o.frame.should == method_names[idx]
        end
      end

      it 'should convert negative indices to their positive counterparts' do
        o = Object.new
        class << o; attr_accessor :frame_number; end
        def o.alpha() binding end
        def o.beta()  binding end
        def o.gamma() binding end

        call_stack   = [o.alpha, o.beta, o.gamma]
        (1..3).each_with_index do |v, idx|
          redirect_pry_io(InputTester.new("frame -#{v}",
                                          "@frame_number = PryStackExplorer.frame_manager(_pry_).binding_index",
                                          "exit-all"), out=StringIO.new) do
            Pry.start(o, :call_stack => call_stack)
          end
          o.frame_number.should == call_stack.size - v
        end
      end
    end
  end
end
