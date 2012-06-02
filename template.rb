options = {}

def ask_with_default(prompt, default)
  value = ask("#{prompt} [#{default}]")
  value.blank? ? default : value
end

if yes?("Do you want to use Devise?")
  options[:devise_model] = ask_with_default(
    "What should the user model be called?", "User").classify

  say "Let's seed the database with the first #{options[:devise_model]}...", :yellow
  git_email = `git config --get user.email`.chomp
  options[:user_email]    = ask_with_default "Email", git_email
  options[:user_password] = ask_with_default "Password", "password"
end

if options[:devise_model]
  gem "devise"
end

gem "newrelic_rpm"
gem "haml", :version => "~> 3.2.0.alpha.10"
gem "jquery-rails"
gem "kramdown"
gem "simple_form"
gem "stamp"
gem "unicorn"

gem_group :assets do
  gem "sass-rails", :version => "~> 3.2.3"
  gem "coffee-rails", :version => "~> 3.2.1"
  gem "uglifier", :version => ">= 1.0.3"

  gem "bootstrap-sass"
  gem 'haml-rails'
  gem 'modernizr-rails'
end

gem_group :development, :test do
  gem "rspec-rails"
  gem "debugger"
end

gem_group :development do
  gem "foreman"
  gem "heroku"

  gem "guard-rspec"
  gem "guard-cucumber"
end

gem_group :test do
  gem "factory_girl_rails"
  gem "ffaker"
  gem "shoulda-matchers"
  gem "valid_attribute"
  gem "cucumber-rails", :require => false
  gem "database_cleaner"
end

# configure newrelic for heroku
get "https://raw.github.com/gist/2253296/newrelic.yml", "config/newrelic.yml"

generate "rspec:install"
generate "cucumber:install"
generate "simple_form:install", "--bootstrap"

if options[:devise_model]
  generate "devise:install"
  generate "devise", options[:devise_model]
  generate "devise:views"

  # create seed user
  append_to_file "db/seeds.rb", <<-CODE
#{options[:devise_model]}.create!(
  :email => %q{#{options[:user_email]}},
  :password => %q{#{options[:user_password]}}) unless #{options[:devise_model]}.any?
CODE

  # create factory for user model
  create_file "spec/factories/#{options[:devise_model].underscore}s.rb", <<-CODE
FactoryGirl.define do
  factory :#{options[:devise_model].underscore} do
    email      { Faker::Internet.disposable_email }
    password   'password'
  end
end
CODE
end


# initialize guard for rspec and cucumber
run "bundle exec guard init rspec"
run "bundle exec guard init cucumber"


# for deployment to heroku
application "config.assets.initialize_on_precompile = false"


# enable simple factory girl syntax (create, build) in rspec and cucumber
create_file "spec/support/factory_girl.rb", <<-CODE
RSpec.configure do |config|
  config.include FactoryGirl::Syntax::Methods
end
CODE
append_to_file "features/support/env.rb", "World(FactoryGirl::Syntax::Methods)"


# configure sendgrid for heroku
create_file "config/initializers/mail.rb", <<-CODE
ActionMailer::Base.smtp_settings = {
  :address        => 'smtp.sendgrid.net',
  :port           => '587',
  :authentication => :plain,
  :user_name      => ENV['SENDGRID_USERNAME'],
  :password       => ENV['SENDGRID_PASSWORD'],
  :domain         => 'heroku.com'
}
ActionMailer::Base.delivery_method = :smtp
CODE


create_file "app/assets/stylesheets/screen.css.sass", <<-CODE
@import "bootstrap"

body
  padding-top: 80px

@import "bootstrap/responsive"
CODE


remove_file "app/views/layouts/application.html.erb"
create_file "app/views/layouts/application.html.haml", <<-CODE
%html.no-js{ lang: 'en' }
  %head
    %title= yield(:title)

    %meta{ name: 'viewport', content: 'width=device-width, initial-scale=1.0' }
    %meta{ charset: 'utf-8' }

    = csrf_meta_tag

    = stylesheet_link_tag :application
    = javascript_include_tag :application

  %body{ body_attributes }
    = render 'shared/flashes'

    .container-fluid
      = yield
CODE


create_file "app/views/shared/_flashes.html.haml", <<-CODE
- flash.each do |key, message|
  %p{ :class => key }= message
CODE


create_file "Procfile", <<-CODE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
CODE


# configure unicorn to run 3 workers for single-dyno concurrency
# http://michaelvanrooijen.com/articles/2011/06/01-more-concurrency-on-a-single-heroku-dyno-with-the-new-celadon-cedar-stack/
create_file "config/unicorn.rb", <<-CODE
worker_processes 3 # number of unicorn workers to spin up
timeout 30         # restarts workers that hang for 30 seconds
CODE


# add js assets
append_to_file "app/assets/javascripts/application.js", <<-CODE
//= require bootstrap
//= require modernizr
CODE


# require css assets explicitly instead of `require_tree`
gsub_file "app/assets/stylesheets/application.css", /require_tree \.$/, 'require screen'


insert_into_file "app/helpers/application_helper.rb", :after => "module ApplicationHelper\n" do
<<-CODE
  # Renders controller and action as CSS classes on the body element.
  def body_attributes
    {
      :class => [controller.controller_name, controller.action_name].join(' ')
    }
  end
CODE
end

insert_into_file "app/controllers/application_controller.rb", :before => /^end$/ do
<<-CODE
  before_filter :set_locale

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
  end
CODE
end


rake "db:migrate"
rake "db:seed"

remove_file 'README.rdoc'
remove_file 'public/index.html'
remove_file 'app/assets/images/rails.png'
remove_dir 'test'

git :init
git :add => "."
git :commit => %{-m "Initial commit.\r\nGenerated by http://github.com/terriblelabs/kickoff"}
