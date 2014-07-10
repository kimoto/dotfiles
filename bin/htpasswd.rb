require "base64"
username, password = ARGV
salt = Base64.encode64((("a".."z").to_a + ("A".."Z").to_a + (0..9).to_a).shuffle[0..7].join)
puts "#{username}:#{password.crypt(salt)}"
