# encoding: utf-8
require 'time'
require 'date'
require 'pp'
IRB.conf[:AUTO_INDENT] = true
IRB.conf[:SAVE_HISTORY] = 10000

class Object
  def local_methods
    (methods - Object.instance_methods).sort
  end
end

