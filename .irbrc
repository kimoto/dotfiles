# encoding: utf-8
require 'irb/completion'
require 'irb/ext/save-history'
require 'time'
require 'date'
require 'wirble'
require 'pp'
require 'open-uri'
require 'readline'
IRB.conf[:AUTO_INDENT] = true
Wirble.init(:skip_prompt => :DEFAULT)
Wirble.colorize

class Object
  def local_methods
    (methods - Object.instance_methods).sort
  end
end

