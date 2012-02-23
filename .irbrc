# encoding: utf-8
require 'rubygems'
require 'irb/completion'
require 'irb/ext/save-history'
require 'time'
require 'date'
require 'wirble'
require 'active_support/all'
require 'open-uri'

Wirble.init(:skip_prompt => :DEFAULT)
Wirble.colorize

class Object
  def local_methods
    (methods - Object.instance_methods).sort
  end
end

