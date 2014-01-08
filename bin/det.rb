#!/bin/env ruby
# encoding: utf-8
# 
# Rubyで行列式の計算練習しまくるためのツール
# ruby ./det.rb で起動
#
# Author: kimoto
# http://ja.wikipedia.org/wiki/%E3%82%AF%E3%83%A9%E3%83%A1%E3%83%AB%E3%81%AE%E5%85%AC%E5%BC%8F

# 正直Rubyなら、標準で入ってるMatrixクラス使えば行ける。この関数は不要
# 例)
# require 'matrix'
# m = Matrix[[2,1,1],[5,2,3],[4,1,2]]
# p m.det
def determinant(narray)
  (l1, l2, l3) = narray # line1, 2, 3
  v1 = l1[0] * (l2[1] * l3[2] - l2[2] * l3[1])
  v2 = l1[1] * (l2[0] * l3[2] - l2[2] * l3[0])
  v3 = l1[2] * (l2[0] * l3[1] - l2[1] * l3[0])
  return v1 - v2 + v3
end

if $0 == __FILE__
  def make_question
    source = (1..6).to_a
    array = []
    3.times{
      columns = []
      3.times{
        columns << source.shuffle.first
      }
      array << columns
    }
    return array
  end

  # 標準入力のキー入力後に次の問題へみたいな感じにする
  while true
    question = make_question()
    puts "question: #{question.to_s}"

    # 失敗したときは正しい値を入力するまでループさせる感じで
    while true
      # waiting for user's input
      print "type answer> "
      input = STDIN.gets; input.chomp!
      if input =~ /quit/
        puts "quitting..."
        exit(0)
      end

      # answer check
      answer = determinant(question)
      if input.to_i == answer
        puts "OK!"
        break
      else
        puts "NG! (correct answer: #{answer})"
      end
    end
  end
end

