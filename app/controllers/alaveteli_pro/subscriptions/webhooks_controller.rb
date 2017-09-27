# -*- encoding : utf-8 -*-
# Does not inherit from AlaveteliPro::BaseController because it doesn't need to
class AlaveteliPro::Subscriptions::WebhooksController < ApplicationController
  before_filter :authenticate_sender

  def update
  end

  private

  def authenticate_sender
    # check sender is Stripe
    # check timestamp seems reasonable
    # check the secret key matches
  end
