GroupUser.class_eval do
  after_create do
    DiscourseEvent.trigger(:group_user_created, self);
  end
end