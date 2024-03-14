PLUGIN_NAME = "chirpy-client"

def get_user
  @chirpy ||= User.find_by({username: "discobot"})

  unless @chirpy
    @chirpy = User.create(
      name: "Chirpy",
      username: "chirpy",
      approved: true, active: true,
      admin: true,
      password: SecureRandom.hex,
      email: "#{SecureRandom.hex}@anon.#{Discourse.current_hostname}",
      trust_level: 4,
      trust_level_locked: true,
      created_at: 10000.years.ago
    )

    @chirpy.grant_admin!
    @chirpy.activate

    UserAvatar.import_url_for_user(
      "https://cdn.discourse.org/dev/uploads/default/original/2X/e/edb63d57a720838a7ce6a68f02ba4618787f2299.png",
      @chirpy,
      override_gravatar: true )
  end
  @chirpy
end

DiscourseEvent.on(:group_user_created) do | group_user |
  Jobs.enqueue(:narrative_input,
    user_id: group_user.user.id,
    narrative: 'staff_introduction',
    input: 'init'
  ) if group_user.group.name === 'staff' && group_user.user.id != get_user.id 
end

DiscourseEvent.on(:post_created) do | post |
  Jobs.enqueue(:narrative_input,
    user_id: post.user.id,
    post_id: post.id,
    narrative: 'staff_introduction',
    input: 'reply'
  )
end

Narrative.create 'staff_introduction' do
  state :begin, on: 'init' do | user |
    title = dialogue('welcome_topic_title', binding)
    main_topic = Topic.find_by({slug: Slug.for(title)})

    data[:missions] = [:tutorial_onebox, :tutorial_picture, :tutorial_formatting, :tutorial_quote, :tutorial_emoji, :tutorial_mention, :tutorial_link, :tutorial_pm]

    if (main_topic != nil)
      data[:topic_id] = main_topic.id
    end

    if (data[:topic_id])
      reply get_user, dialogue('hello', binding)
    else
      data[:topic_id] = ( reply get_user, dialogue('welcome_topic_body', binding), {
          title: title, 
          category: Category.find_by(slug: 'staff').id
        }
      ).topic.id

      reply get_user, dialogue('hello', binding)
    end

    :waiting_quote
  end

  state :waiting_quote, on: 'reply' do | user, post |
    next unless data[:topic_id] === post.topic.id

    sleep(rand(3..5).seconds)
    reply get_user, dialogue('quote_user', binding)
    :tutorial_topic
  end

  state :next_tutorial do | user, post |
    data[:missions].delete(data[:previous])
    next_mission = data[:missions].sample || :congratulations

    dialogue_previous_ending = dialogue( data[:previous].to_s.concat("_ok"), binding ) 
    dialogue_next_mission = dialogue( next_mission.to_s, binding )

    sleep(rand(2..3).seconds)
    PostAction.act(get_user, post, PostActionType.types[:like])
    reply get_user, "#{dialogue_previous_ending}\n#{dialogue_next_mission}"

    go next_mission
  end

  state :tutorial_topic, on: 'reply' do | user, post |
    
    data[:topic_id] = post.topic.id
    data[:subject] = subject

    :next_tutorial
  end

  state :tutorial_onebox, on: 'reply' do | user, post |
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.found_oneboxes?
  end

  state :tutorial_picture, on: 'reply' do | user, post |
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.image_count > 0
  end

  state :tutorial_formatting, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    doc = Nokogiri::HTML.fragment(processor.html)
    :next_tutorial if data[:topic_id] == post.topic.id && doc.css("strong").size > 0 && (doc.css("em").size > 0 || doc.css("i").size > 0)
  end

  state :tutorial_quote, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    doc = Nokogiri::HTML.fragment(processor.html)
    :next_tutorial if data[:topic_id] == post.topic.id && doc.css(".quote").size > 0
  end

  state :tutorial_emoji, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    :next_tutorial if data[:topic_id] == post.topic.id && processor.has_emoji?
  end

  state :tutorial_mention, on: 'reply' do | user, post |
    :next_tutorial if data[:topic_id] == post.topic.id && post.raw.include?("@#{get_user.username}")
  end

  state :tutorial_link, on: 'reply' do | user, post |
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && (post.post_analyzer.link_count() > 0)
  end

  # TODO broken, fix 
  state :tutorial_pm, on: 'reply' do | user, post |
    if post.archetype == Archetype.private_message && post.topic.all_allowed_users.any? { |p| p.id == get_user.id }
      reply get_user, dialogue('tutorial_pm_reply', binding), { topic_id: post.topic }
      :next_tutorial
    end
  end
end