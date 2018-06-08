#!/usr/bin/env ruby

require 'benchmark/ips'
require 'dry-monads'


class User
  attr_reader :id, :name, :age, :email

  def initialize(id, name, age, email)
    @id = id
    @name = name
    @age = age
    @email = email
  end

  def self.all
    @all ||= (1..1000).map do |id|
      new(id, "Name#{id}", rand(2..40), "someone#{id}@domain#{id}.pl")
    end
  end

  def self.find_by_ids(ids = [])
    all.select { |u| ids.include?(u.id) }
  end
end

User.all # initialize cache

class RegularService
  include Dry::Monads::Result::Mixin

  def initialize(user_ids, message)
    @user_ids = user_ids
    @message = message
  end

  def call
    return Failure(:cant_send_empty_message) if @message.empty?
    Success(send_messages)
  end

  private

  def users
    @users ||= User.find_by_ids(@user_ids)
  end

  def send_messages
    users.map do |user|
      {
        id: user.id,
        status: send_message(user.email, formated_message) ? 'delivered' : 'error'
      }
    end
  end

  def send_message(email, message)
    true
  end

  def formated_message
    "Message: #{@message}"
  end
end

class FunctionalService
  include Dry::Monads::Result::Mixin

  def call(user_ids, message)
    Failure(:cant_send_empty_message) if message.empty?
    Success(user_ids).
      bind(method(:users)).
      bind(method(:send_messages).curry[message])
  end

  private

  def users(user_ids)
    Success(User.find_by_ids(user_ids))
  end

  def send_messages(message, users)
    results = users.map do |user|
      {
        id: user.id,
        status: Success(user.email).bind(method(:send_message).curry[message]).success? ? 'delivered' : 'error'
      }
    end
    Success(results)
  end

  def send_message(message, email)
    Success(message).
      bind(method(:format_message)).
      bind { Success(:delivered) }
  end

  def format_message(message)
    Success("Message: #{message}")
  end
end

PARAMS = [
  [
    66, 1, 5, 6, 10, 99, 32
  ],
  'This is a message for %user_email%'
]

puts "Testing speed"

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('regular') do
    RegularService.new(*PARAMS).call
  end

  x.report('functional') do
    FunctionalService.new.call(*PARAMS)
  end
end

puts "Testing memory"

def benchmark_memory(test_name)
  GC.disable
  objects_before = GC.stat(:total_allocated_objects)
  yield
  diff = GC.stat(:total_allocated_objects) - objects_before
  GC.enable
  puts "#{test_name}: Allocated objects #{diff}"
end

benchmark_memory('regular') do
  RegularService.new(*PARAMS).call
end

benchmark_memory('functional') do
  FunctionalService.new.call(*PARAMS)
end

