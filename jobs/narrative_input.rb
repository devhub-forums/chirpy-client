module Jobs
  class NarrativeInput < Jobs::Base

    sidekiq_options queue: 'critical'

    def execute(args)
      user = User.find args[:user_id]
      post = Post.find args[:post_id] rescue nil

      narrative = Narrative.new args[:narrative], ::PluginStore.get(PLUGIN_NAME, "narrative_#{args[:narrative]}_#{user.id}") 
      narrative.on_data do | data |
        ::PluginStore.set(PLUGIN_NAME, "narrative_#{args[:narrative]}_#{user.id}", data) 
      end

      narrative.input args[:input], user, post
    end
  end
end