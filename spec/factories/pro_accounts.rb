# -*- encoding : utf-8 -*-
# == Schema Information
#
# Table name: pro_accounts
#
#  id                       :integer          not null, primary key
#  user_id                  :integer          not null
#  default_embargo_duration :string(255)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
require 'stripe_mock'

FactoryGirl.define do

  factory :pro_account do
    association :user, factory: :pro_user
  end

end
