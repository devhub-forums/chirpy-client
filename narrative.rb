class Narrative
  def data 
    @data ||= {
      state: :begin,
      previous: nil
    }
  end

  def self.stories 
    @stories ||= Hash.new
  end

  def self.create(name, &block)
    stories[name] = block
  end

  def states
    @states ||= Hash.new
  end

  def data_listeners
    @data_listeners ||= Set.new
  end

  def initialize(name, d)
    self.instance_exec &(Narrative.stories[name])
    @story = name
    @data = d
  end

  def state(s, on: 'enter', &block)
    states["#{s}.#{on}"] = block
  end

  def input(input, *params)
    result = fire(data[:state], input, *params)
    go( result, *params ) if result && result.is_a?(Symbol)
  end

  def go(to, *params)
    @data[:previous] = data[:state]
    @data[:state] = to
    dirty
    fire(data[:previous], 'leave', *params)
    fire(data[:state], 'enter', *params)
    dirty
  end

  def fire(state, event, *params)
    event = states["#{state}.#{event}"]
    self.instance_exec(*params, &event) if ( event )
  end

  def on_data(&block)
    data_listeners << block
  end

  def dirty
    data_listeners.each do | listener |
      listener.call(data)
    end
  end

  def reply (as, raw, options = {})
    options[:raw] = raw
    options[:topic_id] ||= data[:topic_id] if data[:topic_id]

    PostCreator.create( as, options )
  end

  def dialogue_file
    @dialogue_file ||= YAML.load_file File.expand_path("../narratives/#{ @story }/dialogue.en.erb.yml", __FILE__)
  end

  def dialogue( term, b=nil)
    (ERB.new dialogue_file[term]).result(b || binding)
  end
end